-- Auto-suspend a seller when unpaid platform fees cross the suspension threshold,
-- and auto-reactivate when a settlement brings them back under (only for the
-- fee-driven suspension, identified by its reason — manual policy suspensions are
-- left alone). Extends tg_platform_fee_sync (see 20260628_fee_model_on_payment.sql).

create or replace function public.tg_platform_fee_sync()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_fee_type text; v_fee_value numeric; v_trial int; v_paid_count bigint; v_base numeric; v_fee numeric;
  v_threshold numeric; v_outstanding numeric;
begin
  if NEW.status = 'cancelled' then
    delete from platform_fees where order_id = NEW.id and status = 'pending';
    return NEW;
  end if;
  if NEW.payment_status = 'paid' and (TG_OP = 'INSERT' or coalesce(OLD.payment_status,'') <> 'paid') then
    if exists (select 1 from platform_fees where order_id = NEW.id) then return NEW; end if;
    select fee_type, fee_value, coalesce(trial_order_limit,0), coalesce(suspension_threshold,500)
      into v_fee_type, v_fee_value, v_trial, v_threshold from platform_config limit 1;
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
    if v_threshold > 0 and v_outstanding >= v_threshold then
      update sellers
         set seller_status = 'suspended', is_active = true,
             suspension_reason = 'Outstanding platform fees of M' || to_char(v_outstanding,'FM999990.00')
               || ' reached the M' || to_char(v_threshold,'FM999990.00') || ' limit. Settle your balance to reactivate.',
             updated_at = now()
       where id = NEW.seller_id and coalesce(seller_status,'active') = 'active';
    end if;
  end if;
  return NEW;
end $$;

create or replace function public.tg_fee_settlement_reactivate()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_threshold numeric; v_outstanding numeric;
begin
  select coalesce(suspension_threshold,500) into v_threshold from platform_config limit 1;
  select coalesce((select sum(fee_amount) from platform_fees where seller_id = NEW.seller_id), 0)
       - coalesce((select sum(amount) from seller_settlements where seller_id = NEW.seller_id), 0)
    into v_outstanding;
  if v_outstanding < v_threshold then
    update sellers
       set seller_status = 'active', is_active = true, suspension_reason = null, updated_at = now()
     where id = NEW.seller_id and seller_status = 'suspended' and suspension_reason ilike '%platform fee%';
  end if;
  return NEW;
end $$;
drop trigger if exists fee_settlement_reactivate on public.seller_settlements;
create trigger fee_settlement_reactivate after insert on public.seller_settlements
  for each row execute function public.tg_fee_settlement_reactivate();
