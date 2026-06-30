-- Two-tier fee enforcement: a notify-only WARNING below the suspension cap.
-- Thresholds are in fees-owed; at 5% these map to M2,000 (warn) / M2,500 (suspend)
-- of gross sales.
alter table public.platform_config add column if not exists warning_threshold numeric;

-- New policy: warn at M100 owed (≈ M2,000 sales), suspend at M125 owed (≈ M2,500
-- sales). Lower than the old M500 cap to reduce unsecured fee credit / default risk.
update public.platform_config set warning_threshold = 100, suspension_threshold = 125, updated_at = now();

-- Surface the seller's outstanding balance + computed fee_state so the dashboard
-- can show a warning banner before the store is ever suspended.
create or replace function public.seller_account_status(p_seller_id uuid)
returns jsonb language sql security definer set search_path to 'public' as $function$
  select case when public.owns_seller(p_seller_id) then (
    select jsonb_build_object(
      'seller_status', coalesce(s.seller_status, 'active'),
      'is_active', coalesce(s.is_active, true),
      'suspension_reason', s.suspension_reason,
      'outstanding', bal.outstanding,
      'warning_threshold', cfg.warning_threshold,
      'suspension_threshold', cfg.suspension_threshold,
      'fee_state', case
        when coalesce(s.seller_status, 'active') <> 'active' then 'suspended'
        when cfg.warning_threshold is not null and cfg.warning_threshold > 0 and bal.outstanding >= cfg.warning_threshold then 'warning'
        else 'ok' end
    )
    from public.sellers s
    cross join lateral (select coalesce(suspension_threshold, 500) as suspension_threshold, warning_threshold from public.platform_config limit 1) cfg
    cross join lateral (select coalesce((select sum(fee_amount) from public.platform_fees where seller_id = s.id), 0)
                             - coalesce((select sum(amount) from public.seller_settlements where seller_id = s.id), 0) as outstanding) bal
    where s.id = p_seller_id
  ) else null end;
$function$;
