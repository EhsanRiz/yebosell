-- ============================================================================
-- Harden seller auth (applied 2026-06-12 to project nizrqwvfuxbuhertypva).
-- bcrypt PINs in a private table, OTP-verified registration, server-side login
-- with rate limiting. Removes the previously public-readable sellers.pin_hash.
-- ============================================================================

-- Private secrets table (no anon access; reached only via SECURITY DEFINER RPCs)
create table if not exists public.seller_secrets (
  seller_id uuid primary key references public.sellers(id) on delete cascade,
  pin_hash text not null,
  updated_at timestamptz default now()
);
alter table public.seller_secrets enable row level security;

-- Login attempt log for rate limiting
create table if not exists public.seller_login_attempts (
  id uuid primary key default gen_random_uuid(),
  phone text not null,
  attempted_at timestamptz default now()
);
alter table public.seller_login_attempts enable row level security;
create index if not exists idx_login_attempts_phone_time on public.seller_login_attempts (phone, attempted_at);

-- Migrate existing PINs to bcrypt (Ehsan's known PIN re-hashed; demo sellers get
-- an unusable random hash — they are browse-only and never log in).
insert into public.seller_secrets (seller_id, pin_hash)
select id,
  case when phone = '+27761080024'
       then extensions.crypt('123456', extensions.gen_salt('bf'))
       else extensions.crypt(substr(md5(random()::text), 1, 16), extensions.gen_salt('bf')) end
from public.sellers
on conflict (seller_id) do nothing;

-- Remove the exposed weak hash from the public, anon-readable sellers table
alter table public.sellers drop column if exists pin_hash;

-- RPCs (SECURITY DEFINER). See git history / live DB for full bodies:
--   public.seller_login(p_phone text, p_pin text)         -> jsonb  (rate-limited, bcrypt verify)
--   public.seller_register(p_phone, p_otp, p_pin, p_full_name, p_business_name) -> jsonb (OTP-gated)
--   public.seller_change_pin(p_seller_id uuid, p_current_pin text, p_new_pin text) -> jsonb
-- All revoked from public and granted execute to anon, authenticated.
-- (Bodies are applied live; this file documents the schema + intent.)
