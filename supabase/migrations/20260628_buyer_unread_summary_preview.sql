-- Add the latest unread message preview (body + time) per order so the buyer
-- bell can show WHAT changed, not just a count. Ordered by most-recent activity.
create or replace function public.buyer_unread_summary(p_tokens text[])
returns jsonb language sql security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'token', t.token,
             'order_number', t.order_number,
             'seller_name', t.seller_name,
             'unread', t.unread,
             'last_message', t.last_message,
             'last_at', t.last_at
           ) order by t.last_at desc nulls last), '[]'::jsonb)
  from (
    select o.track_token   as token,
           o.order_number  as order_number,
           s.business_name as seller_name,
           count(m.id) filter (
             where m.sender <> 'buyer' and m.read_by_buyer_at is null
           )::int as unread,
           (array_agg(m.body order by m.created_at desc) filter (
             where m.sender <> 'buyer' and m.read_by_buyer_at is null
           ))[1] as last_message,
           max(m.created_at) filter (
             where m.sender <> 'buyer' and m.read_by_buyer_at is null
           ) as last_at
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
