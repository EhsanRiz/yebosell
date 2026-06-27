-- Self-serve fee settlement requests: sellers submit payment proof,
-- admin reviews and marks settled via admin_actions.
create table if not exists public.fee_settlement_requests (
    id uuid primary key default gen_random_uuid(),
    seller_id uuid not null references public.sellers(id) on delete cascade,
    amount_claimed numeric(10,2) not null,
    payment_ref text,
    payment_method text,
    notes text,
    status text not null default 'pending', -- pending | approved | rejected
    reviewed_by uuid references public.admins(auth_user_id),
    reviewed_at timestamptz,
    review_notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.fee_settlement_requests enable row level security;

-- Sellers can insert and view their own requests
create policy "sellers_own_settlement_requests_select"
    on public.fee_settlement_requests for select
    using (owns_seller(seller_id));

create policy "sellers_own_settlement_requests_insert"
    on public.fee_settlement_requests for insert
    with check (owns_seller(seller_id));

-- Admins have full access
create policy "admin_all_settlement_requests"
    on public.fee_settlement_requests for all
    using (is_platform_admin());

-- Keep updated_at current on any row change
create or replace function public.touch_fee_settlement_updated()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

drop trigger if exists trg_fee_settlement_updated on public.fee_settlement_requests;
create trigger trg_fee_settlement_updated
    before update on public.fee_settlement_requests
    for each row execute procedure public.touch_fee_settlement_updated();
