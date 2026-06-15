-- Pure-admin model: admin is no longer a seller.
-- - Dedicated public.admins table holds the platform operator identity.
-- - is_platform_admin() repointed from sellers.is_admin to the admins table
--   (centralized, so every RLS policy that calls it follows automatically).
-- - admin_session() RPC returns the admin record for the current auth session.
-- - link_current_seller() now ignores inactive sellers, so the admin's phone
--   no longer resolves to a (retired) seller row.
-- - MyShop retired (data/history kept, login detached); stale +27 admin row cleared.
--
-- ROLLBACK NOTES:
--   create or replace function is_platform_admin() ... from sellers where auth_user_id=auth.uid() and is_admin;
--   update sellers set is_admin=true, is_active=true, seller_status='active',
--          auth_user_id='93f6f34e-c3dc-4096-a5e8-427ad27681bb'
--    where id='b3029b6a-81a2-4e57-bb20-4997eac7d513';
--   drop function admin_session(); drop table admins;

-- 0. Extend seller_status to support retired + deactivated
alter table public.sellers drop constraint if exists sellers_seller_status_check;
alter table public.sellers add constraint sellers_seller_status_check
  check (seller_status = any (array['active','suspended','trial','retired','deactivated']));

-- 1. Dedicated admins table (pure admin, not a seller)
create table if not exists public.admins (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  phone text,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;
drop policy if exists admins_self_select on public.admins;
create policy admins_self_select on public.admins
  for select to authenticated using (auth_user_id = auth.uid());

-- 2. Seed the current working login as the sole admin
insert into public.admins (auth_user_id, full_name, email, phone)
values ('93f6f34e-c3dc-4096-a5e8-427ad27681bb','Ehsan Rizvi','sehsan.rizvi@gmail.com','+26656300091')
on conflict (auth_user_id) do nothing;

-- 3. Repoint is_platform_admin() to the admins table
create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path to 'public'
as $fn$ select exists (select 1 from public.admins where auth_user_id = auth.uid()) $fn$;

-- 4. admin_session RPC
create or replace function public.admin_session()
returns jsonb language sql stable security definer set search_path to 'public'
as $fn$
  select case when exists (select 1 from public.admins where auth_user_id = auth.uid())
    then jsonb_build_object('admin', (select to_jsonb(a) from public.admins a where a.auth_user_id = auth.uid()))
    else jsonb_build_object('error','notadmin')
  end
$fn$;
grant execute on function public.admin_session() to authenticated, anon;

-- 5. Seller linking ignores inactive/retired sellers
create or replace function public.link_current_seller()
returns jsonb language plpgsql security definer set search_path to 'public'
as $fn$
declare
  v_uid uuid := auth.uid();
  v_phone text;
  v_seller public.sellers%rowtype;
begin
  if v_uid is null then
    return jsonb_build_object('error','noauth','message','Not authenticated');
  end if;
  select phone into v_phone from auth.users where id = v_uid;
  select s.* into v_seller from public.sellers s
   where regexp_replace(s.phone, '\D', '', 'g') = regexp_replace(coalesce(v_phone,''), '\D', '', 'g')
     and s.is_active = true
   limit 1;
  if not found then
    return jsonb_build_object('error','noseller','message','No seller account exists for this number. Please register first.');
  end if;
  update public.sellers set auth_user_id = v_uid
   where id = v_seller.id and (auth_user_id is distinct from v_uid);
  select s.* into v_seller from public.sellers s where id = v_seller.id;
  return jsonb_build_object('seller', to_jsonb(v_seller));
end;
$fn$;

-- 6. Retire MyShop + clear stale +27 admin row
update public.sellers
   set is_admin=false, is_active=false, seller_status='retired', auth_user_id=null
 where id='b3029b6a-81a2-4e57-bb20-4997eac7d513';
update public.sellers
   set is_admin=false, is_active=false, seller_status='retired'
 where id='bd224a20-2131-449c-a765-21ce2f9831ff';
