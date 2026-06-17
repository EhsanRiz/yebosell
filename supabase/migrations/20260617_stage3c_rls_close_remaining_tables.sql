-- ============================================================================
-- Stage 3c — close the remaining RLS holes
-- ----------------------------------------------------------------------------
-- Stage 3b locked orders/payments/fees/etc. but LEFT these tables with
-- `USING (true)` policies AND full DML granted to the anon role. Verified live:
-- with only the public anon key, anyone could UPDATE platform_config (fees!),
-- overwrite any seller's row (incl. bank_details), forge settlements/discounts,
-- and read every seller's contact + bank details.
--
-- This migration scopes every one of those tables to:
--   * public/anon: only the storefront-safe reads it genuinely needs
--   * sellers (authenticated): their own rows, via owns_seller(seller_id)
--   * admin: everything, via is_platform_admin()
--
-- Public checkout writes that used to happen as anon (stock decrement, discount
-- usage) move into create_storefront_order() (SECURITY DEFINER) — see the
-- companion function redefinition at the bottom.
--
-- owns_seller()/is_platform_admin() are SECURITY DEFINER, so referencing them in
-- a policy on sellers/products does NOT recurse through RLS. They're wrapped in
-- (select ...) so the planner evaluates them once per query, not once per row
-- (also clears the auth_rls_initplan advisor warnings).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Backfill auth_user_id for already-onboarded sellers (same phone-match rule
-- link_current_seller() uses on login). Without this, the owner policies below
-- would lock out existing sellers until their next OTP login. Only links sellers
-- with exactly ONE matching auth.users row, to avoid mis-linking shared numbers.
-- ---------------------------------------------------------------------------
UPDATE public.sellers s
   SET auth_user_id = u.id
  FROM auth.users u
 WHERE s.auth_user_id IS NULL
   AND regexp_replace(u.phone, '\D', '', 'g') = regexp_replace(s.phone, '\D', '', 'g')
   AND (
     SELECT count(*) FROM auth.users u2
      WHERE regexp_replace(u2.phone, '\D', '', 'g') = regexp_replace(s.phone, '\D', '', 'g')
   ) = 1;

-- ---------------------------------------------------------------------------
-- SELLERS — public storefront needs to read most columns (incl. phone, which is
-- public-by-design for click-to-chat), but NOT bank_details / email / auth_user_id.
-- RLS can't hide columns, so we use column-level SELECT grants. Writes are
-- owner/admin only; registration happens through seller_register() (definer).
-- ---------------------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON public.sellers FROM anon;
REVOKE SELECT ON public.sellers FROM anon, authenticated;
GRANT SELECT (
  id, full_name, phone, business_name, location, preferred_language, is_active,
  created_at, updated_at, slug, business_description, banner_url, logo_url,
  business_hours, delivery_areas, social_links, address, seller_phone, is_admin,
  seller_status, delivery_methods, delivery_fee, delivery_fee_type,
  pickup_address, delivery_notes, is_demo
) ON public.sellers TO anon, authenticated;

DROP POLICY IF EXISTS "Anyone can read sellers"        ON public.sellers;
DROP POLICY IF EXISTS "Anyone can register"            ON public.sellers;
DROP POLICY IF EXISTS "Sellers can update own profile" ON public.sellers;

CREATE POLICY sellers_select_public ON public.sellers
  FOR SELECT USING (true);                              -- column grants limit exposure
CREATE POLICY sellers_update_owner ON public.sellers
  FOR UPDATE
  USING      ((select public.owns_seller(id)) OR (select public.is_platform_admin()))
  WITH CHECK ((select public.owns_seller(id)) OR (select public.is_platform_admin()));
-- INSERT: no policy -> only seller_register() (SECURITY DEFINER) can create rows.

-- ---------------------------------------------------------------------------
-- PLATFORM_CONFIG — admin only. The checkout RPC reads it as definer, so the
-- storefront never needs direct read access.
-- ---------------------------------------------------------------------------
REVOKE ALL ON public.platform_config FROM anon;
DROP POLICY IF EXISTS "Anyone can read config"   ON public.platform_config;
DROP POLICY IF EXISTS "Anyone can update config" ON public.platform_config;
CREATE POLICY platform_config_admin ON public.platform_config
  FOR ALL
  USING      ((select public.is_platform_admin()))
  WITH CHECK ((select public.is_platform_admin()));

-- ---------------------------------------------------------------------------
-- PRODUCTS — public reads active products; owner/admin manage. Checkout stock
-- decrement now happens server-side in create_storefront_order().
-- ---------------------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON public.products FROM anon;
DROP POLICY IF EXISTS "Full access to products" ON public.products;
CREATE POLICY products_select_public ON public.products
  FOR SELECT
  USING (is_active OR (select public.owns_seller(seller_id)) OR (select public.is_platform_admin()));
CREATE POLICY products_write_owner ON public.products
  FOR ALL
  USING      ((select public.owns_seller(seller_id)) OR (select public.is_platform_admin()))
  WITH CHECK ((select public.owns_seller(seller_id)) OR (select public.is_platform_admin()));

-- ---------------------------------------------------------------------------
-- DISCOUNT_CODES — public reads active codes (checkout validation); owner/admin
-- manage. used_count increment now happens in create_storefront_order().
-- ---------------------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON public.discount_codes FROM anon;
DROP POLICY IF EXISTS "Sellers can manage their discount codes" ON public.discount_codes;
-- keep existing "Anyone can read active discount codes" (FOR SELECT, is_active = true)
CREATE POLICY discount_codes_manage_owner ON public.discount_codes
  FOR ALL
  USING      ((select public.owns_seller(seller_id)) OR (select public.is_platform_admin()))
  WITH CHECK ((select public.owns_seller(seller_id)) OR (select public.is_platform_admin()));

-- ---------------------------------------------------------------------------
-- PRODUCT_REVIEWS — anyone reads visible reviews and can submit one; only the
-- owner/admin can edit or hide them.
-- ---------------------------------------------------------------------------
REVOKE UPDATE, DELETE ON public.product_reviews FROM anon;
DROP POLICY IF EXISTS "Allow all on product_reviews" ON public.product_reviews;
CREATE POLICY product_reviews_select_public ON public.product_reviews
  FOR SELECT
  USING (is_visible OR (select public.owns_seller(seller_id)) OR (select public.is_platform_admin()));
CREATE POLICY product_reviews_insert_public ON public.product_reviews
  FOR INSERT WITH CHECK (true);
CREATE POLICY product_reviews_update_owner ON public.product_reviews
  FOR UPDATE
  USING      ((select public.owns_seller(seller_id)) OR (select public.is_platform_admin()))
  WITH CHECK ((select public.owns_seller(seller_id)) OR (select public.is_platform_admin()));
CREATE POLICY product_reviews_delete_owner ON public.product_reviews
  FOR DELETE
  USING ((select public.owns_seller(seller_id)) OR (select public.is_platform_admin()));

-- ---------------------------------------------------------------------------
-- CUSTOMERS — owner/admin only (not read directly by any public page).
-- ---------------------------------------------------------------------------
REVOKE ALL ON public.customers FROM anon;
DROP POLICY IF EXISTS "Full access to customers" ON public.customers;
CREATE POLICY customers_owner ON public.customers
  FOR ALL
  USING      ((select public.owns_seller(seller_id)) OR (select public.is_platform_admin()))
  WITH CHECK ((select public.owns_seller(seller_id)) OR (select public.is_platform_admin()));

-- ---------------------------------------------------------------------------
-- DELIVERIES — owner/admin only.
-- ---------------------------------------------------------------------------
REVOKE ALL ON public.deliveries FROM anon;
DROP POLICY IF EXISTS "Full access to deliveries" ON public.deliveries;
CREATE POLICY deliveries_owner ON public.deliveries
  FOR ALL
  USING      ((select public.owns_seller(seller_id)) OR (select public.is_platform_admin()))
  WITH CHECK ((select public.owns_seller(seller_id)) OR (select public.is_platform_admin()));

-- ---------------------------------------------------------------------------
-- BUYER_WISHLISTS — owner/admin only (buyer-facing wishlist not yet built; if
-- added later, expose it through a scoped RPC rather than reopening this).
-- ---------------------------------------------------------------------------
REVOKE ALL ON public.buyer_wishlists FROM anon;
DROP POLICY IF EXISTS "Allow all on buyer_wishlists" ON public.buyer_wishlists;
CREATE POLICY buyer_wishlists_owner ON public.buyer_wishlists
  FOR ALL
  USING      ((select public.owns_seller(seller_id)) OR (select public.is_platform_admin()))
  WITH CHECK ((select public.owns_seller(seller_id)) OR (select public.is_platform_admin()));

-- ---------------------------------------------------------------------------
-- SELLER_SETTLEMENTS — sellers may read their own; only admin records them.
-- ---------------------------------------------------------------------------
REVOKE ALL ON public.seller_settlements FROM anon;
DROP POLICY IF EXISTS "Anyone can insert settlements" ON public.seller_settlements;
DROP POLICY IF EXISTS "Anyone can read settlements"   ON public.seller_settlements;
CREATE POLICY seller_settlements_select ON public.seller_settlements
  FOR SELECT
  USING ((select public.owns_seller(seller_id)) OR (select public.is_platform_admin()));
CREATE POLICY seller_settlements_admin_write ON public.seller_settlements
  FOR ALL
  USING      ((select public.is_platform_admin()))
  WITH CHECK ((select public.is_platform_admin()));

-- ---------------------------------------------------------------------------
-- WEBHOOK_MESSAGE_LOG — dormant WhatsApp log. No client should touch it; the
-- service role bypasses RLS, so leaving it with no policy = deny-all to clients.
-- ---------------------------------------------------------------------------
REVOKE ALL ON public.webhook_message_log FROM anon, authenticated;
DROP POLICY IF EXISTS "Service role access" ON public.webhook_message_log;

-- ============================================================================
-- create_storefront_order — now also decrements stock/variant inventory and
-- increments discount usage, so the storefront no longer needs anon write access
-- to products/discount_codes. Each item may carry variant_color / variant_size.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_storefront_order(
  p_seller_id uuid, p_customer_name text, p_customer_phone text,
  p_delivery_method text, p_delivery_address text, p_delivery_fee numeric,
  p_payment_method text, p_total numeric, p_notes text,
  p_discount_code text, p_discount_amount numeric, p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_order public.orders%rowtype;
  v_item jsonb;
  v_fee_type text; v_fee_value numeric; v_fee numeric;
  v_order_number text;
  v_pid uuid; v_qty int; v_color text; v_size text;
  v_stock int; v_variants jsonb;
begin
  if p_seller_id is null or not exists (select 1 from sellers where id = p_seller_id) then
    return jsonb_build_object('error','badseller','message','Unknown store');
  end if;
  if coalesce(trim(p_customer_name),'') = '' or coalesce(trim(p_customer_phone),'') = '' then
    return jsonb_build_object('error','badcustomer','message','Name and phone are required');
  end if;

  v_order_number := 'ORD-' || to_char(now(),'YYYYMMDD') || '-' || lpad((floor(random()*900)+100)::int::text, 3, '0');

  insert into orders (seller_id, customer_name, customer_phone, order_number, status,
    delivery_method, delivery_address, delivery_status, delivery_fee, payment_method,
    total, notes, source, discount_code, discount_amount)
  values (p_seller_id, p_customer_name, p_customer_phone, v_order_number, 'new',
    p_delivery_method, coalesce(p_delivery_address,''), 'pending', coalesce(p_delivery_fee,0), p_payment_method,
    coalesce(p_total,0), p_notes, 'storefront', p_discount_code, coalesce(p_discount_amount,0))
  returning * into v_order;

  for v_item in select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    v_pid := nullif(v_item->>'product_id','')::uuid;
    v_qty := coalesce((v_item->>'quantity')::int, 1);

    insert into order_items (order_id, product_id, product_name, quantity, unit_price)
    values (v_order.id, v_pid,
      coalesce(v_item->>'product_name','Item'), v_qty,
      coalesce((v_item->>'unit_price')::numeric, 0));

    -- Inventory decrement (server-side; replaces the old anon client writes).
    if v_pid is not null then
      v_color := nullif(v_item->>'variant_color','');
      v_size  := nullif(v_item->>'variant_size','');
      select stock, variants into v_stock, v_variants
        from products where id = v_pid and seller_id = p_seller_id;

      if (v_color is not null or v_size is not null)
         and v_variants is not null and jsonb_typeof(v_variants) = 'array' then
        update products
           set variants = (
             select jsonb_agg(
               case when coalesce(elem->>'color','') = coalesce(v_color,'')
                     and coalesce(elem->>'size','')  = coalesce(v_size,'')
                    then jsonb_set(elem, '{stock}',
                           to_jsonb(greatest(0, coalesce((elem->>'stock')::int,0) - v_qty)))
                    else elem end)
             from jsonb_array_elements(v_variants) elem)
         where id = v_pid;
      elsif v_stock is not null then
        update products set stock = greatest(0, v_stock - v_qty) where id = v_pid;
      end if;
    end if;
  end loop;

  -- Discount usage (server-side; replaces the old anon client write).
  if coalesce(trim(p_discount_code),'') <> '' then
    update discount_codes
       set used_count = coalesce(used_count,0) + 1
     where seller_id = p_seller_id and lower(code) = lower(trim(p_discount_code)) and is_active = true;
  end if;

  select fee_type, fee_value into v_fee_type, v_fee_value from platform_config limit 1;
  if v_fee_value is not null then
    v_fee := case when v_fee_type = 'percentage' then coalesce(p_total,0) * v_fee_value / 100 else v_fee_value end;
    insert into platform_fees (order_id, seller_id, order_total, fee_amount)
    values (v_order.id, p_seller_id, coalesce(p_total,0), round(v_fee * 100) / 100);
  end if;

  return jsonb_build_object('order_number', v_order.order_number, 'track_token', v_order.track_token, 'total', v_order.total);
end; $function$;
