-- =============================================================================
-- Home8 — listings in Supabase, with Firebase as the login provider.
--
-- Run once in Supabase → SQL Editor (paste the whole file → Run), or with the
-- Supabase CLI (`supabase db push`). Safe to re-run: everything is
-- "if not exists" / "create or replace".
--
-- Who is who:
--   * Users sign in with FIREBASE. The app sends the Firebase ID token to
--     Supabase, which verifies it (Authentication → Third-party auth →
--     Firebase). Firebase user ids are text like "kq3Xr9...", not uuids, so
--     owner columns are TEXT and policies use public.firebase_uid(), never
--     auth.uid() (which casts to uuid and would fail).
--   * Anyone (signed in or not) can read LIVE listings.
--   * Only the owner can see their own non-live listings and change them.
-- =============================================================================

create extension if not exists pg_trgm;

-- -----------------------------------------------------------------------------
-- The signed-in Firebase user, or null.
--
-- Checks issuer and audience so a token from some other Firebase project can
-- never pass as one of ours. Change BOTH 'home8-61d48' strings if the Firebase
-- project id ever changes.
-- -----------------------------------------------------------------------------
create or replace function public.firebase_uid()
returns text
language sql
stable
as $$
  select case
    when auth.jwt() ->> 'iss' = 'https://securetoken.google.com/home8-61d48'
     and auth.jwt() ->> 'aud' = 'home8-61d48'
    then auth.jwt() ->> 'sub'
  end
$$;

-- -----------------------------------------------------------------------------
-- Agents / agencies shown on listing cards and reels.
-- firebase_uid links an agent row to the Firebase account that manages it.
-- -----------------------------------------------------------------------------
create table if not exists public.agents (
  id             text primary key default ('ag_' || replace(gen_random_uuid()::text, '-', '')),
  firebase_uid   text unique,
  name           text not null,
  agency_name    text not null default '',
  avatar_url     text,
  verified       boolean not null default false,
  response_time  text not null default '~15 min',
  created_at     timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Listings. Column names match Property.fromJson in lib/models/property.dart.
-- -----------------------------------------------------------------------------
create table if not exists public.listings (
  id                  text primary key default ('l_' || replace(gen_random_uuid()::text, '-', '')),
  owner_uid           text default public.firebase_uid(),
  agent_id            text references public.agents (id) on delete set null,
  market              text not null default 'AE',
  status              text not null default 'draft'
                      check (status in ('draft', 'in_review', 'live', 'paused', 'rented', 'sold', 'rejected')),

  purpose             text not null check (purpose in ('rent', 'sale')),
  segment             text not null default 'residential' check (segment in ('residential', 'commercial')),
  type                text not null default 'apartment',
  off_plan            boolean not null default false,

  title               text not null,
  description         text not null default '',
  area                text not null default '',
  city                text not null default '',
  address             text not null default '',
  lat                 double precision,
  lng                 double precision,

  beds                integer not null default 0 check (beds >= 0),
  baths               integer not null default 0 check (baths >= 0),
  bua_sqft            integer not null default 0 check (bua_sqft >= 0),
  occupancy           integer,
  furnishing          text,
  age_years           integer,

  price               bigint not null check (price >= 0),
  previous_price      bigint,
  currency            text not null default 'AED',
  rent_period         text check (rent_period in ('yearly', 'monthly', 'weekly')),
  price_per_sqft      numeric generated always as
                        (case when bua_sqft > 0 then round(price::numeric / bua_sqft, 2) end) stored,

  rating              numeric(3, 2) not null default 0,
  reviews             integer not null default 0,
  badges              text[] not null default '{}',   -- 'verified', 'guest_favourite', 'owner'
  featured            boolean not null default false,
  permit_no           text,
  photos              text[] not null default '{}',
  amenities           text[] not null default '{}',
  fair_price          jsonb,                          -- FairPrice.fromJson shape

  available           boolean not null default true,
  unavailable_reason  text,

  search_text         text generated always as
                        (lower(title || ' ' || area || ' ' || city || ' ' || address)) stored,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  published_at        timestamptz
);

-- Indexes for the Filters screen and sorts (live listings only — that's all
-- search ever reads).
create index if not exists listings_live_purpose_price
  on public.listings (market, purpose, price) where status = 'live';
create index if not exists listings_live_purpose_published
  on public.listings (market, purpose, published_at desc) where status = 'live';
create index if not exists listings_live_beds
  on public.listings (beds) where status = 'live';
create index if not exists listings_live_bua
  on public.listings (bua_sqft) where status = 'live';
create index if not exists listings_owner
  on public.listings (owner_uid);
create index if not exists listings_search_text_trgm
  on public.listings using gin (search_text gin_trgm_ops);
create index if not exists listings_amenities
  on public.listings using gin (amenities);
create index if not exists listings_lat_lng
  on public.listings (lat, lng) where status = 'live';

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if new.status = 'live' and (tg_op = 'INSERT' or old.status is distinct from 'live') then
    new.published_at := coalesce(new.published_at, now());
  end if;
  return new;
end $$;

drop trigger if exists listings_touch on public.listings;
create trigger listings_touch before insert or update on public.listings
  for each row execute function public.touch_updated_at();

-- -----------------------------------------------------------------------------
-- Saved listings (the hearts). user_uid fills itself from the token, so the
-- app only sends listing_id.
-- -----------------------------------------------------------------------------
create table if not exists public.saved_listings (
  user_uid    text not null default public.firebase_uid(),
  listing_id  text not null references public.listings (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_uid, listing_id)
);

-- -----------------------------------------------------------------------------
-- Places for the search autocomplete (communities, towers).
-- -----------------------------------------------------------------------------
create table if not exists public.places (
  id         text primary key,
  name       text not null,
  kind       text not null default 'community' check (kind in ('community', 'tower', 'city')),
  parent     text not null default '',            -- "Dubai", or the community of a tower
  market     text not null default 'AE',
  photo_url  text,
  popular    boolean not null default false
);
create index if not exists places_name_trgm on public.places using gin (lower(name) gin_trgm_ops);

-- -----------------------------------------------------------------------------
-- Reels — short property videos (media_url points at Storage / Stream).
-- -----------------------------------------------------------------------------
create table if not exists public.reels (
  id          text primary key default ('r_' || replace(gen_random_uuid()::text, '-', '')),
  listing_id  text not null references public.listings (id) on delete cascade,
  agent_id    text references public.agents (id) on delete set null,
  media_url   text,
  likes       integer not null default 0,
  comments    integer not null default 0,
  created_at  timestamptz not null default now()
);

-- =============================================================================
-- Row Level Security
-- =============================================================================
alter table public.agents          enable row level security;
alter table public.listings        enable row level security;
alter table public.saved_listings  enable row level security;
alter table public.places          enable row level security;
alter table public.reels           enable row level security;

drop policy if exists "agents are public" on public.agents;
create policy "agents are public" on public.agents
  for select to anon, authenticated using (true);

drop policy if exists "live listings are public" on public.listings;
create policy "live listings are public" on public.listings
  for select to anon, authenticated
  using (status = 'live' or owner_uid = public.firebase_uid());

drop policy if exists "owners add listings" on public.listings;
create policy "owners add listings" on public.listings
  for insert to authenticated
  with check (owner_uid = public.firebase_uid() and status in ('draft', 'in_review'));

drop policy if exists "owners edit listings" on public.listings;
create policy "owners edit listings" on public.listings
  for update to authenticated
  using (owner_uid = public.firebase_uid())
  -- Owners can't publish themselves: 'live' is set by review (service role).
  with check (owner_uid = public.firebase_uid()
              and status in ('draft', 'in_review', 'paused', 'rented', 'sold'));

drop policy if exists "owners delete listings" on public.listings;
create policy "owners delete listings" on public.listings
  for delete to authenticated using (owner_uid = public.firebase_uid());

drop policy if exists "users manage their saved listings" on public.saved_listings;
create policy "users manage their saved listings" on public.saved_listings
  for all to authenticated
  using (user_uid = public.firebase_uid())
  with check (user_uid = public.firebase_uid());

drop policy if exists "places are public" on public.places;
create policy "places are public" on public.places
  for select to anon, authenticated using (true);

drop policy if exists "reels are public" on public.reels;
create policy "reels are public" on public.reels
  for select to anon, authenticated
  using (exists (select 1 from public.listings l where l.id = listing_id and l.status = 'live'));

-- =============================================================================
-- Read model: one JSON object per listing, in the exact shape the app parses
-- (Property.fromJson). Runs with the caller's permissions, so RLS applies.
-- =============================================================================
create or replace function public.listing_json(l public.listings)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', l.id,
    'title', l.title,
    'area', l.area,
    'city', l.city,
    'purpose', l.purpose,
    'type', l.type,
    'beds', l.beds,
    'baths', l.baths,
    'bua_sqft', l.bua_sqft,
    'occupancy', l.occupancy,
    'furnishing', l.furnishing,
    'age_years', l.age_years,
    'price', l.price,
    'previous_price', l.previous_price,
    'currency', l.currency,
    'rent_period', l.rent_period,
    'rating', l.rating,
    'reviews', l.reviews,
    'badges', to_jsonb(l.badges),
    'featured', l.featured,
    'permit_no', l.permit_no,
    'photos', to_jsonb(l.photos),
    'amenities', to_jsonb(l.amenities),
    'description', l.description,
    'address', l.address,
    'lat', l.lat,
    'lng', l.lng,
    'fair_price', l.fair_price,
    'available', l.available,
    'unavailable_reason', l.unavailable_reason,
    'agent', (
      select jsonb_build_object(
        'id', a.id, 'name', a.name, 'agency_name', a.agency_name,
        'avatar_url', a.avatar_url, 'verified', a.verified,
        'response_time', a.response_time)
      from public.agents a where a.id = l.agent_id)
  )
$$;

-- -----------------------------------------------------------------------------
-- search_listings(p) — the Results screen.
--
-- `p` is exactly SearchQuery.toQueryParameters() from the app (all values are
-- strings): purpose, segment, sort, page, page_size, q, type, area,
-- price_min, price_max, beds, baths, bua_min, bua_max, furnishing,
-- amenities (comma-separated), verified, plus map bounds
-- min_lat/max_lat/min_lng/max_lng and market (default AE).
--
-- Returns { results: [...], total, page, page_size } = ListingPage.fromJson.
-- -----------------------------------------------------------------------------
create or replace function public.search_listings(p jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
as $$
declare
  v_page       int     := greatest(coalesce(nullif(p ->> 'page', '')::int, 1), 1);
  v_size       int     := least(greatest(coalesce(nullif(p ->> 'page_size', '')::int, 20), 1), 100);
  v_q          text    := lower(trim(coalesce(p ->> 'q', '')));
  v_area       text    := lower(trim(coalesce(p ->> 'area', '')));
  v_type       text    := nullif(p ->> 'type', '');
  v_furnishing text    := nullif(p ->> 'furnishing', '');
  v_amenities  text[]  := case when coalesce(p ->> 'amenities', '') = '' then null
                               else string_to_array(p ->> 'amenities', ',') end;
  v_result     jsonb;
begin
  with matches as (
    select l.*
    from public.listings l
    where l.status = 'live'
      and l.market = coalesce(nullif(p ->> 'market', ''), 'AE')
      and l.purpose = coalesce(nullif(p ->> 'purpose', ''), 'rent')
      and (nullif(p ->> 'segment', '') is null or l.segment = p ->> 'segment')
      and (v_type is null
           or (v_type = 'Off-Plan Homes' and l.off_plan)
           or (v_type <> 'Off-Plan Homes' and l.type = v_type))
      and (v_q = '' or l.search_text like '%' || v_q || '%')
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
  ordered as (
    select m.id, count(*) over () as total_count,
           row_number() over (order by
             case when coalesce(p ->> 'sort', 'relevance') = 'relevance' then m.featured end desc,
             case when coalesce(p ->> 'sort', 'relevance') = 'relevance' then m.rating end desc,
             case when p ->> 'sort' = 'newest'             then m.published_at end desc nulls last,
             case when p ->> 'sort' = 'price_asc'          then m.price end asc,
             case when p ->> 'sort' = 'price_desc'         then m.price end desc,
             case when p ->> 'sort' = 'price_per_sqft_asc' then m.price_per_sqft end asc nulls last,
             case when p ->> 'sort' = 'bua_desc'           then m.bua_sqft end desc,
             m.id) as rn
    from matches m
  )
  select jsonb_build_object(
    -- JSON is built only for the rows on this page.
    'results', coalesce((
        select jsonb_agg(public.listing_json(l) order by o.rn)
        from ordered o join public.listings l on l.id = o.id
        where o.rn > (v_page - 1) * v_size and o.rn <= v_page * v_size),
      '[]'::jsonb),
    'total', coalesce((select max(o.total_count) from ordered o), 0),
    'page', v_page,
    'page_size', v_size)
  into v_result;

  return v_result;
end $$;

-- One listing (detail screen). Null when missing or not visible.
create or replace function public.listing_by_id(p_id text)
returns jsonb language sql stable as $$
  select public.listing_json(l) from public.listings l where l.id = p_id
$$;

-- "Similar homes": same purpose, closest in beds, size and price.
create or replace function public.similar_listings(p_id text, p_limit int default 6)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(public.listing_json(x) order by s.score), '[]'::jsonb)
  from (
    select l.id,
           abs(l.beds - b.beds) * 10
           + abs(l.bua_sqft - b.bua_sqft)::numeric / greatest(b.bua_sqft, 1) * 10
           + abs(l.price - b.price)::numeric / greatest(b.price, 1) * 10
           + case when l.area = b.area then 0 else 3 end as score
    from public.listings l, public.listings b
    where b.id = p_id and l.id <> b.id
      and l.status = 'live' and l.purpose = b.purpose and l.market = b.market
    order by score
    limit greatest(least(p_limit, 20), 1)
  ) s
  join public.listings x on x.id = s.id
$$;

-- Comparables behind the Fair Price sheet (ComparableListing.fromJson shape).
create or replace function public.comparable_listings(p_id text, p_limit int default 6)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'title', c.title, 'beds', c.beds, 'bua_sqft', c.bua_sqft,
           'price', c.price, 'currency', c.currency,
           'photo_url', c.photos[1],
           'recency', case
             when c.published_at > now() - interval '7 days' then 'listed this week'
             when c.published_at > now() - interval '31 days' then 'listed this month'
             else 'listed earlier' end)
         order by c.score), '[]'::jsonb)
  from (
    select l.*, abs(l.bua_sqft - b.bua_sqft) + abs(l.beds - b.beds) * 500 as score
    from public.listings l, public.listings b
    where b.id = p_id and l.id <> b.id and l.status = 'live'
      and l.purpose = b.purpose and l.type = b.type and l.market = b.market
      and abs(l.beds - b.beds) <= 1
    order by score
    limit greatest(least(p_limit, 20), 1)
  ) c
$$;

-- Home carousels: featured first, then best rated.
create or replace function public.highlight_listings(p_limit int default 8, p_market text default 'AE')
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(public.listing_json(h) order by h.featured desc, h.rating desc, h.id), '[]'::jsonb)
  from public.listings h
  where h.id in (
    select id from public.listings
    where status = 'live' and market = p_market
    order by featured desc, rating desc, id
    limit greatest(least(p_limit, 30), 1)
  )
$$;

-- Popular communities with live counts (Community.fromJson shape).
create or replace function public.popular_communities(p_limit int default 4, p_market text default 'AE')
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'name', c.name, 'homes', c.homes, 'photo_url', c.photo_url)
         order by c.homes desc, c.name), '[]'::jsonb)
  from (
    select pl.*, (select count(*) from public.listings l
                  where l.status = 'live' and l.market = pl.market
                    and lower(l.area) = lower(pl.name))::int as homes
    from public.places pl
    where pl.kind = 'community' and pl.market = p_market and pl.popular
    order by homes desc, pl.name
    limit greatest(least(p_limit, 20), 1)
  ) c
$$;

-- Autocomplete (SearchSuggestion.fromJson shape).
create or replace function public.suggest_places(p_term text, p_market text default 'AE')
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'title', s.name,
           'subtitle', initcap(s.kind) || ' · ' || s.parent,
           'count', s.homes)
         order by s.starts desc, s.homes desc, s.name), '[]'::jsonb)
  from (
    select pl.*,
           lower(pl.name) like lower(trim(p_term)) || '%' as starts,
           (select count(*) from public.listings l
             where l.status = 'live' and l.market = pl.market
               and (lower(l.area) = lower(pl.name) or l.search_text like '%' || lower(pl.name) || '%'))::int as homes
    from public.places pl
    where length(trim(p_term)) > 0
      and pl.market = p_market
      and lower(pl.name) like '%' || lower(trim(p_term)) || '%'
    order by starts desc, pl.name
    limit 10
  ) s
$$;

-- Reels feed (Reel.fromJson shape). `saved` reflects the caller's hearts.
create or replace function public.reels_feed(p_limit int default 30)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'listing_id', r.listing_id, 'media_url', r.media_url,
           'likes', r.likes, 'comments', r.comments,
           'saved', exists (select 1 from public.saved_listings s
                            where s.listing_id = r.listing_id and s.user_uid = public.firebase_uid()),
           'agent', (select jsonb_build_object(
                       'id', a.id, 'name', a.name, 'agency_name', a.agency_name,
                       'avatar_url', a.avatar_url, 'verified', a.verified,
                       'response_time', a.response_time)
                     from public.agents a where a.id = r.agent_id))
         order by r.created_at desc, r.id), '[]'::jsonb)
  from (select * from public.reels order by created_at desc, id limit greatest(least(p_limit, 100), 1)) r
$$;

-- Read functions are callable by everyone; RLS inside still decides what rows
-- each caller can see.
grant execute on function
  public.firebase_uid(),
  public.listing_json(public.listings),
  public.search_listings(jsonb),
  public.listing_by_id(text),
  public.similar_listings(text, int),
  public.comparable_listings(text, int),
  public.highlight_listings(int, text),
  public.popular_communities(int, text),
  public.suggest_places(text, text),
  public.reels_feed(int)
to anon, authenticated;
