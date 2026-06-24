-- ============================================================================
-- Realtime Broadcast from the database (instant in-app updates for anon buyers)
-- Anon buyers can't hold a Postgres-changes subscription, so on every non-buyer
-- message (seller / admin / system status) we emit a content-free ping to the
-- PUBLIC topic order-rt:<track_token>. The /track page subscribes to that topic
-- and refetches via get_order_thread. Broadcast failure never blocks the insert.
-- See SPEC_internal_messaging.md §5.
-- ============================================================================

create or replace function public.tg_broadcast_order_message()
returns trigger language plpgsql security definer set search_path = public, realtime as $$
declare v_token text;
begin
  if NEW.sender <> 'buyer' then
    select track_token into v_token from public.orders where id = NEW.order_id;
    if v_token is not null then
      begin
        perform realtime.send(
          jsonb_build_object('event','msg','sender',NEW.sender,'kind',NEW.kind),
          'msg',
          'order-rt:' || v_token,
          false   -- public topic: anon can subscribe, ping carries no order data
        );
      exception when others then null;
      end;
    end if;
  end if;
  return NEW;
end $$;

drop trigger if exists broadcast_order_message on public.order_messages;
create trigger broadcast_order_message after insert on public.order_messages
  for each row execute function public.tg_broadcast_order_message();
