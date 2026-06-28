-- Suspension reason + a seller-readable status RPC so a suspended seller sees a
-- clear banner/notification on their dashboard explaining why and how to fix it.

alter table public.sellers add column if not exists suspension_reason text;

-- Extend admin_set_seller_status with an optional reason (stored on suspend/
-- deactivate, cleared on reactivate). 3-arg with default keeps 2-arg callers working.
drop function if exists public.admin_set_seller_status(uuid, text);
create or replace function public.admin_set_seller_status(p_seller_id uuid, p_status text, p_reason text default null)
returns jsonb language plpgsql security definer set search_path to 'public'
as $fn$
declare v_active boolean; v_name text; v_reason text;
begin
  if not public.is_platform_admin() then return jsonb_build_object('error','forbidden'); end if;
  if p_status not in ('active','suspended','deactivated') then
    return jsonb_build_object('error','badstatus','message','Invalid status');
  end if;
  v_active := (p_status <> 'deactivated');
  v_reason := nullif(btrim(coalesce(p_reason,'')), '');
  update public.sellers
     set seller_status = p_status,
         is_active = v_active,
         suspension_reason = case when p_status = 'active' then null else v_reason end,
         updated_at = now()
   where id = p_seller_id returning business_name into v_name;
  if not found then return jsonb_build_object('error','notfound'); end if;
  insert into public.admin_actions(admin_id, action, target_seller_id, detail)
  values (auth.uid(), 'set_status', p_seller_id, p_status || coalesce(' — ' || v_reason, ''));
  return jsonb_build_object('ok', true, 'status', p_status, 'business_name', v_name);
end; $fn$;
revoke all on function public.admin_set_seller_status(uuid, text, text) from public, anon;
grant execute on function public.admin_set_seller_status(uuid, text, text) to authenticated;

-- The seller reads their own live status + reason (owns_seller-guarded; bypasses
-- column grants on the sellers table).
create or replace function public.seller_account_status(p_seller_id uuid)
returns jsonb language sql security definer set search_path to 'public' as $fn$
  select case when public.owns_seller(p_seller_id) then (
      select jsonb_build_object(
        'seller_status', coalesce(s.seller_status, 'active'),
        'is_active', coalesce(s.is_active, true),
        'suspension_reason', s.suspension_reason
      ) from public.sellers s where s.id = p_seller_id
    ) else null end;
$fn$;
revoke all on function public.seller_account_status(uuid) from public, anon;
grant execute on function public.seller_account_status(uuid) to authenticated;
