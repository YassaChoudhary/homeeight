-- =============================================================================
-- Home8 — demo data: the same 7 homes, agents, communities and reels the app's
-- mock showed, so the app looks identical after switching to Supabase.
--
-- Run AFTER the migration, in Supabase → SQL Editor. Re-running replaces the
-- demo rows (ids p1–p7, ag_0, ag_1, r1–r5, place ids) and touches nothing else.
-- Delete them before launch:  delete from public.listings where id like 'p_';
-- =============================================================================

insert into public.agents (id, name, agency_name, verified, response_time) values
  ('ag_0', 'Tarik Abdullah', 'Prime Realty', true, '~15 min'),
  ('ag_1', 'Sara Ahmed',     'Prime Realty', true, '~10 min')
on conflict (id) do update set
  name = excluded.name, agency_name = excluded.agency_name,
  verified = excluded.verified, response_time = excluded.response_time;

insert into public.listings (
  id, owner_uid, agent_id, status, purpose, type, title, area, city, address, lat, lng,
  beds, baths, bua_sqft, occupancy, furnishing, age_years,
  price, currency, rent_period, rating, reviews, badges, featured, permit_no,
  amenities, description, fair_price, published_at
) values
  ('p1', null, 'ag_0', 'live', 'rent', 'apartment', 'Home in Palm Jumeirah', 'Dubai Marina', 'Dubai',
   'Al Nawras Building, Al Nahda 1, Al Nahda (Dubai), Dubai', 25.0805, 55.1403,
   2, 2, 1050, 4, 'Furnished', 3, 96000, 'AED', 'yearly', 4.96, 217,
   '{verified,guest_favourite,owner}', false, '71-4402',
   '{"Wifi","65\" HD TV","Central A/C & Heating","Covered Parking","CCTV Security","Shared Pool","Sea View","Private Gym","Maintenance Staff"}',
   'Bright, fully-furnished residence with a private beach club, dedicated parking and full sea views from every room. Chiller-free, one cheque accepted, available immediately for a qualified tenant.',
   '{"verdict":"fair","position":0.5,"comparable_count":6,"band_low":78000,"fair_low":88000,"fair_high":104000,"band_high":120000}',
   now() - interval '7 days'),
  ('p2', null, 'ag_1', 'live', 'rent', 'apartment', 'Condo in Downtown', 'Downtown', 'Dubai',
   'Burj Views, Downtown Dubai, Dubai', 25.1972, 55.2744,
   3, 2, 1420, 6, 'Furnished', 2, 142000, 'AED', 'yearly', 4.88, 96,
   '{verified,guest_favourite}', false, null,
   '{"Wifi","Covered Parking","Shared Pool","Private Gym"}',
   'Bright, fully-furnished residence with a private beach club, dedicated parking and full sea views from every room. Chiller-free, one cheque accepted, available immediately for a qualified tenant.',
   '{"verdict":"low","position":0.24,"comparable_count":11}',
   now() - interval '6 days'),
  ('p3', null, 'ag_1', 'live', 'rent', 'villa', 'Villa in JVC', 'JVC', 'Dubai',
   'District 12, Jumeirah Village Circle, Dubai', 25.0590, 55.2090,
   2, 2, 1180, 5, 'Unfurnished', 5, 118000, 'AED', 'yearly', 4.79, 54,
   '{verified}', true, '71-9911',
   '{"Covered Parking","Shared Pool","Maid''s Room"}',
   'Bright, fully-furnished residence with a private beach club, dedicated parking and full sea views from every room. Chiller-free, one cheque accepted, available immediately for a qualified tenant.',
   '{"verdict":"high","position":0.78,"comparable_count":4}',
   now() - interval '5 days'),
  ('p4', null, 'ag_0', 'live', 'rent', 'apartment', 'Condo in Shoreline', 'Shoreline', 'Dubai',
   'Shoreline Apartments, Palm Jumeirah, Dubai', 25.1125, 55.1390,
   2, 2, 1420, null, 'Furnished', 4, 134000, 'AED', 'yearly', 4.72, 33,
   '{verified}', false, null,
   '{"Wifi","Sea View","Covered Parking"}',
   'Bright, fully-furnished residence with a private beach club, dedicated parking and full sea views from every room. Chiller-free, one cheque accepted, available immediately for a qualified tenant.',
   '{"verdict":"fair","position":0.55}',
   now() - interval '4 days'),
  ('p5', null, 'ag_1', 'live', 'rent', 'apartment', 'Marina Gate 2BR', 'Dubai Marina', 'Dubai',
   'Marina Gate 1, Dubai Marina, Dubai', 25.0860, 55.1470,
   2, 2, 1180, null, 'Unfurnished', 1, 118000, 'AED', 'yearly', 4.81, 61,
   '{verified}', false, null,
   '{"Private Gym","Shared Pool","Covered Parking"}',
   'Bright, fully-furnished residence with a private beach club, dedicated parking and full sea views from every room. Chiller-free, one cheque accepted, available immediately for a qualified tenant.',
   '{"verdict":"fair","position":0.46}',
   now() - interval '3 days'),
  ('p6', null, 'ag_1', 'live', 'sale', 'penthouse', 'Penthouse in Bluewaters', 'Bluewaters', 'Dubai',
   'Bluewaters Residences, Bluewaters Island, Dubai', 25.0790, 55.1210,
   4, 5, 3860, null, 'Furnished', 2, 12500000, 'AED', null, 4.91, 12,
   '{verified}', true, '71-2044',
   '{"Sea View","Private Gym","Maid''s Room","Covered Parking"}',
   'Bright, fully-furnished residence with a private beach club, dedicated parking and full sea views from every room. Chiller-free, one cheque accepted, available immediately for a qualified tenant.',
   '{"verdict":"fair","position":0.6}',
   now() - interval '2 days'),
  ('p7', null, 'ag_0', 'live', 'sale', 'studio', 'Studio in Business Bay', 'Business Bay', 'Dubai',
   'Executive Towers, Business Bay, Dubai', 25.1860, 55.2650,
   1, 1, 480, null, 'Unfurnished', 6, 850000, 'AED', null, 4.40, 28,
   '{}', false, null,
   '{"Covered Parking","Shared Pool"}',
   'Bright, fully-furnished residence with a private beach club, dedicated parking and full sea views from every room. Chiller-free, one cheque accepted, available immediately for a qualified tenant.',
   '{"verdict":"low","position":0.2}',
   now() - interval '1 day')
on conflict (id) do update set
  agent_id = excluded.agent_id, status = excluded.status, purpose = excluded.purpose,
  type = excluded.type, title = excluded.title, area = excluded.area, city = excluded.city,
  address = excluded.address, lat = excluded.lat, lng = excluded.lng, beds = excluded.beds,
  baths = excluded.baths, bua_sqft = excluded.bua_sqft, occupancy = excluded.occupancy,
  furnishing = excluded.furnishing, age_years = excluded.age_years, price = excluded.price,
  currency = excluded.currency, rent_period = excluded.rent_period, rating = excluded.rating,
  reviews = excluded.reviews, badges = excluded.badges, featured = excluded.featured,
  permit_no = excluded.permit_no, amenities = excluded.amenities,
  description = excluded.description, fair_price = excluded.fair_price,
  published_at = excluded.published_at;

insert into public.places (id, name, kind, parent, popular) values
  ('pl_marina',     'Dubai Marina',      'community', 'Dubai',        true),
  ('pl_palm',       'Palm Jumeirah',     'community', 'Dubai',        true),
  ('pl_jvc',        'JVC',               'community', 'Dubai',        true),
  ('pl_downtown',   'Downtown',          'community', 'Dubai',        true),
  ('pl_bizbay',     'Business Bay',      'community', 'Dubai',        false),
  ('pl_bluewaters', 'Bluewaters',        'community', 'Dubai',        false),
  ('pl_shoreline',  'Shoreline',         'community', 'Dubai',        false),
  ('pl_marinagate', 'Marina Gate Tower', 'tower',     'Dubai Marina', false),
  ('pl_promenade',  'Marina Promenade',  'tower',     'Dubai Marina', false)
on conflict (id) do update set
  name = excluded.name, kind = excluded.kind, parent = excluded.parent, popular = excluded.popular;

insert into public.reels (id, listing_id, agent_id, likes, comments, created_at) values
  ('r1', 'p1', 'ag_1', 5000, 6000, now() - interval '1 hour'),
  ('r2', 'p2', 'ag_0', 3200, 2400, now() - interval '2 hours'),
  ('r3', 'p3', 'ag_1', 8100, 4000, now() - interval '3 hours'),
  ('r4', 'p5', 'ag_0', 1900,  900, now() - interval '4 hours'),
  ('r5', 'p6', 'ag_1', 6000, 3300, now() - interval '5 hours')
on conflict (id) do update set
  listing_id = excluded.listing_id, agent_id = excluded.agent_id,
  likes = excluded.likes, comments = excluded.comments, created_at = excluded.created_at;
