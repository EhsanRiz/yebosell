-- Optional product fields to broaden the form beyond clothing:
--   unit       — how the item is sold (each / per kg / per litre / per dozen…)
--   condition  — New / Used / Refurbished (for electronics, second-hand goods)
alter table public.products add column if not exists unit text;
alter table public.products add column if not exists condition text;
