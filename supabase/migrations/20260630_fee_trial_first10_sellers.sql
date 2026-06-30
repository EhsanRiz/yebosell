-- Limit the "first 10 paid orders free" trial to the first 10 REAL sellers to join
-- (a launch offer), instead of granting it to every seller forever.
--
-- Mechanism: a per-seller flag `fee_trial_eligible`. It is granted at registration
-- while fewer than 10 sellers already hold it, so exactly the first 10 genuine
-- sign-ups get the trial; sellers 11+ pay the 5% fee from their first paid order.
-- Demo/internal/test accounts are never auto-granted (they aren't created via
-- seller_register and are excluded from the backfill).

-- ---- Flag + backfill -----------------------------------------------------------
alter table public.sellers add column if not exists fee_trial_eligible boolean not null default false;

-- Backfill the earliest genuine sellers (non-demo, active, excluding the internal
-- "Test Store" pilot account) up to the 10-slot cap. Today this is just HelpSell.
update public.sellers set fee_trial_eligible = true
 where id in (
   select id from public.sellers
    where coalesce(is_demo, false) = false
      and coalesce(seller_status, 'active') = 'active'
      and business_name <> 'Test Store'
    order by created_at
    limit 10
 );

-- ---- Fee trigger: trial only applies to eligible sellers -----------------------
create or replace function public.tg_platform_fee_sync()
returns trigger language plpgsql security definer set search_path to 'public', 'net' as $function$
declare
  v_fee_type text; v_fee_value numeric; v_trial int; v_paid_count bigint; v_base numeric; v_fee numeric;
  v_threshold numeric; v_warn numeric; v_outstanding numeric;
  v_url text; v_key text; v_anon text; v_headers jsonb; v_active boolean; v_warned timestamptz; v_phone text;
  v_eligible boolean;
begin
  if NEW.status = 'cancelled' then
    delete from platform_fees where order_id = NEW.id and status = 'pending';
    return NEW;
  end if;
  if NEW.payment_status = 'paid' and (TG_OP = 'INSERT' or coalesce(OLD.payment_status,'') <> 'paid') then
    if exists (select 1 from platform_fees where order_id = NEW.id) then return NEW; end if;
    select fee_type, fee_value, coalesce(trial_order_limit,0), coalesce(suspension_threshold,500), warning_threshold
      into v_fee_type, v_fee_value, v_trial, v_threshold, v_warn from platform_config limit 1;
    if v_fee_value is null then return NEW; end if;
    select count(*) into v_paid_count from orders where seller_id = NEW.seller_id and payment_status = 'paid' and id <> NEW.id;
    select coalesce(fee_trial_eligible, false) into v_eligible from sellers where id = NEW.seller_id;
    -- Free trial only for the first-10 launch sellers; everyone else is charged from order 1.
    if v_trial > 0 and v_eligible and v_paid_count < v_trial then return NEW; end if;
    v_base := greatest(0, coalesce(NEW.total,0) - coalesce(NEW.delivery_fee,0));
    v_fee := case when v_fee_type = 'percentage' then v_base * v_fee_value / 100 else v_fee_value end;
    insert into platform_fees (order_id, seller_id, order_total, fee_amount, status)
    values (NEW.id, NEW.seller_id, NEW.total, round(v_fee * 100) / 100, 'pending');

    select coalesce((select sum(fee_amount) from platform_fees where seller_id = NEW.seller_id), 0)
         - coalesce((select sum(amount) from seller_settlements where seller_id = NEW.seller_id), 0)
      into v_outstanding;
    select coalesce(seller_status,'active') = 'active', fee_warned_at, coalesce(phone, seller_phone)
      into v_active, v_warned, v_phone from sellers where id = NEW.seller_id;
    select value into v_url from private_config where key = 'functions_base_url';
    select value into v_key from private_config where key = 'push_shared_secret';
    select value into v_anon from private_config where key = 'anon_key';
    v_headers := jsonb_build_object('Content-Type','application/json','x-push-key', coalesce(v_key,''),
                                    'Authorization','Bearer ' || coalesce(v_anon,''));

    if v_threshold > 0 and v_outstanding >= v_threshold then
      update sellers
         set seller_status = 'suspended', is_active = true,
             suspension_reason = 'Outstanding platform fees of M' || to_char(v_outstanding,'FM999990.00')
               || ' reached the M' || to_char(v_threshold,'FM999990.00') || ' limit. Settle your balance to reactivate.',
             updated_at = now()
       where id = NEW.seller_id and coalesce(seller_status,'active') = 'active';
      if v_active and v_url is not null then
        begin
          perform net.http_post(url := v_url || '/send-push', headers := v_headers,
            body := jsonb_build_object('order_id', NEW.id, 'audience','seller','event','fee_suspended',
              'preview','Your store is paused — platform fees of M' || to_char(v_outstanding,'FM999990.00') || ' are overdue. Settle to reactivate.'));
        exception when others then null; end;
        if v_phone is not null then begin
          perform net.http_post(url := v_url || '/send-sms', headers := v_headers,
            body := jsonb_build_object('to', v_phone,
              'body','YeboSell: Your store is paused. Platform fees of M' || to_char(v_outstanding,'FM999990.00') || ' are overdue. Settle to reactivate.'));
        exception when others then null; end; end if;
      end if;
    elsif v_warn is not null and v_warn > 0 and v_outstanding >= v_warn then
      if v_active and v_warned is null then
        if v_url is not null then
          begin
            perform net.http_post(url := v_url || '/send-push', headers := v_headers,
              body := jsonb_build_object('order_id', NEW.id, 'audience','seller','event','fee_warning',
                'preview','Platform fees due: M' || to_char(v_outstanding,'FM999990.00') || '. Settle to keep your store open.'));
          exception when others then null; end;
          if v_phone is not null then begin
            perform net.http_post(url := v_url || '/send-sms', headers := v_headers,
              body := jsonb_build_object('to', v_phone,
                'body','YeboSell: Platform fees of M' || to_char(v_outstanding,'FM999990.00') || ' are due. Please settle to keep your store open.'));
          exception when others then null; end; end if;
        end if;
        update sellers set fee_warned_at = now() where id = NEW.seller_id;
      end if;
    end if;
  end if;
  return NEW;
end $function$;

-- ---- Fee summary RPC: in_trial only true for eligible sellers ------------------
create or replace function public.get_seller_fee_summary(p_seller_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_total_fees numeric; v_settled numeric; v_pending numeric;
  v_paid_count bigint; v_order_count bigint;
  v_trial_limit int; v_threshold numeric; v_fee_pct numeric; v_eligible boolean;
begin
  if not owns_seller(p_seller_id) then return jsonb_build_object('error','forbidden'); end if;
  select coalesce(sum(fee_amount),0) into v_total_fees from platform_fees where seller_id = p_seller_id;
  select coalesce(sum(amount),0) into v_settled from seller_settlements where seller_id = p_seller_id;
  v_pending := greatest(0, v_total_fees - v_settled);
  select count(*) into v_order_count from orders where seller_id = p_seller_id;
  select count(*) into v_paid_count from orders where seller_id = p_seller_id and payment_status = 'paid';
  select coalesce(trial_order_limit,0), coalesce(suspension_threshold,500), coalesce(fee_value,5)
    into v_trial_limit, v_threshold, v_fee_pct from platform_config limit 1;
  select coalesce(fee_trial_eligible, false) into v_eligible from sellers where id = p_seller_id;
  return jsonb_build_object(
    'pending_fees',         v_pending,
    'settled_fees',         v_settled,
    'order_count',          v_order_count,
    'trial_order_limit',    v_trial_limit,
    'orders_in_trial',      greatest(0, v_trial_limit - v_paid_count),
    'in_trial',             (v_eligible and v_trial_limit > 0 and v_paid_count < v_trial_limit),
    'trial_eligible',       v_eligible,
    'suspension_threshold', v_threshold,
    'fee_pct',              v_fee_pct,
    'near_suspension',      (v_pending >= v_threshold * 0.8),
    'suspended',            (v_pending >= v_threshold)
  );
end; $function$;

-- ---- Registration: grant a trial slot while fewer than 10 are taken ------------
create or replace function public.seller_register(p_phone text, p_otp text, p_pin text, p_full_name text, p_business_name text, p_email text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare
  v_phone text := regexp_replace(coalesce(p_phone,''), '\s', '', 'g');
  v_suffix text := right(regexp_replace(v_phone, '\D', '', 'g'), 8);
  v_otp_id uuid;
  v_slug text;
  v_new public.sellers%rowtype;
begin
  if length(coalesce(p_pin,'')) < 4 then
    return jsonb_build_object('error','pin','message','PIN must be at least 4 digits');
  end if;
  select id into v_otp_id from buyer_otps
   where right(regexp_replace(coalesce(phone,''), '\D', '', 'g'), 8) = v_suffix
     and otp_code = trim(p_otp) and used = false and expires_at > now()
   order by created_at desc limit 1;
  if v_otp_id is null then
    return jsonb_build_object('error','otp','message','Invalid or expired verification code');
  end if;
  if exists (select 1 from sellers where phone = v_phone) then
    return jsonb_build_object('error','exists','message','This number is already registered. Please log in.');
  end if;
  update buyer_otps set used = true where id = v_otp_id;
  v_slug := trim(both '-' from regexp_replace(lower(coalesce(p_business_name,'seller')), '[^a-z0-9]+', '-', 'g'));
  if v_slug = '' then v_slug := 'seller'; end if;
  if exists (select 1 from sellers where slug = v_slug) then
    v_slug := v_slug || '-' || substr(md5(random()::text), 1, 4);
  end if;
  insert into sellers (phone, full_name, business_name, slug, email)
  values (v_phone, p_full_name, p_business_name, v_slug, nullif(trim(coalesce(p_email,'')), ''))
  returning * into v_new;
  -- Launch offer: the first 10 sellers to register get the free-orders trial.
  if (select count(*) from sellers where fee_trial_eligible) < 10 then
    update sellers set fee_trial_eligible = true where id = v_new.id;
    v_new.fee_trial_eligible := true;
  end if;
  insert into seller_secrets (seller_id, pin_hash)
  values (v_new.id, extensions.crypt(p_pin, extensions.gen_salt('bf')));
  return jsonb_build_object('seller', to_jsonb(v_new));
end; $function$;
