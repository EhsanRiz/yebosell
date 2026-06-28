-- Keep fee-driven suspensions consistent when the admin changes the suspension
-- threshold: re-evaluate every seller. Active sellers now at/over the threshold
-- get suspended; fee-suspended sellers now under it get reactivated. Manual policy
-- suspensions (reason not fee-related) are left untouched, and non-active statuses
-- (retired/deactivated) are never auto-suspended.
create or replace function public.reevaluate_fee_suspensions()
returns void language plpgsql security definer set search_path = public as $$
declare v_threshold numeric;
begin
  select coalesce(suspension_threshold,500) into v_threshold from platform_config limit 1;
  if v_threshold is null or v_threshold <= 0 then return; end if;

  update sellers s
     set seller_status = 'suspended', is_active = true,
         suspension_reason = 'Outstanding platform fees of M' || to_char(bal.outstanding,'FM999990.00')
           || ' reached the M' || to_char(v_threshold,'FM999990.00') || ' limit. Settle your balance to reactivate.',
         updated_at = now()
  from (
    select s2.id,
           coalesce((select sum(fee_amount) from platform_fees where seller_id = s2.id),0)
         - coalesce((select sum(amount) from seller_settlements where seller_id = s2.id),0) as outstanding
    from sellers s2
  ) bal
  where s.id = bal.id and coalesce(s.seller_status,'active') = 'active' and bal.outstanding >= v_threshold;

  update sellers s
     set seller_status = 'active', is_active = true, suspension_reason = null, updated_at = now()
  from (
    select s2.id,
           coalesce((select sum(fee_amount) from platform_fees where seller_id = s2.id),0)
         - coalesce((select sum(amount) from seller_settlements where seller_id = s2.id),0) as outstanding
    from sellers s2
  ) bal
  where s.id = bal.id and s.seller_status = 'suspended'
    and s.suspension_reason ilike '%platform fee%' and bal.outstanding < v_threshold;
end $$;

create or replace function public.tg_config_reevaluate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if NEW.suspension_threshold is distinct from OLD.suspension_threshold then
    perform public.reevaluate_fee_suspensions();
  end if;
  return NEW;
end $$;
drop trigger if exists config_reevaluate on public.platform_config;
create trigger config_reevaluate after update on public.platform_config
  for each row execute function public.tg_config_reevaluate();
