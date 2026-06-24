-- ============================================================================
-- Buyer cross-order unread summary (track-page bell)
-- Token-scoped SECURITY DEFINER, mirrors get_order_thread / order_unread_count.
-- The buyer PWA keeps its order track_tokens on-device ("My Orders"); this RPC
-- takes that list and returns, per order, the count of unread seller/admin/
-- system messages (read_by_buyer_at is null). Only orders with unread > 0 are
-- returned, ordered by most unread. The token array is capped to 200.
-- See SPEC_internal_messaging.md §7a (buyer bell aggregates across all tokens).
-- ============================================================================

create or replace function public.buyer_unread_summary(p_tokens text[])
returns jsonb language sql security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'token', t.token,
             'order_number', t.order_number,
             'seller_name', t.seller_name,
             'unread', t.unread
           ) order by t.unread desc), '[]'::jsonb)
  from (
    select o.track_token  as token,
           o.order_number as order_number,
           s.business_name as seller_name,
           count(m.id) filter (
             where m.sender <> 'buyer' and m.read_by_buyer_at is null
           )::int as unread
    from public.orders o
    join public.sellers s on s.id = o.seller_id
    left join public.order_messages m on m.order_id = o.id
    where o.track_token = any(p_tokens[1:200])
    group by o.track_token, o.order_number, s.business_name
    having count(m.id) filter (
             where m.sender <> 'buyer' and m.read_by_buyer_at is null
           ) > 0
  ) t;
$$;

grant execute on function public.buyer_unread_summary(text[]) to anon, authenticated;
