-- ============================================================================
-- Seller payment options — which methods a seller accepts + per-method details,
-- so buyers know exactly how to pay (payments are off-platform; no gateway).
-- bank_details already holds EFT details; payment_options adds accepted-methods
-- + mobile money + a cash note. Buyer-facing exposure is ONLY via purpose-built
-- SECURITY DEFINER RPCs (direct anon reads of `sellers` can't see bank_details
-- since Stage 3c), so opting in here deliberately publishes "pay me here".
-- ============================================================================
alter table public.sellers
  add column if not exists payment_options jsonb not null default '{}'::jsonb;

-- Storefront (shop) — payment instructions for a seller by slug.
create or replace function public.get_seller_payment_options(p_slug text)
returns jsonb language sql security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'payment_options', coalesce(s.payment_options, '{}'::jsonb),
    'bank_details',    coalesce(s.bank_details, '{}'::jsonb)
  )
  from public.sellers s
  where s.slug = p_slug and coalesce(s.is_active, true) = true
  limit 1;
$$;
grant execute on function public.get_seller_payment_options(text) to anon, authenticated;

-- Track page — fold the same payment instructions into the order's seller blob.
-- (Recreated from 20260612 with bank_details + payment_options added; all
-- previously-returned order/item/seller fields preserved.)
create or replace function public.get_tracked_order(p_token text)
returns jsonb language sql security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'order', jsonb_build_object(
      'order_number', o.order_number, 'status', o.status,
      'payment_status', o.payment_status, 'delivery_status', o.delivery_status,
      'delivery_method', o.delivery_method, 'delivery_address', o.delivery_address,
      'delivery_fee', o.delivery_fee, 'discount_code', o.discount_code,
      'discount_amount', o.discount_amount, 'subtotal', o.subtotal,
      'total', o.total, 'created_at', o.created_at, 'delivery_updated_at', o.delivery_updated_at,
      'payment_method', o.payment_method,
      'buyer_paid_confirmed_at', o.buyer_paid_confirmed_at,
      'buyer_received_confirmed_at', o.buyer_received_confirmed_at,
      'buyer_dispute_at', o.buyer_dispute_at, 'buyer_dispute_reason', o.buyer_dispute_reason
    ),
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'product_name', oi.product_name, 'quantity', oi.quantity, 'unit_price', oi.unit_price)), '[]'::jsonb)
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
$$;
grant execute on function public.get_tracked_order(text) to anon, authenticated;
