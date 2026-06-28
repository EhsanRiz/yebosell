-- Seller web push: notify the seller's device(s) of new orders and buyer
-- messages even when the dashboard is closed. Reuses the push_subscriptions
-- table + send-push edge function; subscriptions are tagged with seller_id.
--
-- NOTE: the two triggers below are CREATED here but were subsequently DROPPED by
-- 20260628_seller_push_triggers_pause.sql until the send-push edge function is
-- redeployed with audience='seller' support. Re-create them (this block) once the
-- function is live. The old function would mis-handle audience='seller' calls.

alter table public.push_subscriptions add column if not exists seller_id uuid references public.sellers(id) on delete cascade;
create index if not exists push_subscriptions_seller_idx on public.push_subscriptions (seller_id);

-- Authenticated seller registers/refreshes this device for their account.
create or replace function public.register_seller_push(p_endpoint text, p_keys jsonb, p_seller_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_endpoint is null or length(p_endpoint) < 10 or p_keys is null then return; end if;
  if not public.owns_seller(p_seller_id) then return; end if;
  insert into public.push_subscriptions (endpoint, keys, seller_id, updated_at)
  values (p_endpoint, p_keys, p_seller_id, now())
  on conflict (endpoint) do update
    set keys = excluded.keys, seller_id = excluded.seller_id, updated_at = now();
end $$;
revoke all on function public.register_seller_push(text, jsonb, uuid) from public, anon;
grant execute on function public.register_seller_push(text, jsonb, uuid) to authenticated;

-- Push to the seller when a BUYER posts a message.
create or replace function public.tg_push_seller_on_buyer_message()
returns trigger language plpgsql security definer set search_path = public, net as $$
declare v_url text; v_key text;
begin
  if NEW.sender = 'buyer' then
    select value into v_url from public.private_config where key = 'functions_base_url';
    select value into v_key from public.private_config where key = 'push_shared_secret';
    if v_url is not null then
      begin
        perform net.http_post(
          url := v_url || '/send-push',
          headers := jsonb_build_object('Content-Type','application/json','x-push-key', coalesce(v_key,'')),
          body := jsonb_build_object('order_id', NEW.order_id, 'audience','seller', 'event','message', 'preview', left(NEW.body, 120))
        );
      exception when others then null;
      end;
    end if;
  end if;
  return NEW;
end $$;

-- Push to the seller when a NEW order arrives.
create or replace function public.tg_push_seller_on_new_order()
returns trigger language plpgsql security definer set search_path = public, net as $$
declare v_url text; v_key text;
begin
  select value into v_url from public.private_config where key = 'functions_base_url';
  select value into v_key from public.private_config where key = 'push_shared_secret';
  if v_url is not null then
    begin
      perform net.http_post(
        url := v_url || '/send-push',
        headers := jsonb_build_object('Content-Type','application/json','x-push-key', coalesce(v_key,'')),
        body := jsonb_build_object('order_id', NEW.id, 'audience','seller', 'event','new_order', 'preview', coalesce(NEW.customer_name,'A buyer'))
      );
    exception when others then null;
    end;
  end if;
  return NEW;
end $$;

-- Triggers (re-enable AFTER deploying the updated send-push edge function):
create trigger push_seller_on_buyer_message after insert on public.order_messages
  for each row execute function public.tg_push_seller_on_buyer_message();
create trigger push_seller_on_new_order after insert on public.orders
  for each row execute function public.tg_push_seller_on_new_order();
