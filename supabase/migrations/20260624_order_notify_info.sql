-- ============================================================================
-- order_notify_info — seller-side helper for the "notify on WhatsApp" nudge
-- Returns, for an order the caller owns: whether the buyer's device is
-- push-subscribed for this order's token, plus the track_token (so the
-- dashboard can build the click-to-chat link). owns_seller-guarded; only the
-- owner gets data (others get null). SECURITY DEFINER so it can read the
-- otherwise-locked push_subscriptions table without exposing endpoints.
-- Used to show a fallback WhatsApp nudge ONLY for buyers push can't reach.
-- ============================================================================
create or replace function public.order_notify_info(p_order_id uuid)
returns jsonb language sql security definer set search_path to 'public' as $$
  select case when public.owns_seller(o.seller_id) then
    jsonb_build_object(
      'has_push', exists(
        select 1 from public.push_subscriptions ps
        where ps.tokens @> array[o.track_token]
      ),
      'track_token', o.track_token
    )
  else null end
  from public.orders o
  where o.id = p_order_id;
$$;

grant execute on function public.order_notify_info(uuid) to authenticated;
