-- Capture a seller's electronic signature (typed name + place of signing) alongside
-- the existing terms_accepted_at / terms_version, so we can produce a signed PDF
-- agreement on demand. The dashboard renders/downloads the PDF from this data;
-- admins see it via the full seller row returned by admin_seller_detail.

alter table public.sellers add column if not exists terms_signed_name text;
alter table public.sellers add column if not exists terms_signed_place text;

-- Acceptance now records the typed name + place. Drop the prior 2-arg signature so
-- the defaulted params don't create an ambiguous overload.
drop function if exists public.seller_accept_terms(uuid, text);

create or replace function public.seller_accept_terms(p_seller_id uuid, p_version text, p_name text default null, p_place text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not owns_seller(p_seller_id) then return jsonb_build_object('error','forbidden'); end if;
  update sellers
     set terms_accepted_at = now(),
         terms_version     = nullif(trim(p_version),''),
         terms_signed_name = nullif(trim(p_name),''),
         terms_signed_place= nullif(trim(p_place),''),
         updated_at        = now()
   where id = p_seller_id;
  return jsonb_build_object('ok', true, 'terms_version', p_version,
    'signed_name', nullif(trim(p_name),''), 'signed_place', nullif(trim(p_place),''), 'signed_at', now());
end $function$;

grant execute on function public.seller_accept_terms(uuid, text, text, text) to authenticated;

-- Surface the signature in the account-status RPC the dashboard already polls, so it
-- can render the signed record and regenerate the PDF later.
create or replace function public.seller_account_status(p_seller_id uuid)
returns jsonb
language sql
security definer
set search_path to 'public'
as $function$
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
        else 'ok' end,
      'terms_version', s.terms_version,
      'terms_accepted_at', s.terms_accepted_at,
      'terms_signed_name', s.terms_signed_name,
      'terms_signed_place', s.terms_signed_place
    )
    from public.sellers s
    cross join lateral (select coalesce(suspension_threshold, 500) as suspension_threshold, warning_threshold from public.platform_config limit 1) cfg
    cross join lateral (select coalesce((select sum(fee_amount) from public.platform_fees where seller_id = s.id), 0)
                             - coalesce((select sum(amount) from public.seller_settlements where seller_id = s.id), 0) as outstanding) bal
    where s.id = p_seller_id
  ) else null end;
$function$;
