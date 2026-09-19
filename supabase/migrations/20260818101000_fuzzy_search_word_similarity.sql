-- similarity() compares whole strings, so a short misspelling scored
-- badly against a longer name: "amool" vs "Amul Butter" fell under the
-- threshold and returned nothing -- precisely the case fuzzy search
-- exists for.
--
-- word_similarity() matches the query against the best-matching WORD in
-- the target instead, so "amool" is compared with "amul" rather than
-- with the whole "amul butter". That is the right comparison for
-- product names, which are several words of which the shopper usually
-- types one.

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
      case when lower(p.name) = (select term from q) then 1.0
           when lower(p.name) like (select term from q) || '%' then 0.95
           when lower(p.name) like '%' || (select term from q) || '%' then 0.9
           else 0 end,
      -- Best-matching word, not the whole string.
      extensions.word_similarity((select term from q), lower(p.name)),
      extensions.word_similarity((select term from q), lower(coalesce(p.description, ''))) * 0.6,
      extensions.word_similarity((select term from q), lower(coalesce(c.name, ''))) * 0.7,
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
      -- 0.4 on word_similarity is roughly "one or two letters wrong in a
      -- word", which is what a real typo looks like.
      or extensions.word_similarity((select term from q), lower(p.name)) > 0.4
      or extensions.word_similarity((select term from q), lower(coalesce(c.name, ''))) > 0.5
      or extensions.word_similarity((select term from q), lower(coalesce(p.description, ''))) > 0.5
    )
  order by score desc, p.name
  limit greatest(1, least(p_limit, 100));
$$;
