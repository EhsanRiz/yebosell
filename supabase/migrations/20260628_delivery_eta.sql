-- Delivery ETA: per-product lead time → auto-computed per-order ETA on confirm
-- (seller can override), surfaced to the buyer.
alter table public.products add column if not exists lead_time_days int;
alter table public.sellers  add column if not exists default_lead_time_days int;
alter table public.orders   add column if not exists eta_date date;

-- Auto-set the ETA the first time an order leaves 'new' (i.e. the seller confirms),
-- unless one is already set (seller override). ETA = today + slowest item lead time
-- (falling back to the store default, then 2 days) + 1 transit day for delivery/courier.
create or replace function public.tg_set_order_eta()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_lead int; v_default int; v_eff int; v_transit int;
begin
  if NEW.status is distinct from 'new' and NEW.status is distinct from 'cancelled' and NEW.eta_date is null then
    select max(coalesce(p.lead_time_days, 0)) into v_lead
      from order_items oi join products p on p.id = oi.product_id
      where oi.order_id = NEW.id;
    select default_lead_time_days into v_default from sellers where id = NEW.seller_id;
    v_eff := greatest(coalesce(v_lead, 0), coalesce(v_default, 0));
    if v_eff <= 0 then v_eff := 2; end if;
    v_transit := case when NEW.delivery_method = 'pickup' then 0 else 1 end;
    NEW.eta_date := ((now() at time zone 'Africa/Maseru')::date) + (v_eff + v_transit);
  end if;
  return NEW;
end $$;
drop trigger if exists set_order_eta on public.orders;
create trigger set_order_eta before insert or update on public.orders
  for each row execute function public.tg_set_order_eta();

-- Expose eta_date on the buyer tracking RPC.
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
$function$;
