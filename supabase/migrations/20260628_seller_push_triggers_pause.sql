-- Pause the seller-push triggers until the send-push edge function is redeployed
-- with audience='seller' support. The trigger FUNCTIONS remain defined; only the
-- triggers are dropped so no calls hit the (currently old) function — which would
-- otherwise mis-route a seller-targeted call back to the buyer's devices.
-- Re-create the two triggers (see 20260628_seller_web_push.sql) once send-push
-- has been redeployed.
drop trigger if exists push_seller_on_buyer_message on public.order_messages;
drop trigger if exists push_seller_on_new_order on public.orders;
