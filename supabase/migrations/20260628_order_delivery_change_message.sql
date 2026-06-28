-- When the seller edits an order's delivery method/fee (e.g. settles a courier
-- quote, or switches the buyer to pickup), post a system message into the order
-- thread. order_messages inserts already (a) show in the buyer's message centre,
-- (b) count toward the buyer bell (sender <> 'buyer' & read_by_buyer_at is null),
-- and (c) fire tg_broadcast_order_message for instant in-app refresh. We extend
-- the existing status trigger so this rides the same single source of truth.
create or replace function public.tg_order_status_message()
returns trigger language plpgsql security definer set search_path to 'public' as $$
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

  return new;
end $$;

-- Trigger already exists (order_status_message AFTER UPDATE on public.orders) and
-- points at this function, so no trigger DDL is needed.
