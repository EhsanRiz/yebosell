-- ============================================================================
-- Re-lock admin RPC grants (defense-in-depth)
-- The admin_* RPCs had drifted back to PUBLIC EXECUTE — a later
-- `create or replace function` resets grants to the default PUBLIC, so anon
-- could invoke them again (they still self-guard via is_platform_admin(), but
-- should not be anon-callable). Revoke PUBLIC/anon; keep authenticated (the
-- admin logs in with a real Supabase session). Also strip all direct EXECUTE
-- from the trigger functions, which are only ever invoked by the trigger
-- system (EXECUTE is checked at CREATE TRIGGER time, not at firing time —
-- verified that seller-context order updates still fire their triggers).
-- ============================================================================
do $$
declare fn text;
begin
  foreach fn in array array[
    'public.admin_actions_log(integer)',
    'public.admin_login_audit(uuid, integer)',
    'public.admin_reset_seller_pin(uuid, text)',
    'public.admin_seller_detail(uuid)',
    'public.admin_session()',
    'public.admin_set_seller_status(uuid, text)'
  ] loop
    execute format('revoke execute on function %s from public', fn);
    execute format('revoke execute on function %s from anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;

revoke execute on function public.tg_broadcast_order_message() from public, anon, authenticated;
revoke execute on function public.tg_order_status_message()    from public, anon, authenticated;
revoke execute on function public.tg_push_on_message()         from public, anon, authenticated;
