-- ============================================================================
-- Optional seller email + Forgot-PIN reset (applied 2026-06-12).
-- ============================================================================

alter table public.sellers add column if not exists email text;

-- seller_register now takes an optional p_email (old 5-arg version dropped).
-- Full body applied live; signature:
--   public.seller_register(p_phone, p_otp, p_pin, p_full_name, p_business_name, p_email default null) -> jsonb
-- Stores nullif(trim(email),'') on the new seller row.

-- Forgot-PIN reset: verify phone via OTP, set a new bcrypt PIN, clear any lockout.
--   public.seller_reset_pin(p_phone text, p_otp text, p_new_pin text) -> jsonb
-- Verifies a fresh buyer_otps code for the number, confirms the seller exists,
-- upserts seller_secrets.pin_hash = crypt(new_pin, gen_salt('bf')),
-- and deletes seller_login_attempts for the phone. Returns the seller (auto-login).
-- Granted execute to anon, authenticated.
