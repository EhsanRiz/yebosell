-- Buyer-initiated cancellation + accurate stock restore. Needs the chosen variant
-- persisted on the line item (previously only used transiently to decrement stock).
alter table public.order_items add column if not exists variant_color text;
alter table public.order_items add column if not exists variant_size text;
alter table public.orders add column if not exists buyer_cancelled_at timestamptz;
alter table public.orders add column if not exists buyer_cancel_reason text;
grant select (variant_color, variant_size) on public.order_items to anon, authenticated;

-- Recreate the storefront order RPC: let the trigger assign the order number, and
-- persist variant_color/variant_size on each line item.
create or replace function public.create_storefront_order(p_seller_id uuid, p_customer_name text, p_customer_phone text, p_delivery_method text, p_delivery_address text, p_delivery_fee numeric, p_payment_method text, p_total numeric, p_notes text, p_discount_code text, p_discount_amount numeric, p_items jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_order public.orders%rowtype; v_item jsonb;
  v_pid uuid; v_qty int; v_color text; v_size text; v_stock int; v_variants jsonb;
begin
  if p_seller_id is null or not exists (select 1 from sellers where id = p_seller_id) then
    return jsonb_build_object('error','badseller','message','Unknown store'); end if;
  if not public.seller_is_active(p_seller_id) then
    return jsonb_build_object('error','inactive','message','This store is not currently accepting orders.'); end if;
  if coalesce(trim(p_customer_name),'')='' or coalesce(trim(p_customer_phone),'')='' then
    return jsonb_build_object('error','badcustomer','message','Name and phone are required'); end if;
  insert into orders (seller_id, customer_name, customer_phone, status, delivery_method, delivery_address, delivery_status, delivery_fee, payment_method, total, notes, source, discount_code, discount_amount)
  values (p_seller_id, p_customer_name, p_customer_phone, 'new', p_delivery_method, coalesce(p_delivery_address,''), 'pending', coalesce(p_delivery_fee,0), p_payment_method, coalesce(p_total,0), p_notes, 'storefront', p_discount_code, coalesce(p_discount_amount,0))
  returning * into v_order;
  for v_item in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    v_pid := nullif(v_item->>'product_id','')::uuid; v_qty := coalesce((v_item->>'quantity')::int,1);
    v_color := nullif(v_item->>'variant_color',''); v_size := nullif(v_item->>'variant_size','');
    insert into order_items (order_id, product_id, product_name, quantity, unit_price, variant_color, variant_size)
    values (v_order.id, v_pid, coalesce(v_item->>'product_name','Item'), v_qty, coalesce((v_item->>'unit_price')::numeric,0), v_color, v_size);
    if v_pid is not null then
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

-- Buyer cancels their own order via the tracking token. Allowed until the order
-- is out for delivery / delivered / already cancelled. Restores stock (variant-aware)
-- and leaves a clear note for the seller.
create or replace function public.buyer_cancel_order(p_token text, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_order orders%rowtype; v_item record; v_variants jsonb;
begin
  select * into v_order from orders where track_token = p_token;
  if not found then return jsonb_build_object('error','notfound','message','Order not found.'); end if;
  if v_order.status in ('out_for_delivery','delivered','cancelled') then
    return jsonb_build_object('error','toolate','message','This order can no longer be cancelled here. Please message the seller.');
  end if;
  for v_item in select product_id, quantity, variant_color, variant_size from order_items where order_id = v_order.id loop
    if v_item.product_id is not null then
      if coalesce(v_item.variant_color,'')<>'' or coalesce(v_item.variant_size,'')<>'' then
        select variants into v_variants from products where id=v_item.product_id;
        if v_variants is not null and jsonb_typeof(v_variants)='array' then
          update products set variants = (
            select jsonb_agg(case when coalesce(elem->>'color','')=coalesce(v_item.variant_color,'') and coalesce(elem->>'size','')=coalesce(v_item.variant_size,'')
              then jsonb_set(elem,'{stock}', to_jsonb(coalesce((elem->>'stock')::int,0)+v_item.quantity)) else elem end)
            from jsonb_array_elements(v_variants) elem) where id=v_item.product_id;
        end if;
      else
        update products set stock = coalesce(stock,0)+v_item.quantity where id=v_item.product_id and stock is not null;
      end if;
    end if;
  end loop;
  insert into order_messages (order_id, seller_id, sender, kind, body, meta)
  values (v_order.id, v_order.seller_id, 'buyer', 'message',
          'Buyer cancelled this order' || case when coalesce(trim(p_reason),'')<>'' then '. Reason: ' || trim(p_reason) else '.' end,
          jsonb_build_object('event','buyer_cancel'));
  update orders set status='cancelled', delivery_status='cancelled',
      buyer_cancelled_at=now(), buyer_cancel_reason=nullif(trim(p_reason),''), delivery_updated_at=now()
    where id = v_order.id;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.buyer_cancel_order(text, text) to anon, authenticated;

-- Surface cancellation + line-item variants on the buyer tracking RPC.
create or replace function public.get_tracked_order(p_token text)
 returns jsonb language sql security definer set search_path to 'public'
as $function$
  select jsonb_build_object(
    'order', jsonb_build_object(
      'order_number', o.order_number, 'status', o.status,
      'payment_status', o.payment_status, 'delivery_status', o.delivery_status,
      'delivery_method', o.delivery_method, 'delivery_address', o.delivery_address,
      'delivery_fee', o.delivery_fee, 'discount_code', o.discount_code,
      'discount_amount', o.discount_amount, 'subtotal', o.subtotal,
      'total', o.total, 'created_at', o.created_at, 'delivery_updated_at', o.delivery_updated_at,
      'payment_method', o.payment_method, 'eta_date', o.eta_date,
      'buyer_paid_confirmed_at', o.buyer_paid_confirmed_at,
      'buyer_received_confirmed_at', o.buyer_received_confirmed_at,
      'buyer_dispute_at', o.buyer_dispute_at, 'buyer_dispute_reason', o.buyer_dispute_reason,
      'buyer_cancelled_at', o.buyer_cancelled_at, 'buyer_cancel_reason', o.buyer_cancel_reason
    ),
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'product_name', oi.product_name, 'quantity', oi.quantity, 'unit_price', oi.unit_price,
        'variant_color', oi.variant_color, 'variant_size', oi.variant_size)), '[]'::jsonb)
      from public.order_items oi where oi.order_id = o.id
    ),
    'seller', (
      select jsonb_build_object(
        'business_name', s.business_name, 'logo_url', s.logo_url, 'phone', s.phone,
        'pickup_address', s.pickup_address, 'delivery_notes', s.delivery_notes, 'slug', s.slug,
        'bank_details', coalesce(s.bank_details, '{}'::jsonb),
        'payment_options', coalesce(s.payment_options, '{}'::jsonb))
      from public.sellers s where s.id = o.seller_id
    )
  )
  from public.orders o
  where o.track_token = p_token
  limit 1;
$function$;
