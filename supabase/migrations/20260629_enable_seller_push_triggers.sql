-- Enable the (previously paused) seller-push triggers now that the send-push
-- edge function handles audience='seller' (fan-out to the store's own devices).
-- New storefront orders and buyer messages push the seller's subscribed devices.
drop trigger if exists push_seller_new_order on public.orders;
create trigger push_seller_new_order
  after insert on public.orders
  for each row
  when (NEW.source = 'storefront')
  execute function public.tg_push_seller_on_new_order();

drop trigger if exists push_seller_buyer_message on public.order_messages;
create trigger push_seller_buyer_message
  after insert on public.order_messages
  for each row
  when (NEW.sender = 'buyer')
  execute function public.tg_push_seller_on_buyer_message();
