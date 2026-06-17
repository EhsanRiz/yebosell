-- ============================================================================
-- Stage 3d — defense-in-depth hardening (advisor cleanup)
-- ----------------------------------------------------------------------------
-- 1. admin_* RPCs: revoke EXECUTE from anon. They already self-guard with
--    is_platform_admin(), but anon should never be able to invoke them. Kept
--    executable by `authenticated` (the admin signs in → authenticated session).
-- 2. generate_order_number: pin search_path (was role-mutable).
-- 3. storage product-photos bucket: writes were granted to PUBLIC (anon) —
--    anyone with the anon key could delete/overwrite/upload product images.
--    Scope INSERT/UPDATE/DELETE to authenticated; drop the broad public-listing
--    SELECT policy. The bucket is public, so object display via getPublicUrl is
--    unaffected (public serving bypasses RLS); only arbitrary listing is removed.
-- ============================================================================

-- 1. admin_* RPCs — no anon execution
REVOKE EXECUTE ON FUNCTION public.admin_actions_log(integer)            FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_login_audit(uuid, integer)      FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_reset_seller_pin(uuid, text)    FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_seller_detail(uuid)             FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_session()                       FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_set_seller_status(uuid, text)   FROM anon;

-- 2. generate_order_number — pin search_path
ALTER FUNCTION public.generate_order_number() SET search_path = public;

-- 3. storage product-photos — anon can no longer write or list
DROP POLICY IF EXISTS "Allow uploads"      ON storage.objects;
DROP POLICY IF EXISTS "Allow updates"      ON storage.objects;
DROP POLICY IF EXISTS "Allow deletes"      ON storage.objects;
DROP POLICY IF EXISTS "Public read access" ON storage.objects;

CREATE POLICY "product_photos_insert_auth" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'product-photos');
CREATE POLICY "product_photos_update_auth" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'product-photos') WITH CHECK (bucket_id = 'product-photos');
CREATE POLICY "product_photos_delete_auth" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'product-photos');
