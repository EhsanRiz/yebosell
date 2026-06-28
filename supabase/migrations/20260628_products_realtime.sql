-- Publish products to realtime so stock/product edits propagate live to the
-- seller's notification bell and inventory views (RLS still scopes delivery to
-- the owning seller / admin).
do $$ begin
  alter publication supabase_realtime add table public.products;
exception when duplicate_object then null; end $$;
