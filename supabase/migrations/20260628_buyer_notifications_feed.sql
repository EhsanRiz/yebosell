-- Per-message notification feed for the buyer bell: returns recent non-buyer
-- messages (seller / admin / system) across all of the buyer's saved orders as
-- individual rows, newest first, INCLUDING already-read ones so the bell doubles
-- as a traceable history. Read state is flagged so the UI can dim the read ones
-- and badge only the unread count. Capped at 60 most-recent across all orders.
-- (Supersedes buyer_unread_summary for the bell; that RPC is kept for any other
-- callers.)
create or replace function public.buyer_notifications(p_tokens text[])
returns jsonb language sql security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', x.id,
             'token', x.token,
             'order_number', x.order_number,
             'seller_name', x.seller_name,
             'body', x.body,
             'kind', x.kind,
             'created_at', x.created_at,
             'read', x.read_by_buyer_at is not null
           ) order by x.created_at desc), '[]'::jsonb)
  from (
    select m.id, o.track_token as token, o.order_number,
           s.business_name as seller_name, m.body, m.kind,
           m.created_at, m.read_by_buyer_at
    from public.orders o
    join public.sellers s on s.id = o.seller_id
    join public.order_messages m on m.order_id = o.id
    where o.track_token = any(p_tokens[1:200])
      and m.sender <> 'buyer'
    order by m.created_at desc
    limit 60
  ) x;
$$;

grant execute on function public.buyer_notifications(text[]) to anon, authenticated;
