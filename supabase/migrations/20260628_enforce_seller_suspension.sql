-- Enforce suspension server-side: (1) block storefront checkout for non-active
-- stores, (2) block catalog writes (products/discount_codes) by suspended sellers
-- via RESTRICTIVE policies (reads + login stay intact so they still see the
-- "why/how to reactivate" banner and can wind down existing orders).

create or replace function public.seller_is_active(p_seller_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.sellers s
    where s.id = p_seller_id
      and coalesce(s.is_active, true) = true
      and coalesce(s.seller_status, 'active') in ('active', 'trial')
  );
$$;
grant execute on function public.seller_is_active(uuid) to anon, authenticated;

-- (1) create_storefront_order now rejects non-active stores (deactivated + any
-- direct API call, not just the storefront UI gate). The only change vs. the
-- prior body is the seller_is_active() guard near the top; see migration
-- 20260617_stage3c for the original.
create or replace function public.create_storefront_order(p_seller_id uuid, p_customer_name text, p_customer_phone text, p_delivery_method text, p_delivery_address text, p_delivery_fee numeric, p_payment_method text, p_total numeric, p_notes text, p_discount_code text, p_discount_amount numeric, p_items jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_order public.orders%rowtype; v_item jsonb;
  v_fee_type text; v_fee_value numeric; v_fee numeric; v_order_number text;
  v_pid uuid; v_qty int; v_color text; v_size text; v_stock int; v_variants jsonb;
  v_trial_limit int; v_prev_order_count bigint;
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
  select fee_type, fee_value, coalesce(trial_order_limit, 0)
    into v_fee_type, v_fee_value, v_trial_limit from platform_config limit 1;
  if v_fee_value is not null then
    select count(*) into v_prev_order_count from orders where seller_id = p_seller_id and id != v_order.id;
    if v_trial_limit = 0 or v_prev_order_count >= v_trial_limit then
      v_fee := case when v_fee_type='percentage' then coalesce(p_total,0)*v_fee_value/100 else v_fee_value end;
      insert into platform_fees (order_id, seller_id, order_total, fee_amount)
      values (v_order.id, p_seller_id, coalesce(p_total,0), round(v_fee*100)/100);
    end if;
  end if;
  return jsonb_build_object('order_number', v_order.order_number, 'track_token', v_order.track_token, 'total', v_order.total);
end; $function$;

-- (2) Restrictive catalog-write block for suspended/deactivated sellers. RESTRICTIVE
-- = ANDed with the existing permissive owner policies, only on write commands, so
-- owner SELECT/login are unaffected. Admin always allowed. SECURITY DEFINER RPCs
-- (e.g. checkout stock decrement) bypass RLS, so they're unaffected.
drop policy if exists products_active_insert on public.products;
drop policy if exists products_active_update on public.products;
drop policy if exists products_active_delete on public.products;
create policy products_active_insert on public.products as restrictive for insert
  with check (public.seller_is_active(seller_id) or public.is_platform_admin());
create policy products_active_update on public.products as restrictive for update
  using (public.seller_is_active(seller_id) or public.is_platform_admin())
  with check (public.seller_is_active(seller_id) or public.is_platform_admin());
create policy products_active_delete on public.products as restrictive for delete
  using (public.seller_is_active(seller_id) or public.is_platform_admin());

drop policy if exists discounts_active_insert on public.discount_codes;
drop policy if exists discounts_active_update on public.discount_codes;
drop policy if exists discounts_active_delete on public.discount_codes;
create policy discounts_active_insert on public.discount_codes as restrictive for insert
  with check (public.seller_is_active(seller_id) or public.is_platform_admin());
create policy discounts_active_update on public.discount_codes as restrictive for update
  using (public.seller_is_active(seller_id) or public.is_platform_admin())
  with check (public.seller_is_active(seller_id) or public.is_platform_admin());
create policy discounts_active_delete on public.discount_codes as restrictive for delete
  using (public.seller_is_active(seller_id) or public.is_platform_admin());
