-- ============================================================================
-- Generic product options — product.option_label
-- The product variant editor was hardcoded to Colour × Size (apparel only).
-- It's now ONE seller-named option (Size / Colour / Flavour / Length / Weight…)
-- whose values are stored in the existing variant `size` slot (colour empty),
-- so the checkout RPC (which matches colour+size) keeps working unchanged and
-- old apparel products still load. option_label holds the human label the
-- buyer sees ("Size", "Flavour", …).
-- ============================================================================
alter table public.products add column if not exists option_label text;
