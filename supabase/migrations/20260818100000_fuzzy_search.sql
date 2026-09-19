-- Product search that tolerates a misspelling.
--
-- Until now "search" was one line of Dart: a case-insensitive substring
-- test on the product name, over whatever list happened to be loaded.
-- "amul" found Amul Butter; "amool" and "amul buter" found nothing, and
-- nothing outside the name was searched at all.
--
-- pg_trgm compares three-letter fragments, so "amool" still scores
-- highly against "amul" -- the two share most of their trigrams. That
-- covers real typing mistakes without the machinery of embeddings.
--
-- Note what this is NOT: it is fuzzy *spelling*, not meaning. Searching
-- "milk" will not surface curd or paneer. Searching the category name
-- gets part of the way there -- "dairy" finds everything in Dairy --
-- which is most of the practical benefit for a shop this size.

create extension if not exists pg_trgm with schema extensions;

-- GIN trigram indexes: without these every search is a full scan, which
-- is survivable at 50 products and not at 5,000.
create index if not exists products_name_trgm_idx
  on public.products using gin (name extensions.gin_trgm_ops);
create index if not exists products_description_trgm_idx
  on public.products using gin (description extensions.gin_trgm_ops);
create index if not exists categories_name_trgm_idx
  on public.categories using gin (name extensions.gin_trgm_ops);

-- One search for both apps.
--
-- security_invoker semantics come free: it is a plain (non-definer)
-- function, so the caller's RLS on products still applies -- customers
-- get active products, staff get everything.
create or replace function public.search_products(
  p_query text,
  p_limit int default 50
)
returns table (
  id uuid,
  score real,
  matched_on text
)
language sql
stable
set search_path = public
as $$
  with q as (
    select lower(trim(coalesce(p_query, ''))) as term
  )
  select
    p.id,
    greatest(
      -- Exact and prefix matches must win outright, or a fuzzy near-miss
      -- on another product can outrank what the user literally typed.
      case when lower(p.name) = (select term from q) then 1.0
           when lower(p.name) like (select term from q) || '%' then 0.95
           when lower(p.name) like '%' || (select term from q) || '%' then 0.9
           else 0 end,
      extensions.similarity(lower(p.name), (select term from q)),
      -- Secondary fields matter less than the name, so they are damped.
      extensions.similarity(lower(coalesce(p.description, '')), (select term from q)) * 0.6,
      extensions.similarity(lower(coalesce(c.name, '')), (select term from q)) * 0.7,
      case when p.barcode is not null
            and p.barcode like '%' || (select term from q) || '%'
           then 0.85 else 0 end
    )::real as score,
    case
      when lower(p.name) like '%' || (select term from q) || '%' then 'name'
      when p.barcode like '%' || (select term from q) || '%' then 'barcode'
      when lower(coalesce(c.name, '')) like '%' || (select term from q) || '%' then 'category'
      when lower(coalesce(p.description, '')) like '%' || (select term from q) || '%' then 'description'
      else 'similar'
    end as matched_on
  from public.products p
  left join public.categories c on c.id = p.category_id
  where (select term from q) <> ''
    and (
      lower(p.name) like '%' || (select term from q) || '%'
      or p.barcode like '%' || (select term from q) || '%'
      or lower(coalesce(c.name, '')) like '%' || (select term from q) || '%'
      -- 0.25 is deliberately loose: a shopper typing one-handed misses
      -- more letters than a desk user, and a slightly noisy list beats
      -- "no results" for something the shop actually stocks.
      or extensions.similarity(lower(p.name), (select term from q)) > 0.25
      or extensions.similarity(lower(coalesce(p.description, '')), (select term from q)) > 0.35
    )
  order by score desc, p.name
  limit greatest(1, least(p_limit, 100));
$$;

comment on function public.search_products(text, int) is
  'Typo-tolerant product search over name, description, category and barcode, ranked. Respects the caller''s RLS on products.';
