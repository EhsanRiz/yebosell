-- ============================================================================
-- Orders realtime — let authenticated sellers receive live changes to their
-- own orders so the dashboard pops new orders in without a manual refresh.
-- RLS (owns_seller SELECT policy) already scopes delivery to the seller's rows.
-- ============================================================================
do $$ begin
  alter publication supabase_realtime add table public.orders;
exception when duplicate_object then null; end $$;
