-- Stage 3e — smooth out product actions

-- 1. product-photos bucket: accept the image types phones actually produce, and
--    match the dashboard's 5MB client-side limit (was 2MB, causing confusing failures).
UPDATE storage.buckets
   SET allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp','image/avif','image/gif'],
       file_size_limit = 5242880
 WHERE id = 'product-photos';

-- 2. Allow deleting a product that appears in past orders: keep the order line
--    (product_name is denormalised on order_items) but null the product link
--    instead of blocking the delete with a FK violation.
ALTER TABLE public.order_items DROP CONSTRAINT IF EXISTS order_items_product_id_fkey;
ALTER TABLE public.order_items
  ADD CONSTRAINT order_items_product_id_fkey
  FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;

-- NOTE (frontend, dashboard/index.html): the seller dashboard now requires an
-- active Supabase session for write actions. After Stage 3b/3c, PIN-only login
-- (no session) acts as `anon`, so product/photo writes fail. The dashboard now
-- forces a one-time SMS-OTP verification when a device has no session, and won't
-- enter a write-disabled state from a stale localStorage seller.
