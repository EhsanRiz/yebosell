-- ============================================================================
-- Order Documents hub — generalize payment proofs into a shared per-order
-- document store (proof of payment, receipts/invoices, delivery proof, other).
-- Files stay in the private 'payment-proofs' bucket (kept for back-compat; now
-- holds all order document types). Both parties see the same list: seller via
-- storage RLS + signed URLs, buyer (anon) via token-validated Edge Functions.
-- ============================================================================

-- 1) Rename table + add doc_type
alter table public.payment_proofs rename to order_documents;
alter table public.order_documents
  add column if not exists doc_type text not null default 'payment_proof'
    check (doc_type in ('payment_proof','receipt','delivery_proof','other'));

-- 2) Seller (owner) may INSERT document rows for their own orders (source='seller').
--    Buyer rows are still inserted by the upload-payment-proof Edge Function
--    (service role). Read policy pp_select_owner already covers seller viewing.
drop policy if exists od_insert_owner on public.order_documents;
create policy od_insert_owner on public.order_documents for insert to authenticated
  with check (
    (public.owns_seller(seller_id) and source = 'seller') or public.is_platform_admin()
  );
grant insert on public.order_documents to authenticated;

-- 3) Storage: allow the order owner to UPLOAD objects under <order_id>/...
drop policy if exists order_docs_owner_write on storage.objects;
create policy order_docs_owner_write on storage.objects for insert to authenticated
with check (
  bucket_id = 'payment-proofs' and exists (
    select 1 from public.orders o
    where o.id::text = split_part(name, '/', 1) and public.owns_seller(o.seller_id)
  )
);

-- 4) Buyer RPC: token-scoped list of ALL documents on the order (metadata only;
--    file access is via the get-order-document Edge Function).
create or replace function public.get_order_documents(p_token text)
returns jsonb language sql security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', d.id, 'doc_type', d.doc_type, 'file_name', d.file_name,
           'source', d.source, 'created_at', d.created_at
         ) order by d.created_at desc), '[]'::jsonb)
  from public.order_documents d
  join public.orders o on o.id = d.order_id
  where o.track_token = p_token;
$$;
grant execute on function public.get_order_documents(text) to anon, authenticated;

-- Back-compat alias (older deployed frontend calls this name).
create or replace function public.get_order_payment_proofs(p_token text)
returns jsonb language sql security definer set search_path to 'public' as $$
  select public.get_order_documents(p_token);
$$;
grant execute on function public.get_order_payment_proofs(text) to anon, authenticated;
