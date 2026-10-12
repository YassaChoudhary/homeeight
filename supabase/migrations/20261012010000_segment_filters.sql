-- =============================================================================
-- Home8 — Residential / Commercial filter on the Home carousels
--          + commercial demo listings.
--
-- Run once in Supabase → SQL Editor (paste the whole file → Run).
-- Safe to re-run. Run it AFTER 20261012000000_purpose_filters.sql.
--
-- Adds p_segment ('residential' | 'commercial') next to p_purpose on
-- highlight_listings and popular_communities. Null = no filter.
-- =============================================================================

-- Replace (not overload) the three-argument versions.
drop function if exists public.highlight_listings(int, text);
drop function if exists public.highlight_listings(int, text, text);
drop function if exists public.popular_communities(int, text);
drop function if exists public.popular_communities(int, text, text);

-- "The most relevant": featured first, then best rated.
create or replace function public.highlight_listings(
  p_limit   int  default 8,
  p_market  text default 'AE',
  p_purpose text default null,
  p_segment text default null
)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(public.listing_json(h) order by h.featured desc, h.rating desc, h.id), '[]'::jsonb)
  from public.listings h
  where h.id in (
    select id from public.listings
    where status = 'live'
      and market = p_market
      and (p_purpose is null or purpose = p_purpose)
      and (p_segment is null or segment = p_segment)
    order by featured desc, rating desc, id
    limit greatest(least(p_limit, 30), 1)
  )
$$;

-- "Popular communities": ranked by live listings matching the filters, and
-- `homes` counts only those. With no filter: the curated popular list. With a
-- filter: only communities that actually have matching listings, so the app
-- never shows a "0 homes" tile.
create or replace function public.popular_communities(
  p_limit   int  default 4,
  p_market  text default 'AE',
  p_purpose text default null,
  p_segment text default null
)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'name', c.name, 'homes', c.homes, 'photo_url', c.photo_url)
         order by c.homes desc, c.popular desc, c.name), '[]'::jsonb)
  from (
    select s.* from (
      select pl.*,
             (select count(*) from public.listings l
               where l.status = 'live' and l.market = pl.market
                 and lower(l.area) = lower(pl.name)
                 and (p_purpose is null or l.purpose = p_purpose)
                 and (p_segment is null or l.segment = p_segment))::int as homes
      from public.places pl
      where pl.kind = 'community' and pl.market = p_market
    ) s
    where (p_purpose is null and p_segment is null and s.popular)
       or ((p_purpose is not null or p_segment is not null) and s.homes > 0)
    order by s.homes desc, s.popular desc, s.name
    limit greatest(least(p_limit, 20), 1)
  ) c
$$;

grant execute on function
  public.highlight_listings(int, text, text, text),
  public.popular_communities(int, text, text, text)
to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Commercial demo listings (so the Commercial tab isn't empty while testing).
-- Same rules as seed.sql: re-running updates them; delete before launch with
--   delete from public.listings where id like 'c\_%';
-- -----------------------------------------------------------------------------
insert into public.places (id, name, kind, parent, popular) values
  ('pl_difc',   'DIFC',    'community', 'Dubai', false),
  ('pl_alquoz', 'Al Quoz', 'community', 'Dubai', false)
on conflict (id) do update set name = excluded.name, kind = excluded.kind, parent = excluded.parent;

insert into public.listings (
  id, owner_uid, agent_id, status, purpose, segment, type, title, area, city, address, lat, lng,
  beds, baths, bua_sqft, furnishing, age_years, price, currency, rent_period,
  rating, reviews, badges, featured, permit_no, amenities, description, fair_price, published_at
) values
  ('c_1', null, 'ag_1', 'live', 'rent', 'commercial', 'office', 'Fitted office in Business Bay', 'Business Bay', 'Dubai',
   'Bay Square, Business Bay, Dubai', 25.1870, 55.2790,
   0, 2, 1850, 'Furnished', 4, 210000, 'AED', 'yearly',
   4.70, 18, '{verified}', true, '71-5501',
   '{"Covered Parking","Meeting Rooms","24/7 Access","Pantry"}',
   'Fully fitted office with glass partitions, two meeting rooms and a pantry. Metro 5 minutes away, ready to move in.',
   '{"verdict":"fair","position":0.5}', now() - interval '12 hours'),
  ('c_2', null, 'ag_0', 'live', 'rent', 'commercial', 'retail', 'Retail shop in DIFC', 'DIFC', 'Dubai',
   'Gate Avenue, DIFC, Dubai', 25.2120, 55.2810,
   0, 1, 950, 'Unfurnished', 3, 320000, 'AED', 'yearly',
   4.60, 9, '{verified}', false, '71-5502',
   '{"Shop Front","Covered Parking","High Footfall"}',
   'Ground-floor unit on Gate Avenue with a double-height glass front and steady weekday footfall.',
   '{"verdict":"high","position":0.72}', now() - interval '10 hours'),
  ('c_3', null, 'ag_1', 'live', 'rent', 'commercial', 'warehouse', 'Warehouse in Al Quoz', 'Al Quoz', 'Dubai',
   'Al Quoz Industrial Area 3, Dubai', 25.1330, 55.2280,
   0, 1, 6500, 'Unfurnished', 8, 380000, 'AED', 'yearly',
   4.40, 6, '{}', false, null,
   '{"Loading Bay","Power 3-Phase","Office Mezzanine"}',
   'Clear-span warehouse with a loading bay, 3-phase power and a small office mezzanine.',
   '{"verdict":"low","position":0.25}', now() - interval '8 hours'),
  ('c_4', null, 'ag_0', 'live', 'sale', 'commercial', 'office', 'Office floor for sale in Business Bay', 'Business Bay', 'Dubai',
   'Executive Towers, Business Bay, Dubai', 25.1860, 55.2650,
   0, 4, 4200, 'Unfurnished', 6, 6800000, 'AED', null,
   4.80, 4, '{verified}', true, '71-5503',
   '{"Covered Parking","Canal View","24/7 Access"}',
   'Half-floor office with canal views, shell and core, eight parking bays included.',
   '{"verdict":"fair","position":0.45}', now() - interval '6 hours'),
  ('c_5', null, 'ag_1', 'live', 'sale', 'commercial', 'retail', 'Retail unit for sale in DIFC', 'DIFC', 'Dubai',
   'Index Tower podium, DIFC, Dubai', 25.2100, 55.2790,
   0, 1, 1200, 'Unfurnished', 5, 4100000, 'AED', null,
   4.50, 3, '{}', false, null,
   '{"Shop Front","High Footfall"}',
   'Podium retail unit with a long-standing café tenant, sold with lease in place.',
   '{"verdict":"fair","position":0.55}', now() - interval '4 hours')
on conflict (id) do update set
  agent_id = excluded.agent_id, status = excluded.status, purpose = excluded.purpose,
  segment = excluded.segment, type = excluded.type, title = excluded.title, area = excluded.area,
  city = excluded.city, address = excluded.address, lat = excluded.lat, lng = excluded.lng,
  beds = excluded.beds, baths = excluded.baths, bua_sqft = excluded.bua_sqft,
  furnishing = excluded.furnishing, age_years = excluded.age_years, price = excluded.price,
  currency = excluded.currency, rent_period = excluded.rent_period, rating = excluded.rating,
  reviews = excluded.reviews, badges = excluded.badges, featured = excluded.featured,
  permit_no = excluded.permit_no, amenities = excluded.amenities,
  description = excluded.description, fair_price = excluded.fair_price,
  published_at = excluded.published_at;
