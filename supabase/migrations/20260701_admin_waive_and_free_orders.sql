-- Pilot fee controls (open-ended, admin-driven — no time-based automation):
--  * sellers.free_orders_remaining — a counter of "next N paid orders are free",
--    consumed by the fee trigger. Lets us reward sellers with 10 free orders after
--    the test, independent of their order history.
--  * admin_waive_seller_fees — one action that zeroes a seller's outstanding balance
--    (records a 'waived' settlement, marks pending fees settled, reactivates if the
--    store was paused for fees).
--  * admin_grant_free_orders — grant (or deduct) free orders as a reward.

alter table public.sellers add column if not exists free_orders_remaining int not null default 0;

-- Fee trigger: after the launch-trial check, consume a free order (if any) before charging.
create or replace function public.tg_platform_fee_sync()
returns trigger language plpgsql security definer set search_path to 'public', 'net' as $function$
declare
  v_fee_type text; v_fee_value numeric; v_trial int; v_paid_count bigint; v_base numeric; v_fee numeric;
  v_threshold numeric; v_warn numeric; v_outstanding numeric;
  v_url text; v_key text; v_anon text; v_headers jsonb; v_active boolean; v_warned timestamptz; v_phone text;
  v_eligible boolean; v_free int;
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
    -- Launch trial (first-10 sellers): first N paid orders free.
    if v_trial > 0 and v_eligible and v_paid_count < v_trial then return NEW; end if;
    -- Granted free orders (e.g. pilot reward): consume one and charge nothing.
    select coalesce(free_orders_remaining, 0) into v_free from sellers where id = NEW.seller_id;
    if v_free > 0 then
      update sellers set free_orders_remaining = greatest(0, v_free - 1), updated_at = now() where id = NEW.seller_id;
      return NEW;
    end if;
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

-- Admin: waive a seller's entire outstanding balance in one action (atomic + logged).
create or replace function public.admin_waive_seller_fees(p_seller_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_out numeric;
begin
  if not is_platform_admin() then return jsonb_build_object('error','forbidden'); end if;
  if not exists (select 1 from sellers where id = p_seller_id) then return jsonb_build_object('error','notfound'); end if;
  select coalesce((select sum(fee_amount) from platform_fees where seller_id = p_seller_id), 0)
       - coalesce((select sum(amount) from seller_settlements where seller_id = p_seller_id), 0)
    into v_out;
  if coalesce(v_out,0) <= 0 then return jsonb_build_object('ok', true, 'waived', 0, 'message', 'No outstanding balance to waive'); end if;
  insert into seller_settlements (seller_id, amount, method, reference, notes)
  values (p_seller_id, v_out, 'waived', 'admin_waiver', nullif(btrim(coalesce(p_reason,'')), ''));
  update platform_fees set status = 'settled', settled_at = now()
   where seller_id = p_seller_id and status = 'pending';
  update sellers set seller_status = 'active', is_active = true, suspension_reason = null, fee_warned_at = null, updated_at = now()
   where id = p_seller_id and seller_status = 'suspended' and suspension_reason ilike '%platform fee%';
  insert into admin_actions (admin_id, action, target_seller_id, detail)
  values (auth.uid(), 'waive_fees', p_seller_id,
          'Waived M' || to_char(v_out,'FM999990.00') || coalesce(' — ' || nullif(btrim(coalesce(p_reason,'')), ''), ''));
  return jsonb_build_object('ok', true, 'waived', v_out);
end $function$;

grant execute on function public.admin_waive_seller_fees(uuid, text) to authenticated;

-- Admin: grant (or deduct, with a negative count) free orders as a reward.
create or replace function public.admin_grant_free_orders(p_seller_id uuid, p_count int, p_reason text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_new int;
begin
  if not is_platform_admin() then return jsonb_build_object('error','forbidden'); end if;
  if coalesce(p_count,0) = 0 then return jsonb_build_object('error','badcount','message','Count must be non-zero'); end if;
  update sellers set free_orders_remaining = greatest(0, coalesce(free_orders_remaining,0) + p_count), updated_at = now()
   where id = p_seller_id returning free_orders_remaining into v_new;
  if not found then return jsonb_build_object('error','notfound'); end if;
  insert into admin_actions (admin_id, action, target_seller_id, detail)
  values (auth.uid(), 'grant_free_orders', p_seller_id,
          (case when p_count > 0 then '+' else '' end) || p_count || ' free orders (now ' || v_new || ')'
          || coalesce(' — ' || nullif(btrim(coalesce(p_reason,'')), ''), ''));
  return jsonb_build_object('ok', true, 'free_orders_remaining', v_new);
end $function$;

grant execute on function public.admin_grant_free_orders(uuid, int, text) to authenticated;

-- Surface the free-orders balance to the seller dashboard.
create or replace function public.get_seller_fee_summary(p_seller_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_total_fees numeric; v_settled numeric; v_pending numeric;
  v_paid_count bigint; v_order_count bigint;
  v_trial_limit int; v_threshold numeric; v_fee_pct numeric; v_eligible boolean; v_free int;
begin
  if not owns_seller(p_seller_id) then return jsonb_build_object('error','forbidden'); end if;
  select coalesce(sum(fee_amount),0) into v_total_fees from platform_fees where seller_id = p_seller_id;
  select coalesce(sum(amount),0) into v_settled from seller_settlements where seller_id = p_seller_id;
  v_pending := greatest(0, v_total_fees - v_settled);
  select count(*) into v_order_count from orders where seller_id = p_seller_id;
  select count(*) into v_paid_count from orders where seller_id = p_seller_id and payment_status = 'paid';
  select coalesce(trial_order_limit,0), coalesce(suspension_threshold,500), coalesce(fee_value,5)
    into v_trial_limit, v_threshold, v_fee_pct from platform_config limit 1;
  select coalesce(fee_trial_eligible, false), coalesce(free_orders_remaining, 0) into v_eligible, v_free from sellers where id = p_seller_id;
  return jsonb_build_object(
    'pending_fees',         v_pending,
    'settled_fees',         v_settled,
    'order_count',          v_order_count,
    'trial_order_limit',    v_trial_limit,
    'orders_in_trial',      greatest(0, v_trial_limit - v_paid_count),
    'in_trial',             (v_eligible and v_trial_limit > 0 and v_paid_count < v_trial_limit),
    'trial_eligible',       v_eligible,
    'free_orders_remaining', v_free,
    'suspension_threshold', v_threshold,
    'fee_pct',              v_fee_pct,
    'near_suspension',      (v_pending >= v_threshold * 0.8),
    'suspended',            (v_pending >= v_threshold)
  );
end; $function$;
