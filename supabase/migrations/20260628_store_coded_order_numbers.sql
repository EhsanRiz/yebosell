-- Store-coded order numbers: CODE-YYMMDD-NN (store acronym + date + per-store
-- daily sequence). Replaces the old random ORD-YYYYMMDD-### scheme.

-- Derive a short uppercase store code from the business name: initials of the
-- first up-to-4 words, or the first 4 letters of a single-word name.
create or replace function public.make_order_code(p_name text)
returns text language sql immutable set search_path = '' as $$
  with parts as (
    select upper(regexp_replace(word,'[^A-Za-z0-9]','','g')) as word, ord
    from unnest(regexp_split_to_array(trim(coalesce(p_name,'')), '\s+')) with ordinality as t(word, ord)
  ), ne as (
    select word, ord from parts where word <> ''
  )
  select coalesce(
    case
      when (select count(*) from ne) = 0 then 'ORD'
      when (select count(*) from ne) = 1 then left((select word from ne limit 1), 4)
      else (select string_agg(left(word,1), '' order by ord) from (select word, ord from ne order by ord limit 4) f)
    end, 'ORD');
$$;

-- Stable per-seller code (editable later). Backfill from business name.
alter table public.sellers add column if not exists order_code text;
update public.sellers set order_code = public.make_order_code(business_name)
  where order_code is null or order_code = '';
grant select (order_code) on public.sellers to authenticated;

-- Assign the order number on insert when one isn't supplied. Sequence is the
-- max existing daily suffix for this store + 1 (robust to deletes), padded to 2.
create or replace function public.tg_set_order_number()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_code text; v_date text; v_seq int;
begin
  if NEW.order_number is not null and NEW.order_number <> '' then return NEW; end if;
  select order_code into v_code from sellers where id = NEW.seller_id;
  if v_code is null or v_code = '' then
    select coalesce(make_order_code(business_name),'ORD') into v_code from sellers where id = NEW.seller_id;
  end if;
  v_code := coalesce(v_code,'ORD');
  v_date := to_char((now() at time zone 'Africa/Maseru'),'YYMMDD');
  select coalesce(max(nullif(split_part(order_number,'-',3),'')::int),0) + 1 into v_seq
    from orders
    where seller_id = NEW.seller_id and order_number like v_code || '-' || v_date || '-%';
  NEW.order_number := v_code || '-' || v_date || '-' || lpad(v_seq::text, 2, '0');
  return NEW;
end $$;
drop trigger if exists set_order_number on public.orders;
create trigger set_order_number before insert on public.orders
  for each row execute function public.tg_set_order_number();
