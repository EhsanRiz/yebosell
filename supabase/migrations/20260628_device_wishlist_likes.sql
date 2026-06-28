-- Device-based anonymous product likes, so the buyer "Saved" filter and the
-- seller-side like counts work without requiring a buyer account/phone (likes
-- happen before any phone is entered). buyer_wishlists was keyed on buyer_phone;
-- add an anonymous device_id and key dedup on that.
alter table public.buyer_wishlists add column if not exists device_id text;
alter table public.buyer_wishlists alter column buyer_phone drop not null;
create unique index if not exists buyer_wishlists_product_device_uidx
  on public.buyer_wishlists (product_id, device_id) where device_id is not null;

-- Toggle a like for an anonymous device. Validates that the product belongs to
-- the store (resolved by slug) and is active. Returns the product's new like count.
create or replace function public.set_wishlist(p_slug text, p_product_id uuid, p_device_id text, p_liked boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_seller uuid;
begin
  if p_device_id is null or length(trim(p_device_id)) = 0 then raise exception 'device required'; end if;
  select s.id into v_seller from sellers s where s.slug = p_slug;
  if v_seller is null then raise exception 'store not found'; end if;
  if not exists (select 1 from products p where p.id = p_product_id and p.seller_id = v_seller and p.is_active) then
    raise exception 'product not found';
  end if;
  if p_liked then
    insert into buyer_wishlists (product_id, seller_id, device_id)
    values (p_product_id, v_seller, p_device_id)
    on conflict (product_id, device_id) where device_id is not null do nothing;
  else
    delete from buyer_wishlists where product_id = p_product_id and device_id = p_device_id;
  end if;
  return (select count(*) from buyer_wishlists where product_id = p_product_id);
end $$;
grant execute on function public.set_wishlist(text, uuid, text, boolean) to anon, authenticated;

-- Aggregate like counts for a seller's products (owner or admin only).
create or replace function public.get_product_like_counts(p_seller_id uuid)
returns table(product_id uuid, likes bigint)
language plpgsql security definer set search_path = public as $$
begin
  if not (owns_seller(p_seller_id) or is_platform_admin()) then
    raise exception 'not authorized';
  end if;
  return query
    select bw.product_id, count(*)::bigint
    from buyer_wishlists bw
    where bw.seller_id = p_seller_id
    group by bw.product_id;
end $$;
grant execute on function public.get_product_like_counts(uuid) to authenticated;
