-- Trigrams alone could not match "amool" to "Amul".
--
-- Trigram similarity compares three-letter fragments, and changing the
-- middle vowels destroys nearly all of them: "amool" gives amo/moo/ool,
-- "amul" gives amu/mul -- almost no overlap, however low the threshold
-- goes. Lowering it far enough to catch this would drag in genuine
-- noise.
--
-- Levenshtein sees the same pair as two edits, which for a five-letter
-- word is an obvious near-miss. The two measures fail in different
-- directions, so using both catches far more real typos than either:
-- trigrams handle inserted/dropped letters and word order, edit distance
-- handles substituted letters.
--
-- Comparison is per WORD, because a shopper types one word ("buter")
-- against a multi-word name ("Amul Butter").

create extension if not exists fuzzystrmatch with schema extensions;

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
  ),
  -- Closest single word of the product name to the query, by edit
  -- distance, expressed as a 0..1 score.
  scored as (
    select
      p.id,
      p.name,
      p.barcode,
      p.description,
      c.name as category_name,
      (
        select min(extensions.levenshtein(w, (select term from q)))
        from unnest(string_to_array(lower(p.name), ' ')) as w
        where length(w) >= 3
      ) as name_edits
    from public.products p
    left join public.categories c on c.id = p.category_id
  )
  select
    s.id,
    greatest(
      case when lower(s.name) = (select term from q) then 1.0
           when lower(s.name) like (select term from q) || '%' then 0.95
           when lower(s.name) like '%' || (select term from q) || '%' then 0.9
           else 0 end,
      extensions.word_similarity((select term from q), lower(s.name)),
      extensions.word_similarity((select term from q), lower(coalesce(s.description, ''))) * 0.6,
      extensions.word_similarity((select term from q), lower(coalesce(s.category_name, ''))) * 0.7,
      case when s.barcode is not null
            and s.barcode like '%' || (select term from q) || '%'
           then 0.85 else 0 end,
      -- Edit distance as a score: 1 edit on a 5-letter word ~0.8,
      -- 2 edits ~0.6. Never outranks a literal substring match.
      case when s.name_edits is null then 0
           else greatest(0.0,
             0.88 - (s.name_edits::numeric
                     / greatest(length((select term from q)), 4)))
      end
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
      -- Allow more edits on longer words: two wrong letters in a short
      -- word is a different word, in a long one it is a slip.
      or s.name_edits <= (case
            when length((select term from q)) >= 8 then 3
            when length((select term from q)) >= 5 then 2
            else 1 end)
    )
  order by score desc, s.name
  limit greatest(1, least(p_limit, 100));
$$;

comment on function public.search_products(text, int) is
  'Typo-tolerant ranked product search over name, description, category and barcode. Combines trigram similarity with Levenshtein edit distance -- the two catch different classes of mistake. Respects the caller''s RLS.';
