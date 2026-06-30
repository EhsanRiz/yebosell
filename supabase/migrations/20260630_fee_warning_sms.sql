-- Add SMS (BulkSMS via the send-sms edge function) alongside the web push on the
-- fee warning and suspension events. SMS reaches sellers who haven't installed
-- the PWA / granted push — important for a money/closure notice.
create or replace function public.tg_platform_fee_sync()
returns trigger language plpgsql security definer set search_path to 'public', 'net' as $function$
declare
  v_fee_type text; v_fee_value numeric; v_trial int; v_paid_count bigint; v_base numeric; v_fee numeric;
  v_threshold numeric; v_warn numeric; v_outstanding numeric;
  v_url text; v_key text; v_active boolean; v_warned timestamptz; v_phone text;
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
    if v_trial > 0 and v_paid_count < v_trial then return NEW; end if;
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

    if v_threshold > 0 and v_outstanding >= v_threshold then
      update sellers
         set seller_status = 'suspended', is_active = true,
             suspension_reason = 'Outstanding platform fees of M' || to_char(v_outstanding,'FM999990.00')
               || ' reached the M' || to_char(v_threshold,'FM999990.00') || ' limit. Settle your balance to reactivate.',
             updated_at = now()
       where id = NEW.seller_id and coalesce(seller_status,'active') = 'active';
      if v_active and v_url is not null then
        begin
          perform net.http_post(url := v_url || '/send-push',
            headers := jsonb_build_object('Content-Type','application/json','x-push-key', coalesce(v_key,'')),
            body := jsonb_build_object('order_id', NEW.id, 'audience','seller','event','fee_suspended',
              'preview','Your store is paused — platform fees of M' || to_char(v_outstanding,'FM999990.00') || ' are overdue. Settle to reactivate.'));
        exception when others then null; end;
        if v_phone is not null then begin
          perform net.http_post(url := v_url || '/send-sms',
            headers := jsonb_build_object('Content-Type','application/json','x-push-key', coalesce(v_key,'')),
            body := jsonb_build_object('to', v_phone,
              'body','YeboSell: Your store is paused. Platform fees of M' || to_char(v_outstanding,'FM999990.00') || ' are overdue. Settle to reactivate.'));
        exception when others then null; end; end if;
      end if;
    elsif v_warn is not null and v_warn > 0 and v_outstanding >= v_warn then
      if v_active and v_warned is null then
        if v_url is not null then
          begin
            perform net.http_post(url := v_url || '/send-push',
              headers := jsonb_build_object('Content-Type','application/json','x-push-key', coalesce(v_key,'')),
              body := jsonb_build_object('order_id', NEW.id, 'audience','seller','event','fee_warning',
                'preview','Platform fees due: M' || to_char(v_outstanding,'FM999990.00') || '. Settle to keep your store open.'));
          exception when others then null; end;
          if v_phone is not null then begin
            perform net.http_post(url := v_url || '/send-sms',
              headers := jsonb_build_object('Content-Type','application/json','x-push-key', coalesce(v_key,'')),
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
