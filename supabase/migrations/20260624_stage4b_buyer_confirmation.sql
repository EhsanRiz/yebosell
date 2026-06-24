-- ============================================================================
-- Stage 4b — Buyer-side confirmation of payment & delivery (two-sided state)
-- In the direct-payment model YeboSell never holds funds, so protection is
-- evidentiary, not financial: the seller asserts status, the BUYER confirms or
-- disputes it independently. Any mismatch is recorded with timestamps and
-- surfaced to the seller (unread bell) and admin (dispute flag).
-- See payment-model discussion + SPEC_internal_messaging.md.
-- ============================================================================

-- ---- buyer confirmation columns on orders ----------------------------------
alter table public.orders
  add column if not exists buyer_paid_confirmed_at     timestamptz,
  add column if not exists buyer_received_confirmed_at timestamptz,
  add column if not exists buyer_dispute_at            timestamptz,
  add column if not exists buyer_dispute_reason        text;

-- index so the future admin console can list open disputes cheaply
create index if not exists orders_dispute_idx
  on public.orders (buyer_dispute_at desc) where buyer_dispute_at is not null;

-- ---- RPC: buyer confirms/disputes their own order (token-scoped, anon) ------
create or replace function public.buyer_confirm_order(
  p_token text, p_action text, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  v_order public.orders%rowtype;
  v_note  text := btrim(coalesce(p_note, ''));
  v_body  text;
begin
  select * into v_order from public.orders where track_token = p_token limit 1;
  if not found then
    return jsonb_build_object('error', 'badtoken', 'message', 'Order not found');
  end if;
  if p_action not in ('paid', 'received', 'dispute') then
    return jsonb_build_object('error', 'badaction', 'message', 'Unknown action');
  end if;
  if length(v_note) > 500 then v_note := left(v_note, 500); end if;

  if p_action = 'paid' then
    if v_order.buyer_paid_confirmed_at is null then
      update public.orders set buyer_paid_confirmed_at = now(), updated_at = now()
       where id = v_order.id;
      v_body := 'Buyer confirmed they have sent payment.';
    end if;

  elsif p_action = 'received' then
    if v_order.buyer_received_confirmed_at is null then
      update public.orders set buyer_received_confirmed_at = now(), updated_at = now()
       where id = v_order.id;
      v_body := 'Buyer confirmed they received this order.';
    end if;

  elsif p_action = 'dispute' then
    -- announce at most once per minute (a leaked token can't spam the thread)
    if v_order.buyer_dispute_at is null
       or v_order.buyer_dispute_at < now() - interval '1 minute' then
      v_body := 'Buyer reported a problem'
                || case when v_note <> '' then ': ' || v_note else '.' end;
    end if;
    update public.orders
       set buyer_dispute_at = now(),
           buyer_dispute_reason = nullif(v_note, ''),
           updated_at = now()
     where id = v_order.id;
  end if;

  -- record into the order thread; sender='buyer' so it lights the seller's bell
  if v_body is not null then
    insert into public.order_messages (order_id, seller_id, sender, kind, body, meta)
    values (v_order.id, v_order.seller_id, 'buyer', 'message', v_body,
            jsonb_build_object('confirm', p_action));
  end if;

  select * into v_order from public.orders where id = v_order.id;
  return jsonb_build_object(
    'ok', true,
    'buyer_paid_confirmed_at',     v_order.buyer_paid_confirmed_at,
    'buyer_received_confirmed_at', v_order.buyer_received_confirmed_at,
    'buyer_dispute_at',            v_order.buyer_dispute_at,
    'buyer_dispute_reason',        v_order.buyer_dispute_reason
  );
end $$;
revoke all on function public.buyer_confirm_order(text, text, text) from public;
grant execute on function public.buyer_confirm_order(text, text, text) to anon, authenticated;

-- ---- get_tracked_order: surface the buyer-confirmation state ----------------
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
      'total', o.total, 'created_at', o.created_at, 'delivery_updated_at', o.delivery_updated_at,
      'buyer_paid_confirmed_at', o.buyer_paid_confirmed_at,
      'buyer_received_confirmed_at', o.buyer_received_confirmed_at,
      'buyer_dispute_at', o.buyer_dispute_at,
      'buyer_dispute_reason', o.buyer_dispute_reason
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
