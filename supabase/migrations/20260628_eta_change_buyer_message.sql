-- When the ETA is set (on confirm) or revised (seller edits the date), tell the
-- buyer automatically: a system message in the order thread, which the buyer's
-- bell feed surfaces and the track page reflects live. Extends the existing
-- status/delivery message trigger.
create or replace function public.tg_order_status_message()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare v_kind text;
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status and new.status is not null then
    insert into public.order_messages (order_id, seller_id, sender, kind, body, meta)
    values (new.id, new.seller_id, 'system', 'status',
            'Order status: ' || initcap(replace(new.status, '_', ' ')),
            jsonb_build_object('status', new.status));
  end if;

  -- Delivery method / fee change -> notify the buyer (chat + bell + live total).
  if tg_op = 'UPDATE'
     and (new.delivery_method is distinct from old.delivery_method
          or new.delivery_fee is distinct from old.delivery_fee) then
    insert into public.order_messages (order_id, seller_id, sender, kind, body, meta)
    values (new.id, new.seller_id, 'system', 'status',
            case
              when new.delivery_method = 'pickup'
                then 'Delivery changed to Customer Pickup — no delivery fee. New total: M'
                     || to_char(coalesce(new.total,0),'FM999990.00')
              else
                'Delivery updated: ' || initcap(replace(coalesce(new.delivery_method,''), '_', ' '))
                || case when coalesce(new.delivery_fee,0) > 0
                        then ' · fee M' || to_char(new.delivery_fee,'FM999990.00') else '' end
                || ' · New total: M' || to_char(coalesce(new.total,0),'FM999990.00')
            end,
            jsonb_build_object('delivery_method', new.delivery_method,
                               'delivery_fee', new.delivery_fee, 'total', new.total));
  end if;

  -- ETA set / revised -> tell the buyer. Track page ETA updates live.
  if tg_op = 'UPDATE' and new.eta_date is distinct from old.eta_date and new.eta_date is not null then
    v_kind := case when new.delivery_method = 'pickup' then 'ready-for-pickup' else 'delivery' end;
    insert into public.order_messages (order_id, seller_id, sender, kind, body, meta)
    values (new.id, new.seller_id, 'system', 'status',
            case when old.eta_date is null
              then 'Estimated ' || v_kind || ' date: ' || to_char(new.eta_date, 'Dy, DD Mon')
              else 'Estimated ' || v_kind || ' date updated to ' || to_char(new.eta_date, 'Dy, DD Mon')
            end,
            jsonb_build_object('eta_date', new.eta_date));
  end if;

  return new;
end $function$;
