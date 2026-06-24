-- ============================================================================
-- Proof-of-payment uploads
-- Buyers (anon, token-only) upload via the upload-payment-proof Edge Function
-- (service role) into a PRIVATE bucket; sellers (authenticated, order owner)
-- read via signed URLs. Sensitive financial screenshots — never world-readable.
-- ============================================================================

-- 1) Private bucket (jpg/png/webp/pdf, 5MB)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('payment-proofs', 'payment-proofs', false, 5242880,
        array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update
  set public = false, file_size_limit = 5242880,
      allowed_mime_types = array['image/jpeg','image/png','image/webp','application/pdf'];

-- 2) Storage RLS: only the order's owner (or admin) may read objects, keyed on
--    the path prefix <order_id>/...  No anon/authenticated writes (the Edge
--    Function uses the service role, which bypasses RLS).
drop policy if exists payment_proofs_owner_read on storage.objects;
create policy payment_proofs_owner_read on storage.objects for select to authenticated
using (
  bucket_id = 'payment-proofs' and (
    public.is_platform_admin() or exists (
      select 1 from public.orders o
      where o.id::text = split_part(name, '/', 1)
        and public.owns_seller(o.seller_id)
    )
  )
);

-- 3) Metadata table
create table if not exists public.payment_proofs (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null references public.orders(id)  on delete cascade,
  seller_id     uuid not null references public.sellers(id) on delete cascade,
  storage_path  text not null,
  content_type  text,
  file_name     text,
  source        text not null default 'buyer' check (source in ('buyer','seller')),
  created_at    timestamptz not null default now()
);
create index if not exists payment_proofs_order_idx on public.payment_proofs (order_id, created_at desc);

alter table public.payment_proofs enable row level security;
revoke all on public.payment_proofs from anon;
grant select on public.payment_proofs to authenticated;

drop policy if exists pp_select_owner on public.payment_proofs;
create policy pp_select_owner on public.payment_proofs for select
  using (public.owns_seller(seller_id) or public.is_platform_admin());

-- 4) Buyer RPC: token-scoped metadata (to show "proof attached ✓"); no file/URL.
create or replace function public.get_order_payment_proofs(p_token text)
returns jsonb language sql security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', pp.id, 'file_name', pp.file_name, 'created_at', pp.created_at
         ) order by pp.created_at desc), '[]'::jsonb)
  from public.payment_proofs pp
  join public.orders o on o.id = pp.order_id
  where o.track_token = p_token;
$$;
grant execute on function public.get_order_payment_proofs(text) to anon, authenticated;
