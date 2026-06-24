-- ============================================================================
-- Web Push (Phase 2) — buyer push notifications for order messages.
-- Buyers are anon + token-scoped; a device registers its PushSubscription plus
-- the track_tokens it holds. On any non-buyer message, a trigger pings the
-- send-push Edge Function (via pg_net), which fans out web-push to the devices
-- subscribed to that order's token.
--
-- Secrets (VAPID private key, push shared secret, functions URL) live in
-- public.private_config and are inserted OUT OF BAND (never committed to the
-- repo, which is web-served). This migration only creates the schema.
-- See SPEC_internal_messaging.md §6.
-- ============================================================================

create extension if not exists pg_net;

-- Device subscriptions (anon writes only via the SECURITY DEFINER RPC below).
create table if not exists public.push_subscriptions (
  endpoint   text primary key,
  keys       jsonb not null,                 -- { p256dh, auth }
  tokens     text[] not null default '{}',   -- track_tokens this device holds
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists push_subscriptions_tokens_idx on public.push_subscriptions using gin (tokens);
alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from anon, authenticated;
grant all on public.push_subscriptions to service_role;

-- Server-only secrets (values inserted out of band; never in the repo).
create table if not exists public.private_config (
  key   text primary key,
  value text not null
);
alter table public.private_config enable row level security;
revoke all on public.private_config from anon, authenticated;
grant all on public.private_config to service_role;

-- Register / refresh a device's subscription and the orders it cares about.
create or replace function public.register_push_subscription(p_endpoint text, p_keys jsonb, p_tokens text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_endpoint is null or length(p_endpoint) < 10 or p_keys is null then return; end if;
  insert into public.push_subscriptions (endpoint, keys, tokens, updated_at)
  values (p_endpoint, p_keys, coalesce(p_tokens, '{}'), now())
  on conflict (endpoint) do update
    set keys = excluded.keys, tokens = excluded.tokens, updated_at = now();
end $$;
revoke all on function public.register_push_subscription(text, jsonb, text[]) from public;
grant execute on function public.register_push_subscription(text, jsonb, text[]) to anon, authenticated;

-- Trigger: ping the send-push function on every non-buyer message.
create or replace function public.tg_push_on_message()
returns trigger language plpgsql security definer set search_path = public, net as $$
declare v_url text; v_key text;
begin
  if NEW.sender <> 'buyer' then
    select value into v_url from public.private_config where key = 'functions_base_url';
    select value into v_key from public.private_config where key = 'push_shared_secret';
    if v_url is not null then
      begin
        perform net.http_post(
          url := v_url || '/send-push',
          headers := jsonb_build_object('Content-Type','application/json','x-push-key', coalesce(v_key,'')),
          body := jsonb_build_object('order_id', NEW.order_id, 'sender', NEW.sender, 'kind', NEW.kind, 'preview', left(NEW.body, 120))
        );
      exception when others then null;
      end;
    end if;
  end if;
  return NEW;
end $$;
drop trigger if exists push_on_message on public.order_messages;
create trigger push_on_message after insert on public.order_messages
  for each row execute function public.tg_push_on_message();
