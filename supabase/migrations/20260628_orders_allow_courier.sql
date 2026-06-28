-- The storefront + dashboard use 'courier' as the delivery_method value for a
-- third-party courier, but the orders.delivery_method CHECK constraint only
-- permitted 'local_courier' — so every courier checkout failed the constraint
-- and create_storefront_order returned "Failed to create order".
-- Add 'courier' to the allowed set (keep 'local_courier' for backward safety).
alter table public.orders drop constraint if exists orders_delivery_method_check;
alter table public.orders add constraint orders_delivery_method_check
  check (delivery_method = any (array['self_delivery','taxi','bus','courier','local_courier','pickup']));
