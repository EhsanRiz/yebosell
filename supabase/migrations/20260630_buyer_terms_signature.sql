-- Capture the buyer's electronic signature at checkout: their name (already collected
-- as customer_name) plus a place of signing, stamped on the order alongside the
-- accepted buyer_terms_version and the order timestamp. Lets us produce a signed
-- order-agreement PDF for the buyer (on the confirmation screen and the tracking page).

alter table public.orders add column if not exists buyer_signed_place text;

-- create_storefront_order gains a trailing p_buyer_signed_place param. Drop the prior
-- 13-arg signature so the defaulted new param doesn't create an ambiguous overload.
drop function if exists public.create_storefront_order(uuid, text, text, text, text, numeric, text, numeric, text, text, numeric, jsonb, text);

create or replace function public.create_storefront_order(
  p_seller_id uuid, p_customer_name text, p_customer_phone text, p_delivery_method text,
  p_delivery_address text, p_delivery_fee numeric, p_payment_method text, p_total numeric,
  p_notes text, p_discount_code text, p_discount_amount numeric, p_items jsonb,
  p_buyer_terms_version text default null, p_buyer_signed_place text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
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
  insert into orders (seller_id, customer_name, customer_phone, status, delivery_method, delivery_address, delivery_status, delivery_fee, payment_method, total, notes, source, discount_code, discount_amount, buyer_terms_version, buyer_signed_place)
  values (p_seller_id, p_customer_name, p_customer_phone, 'new', p_delivery_method, coalesce(p_delivery_address,''), 'pending', coalesce(p_delivery_fee,0), p_payment_method, coalesce(p_total,0), p_notes, 'storefront', p_discount_code, coalesce(p_discount_amount,0), nullif(trim(p_buyer_terms_version),''), nullif(trim(p_buyer_signed_place),''))
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

grant execute on function public.create_storefront_order(uuid, text, text, text, text, numeric, text, numeric, text, text, numeric, jsonb, text, text) to anon, authenticated;

-- Expose the buyer's signing details on the tracked order so the tracking page can
-- regenerate the signed PDF.
create or replace function public.get_tracked_order(p_token text)
returns jsonb
language sql
security definer
set search_path to 'public'
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
      'customer_name', o.customer_name,
      'buyer_terms_version', o.buyer_terms_version, 'buyer_signed_place', o.buyer_signed_place,
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
