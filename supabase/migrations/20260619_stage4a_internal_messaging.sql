-- ============================================================================
-- Stage 4a — Internal messaging (Phase 1 backend)
-- order-scoped buyer/seller/admin chat + auto status-update messages.
-- See SPEC_internal_messaging.md.
-- ============================================================================

-- ---- table -----------------------------------------------------------------
create table if not exists public.order_messages (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null references public.orders(id)  on delete cascade,
  seller_id     uuid not null references public.sellers(id) on delete cascade,
  sender        text not null check (sender in ('buyer','seller','admin','system')),
  kind          text not null default 'message' check (kind in ('message','status')),
  body          text not null check (length(btrim(body)) between 1 and 2000),
  meta          jsonb,
  created_at    timestamptz not null default now(),
  read_by_buyer_at  timestamptz,
  read_by_seller_at timestamptz
);
create index if not exists order_messages_order_idx  on public.order_messages (order_id, created_at);
create index if not exists order_messages_seller_idx on public.order_messages (seller_id, created_at desc);

alter table public.order_messages enable row level security;

-- ---- grants: anon writes/reads NOTHING directly (buyers go through RPCs) ----
revoke all on public.order_messages from anon;
grant select, insert, update on public.order_messages to authenticated;

-- ---- RLS: seller (owner) + admin only; trigger/RPCs are SECURITY DEFINER ----
drop policy if exists om_select_owner on public.order_messages;
create policy om_select_owner on public.order_messages for select
  using ((select public.owns_seller(seller_id)) or (select public.is_platform_admin()));

drop policy if exists om_insert_owner on public.order_messages;
create policy om_insert_owner on public.order_messages for insert
  with check (
    ((select public.owns_seller(seller_id)) and sender = 'seller')
    or ((select public.is_platform_admin()) and sender = 'admin')
  );

drop policy if exists om_update_owner on public.order_messages;
create policy om_update_owner on public.order_messages for update
  using ((select public.owns_seller(seller_id)) or (select public.is_platform_admin()))
  with check ((select public.owns_seller(seller_id)) or (select public.is_platform_admin()));

-- ---- buyer RPCs (SECURITY DEFINER, keyed on the order's track_token) --------
create or replace function public.get_order_thread(p_token text)
returns jsonb language sql security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'order_number', o.order_number,
    'status', o.status,
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'sender', m.sender, 'kind', m.kind,
        'body', m.body, 'meta', m.meta, 'created_at', m.created_at)
        order by m.created_at)
      from public.order_messages m where m.order_id = o.id), '[]'::jsonb)
  )
  from public.orders o where o.track_token = p_token limit 1;
$$;

-- Buyer-unread count for one order (for the bell; does NOT mark read)
create or replace function public.order_unread_count(p_token text)
returns int language sql security definer set search_path to 'public' as $$
  select coalesce(count(*),0)::int
  from public.order_messages m
  join public.orders o on o.id = m.order_id
  where o.track_token = p_token and m.sender <> 'buyer' and m.read_by_buyer_at is null;
$$;

create or replace function public.mark_thread_read_buyer(p_token text)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_order uuid;
begin
  select id into v_order from public.orders where track_token = p_token limit 1;
  if v_order is null then return; end if;
  update public.order_messages
     set read_by_buyer_at = now()
   where order_id = v_order and sender <> 'buyer' and read_by_buyer_at is null;
end $$;

create or replace function public.post_order_message(p_token text, p_body text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  v_order public.orders%rowtype;
  v_body  text := btrim(coalesce(p_body,''));
  v_recent int;
  v_msg   public.order_messages%rowtype;
begin
  select * into v_order from public.orders where track_token = p_token limit 1;
  if not found then return jsonb_build_object('error','badtoken','message','Order not found'); end if;
  if length(v_body) = 0 then return jsonb_build_object('error','empty','message','Message is empty'); end if;
  if length(v_body) > 2000 then v_body := left(v_body, 2000); end if;

  -- light rate limit: max 10 buyer messages / minute per order
  select count(*) into v_recent from public.order_messages
   where order_id = v_order.id and sender = 'buyer' and created_at > now() - interval '1 minute';
  if v_recent >= 10 then
    return jsonb_build_object('error','ratelimited','message','Too many messages — please wait a moment.');
  end if;

  insert into public.order_messages (order_id, seller_id, sender, kind, body)
  values (v_order.id, v_order.seller_id, 'buyer', 'message', v_body)
  returning * into v_msg;

  return jsonb_build_object('id', v_msg.id, 'sender', v_msg.sender, 'kind', v_msg.kind,
                            'body', v_msg.body, 'created_at', v_msg.created_at);
end $$;

-- ---- auto status-update messages (trigger, single source of truth) ---------
create or replace function public.tg_order_status_message()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status and new.status is not null then
    insert into public.order_messages (order_id, seller_id, sender, kind, body, meta)
    values (new.id, new.seller_id, 'system', 'status',
            'Order status: ' || initcap(replace(new.status, '_', ' ')),
            jsonb_build_object('status', new.status));
  end if;
  return new;
end $$;

drop trigger if exists order_status_message on public.orders;
create trigger order_status_message after update on public.orders
  for each row execute function public.tg_order_status_message();

-- ---- realtime: let authenticated sellers subscribe to their threads --------
do $$ begin
  alter publication supabase_realtime add table public.order_messages;
exception when duplicate_object then null; end $$;
