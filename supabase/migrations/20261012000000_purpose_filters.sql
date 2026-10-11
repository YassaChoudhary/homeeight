-- =============================================================================
-- Home8 — For Rent / For Sale filter on the Home carousels.
--
-- Run once in Supabase → SQL Editor (paste the whole file → Run). Safe to re-run.
--
-- Adds an optional p_purpose ('rent' | 'sale') to highlight_listings and
-- popular_communities. Null keeps the old behaviour (both), which is what the
-- Search screen still asks for.
-- =============================================================================

-- Old two-argument versions are replaced, not overloaded: two functions with
-- the same name and compatible arguments make API calls ambiguous.
drop function if exists public.highlight_listings(int, text);
drop function if exists public.popular_communities(int, text);

-- "The most relevant": featured first, then best rated.
create or replace function public.highlight_listings(
  p_limit   int  default 8,
  p_market  text default 'AE',
  p_purpose text default null
)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(public.listing_json(h) order by h.featured desc, h.rating desc, h.id), '[]'::jsonb)
  from public.listings h
  where h.id in (
    select id from public.listings
    where status = 'live'
      and market = p_market
      and (p_purpose is null or purpose = p_purpose)
    order by featured desc, rating desc, id
    limit greatest(least(p_limit, 30), 1)
  )
$$;

-- "Popular communities": ranked by live homes. With a purpose, only homes FOR
-- THAT PURPOSE count (so "For Sale" surfaces where the sales actually are).
-- The `popular` flag breaks ties.
create or replace function public.popular_communities(
  p_limit   int  default 4,
  p_market  text default 'AE',
  p_purpose text default null
)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'name', c.name, 'homes', c.homes, 'photo_url', c.photo_url)
         order by c.homes desc, c.popular desc, c.name), '[]'::jsonb)
  from (
    select pl.*,
           (select count(*) from public.listings l
             where l.status = 'live' and l.market = pl.market
               and lower(l.area) = lower(pl.name)
               and (p_purpose is null or l.purpose = p_purpose))::int as homes
    from public.places pl
    where pl.kind = 'community' and pl.market = p_market
      -- No purpose: the curated popular list, as before. With a purpose: any
      -- community, so "For Sale" can surface where the sales actually are.
      and (p_purpose is not null or pl.popular)
    order by homes desc, pl.popular desc, pl.name
    limit greatest(least(p_limit, 20), 1)
  ) c
$$;

grant execute on function
  public.highlight_listings(int, text, text),
  public.popular_communities(int, text, text)
to anon, authenticated;
