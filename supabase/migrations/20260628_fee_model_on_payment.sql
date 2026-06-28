-- New fee model (decided with the operator):
--  • Accrue the platform fee when an order is marked PAID (not at creation) —
--    naturally covers manual + storefront orders.
--  • Base the % on the GOODS SUBTOTAL (order total minus delivery fee).
--  • Reverse (drop unsettled) the fee if the order is cancelled.
--  • Trial "first N free" now counts the seller's first N PAID orders.
--  • get_seller_fee_summary reports balance amount-based (fees − settlements) so
--    it can't drift from the admin balance after partial payments.
--
-- One-time data reconcile (run alongside): delete pending fees that the old
-- accrue-at-creation rule left on not-yet-paid, non-cancelled orders.

-- 1) Stop accruing at order creation (recreate without the fee block).
create or replace function public.create_storefront_order(p_seller_id uuid, p_customer_name text, p_customer_phone text, p_delivery_method text, p_delivery_address text, p_delivery_fee numeric, p_payment_method text, p_total numeric, p_notes text, p_discount_code text, p_discount_amount numeric, p_items jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_order public.orders%rowtype; v_item jsonb;
  v_order_number text;
  v_pid uuid; v_qty int; v_color text; v_size text; v_stock int; v_variants jsonb;
begin
  if p_seller_id is null or not exists (select 1 from sellers where id = p_seller_id) then
    return jsonb_build_object('error','badseller','message','Unknown store'); end if;
  if not public.seller_is_active(p_seller_id) then
    return jsonb_build_object('error','inactive','message','This store is not currently accepting orders.'); end if;
  if coalesce(trim(p_customer_name),'')='' or coalesce(trim(p_customer_phone),'')='' then
    return jsonb_build_object('error','badcustomer','message','Name and phone are required'); end if;
  v_order_number := 'ORD-'||to_char(now(),'YYYYMMDD')||'-'||lpad((floor(random()*900)+100)::int::text,3,'0');
  insert into orders (seller_id, customer_name, customer_phone, order_number, status, delivery_method, delivery_address, delivery_status, delivery_fee, payment_method, total, notes, source, discount_code, discount_amount)
  values (p_seller_id, p_customer_name, p_customer_phone, v_order_number, 'new', p_delivery_method, coalesce(p_delivery_address,''), 'pending', coalesce(p_delivery_fee,0), p_payment_method, coalesce(p_total,0), p_notes, 'storefront', p_discount_code, coalesce(p_discount_amount,0))
  returning * into v_order;
  for v_item in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    v_pid := nullif(v_item->>'product_id','')::uuid; v_qty := coalesce((v_item->>'quantity')::int,1);
    insert into order_items (order_id, product_id, product_name, quantity, unit_price)
    values (v_order.id, v_pid, coalesce(v_item->>'product_name','Item'), v_qty, coalesce((v_item->>'unit_price')::numeric,0));
    if v_pid is not null then
      v_color := nullif(v_item->>'variant_color',''); v_size := nullif(v_item->>'variant_size','');
      select stock, variants into v_stock, v_variants from products where id=v_pid and seller_id=p_seller_id;
      if (v_color is not null or v_size is not null) and v_variants is not null and jsonb_typeof(v_variants)='array' then
        update products set variants = (
          select jsonb_agg(case when coalesce(elem->>'color','')=coalesce(v_color,'') and coalesce(elem->>'size','')=coalesce(v_size,'')
            then jsonb_set(elem,'{stock}', to_jsonb(greatest(0, coalesce((elem->>'stock')::int,0)-v_qty))) else elem end)
          from jsonb_array_elements(v_variants) elem) where id=v_pid;
      elsif v_stock is not null then
        update products set stock = greatest(0, v_stock - v_qty) where id=v_pid; end if;
    end if;
  end loop;
  if coalesce(trim(p_discount_code),'')<>'' then
    update discount_codes set used_count=coalesce(used_count,0)+1 where seller_id=p_seller_id and lower(code)=lower(trim(p_discount_code)) and is_active=true; end if;
  return jsonb_build_object('order_number', v_order.order_number, 'track_token', v_order.track_token, 'total', v_order.total);
end; $function$;

-- 2) Accrue on paid / reverse on cancel, from the orders table.
create or replace function public.tg_platform_fee_sync()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_fee_type text; v_fee_value numeric; v_trial int; v_paid_count bigint; v_base numeric; v_fee numeric;
begin
  if NEW.status = 'cancelled' then
    delete from platform_fees where order_id = NEW.id and status = 'pending';
    return NEW;
  end if;
  if NEW.payment_status = 'paid' and (TG_OP = 'INSERT' or coalesce(OLD.payment_status,'') <> 'paid') then
    if exists (select 1 from platform_fees where order_id = NEW.id) then return NEW; end if;
    select fee_type, fee_value, coalesce(trial_order_limit,0) into v_fee_type, v_fee_value, v_trial from platform_config limit 1;
    if v_fee_value is null then return NEW; end if;
    select count(*) into v_paid_count from orders where seller_id = NEW.seller_id and payment_status = 'paid' and id <> NEW.id;
    if v_trial > 0 and v_paid_count < v_trial then return NEW; end if;
    v_base := greatest(0, coalesce(NEW.total,0) - coalesce(NEW.delivery_fee,0));
    v_fee := case when v_fee_type = 'percentage' then v_base * v_fee_value / 100 else v_fee_value end;
    insert into platform_fees (order_id, seller_id, order_total, fee_amount, status)
    values (NEW.id, NEW.seller_id, NEW.total, round(v_fee * 100) / 100, 'pending');
  end if;
  return NEW;
end $$;
drop trigger if exists platform_fee_sync on public.orders;
create trigger platform_fee_sync after insert or update on public.orders
  for each row execute function public.tg_platform_fee_sync();

-- 3) Balance-consistent fee summary; trial based on PAID orders.
create or replace function public.get_seller_fee_summary(p_seller_id uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_total_fees numeric; v_settled numeric; v_pending numeric;
  v_paid_count bigint; v_order_count bigint;
  v_trial_limit int; v_threshold numeric; v_fee_pct numeric;
begin
  if not owns_seller(p_seller_id) then return jsonb_build_object('error','forbidden'); end if;
  select coalesce(sum(fee_amount),0) into v_total_fees from platform_fees where seller_id = p_seller_id;
  select coalesce(sum(amount),0) into v_settled from seller_settlements where seller_id = p_seller_id;
  v_pending := greatest(0, v_total_fees - v_settled);
  select count(*) into v_order_count from orders where seller_id = p_seller_id;
  select count(*) into v_paid_count from orders where seller_id = p_seller_id and payment_status = 'paid';
  select coalesce(trial_order_limit,0), coalesce(suspension_threshold,500), coalesce(fee_value,5)
    into v_trial_limit, v_threshold, v_fee_pct from platform_config limit 1;
  return jsonb_build_object(
    'pending_fees', v_pending, 'settled_fees', v_settled, 'order_count', v_order_count,
    'trial_order_limit', v_trial_limit,
    'orders_in_trial', greatest(0, v_trial_limit - v_paid_count),
    'in_trial', (v_trial_limit > 0 and v_paid_count < v_trial_limit),
    'suspension_threshold', v_threshold, 'fee_pct', v_fee_pct,
    'near_suspension', (v_pending >= v_threshold * 0.8),
    'suspended', (v_pending >= v_threshold)
  );
end; $function$;

-- 4) Reconcile legacy creation-time fees on unpaid, non-cancelled orders.
delete from platform_fees pf using orders o
 where pf.order_id = o.id and pf.status = 'pending'
   and coalesce(o.payment_status,'') <> 'paid' and o.status <> 'cancelled';
