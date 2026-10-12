-- =============================================================================
-- Home8 — smarter text search.
--
-- Run once in Supabase → SQL Editor (paste → Run). Safe to re-run.
-- Run AFTER 20261015000000_search.sql.
--
-- Before: typing "penthouse" only matched title / area / city / address as one
-- exact phrase, so a listing whose TYPE is penthouse (but whose title says
-- "Sky Residence") never showed, and "penthouses" (plural) matched nothing.
--
-- Now:
--   * Every word typed must appear somewhere in the listing — title, type,
--     area, city, address, description, reference, furnishing, purpose,
--     "2 bed", "studio", "off plan"…  ("2 bed penthouse marina" works.)
--   * Plurals are folded: penthouses → penthouse, communities → community.
--   * Filler words (in, for, the, with, near…) are ignored.
--   * Title / type hits rank first under "Relevance".
--   * The response also says how many match under the OTHER purpose
--     (`other_total`), so the app can switch Rent ↔ Sale instead of
--     showing "No results" when the homes are actually for sale.
--   * The map can ask for up to 300 pins in one call.
--   * Suggestions include property types ("Penthouse · Property type") and
--     matching listings by title, with counts that use the same matching as
--     the results — the count you see is the count you get.
-- =============================================================================

-- Words of a search term, lower-cased, plurals folded, filler removed.
create or replace function public._search_words(p_term text)
returns text[] language sql immutable as $$
  select coalesce(array_agg(w2), '{}')
  from (
    select case
             when length(w) > 4 and w like '%ies' then left(w, length(w) - 3) || 'y'
             when length(w) > 3 and w like '%s' and w not like '%ss' then left(w, length(w) - 1)
             else w
           end as w2
    from regexp_split_to_table(lower(trim(coalesce(p_term, ''))), '[^[:alnum:]]+') as w
    where length(w) > 0
      and w not in ('a', 'an', 'the', 'in', 'at', 'for', 'with', 'near', 'of', 'and', 'on', 'to')
  ) x
$$;

-- Everything a buyer might type about one listing, in one lower-case string.
create or replace function public._listing_haystack(l public.listings)
returns text language sql stable as $$
  select lower(concat_ws(' ',
    l.title, l.area, l.city, l.address,
    l.type, replace(l.type, '_', ' '),
    l.segment, l.purpose, 'for ' || l.purpose,
    l.furnishing, l.reference, l.description,
    l.beds || ' bed', l.beds || 'bed', l.beds || ' bedroom', l.beds || ' br',
    case when l.beds = 0 then 'studio' end,
    case when l.off_plan then 'off plan off-plan offplan' end))
$$;

-- True when every word appears in the haystack.
create or replace function public._matches_words(p_hay text, p_words text[])
returns boolean language sql immutable as $$
  select not exists (select 1 from unnest(p_words) w where position(w in p_hay) = 0)
$$;

-- -----------------------------------------------------------------------------
-- search_listings(p) — same input/output as before, plus `other_total`.
-- -----------------------------------------------------------------------------
create or replace function public.search_listings(p jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
as $$
declare
  v_page       int     := greatest(coalesce(nullif(p ->> 'page', '')::int, 1), 1);
  v_size       int     := least(greatest(coalesce(nullif(p ->> 'page_size', '')::int, 20), 1), 300);
  v_words      text[]  := public._search_words(p ->> 'q');
  v_area       text    := lower(trim(coalesce(p ->> 'area', '')));
  v_type       text    := nullif(p ->> 'type', '');
  v_purpose    text    := coalesce(nullif(p ->> 'purpose', ''), 'rent');
  v_sort       text    := coalesce(nullif(p ->> 'sort', ''), 'relevance');
  v_furnishing text    := nullif(p ->> 'furnishing', '');
  v_amenities  text[]  := case when coalesce(p ->> 'amenities', '') = '' then null
                               else string_to_array(p ->> 'amenities', ',') end;
  v_result     jsonb;
begin
  with base as (
    -- Every filter except purpose.
    select l.*,
           (select count(*) from unnest(v_words) w
             where position(w in lower(l.title || ' ' || replace(l.type, '_', ' '))) > 0) as score
    from public.listings l
    where l.status = 'live'
      and l.market = coalesce(nullif(p ->> 'market', ''), 'AE')
      and (nullif(p ->> 'segment', '') is null or l.segment = p ->> 'segment')
      and (v_type is null
           or (v_type = 'Off-Plan Homes' and l.off_plan)
           or (v_type <> 'Off-Plan Homes' and l.type = v_type))
      and (cardinality(v_words) = 0 or public._matches_words(public._listing_haystack(l), v_words))
      and (v_area = '' or lower(l.area) like '%' || v_area || '%')
      and (nullif(p ->> 'price_min', '') is null or l.price >= (p ->> 'price_min')::bigint)
      and (nullif(p ->> 'price_max', '') is null or l.price <= (p ->> 'price_max')::bigint)
      and (nullif(p ->> 'beds', '')  is null or l.beds  >= (p ->> 'beds')::int)
      and (nullif(p ->> 'baths', '') is null or l.baths >= (p ->> 'baths')::int)
      and (nullif(p ->> 'bua_min', '') is null or l.bua_sqft >= (p ->> 'bua_min')::int)
      and (nullif(p ->> 'bua_max', '') is null or l.bua_sqft <= (p ->> 'bua_max')::int)
      and (v_furnishing is null or v_furnishing = 'Any' or lower(l.furnishing) = lower(v_furnishing))
      and (v_amenities is null or l.amenities @> v_amenities)
      and (coalesce(p ->> 'verified', '') <> 'true' or 'verified' = any (l.badges))
      and (nullif(p ->> 'min_lat', '') is null or l.lat >= (p ->> 'min_lat')::float8)
      and (nullif(p ->> 'max_lat', '') is null or l.lat <= (p ->> 'max_lat')::float8)
      and (nullif(p ->> 'min_lng', '') is null or l.lng >= (p ->> 'min_lng')::float8)
      and (nullif(p ->> 'max_lng', '') is null or l.lng <= (p ->> 'max_lng')::float8)
  ),
  matches as (
    select * from base where purpose = v_purpose
  ),
  ordered as (
    select m.id, count(*) over () as total_count,
           row_number() over (order by
             case when v_sort = 'relevance' then m.score end desc,
             case when v_sort = 'relevance' then m.featured end desc,
             case when v_sort = 'relevance' then m.rating end desc,
             case when v_sort = 'newest'             then m.published_at end desc nulls last,
             case when v_sort = 'price_asc'          then m.price end asc,
             case when v_sort = 'price_desc'         then m.price end desc,
             case when v_sort = 'price_per_sqft_asc' then m.price_per_sqft end asc nulls last,
             case when v_sort = 'bua_desc'           then m.bua_sqft end desc,
             m.id) as rn
    from matches m
  )
  select jsonb_build_object(
    'results', coalesce((
        select jsonb_agg(public.listing_json(l) order by o.rn)
        from ordered o join public.listings l on l.id = o.id
        where o.rn > (v_page - 1) * v_size and o.rn <= v_page * v_size),
      '[]'::jsonb),
    'total', coalesce((select max(o.total_count) from ordered o), 0),
    -- Same search, the other purpose (rent ↔ sale).
    'other_total', (select count(*) from base where purpose <> v_purpose),
    'page', v_page,
    'page_size', v_size)
  into v_result;

  return v_result;
end $$;

-- -----------------------------------------------------------------------------
-- suggest_places(term) — places, property types and listings, with real
-- counts (same word matching as search_listings).
-- Ids: place id | 'a:<area>' | 'c:<city>' | 't:<type>' | 'l:<listing id>'.
-- -----------------------------------------------------------------------------
create or replace function public.suggest_places(p_term text, p_market text default 'AE')
returns jsonb language sql stable as $$
  with q as (
    select public._search_words(p_term) as words,
           lower(trim(coalesce(p_term, ''))) as t
  ),
  live as (
    select l.id, l.title, l.area, l.city, l.type, public._listing_haystack(l) as hay
    from public.listings l
    where l.status = 'live' and l.market = p_market
  ),
  candidates as (
    -- Known places.
    select pl.id, pl.name, initcap(pl.kind) || ' · ' || pl.parent as subtitle, 0 as priority
    from public.places pl, q
    where pl.market = p_market and cardinality(q.words) > 0
      and public._matches_words(lower(pl.name), q.words)
    union all
    -- Communities and cities that have live listings.
    select 'a:' || lower(lv.area), min(lv.area), 'Community · ' || min(lv.city), 1
    from live lv, q
    where cardinality(q.words) > 0 and lv.area <> ''
      and public._matches_words(lower(lv.area), q.words)
    group by lower(lv.area)
    union all
    select 'c:' || lower(lv.city), min(lv.city), 'City', 2
    from live lv, q
    where cardinality(q.words) > 0 and lv.city <> ''
      and public._matches_words(lower(lv.city), q.words)
    group by lower(lv.city)
    union all
    -- Property types ("pent" → Penthouse).
    select 't:' || lv.type, initcap(replace(lv.type, '_', ' ')), 'Property type', 3
    from live lv, q
    where cardinality(q.words) > 0
      and public._matches_words(lower(replace(lv.type, '_', ' ')), q.words)
    group by lv.type
  ),
  unique_names as (
    select distinct on (lower(c.name)) c.*
    from candidates c
    order by lower(c.name), c.priority
  ),
  counted as (
    select u.id, u.name, u.subtitle,
           (select count(*) from live lv
             where public._matches_words(lv.hay, public._search_words(u.name)))::int as homes,
           lower(u.name) like (select t from q) || '%' as starts
    from unique_names u
  ),
  top_places as (
    select * from counted
    order by homes > 0 desc, starts desc, homes desc, name
    limit 7
  ),
  -- Listings whose title matches, so a buyer can jump straight to one.
  top_listings as (
    select 'l:' || lv.id as id, lv.title as name,
           'Home · ' || concat_ws(', ', nullif(lv.area, ''), nullif(lv.city, '')) as subtitle,
           1 as homes, true as starts
    from live lv, q
    where cardinality(q.words) > 0
      and public._matches_words(lower(lv.title), q.words)
    order by lv.title
    limit 3
  ),
  combined as (
    select *, 0 as grp from top_places
    union all
    select *, 1 from top_listings
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'title', c.name, 'subtitle', c.subtitle, 'count', c.homes)
         order by c.grp, c.homes > 0 desc, c.starts desc, c.homes desc, c.name), '[]'::jsonb)
  from combined c
$$;

grant execute on function public._search_words(text) to anon, authenticated;
grant execute on function public._listing_haystack(public.listings) to anon, authenticated;
grant execute on function public._matches_words(text, text[]) to anon, authenticated;
grant execute on function public.search_listings(jsonb) to anon, authenticated;
grant execute on function public.suggest_places(text, text) to anon, authenticated;
