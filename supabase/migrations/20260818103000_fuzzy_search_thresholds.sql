-- Loosen the edit-distance thresholds by one step for short queries.
--
-- "mlik" (transposed) and "bttr" (dropped vowels) are both two edits
-- from their target on a four-letter query, and the previous rule
-- allowed only one below five characters -- so the two most ordinary
-- typing mistakes there are both missed.
--
-- Plain Levenshtein counts a transposition as two edits, which is why
-- four-letter words need two to be usable at all.

create or replace function public.search_products(
  p_query text,
  p_limit int default 50
)
returns table (id uuid, score real, matched_on text)
language sql
stable
set search_path = public
as $$
  with q as (select lower(trim(coalesce(p_query, ''))) as term),
  scored as (
    select p.id, p.name, p.barcode, p.description, c.name as category_name,
      (select min(extensions.levenshtein(w, (select term from q)))
       from unnest(string_to_array(lower(p.name), ' ')) as w
       where length(w) >= 3) as name_edits
    from public.products p
    left join public.categories c on c.id = p.category_id
  )
  select s.id,
    greatest(
      case when lower(s.name) = (select term from q) then 1.0
           when lower(s.name) like (select term from q) || '%' then 0.95
           when lower(s.name) like '%' || (select term from q) || '%' then 0.9
           else 0 end,
      extensions.word_similarity((select term from q), lower(s.name)),
      extensions.word_similarity((select term from q), lower(coalesce(s.description, ''))) * 0.6,
      extensions.word_similarity((select term from q), lower(coalesce(s.category_name, ''))) * 0.7,
      case when s.barcode is not null and s.barcode like '%' || (select term from q) || '%'
           then 0.85 else 0 end,
      case when s.name_edits is null then 0
           else greatest(0.0, 0.88 - (s.name_edits::numeric
                / greatest(length((select term from q)), 4))) end
    )::real as score,
    case
      when lower(s.name) like '%' || (select term from q) || '%' then 'name'
      when s.barcode like '%' || (select term from q) || '%' then 'barcode'
      when lower(coalesce(s.category_name, '')) like '%' || (select term from q) || '%' then 'category'
      when lower(coalesce(s.description, '')) like '%' || (select term from q) || '%' then 'description'
      else 'similar'
    end as matched_on
  from scored s
  where (select term from q) <> ''
    and (
      lower(s.name) like '%' || (select term from q) || '%'
      or s.barcode like '%' || (select term from q) || '%'
      or lower(coalesce(s.category_name, '')) like '%' || (select term from q) || '%'
      or extensions.word_similarity((select term from q), lower(s.name)) > 0.4
      or extensions.word_similarity((select term from q), lower(coalesce(s.category_name, ''))) > 0.5
      or extensions.word_similarity((select term from q), lower(coalesce(s.description, ''))) > 0.5
      or s.name_edits <= (case
            when length((select term from q)) >= 8 then 3
            when length((select term from q)) >= 4 then 2
            else 1 end)
    )
  order by score desc, s.name
  limit greatest(1, least(p_limit, 100));
$$;
