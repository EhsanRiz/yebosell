-- Admin user management backend.
-- All admin write/read RPCs are guarded by is_platform_admin() (pure-admin model).
--
-- Tables:
--   seller_login_events  -- who logged in, when, how (pin/otp), success/fail
--   admin_actions        -- audit trail of every admin operation
-- RPCs:
--   seller_login()         -- now logs events + blocks disabled accounts (replaces prior body)
--   record_login_event()   -- frontend calls after a successful OTP sign-in (method='otp')
--   admin_set_seller_status(seller, status)   -- active|suspended|deactivated
--   admin_reset_seller_pin(seller, temp_pin?) -- clear PIN (or set temp) + clear lockout
--   admin_seller_detail(seller)               -- drill-down: stats + recent logins
--   admin_login_audit(seller?, limit)         -- login feed
--   admin_actions_log(limit)                  -- admin action feed

-- A. Login event log
create table if not exists public.seller_login_events (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid references public.sellers(id) on delete set null,
  phone text,
  method text,
  success boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists idx_sle_seller on public.seller_login_events(seller_id, created_at desc);
create index if not exists idx_sle_created on public.seller_login_events(created_at desc);
alter table public.seller_login_events enable row level security;
drop policy if exists sle_admin_select on public.seller_login_events;
create policy sle_admin_select on public.seller_login_events
  for select to authenticated using (public.is_platform_admin());

-- B. Admin action log
create table if not exists public.admin_actions (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid,
  action text not null,
  target_seller_id uuid references public.sellers(id) on delete set null,
  detail text,
  created_at timestamptz not null default now()
);
create index if not exists idx_aa_created on public.admin_actions(created_at desc);
alter table public.admin_actions enable row level security;
drop policy if exists aa_admin_select on public.admin_actions;
create policy aa_admin_select on public.admin_actions
  for select to authenticated using (public.is_platform_admin());

-- C. seller_login logs events + blocks disabled accounts
create or replace function public.seller_login(p_phone text, p_pin text)
returns jsonb language plpgsql security definer set search_path to 'public','extensions'
as $fn$
declare
  v_phone text := regexp_replace(coalesce(p_phone,''), '\s', '', 'g');
  v_seller public.sellers%rowtype;
  v_hash text;
  v_fails int;
begin
  select count(*) into v_fails from seller_login_attempts
   where phone = v_phone and attempted_at > now() - interval '15 minutes';
  if v_fails >= 5 then
    return jsonb_build_object('error','locked','message','Too many attempts. Please wait 15 minutes and try again.');
  end if;
  select s.* into v_seller from sellers s where s.phone = v_phone;
  if not found then
    insert into seller_login_attempts(phone) values (v_phone);
    insert into seller_login_events(seller_id, phone, method, success) values (null, v_phone, 'pin', false);
    return jsonb_build_object('error','invalid','message','Phone or PIN incorrect');
  end if;
  if coalesce(v_seller.is_active, true) = false then
    insert into seller_login_events(seller_id, phone, method, success) values (v_seller.id, v_phone, 'pin', false);
    return jsonb_build_object('error','disabled','message','This account is not active. Please contact support.');
  end if;
  select pin_hash into v_hash from seller_secrets where seller_id = v_seller.id;
  if v_hash is null or extensions.crypt(p_pin, v_hash) <> v_hash then
    insert into seller_login_attempts(phone) values (v_phone);
    insert into seller_login_events(seller_id, phone, method, success) values (v_seller.id, v_phone, 'pin', false);
    return jsonb_build_object('error','invalid','message','Phone or PIN incorrect');
  end if;
  delete from seller_login_attempts where phone = v_phone;
  insert into seller_login_events(seller_id, phone, method, success) values (v_seller.id, v_phone, 'pin', true);
  return jsonb_build_object('seller', to_jsonb(v_seller));
end; $fn$;

-- D. record_login_event (OTP sign-ins)
create or replace function public.record_login_event(p_method text default 'otp')
returns void language plpgsql security definer set search_path to 'public'
as $fn$
declare v_seller public.sellers%rowtype;
begin
  if auth.uid() is null then return; end if;
  select s.* into v_seller from sellers s where s.auth_user_id = auth.uid() limit 1;
  if not found then return; end if;
  insert into seller_login_events(seller_id, phone, method, success)
  values (v_seller.id, v_seller.phone, coalesce(p_method,'otp'), true);
end; $fn$;
grant execute on function public.record_login_event(text) to authenticated;

-- E. admin_set_seller_status
create or replace function public.admin_set_seller_status(p_seller_id uuid, p_status text)
returns jsonb language plpgsql security definer set search_path to 'public'
as $fn$
declare v_active boolean; v_name text;
begin
  if not public.is_platform_admin() then return jsonb_build_object('error','forbidden'); end if;
  if p_status not in ('active','suspended','deactivated') then
    return jsonb_build_object('error','badstatus','message','Invalid status');
  end if;
  v_active := (p_status <> 'deactivated');
  update public.sellers set seller_status = p_status, is_active = v_active, updated_at = now()
   where id = p_seller_id returning business_name into v_name;
  if not found then return jsonb_build_object('error','notfound'); end if;
  insert into public.admin_actions(admin_id, action, target_seller_id, detail)
  values (auth.uid(), 'set_status', p_seller_id, p_status);
  return jsonb_build_object('ok', true, 'status', p_status, 'business_name', v_name);
end; $fn$;
grant execute on function public.admin_set_seller_status(uuid, text) to authenticated;

-- F. admin_reset_seller_pin
create or replace function public.admin_reset_seller_pin(p_seller_id uuid, p_temp_pin text default null)
returns jsonb language plpgsql security definer set search_path to 'public','extensions'
as $fn$
declare v_phone text;
begin
  if not public.is_platform_admin() then return jsonb_build_object('error','forbidden'); end if;
  select phone into v_phone from public.sellers where id = p_seller_id;
  if v_phone is null then return jsonb_build_object('error','notfound'); end if;
  if p_temp_pin is not null and length(p_temp_pin) >= 4 then
    insert into public.seller_secrets(seller_id, pin_hash)
    values (p_seller_id, extensions.crypt(p_temp_pin, extensions.gen_salt('bf')))
    on conflict (seller_id) do update set pin_hash = excluded.pin_hash, updated_at = now();
  else
    delete from public.seller_secrets where seller_id = p_seller_id;
  end if;
  delete from public.seller_login_attempts where phone = regexp_replace(coalesce(v_phone,''),'\s','','g');
  insert into public.admin_actions(admin_id, action, target_seller_id, detail)
  values (auth.uid(), 'reset_pin', p_seller_id,
          case when p_temp_pin is not null then 'temp_pin_set' else 'pin_cleared' end);
  return jsonb_build_object('ok', true, 'mode', case when p_temp_pin is not null then 'temp' else 'cleared' end);
end; $fn$;
grant execute on function public.admin_reset_seller_pin(uuid, text) to authenticated;

-- G. admin_seller_detail
create or replace function public.admin_seller_detail(p_seller_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $fn$
declare v jsonb; v_uid uuid; v_last timestamptz;
begin
  if not public.is_platform_admin() then return jsonb_build_object('error','forbidden'); end if;
  select auth_user_id into v_uid from public.sellers where id = p_seller_id;
  if v_uid is not null then select last_sign_in_at into v_last from auth.users where id = v_uid; end if;
  select jsonb_build_object(
    'seller', (select to_jsonb(s) from public.sellers s where s.id = p_seller_id),
    'order_count', (select count(*) from public.orders where seller_id = p_seller_id),
    'gmv', (select coalesce(sum(total),0) from public.orders where seller_id = p_seller_id and coalesce(status,'') <> 'cancelled'),
    'product_count', (select count(*) from public.products where seller_id = p_seller_id),
    'fees_pending', (select coalesce(sum(fee_amount),0) from public.platform_fees where seller_id = p_seller_id and status='pending'),
    'last_login', v_last,
    'recent_logins', (select coalesce(jsonb_agg(jsonb_build_object('method',method,'success',success,'at',created_at)),'[]'::jsonb)
                      from (select * from public.seller_login_events where seller_id = p_seller_id order by created_at desc limit 20) e)
  ) into v;
  return v;
end; $fn$;
grant execute on function public.admin_seller_detail(uuid) to authenticated;

-- H. admin_login_audit
create or replace function public.admin_login_audit(p_seller_id uuid default null, p_limit int default 100)
returns jsonb language plpgsql security definer set search_path to 'public'
as $fn$
begin
  if not public.is_platform_admin() then return jsonb_build_object('error','forbidden'); end if;
  return coalesce((select jsonb_agg(row_to_json(t)) from (
    select e.id, e.seller_id, coalesce(s.business_name, s.full_name, e.phone) as seller_name,
           e.phone, e.method, e.success, e.created_at
    from public.seller_login_events e
    left join public.sellers s on s.id = e.seller_id
    where p_seller_id is null or e.seller_id = p_seller_id
    order by e.created_at desc
    limit greatest(1, least(coalesce(p_limit,100), 500))
  ) t), '[]'::jsonb);
end; $fn$;
grant execute on function public.admin_login_audit(uuid, int) to authenticated;

-- I. admin_actions_log
create or replace function public.admin_actions_log(p_limit int default 100)
returns jsonb language plpgsql security definer set search_path to 'public'
as $fn$
begin
  if not public.is_platform_admin() then return jsonb_build_object('error','forbidden'); end if;
  return coalesce((select jsonb_agg(row_to_json(t)) from (
    select a.id, a.action, a.target_seller_id, coalesce(s.business_name, s.full_name) as seller_name,
           a.detail, a.created_at, ad.full_name as admin_name
    from public.admin_actions a
    left join public.sellers s on s.id = a.target_seller_id
    left join public.admins ad on ad.auth_user_id = a.admin_id
    order by a.created_at desc
    limit greatest(1, least(coalesce(p_limit,100), 500))
  ) t), '[]'::jsonb);
end; $fn$;
grant execute on function public.admin_actions_log(int) to authenticated;
