-- ============================================================================
-- YeboSell — "WhatsApp without the API" backend migrations (applied 2026-06-12)
-- These were applied to project nizrqwvfuxbuhertypva via the Supabase MCP and
-- are recorded here for version control. Run order top-to-bottom.
-- ============================================================================

-- 1) Per-order unguessable tracking token (32-char hex) ----------------------
alter table public.orders
  add column if not exists track_token text;

update public.orders
  set track_token = replace(gen_random_uuid()::text, '-', '')
  where track_token is null;

alter table public.orders
  alter column track_token set default replace(gen_random_uuid()::text, '-', '');

alter table public.orders
  add constraint orders_track_token_key unique (track_token);

-- 2) Sanitized public order read by token (no buyer phone leaked) -------------
create or replace function public.get_tracked_order(p_token text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'order', jsonb_build_object(
      'order_number', o.order_number, 'status', o.status,
      'payment_status', o.payment_status, 'delivery_status', o.delivery_status,
      'delivery_method', o.delivery_method, 'delivery_address', o.delivery_address,
      'delivery_fee', o.delivery_fee, 'discount_code', o.discount_code,
      'discount_amount', o.discount_amount, 'subtotal', o.subtotal,
      'total', o.total, 'created_at', o.created_at, 'delivery_updated_at', o.delivery_updated_at
    ),
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'product_name', oi.product_name, 'quantity', oi.quantity, 'unit_price', oi.unit_price)), '[]'::jsonb)
      from public.order_items oi where oi.order_id = o.id
    ),
    'seller', (
      select jsonb_build_object(
        'business_name', s.business_name, 'logo_url', s.logo_url, 'phone', s.phone,
        'pickup_address', s.pickup_address, 'delivery_notes', s.delivery_notes, 'slug', s.slug)
      from public.sellers s where s.id = o.seller_id
    )
  )
  from public.orders o
  where o.track_token = p_token
  limit 1;
$$;
revoke all on function public.get_tracked_order(text) from public;
grant execute on function public.get_tracked_order(text) to anon, authenticated;

-- 3) Phone-sync RPCs ---------------------------------------------------------
-- OTP-verified list of all a buyer's orders (phone matched on last 8 digits)
create or replace function public.get_orders_by_otp(p_phone text, p_otp text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_suffix text := right(regexp_replace(coalesce(p_phone,''), '\D', '', 'g'), 8);
  v_otp_id uuid;
begin
  if length(v_suffix) < 7 or coalesce(trim(p_otp),'') = '' then return '[]'::jsonb; end if;
  select id into v_otp_id from buyer_otps
  where right(regexp_replace(coalesce(phone,''), '\D', '', 'g'), 8) = v_suffix
    and otp_code = trim(p_otp) and used = false and expires_at > now()
  order by created_at desc limit 1;
  if v_otp_id is null then return '[]'::jsonb; end if;
  update buyer_otps set used = true where id = v_otp_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'token', o.track_token, 'order_number', o.order_number, 'status', o.status,
      'payment_status', o.payment_status, 'delivery_status', o.delivery_status,
      'total', o.total, 'created_at', o.created_at,
      'seller_name', (select s.business_name from sellers s where s.id = o.seller_id)
    ) order by o.created_at desc)
    from orders o
    where right(regexp_replace(coalesce(o.customer_phone,''), '\D', '', 'g'), 8) = v_suffix
  ), '[]'::jsonb);
end;
$$;

-- Knowledge-based silent refresh: phone + one known order number as proof
create or replace function public.get_orders_by_phone(p_phone text, p_order_number text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_suffix text := right(regexp_replace(coalesce(p_phone,''), '\D', '', 'g'), 8);
  v_ok boolean;
begin
  if length(v_suffix) < 7 or coalesce(trim(p_order_number),'') = '' then return '[]'::jsonb; end if;
  select exists(
    select 1 from orders o
    where upper(o.order_number) = upper(trim(p_order_number))
      and right(regexp_replace(coalesce(o.customer_phone,''), '\D', '', 'g'), 8) = v_suffix
  ) into v_ok;
  if not v_ok then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'token', o.track_token, 'order_number', o.order_number, 'status', o.status,
      'payment_status', o.payment_status, 'delivery_status', o.delivery_status,
      'total', o.total, 'created_at', o.created_at,
      'seller_name', (select s.business_name from sellers s where s.id = o.seller_id)
    ) order by o.created_at desc)
    from orders o
    where right(regexp_replace(coalesce(o.customer_phone,''), '\D', '', 'g'), 8) = v_suffix
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.get_orders_by_otp(text, text) from public;
revoke all on function public.get_orders_by_phone(text, text) from public;
grant execute on function public.get_orders_by_otp(text, text) to anon, authenticated;
grant execute on function public.get_orders_by_phone(text, text) to anon, authenticated;

-- 4) Phase 3 RLS hardening ---------------------------------------------------
-- OTP codes must NOT be readable via the anon key. The frontend no longer
-- touches buyer_otps directly (send-otp uses the service role; the RPCs above
-- are SECURITY DEFINER) — both bypass RLS, so dropping the open policy is safe.
drop policy if exists "Allow all on buyer_otps" on public.buyer_otps;

-- Close the critical advisory: data_deletion_requests was fully exposed to anon.
-- Its edge function uses the service role (bypasses RLS).
alter table public.data_deletion_requests enable row level security;

-- ============================================================================
-- KNOWN FOLLOW-UP (NOT yet applied — needs an auth/RPC refactor):
-- public.orders / order_items / products still have an open "ALL/public/true"
-- policy because auth is PIN-based (the seller dashboard queries as the anon
-- role). Revoking anon SELECT on orders would break the dashboard, checkout,
-- and the legacy order-number lookup. Tightening this requires moving the
-- dashboard's reads to SECURITY DEFINER RPCs or adopting Supabase Auth.
-- ============================================================================
