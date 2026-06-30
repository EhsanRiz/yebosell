-- User agreements: sellers accept the platform terms (incl. the 5% fee + obligation
-- to settle outstanding fees) on first login / after a terms change; buyers accept the
-- buyer terms at checkout. Acceptance is recorded server-side so it persists across
-- devices (sellers) and stamps each order with the accepted version (buyers).

-- ---- Columns -------------------------------------------------------------------
alter table public.sellers add column if not exists terms_accepted_at timestamptz;
alter table public.sellers add column if not exists terms_version text;
alter table public.orders  add column if not exists buyer_terms_version text;

-- The dashboard reads terms_version via seller_account_status (SECURITY DEFINER), but
-- grant the column too so an authenticated owner can read it directly if needed.
grant select (terms_version, terms_accepted_at) on public.sellers to authenticated;

-- ---- Seller acceptance RPC -----------------------------------------------------
-- Records that the signed-in seller accepted a given terms version. Guarded by
-- owns_seller so a seller can only accept on their own behalf.
create or replace function public.seller_accept_terms(p_seller_id uuid, p_version text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not owns_seller(p_seller_id) then return jsonb_build_object('error','forbidden'); end if;
  update sellers set terms_accepted_at = now(), terms_version = nullif(trim(p_version),''), updated_at = now()
   where id = p_seller_id;
  return jsonb_build_object('ok', true, 'terms_version', p_version);
end $function$;

grant execute on function public.seller_accept_terms(uuid, text) to authenticated;

-- ---- Surface the seller's accepted version in the account-status RPC ------------
-- (Used by the dashboard to decide whether to show the blocking agreement modal.)
create or replace function public.seller_account_status(p_seller_id uuid)
returns jsonb
language sql
security definer
set search_path to 'public'
as $function$
  select case when public.owns_seller(p_seller_id) then (
    select jsonb_build_object(
      'seller_status', coalesce(s.seller_status, 'active'),
      'is_active', coalesce(s.is_active, true),
      'suspension_reason', s.suspension_reason,
      'outstanding', bal.outstanding,
      'warning_threshold', cfg.warning_threshold,
      'suspension_threshold', cfg.suspension_threshold,
      'fee_state', case
        when coalesce(s.seller_status, 'active') <> 'active' then 'suspended'
        when cfg.warning_threshold is not null and cfg.warning_threshold > 0 and bal.outstanding >= cfg.warning_threshold then 'warning'
        else 'ok' end,
      'terms_version', s.terms_version
    )
    from public.sellers s
    cross join lateral (select coalesce(suspension_threshold, 500) as suspension_threshold, warning_threshold from public.platform_config limit 1) cfg
    cross join lateral (select coalesce((select sum(fee_amount) from public.platform_fees where seller_id = s.id), 0)
                             - coalesce((select sum(amount) from public.seller_settlements where seller_id = s.id), 0) as outstanding) bal
    where s.id = p_seller_id
  ) else null end;
$function$;

-- ---- Stamp the buyer's accepted terms version onto the order -------------------
-- Adds a trailing p_buyer_terms_version param (defaulted so older callers still work)
-- and writes it into orders.buyer_terms_version. Drop the prior 12-arg signature so
-- the defaulted new param doesn't create an ambiguous overload.
drop function if exists public.create_storefront_order(uuid, text, text, text, text, numeric, text, numeric, text, text, numeric, jsonb);

create or replace function public.create_storefront_order(
  p_seller_id uuid, p_customer_name text, p_customer_phone text, p_delivery_method text,
  p_delivery_address text, p_delivery_fee numeric, p_payment_method text, p_total numeric,
  p_notes text, p_discount_code text, p_discount_amount numeric, p_items jsonb,
  p_buyer_terms_version text default null)
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
  insert into orders (seller_id, customer_name, customer_phone, status, delivery_method, delivery_address, delivery_status, delivery_fee, payment_method, total, notes, source, discount_code, discount_amount, buyer_terms_version)
  values (p_seller_id, p_customer_name, p_customer_phone, 'new', p_delivery_method, coalesce(p_delivery_address,''), 'pending', coalesce(p_delivery_fee,0), p_payment_method, coalesce(p_total,0), p_notes, 'storefront', p_discount_code, coalesce(p_discount_amount,0), nullif(trim(p_buyer_terms_version),''))
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

grant execute on function public.create_storefront_order(uuid, text, text, text, text, numeric, text, numeric, text, text, numeric, jsonb, text) to anon, authenticated;
