-- ============================================================================
-- Unify order lifecycle — one stage shown identically to buyer & seller
-- Merges the previously-split `status` + `delivery_status` into a single
-- progression on public.orders.status:
--   new -> confirmed -> preparing -> (ready_for_pickup | out_for_delivery) -> delivered
--   (+ cancelled, a separate terminal state)
-- Step 4 is delivery-method-aware: pickup orders use `ready_for_pickup`;
-- all other methods use `out_for_delivery`. Payment remains its own axis
-- (payment_status). `delivery_status` is kept for back-compat but is no
-- longer the source of truth for progress.
-- ============================================================================

-- 1) Widen the status CHECK to allow the unified values (legacy values kept so
--    the backfill update below can't transiently violate the constraint).
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check
  check (status = any (array[
    'new','confirmed','preparing','paid','shipped','dispatched',
    'ready_for_pickup','out_for_delivery','delivered','cancelled'
  ]));

-- 2) Backfill existing orders to the furthest-along unified stage, derived from
--    the max progress of their old status and delivery_status.
update public.orders o
set status = sub.new_status
from (
  select id,
    case
      when status = 'cancelled' then 'cancelled'
      else (
        case greatest(
          case status
            when 'new' then 0 when 'confirmed' then 1 when 'paid' then 1
            when 'preparing' then 2 when 'dispatched' then 3 when 'shipped' then 3
            when 'delivered' then 4 else 0 end,
          case delivery_status
            when 'pending' then 0 when 'ready_for_pickup' then 3
            when 'out_for_delivery' then 3 when 'in_transit' then 3
            when 'delivered' then 4 else 0 end
        )
          when 0 then 'new'
          when 1 then 'confirmed'
          when 2 then 'preparing'
          when 3 then case when delivery_method = 'pickup' then 'ready_for_pickup' else 'out_for_delivery' end
          when 4 then 'delivered'
          else 'new'
        end
      )
    end as new_status
  from public.orders
) sub
where o.id = sub.id and o.status is distinct from sub.new_status;
