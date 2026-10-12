-- =============================================================================
-- Home8 — search suggestions from REAL listings.
--
-- Run once in Supabase → SQL Editor (paste → Run). Safe to re-run.
--
-- Typing in Search now suggests:
--   * known places (the `places` table: communities, towers, cities), and
--   * every community and city that has live listings — including ones
--     sellers posted that aren't in `places` yet,
-- each with the real number of live homes, most relevant first.
-- =============================================================================

create or replace function public.suggest_places(p_term text, p_market text default 'AE')
returns jsonb language sql stable as $$
  with q as (
    select lower(trim(coalesce(p_term, ''))) as t
  ),
  live as (
    select l.area, l.city, l.search_text
    from public.listings l
    where l.status = 'live' and l.market = p_market
  ),
  candidates as (
    -- Known places first (priority 0), then areas and cities from listings.
    select pl.id, pl.name, initcap(pl.kind) || ' · ' || pl.parent as subtitle, 0 as priority
    from public.places pl, q
    where pl.market = p_market and length(q.t) > 0 and lower(pl.name) like '%' || q.t || '%'
    union all
    select 'a:' || lower(lv.area), min(lv.area), 'Community · ' || min(lv.city), 1
    from live lv, q
    where length(q.t) > 0 and lv.area <> '' and lower(lv.area) like '%' || q.t || '%'
    group by lower(lv.area)
    union all
    select 'c:' || lower(lv.city), min(lv.city), 'City', 2
    from live lv, q
    where length(q.t) > 0 and lv.city <> '' and lower(lv.city) like '%' || q.t || '%'
    group by lower(lv.city)
  ),
  unique_names as (
    select distinct on (lower(c.name)) c.*
    from candidates c
    order by lower(c.name), c.priority
  ),
  counted as (
    select u.*,
           (select count(*) from live lv where lv.search_text like '%' || lower(u.name) || '%')::int as homes,
           lower(u.name) like (select t from q) || '%' as starts
    from unique_names u
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'title', c.name, 'subtitle', c.subtitle, 'count', c.homes)
         order by c.homes > 0 desc, c.starts desc, c.homes desc, c.name), '[]'::jsonb)
  -- Places with homes first, then names that start with what was typed.
  from (select * from counted order by homes > 0 desc, starts desc, homes desc, name limit 10) c
$$;

grant execute on function public.suggest_places(text, text) to anon, authenticated;
