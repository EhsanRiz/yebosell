-- Stage 1 of the Supabase Auth migration (applied 2026-06-13).
-- Link column from sellers to auth.users (nullable, additive). See SPEC_supabase_auth_migration.md.
alter table public.sellers
  add column if not exists auth_user_id uuid references auth.users(id) on delete set null;
create index if not exists idx_sellers_auth_user_id on public.sellers (auth_user_id);
