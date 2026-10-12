-- =============================================================================
-- Home8 — posting listings for real (seller side).
--
-- Run AFTER the earlier migrations, once, in Supabase → SQL Editor (paste the
-- whole file → Run). Safe to re-run.
--
-- What this adds:
--   * Storage buckets for listing photos, videos and private documents
--     (title deed, ID, selfie, licences) with per-user folder rules.
--   * listing_private: the exact address, exact pin and document files —
--     readable only by the owner (and you, in the dashboard). Buyers only ever
--     get the community, city and a rounded pin.
--   * RPCs the app calls: save/submit a listing, my listings, change status,
--     delete, request boost, live price guidance, stats, performance, and view
--     / contact tracking.
--   * Admin functions you run in the SQL editor to approve or reject:
--       select public.review_listing('l_…', true);                 -- approve
--       select public.review_listing('l_…', false, 'Blurry photos'); -- reject
--
-- Sellers can no longer write to the listings table directly; every write
-- goes through the functions below, which only accept whitelisted fields.
-- That stops anyone giving themselves a "verified" badge, a rating or
-- featured placement through the API.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Listing columns
-- -----------------------------------------------------------------------------
alter table public.listings alter column type drop not null;
alter table public.listings alter column type set default null;

alter table public.listings add column if not exists contact_phone      text;
alter table public.listings add column if not exists contact_whatsapp   text;
alter table public.listings add column if not exists contact_email      text;
alter table public.listings add column if not exists video_url          text;
alter table public.listings add column if not exists tour_requested     boolean not null default false;
alter table public.listings add column if not exists boost_requested_at timestamptz;
alter table public.listings add column if not exists area_unit          text not null default 'sqft';
alter table public.listings add column if not exists bua_value          integer;
alter table public.listings add column if not exists submitted_at       timestamptz;
alter table public.listings add column if not exists review_note        text;
alter table public.listings add column if not exists reference          text;
-- Step 6 "Reels package" — the seller's choice. Payments aren't live yet, so
-- this is a request you follow up on: 'unlimited_30d' (AED 99) or 'century'
-- (AED 29), null = skipped.
alter table public.listings add column if not exists reels_package      text;
alter table public.listings drop constraint if exists listings_reels_package_check;
alter table public.listings add constraint listings_reels_package_check
  check (reels_package in ('unlimited_30d', 'century'));

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'listings_reference_key') then
    alter table public.listings add constraint listings_reference_key unique (reference);
  end if;
end $$;

alter table public.listings drop constraint if exists listings_rent_period_check;
alter table public.listings add constraint listings_rent_period_check
  check (rent_period in ('yearly', 'monthly', 'weekly', 'nightly'));

alter table public.listings drop constraint if exists listings_area_unit_check;
alter table public.listings add constraint listings_area_unit_check
  check (area_unit in ('sqft', 'sqm'));

create sequence if not exists public.listing_ref_seq start 10001;

-- Rented / sold listings stay readable so a buyer's saved card can say
-- "No longer available" instead of vanishing. Search still shows live only.
drop policy if exists "live listings are public" on public.listings;
create policy "live listings are public" on public.listings
  for select to anon, authenticated
  using (status in ('live', 'rented', 'sold') or owner_uid = public.firebase_uid());

-- All seller writes go through the functions in this file.
revoke insert, update, delete on public.listings from authenticated, anon;

-- -----------------------------------------------------------------------------
-- 2. Private part of a listing (owner-only, never in any public response)
-- -----------------------------------------------------------------------------
create table if not exists public.listing_private (
  listing_id   text primary key references public.listings (id) on delete cascade,
  owner_uid    text not null,
  address      text not null default '',   -- exact, as the seller typed it
  lat          double precision,           -- exact pin
  lng          double precision,
  lister_type  text not null default 'individual',
  title_deed   jsonb,                      -- {name, bytes, path}
  id_front     jsonb,
  id_back      jsonb,
  selfie       jsonb,
  updated_at   timestamptz not null default now()
);
alter table public.listing_private enable row level security;
revoke all on public.listing_private from anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. Views and contact taps (for My Listings numbers and Performance)
-- One row per listing, kind, device and hour — so refreshing the page
-- doesn't inflate the count.
-- -----------------------------------------------------------------------------
create table if not exists public.listing_events (
  listing_id  text not null references public.listings (id) on delete cascade,
  kind        text not null check (kind in ('view', 'call', 'whatsapp', 'email')),
  device      text not null,
  hour        timestamptz not null,
  primary key (listing_id, kind, device, hour)
);
create index if not exists listing_events_listing_hour on public.listing_events (listing_id, hour);
alter table public.listing_events enable row level security;
revoke all on public.listing_events from anon, authenticated;

-- -----------------------------------------------------------------------------
-- 4. Agent / company verification requests (screen 29)
-- -----------------------------------------------------------------------------
create table if not exists public.lister_verifications (
  id              text primary key default ('v_' || replace(gen_random_uuid()::text, '-', '')),
  owner_uid       text not null,
  lister_type     text not null,
  organisation    text not null default '',
  licence_number  text not null default '',
  trade_licence   jsonb,
  broker_card     jsonb,
  status          text not null default 'pending' check (status in ('pending', 'verified', 'rejected')),
  review_note     text,
  created_at      timestamptz not null default now()
);
create index if not exists lister_verifications_owner on public.lister_verifications (owner_uid, created_at desc);
alter table public.lister_verifications enable row level security;
revoke all on public.lister_verifications from anon, authenticated;

-- -----------------------------------------------------------------------------
-- 5. Storage buckets
--   listing-photos   public   10 MB  images
--   listing-videos   public   50 MB  videos (free plan max per file)
--   listing-private  PRIVATE  15 MB  PDFs + images (deeds, IDs, licences)
-- Every file lives under "<firebase uid>/…", and users can only touch their
-- own folder.
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('listing-photos', 'listing-photos', true, 10485760,
   array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']),
  ('listing-videos', 'listing-videos', true, 52428800,
   array['video/mp4', 'video/quicktime', 'video/3gpp', 'video/webm', 'video/x-matroska']),
  ('listing-private', 'listing-private', false, 15728640,
   array['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "home8 users upload to own folder" on storage.objects;
create policy "home8 users upload to own folder" on storage.objects
  for insert to authenticated
  with check (
    bucket_id in ('listing-photos', 'listing-videos', 'listing-private')
    and (storage.foldername(name))[1] = public.firebase_uid()
  );

drop policy if exists "home8 users read own files" on storage.objects;
create policy "home8 users read own files" on storage.objects
  for select to authenticated
  using (
    bucket_id in ('listing-photos', 'listing-videos', 'listing-private')
    and (storage.foldername(name))[1] = public.firebase_uid()
  );

drop policy if exists "home8 users update own files" on storage.objects;
create policy "home8 users update own files" on storage.objects
  for update to authenticated
  using (
    bucket_id in ('listing-photos', 'listing-videos', 'listing-private')
    and (storage.foldername(name))[1] = public.firebase_uid()
  );

drop policy if exists "home8 users delete own files" on storage.objects;
create policy "home8 users delete own files" on storage.objects
  for delete to authenticated
  using (
    bucket_id in ('listing-photos', 'listing-videos', 'listing-private')
    and (storage.foldername(name))[1] = public.firebase_uid()
  );

-- -----------------------------------------------------------------------------
-- 6. Small helpers
-- -----------------------------------------------------------------------------

-- The signed-in seller, or an error the app shows as "Sign in again".
create or replace function public._require_uid()
returns text language plpgsql stable as $$
declare v text := public.firebase_uid();
begin
  if v is null then
    raise exception 'Please sign in again to manage your listings.' using errcode = '28000';
  end if;
  return v;
end $$;

-- An int from JSON, clamped; null when missing or not a number.
create or replace function public._jint(p jsonb, k text, lo bigint, hi bigint)
returns bigint language sql immutable as $$
  select case
    when jsonb_typeof(p -> k) = 'number' then least(greatest(round((p ->> k)::numeric)::bigint, lo), hi)
    when jsonb_typeof(p -> k) = 'string' and (p ->> k) ~ '^\s*-?\d+(\.\d+)?\s*$'
      then least(greatest(round((p ->> k)::numeric)::bigint, lo), hi)
  end
$$;

create or replace function public._jtext(p jsonb, k text, maxlen int)
returns text language sql immutable as $$
  select nullif(left(btrim(coalesce(p ->> k, '')), maxlen), '')
$$;

-- A stored file reference {name, bytes, path}, accepted only inside the
-- caller's own folder of the private bucket.
create or replace function public._jdoc(p jsonb, k text, uid text)
returns jsonb language sql immutable as $$
  select case
    when jsonb_typeof(p -> k) = 'object'
     and left(coalesce(p -> k ->> 'path', ''), length(uid) + 1) = uid || '/'
    then jsonb_build_object(
      'name', left(coalesce(p -> k ->> 'name', 'file'), 120),
      'bytes', coalesce(public._jint(p -> k, 'bytes', 0, 1000000000), 0),
      'path', left(p -> k ->> 'path', 300))
  end
$$;

-- A public media URL is accepted only if it points into the caller's folder
-- of our own bucket — no hotlinking other people's photos.
create or replace function public._own_media_url(url text, bucket text, uid text)
returns boolean language sql immutable as $$
  select url like 'https://%'
     and position('/storage/v1/object/public/' || bucket || '/' || uid || '/' in url) > 0
$$;

create or replace function public._clean_phone(v text)
returns text language sql immutable as $$
  select nullif(left(regexp_replace(coalesce(v, ''), '[^0-9+]', '', 'g'), 20), '')
$$;

-- Yearly-equivalent multiplier for a rent period (sale = 1).
create or replace function public._period_factor(purpose text, period text)
returns numeric language sql immutable as $$
  select case
    when purpose = 'sale' then 1
    when period = 'monthly' then 12
    when period = 'weekly' then 52
    when period = 'nightly' then 365
    else 1
  end::numeric
$$;

create or replace function public._ago(t timestamptz)
returns text language sql stable as $$
  select case
    when t is null then ''
    when now() - t < interval '1 hour' then 'just now'
    when now() - t < interval '1 day' then extract(hour from now() - t)::int || ' h ago'
    else extract(day from now() - t)::int || ' d ago'
  end
$$;

-- -----------------------------------------------------------------------------
-- 7. Fair price — the band under the price field, and the gauge on the
-- detail screen. Built from LIVE listings like this one: same market,
-- purpose and segment, same type when there are enough, similar bedrooms.
-- Returns null when there are fewer than 3 comparables (the app then says
-- "not enough similar listings yet" instead of guessing).
-- -----------------------------------------------------------------------------
create or replace function public._fair_price(
  p_market text, p_purpose text, p_segment text, p_type text, p_beds int,
  p_bua_sqft int, p_price bigint, p_period text, p_exclude text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_factor numeric := public._period_factor(p_purpose, p_period);
  v_count int; v_p10 numeric; v_p25 numeric; v_p75 numeric; v_p90 numeric;
  v_band_low numeric; v_fair_low numeric; v_fair_high numeric; v_band_high numeric;
  v_verdict text; v_pos numeric;
begin
  if coalesce(p_bua_sqft, 0) <= 0 or coalesce(p_price, 0) <= 0 then return null; end if;

  -- Yearly-equivalent price per sqft of the comparables.
  with base as (
    select l.type, l.beds,
           l.price * public._period_factor(l.purpose, l.rent_period) / l.bua_sqft as ppsf
    from public.listings l
    where l.status = 'live' and l.bua_sqft > 0 and l.price > 0
      and l.market = p_market and l.purpose = p_purpose and l.segment = p_segment
      and (p_exclude is null or l.id <> p_exclude)
  ),
  same_type as (
    select ppsf from base
    where type = p_type and (p_segment = 'commercial' or abs(beds - coalesce(p_beds, 0)) <= 1)
  ),
  pool as (
    select ppsf from same_type where (select count(*) from same_type) >= 3
    union all
    -- Not enough of the same type: widen to the whole segment.
    select ppsf from base where (select count(*) from same_type) < 3
  )
  select count(*),
         percentile_cont(0.10) within group (order by ppsf),
         percentile_cont(0.25) within group (order by ppsf),
         percentile_cont(0.75) within group (order by ppsf),
         percentile_cont(0.90) within group (order by ppsf)
    into v_count, v_p10, v_p25, v_p75, v_p90
  from pool;

  if v_count < 3 then return null; end if;

  -- Back to this listing's size and period.
  v_fair_low  := v_p25 * p_bua_sqft / v_factor;
  v_fair_high := v_p75 * p_bua_sqft / v_factor;
  v_band_low  := v_p10 * p_bua_sqft / v_factor;
  v_band_high := v_p90 * p_bua_sqft / v_factor;

  -- Few or identical comparables give a zero-width band; keep it readable.
  if v_fair_high - v_fair_low < v_fair_low * 0.08 then
    v_fair_low := v_fair_low * 0.96; v_fair_high := v_fair_high * 1.04;
  end if;
  v_band_low  := least(v_band_low, v_fair_low * 0.88);
  v_band_high := greatest(v_band_high, v_fair_high * 1.12);

  v_verdict := case when p_price < v_fair_low then 'low'
                    when p_price > v_fair_high then 'high'
                    else 'fair' end;
  v_pos := least(greatest((p_price - v_band_low) / nullif(v_band_high - v_band_low, 0), 0.03), 0.97);

  return jsonb_build_object(
    'verdict', v_verdict,
    'position', round(coalesce(v_pos, 0.5), 3),
    'comparable_count', v_count,
    'band_low', round(v_band_low),
    'fair_low', round(v_fair_low),
    'fair_high', round(v_fair_high),
    'band_high', round(v_band_high));
end $$;

-- Live guidance for the details step. `p` is the draft JSON.
create or replace function public.price_guidance(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_unit text := case when p ->> 'area_unit' = 'sqm' then 'sqm' else 'sqft' end;
  v_bua bigint := public._jint(p, 'bua', 0, 10000000);
  v_purpose text := case when p ->> 'purpose' = 'sale' then 'sale' else 'rent' end;
begin
  perform public._require_uid();
  return public._fair_price(
    coalesce(upper(public._jtext(p, 'country', 2)), 'AE'),
    v_purpose,
    case when p ->> 'segment' = 'commercial' then 'commercial' else 'residential' end,
    public._jtext(p, 'type', 40),
    coalesce(public._jint(p, 'beds', 0, 50), 0)::int,
    (case when v_unit = 'sqm' then round(v_bua * 10.7639) else v_bua end)::int,
    public._jint(p, 'price', 0, 1000000000000),
    case when v_purpose = 'rent' then coalesce(p ->> 'rent_period', 'yearly') end);
end $$;

-- -----------------------------------------------------------------------------
-- 8. The seller's view of one listing — MyListing.fromJson shape, with the
-- full draft inside (ListingDraft.fromJson) so "Continue editing" reopens
-- exactly what was saved.
-- -----------------------------------------------------------------------------
create or replace function public._my_listing_json(p_id text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', l.id,
    'status', case l.status
                when 'in_review' then 'inReview'
                when 'live' then 'live'
                when 'rejected' then 'rejected'
                when 'draft' then 'draft'
                else 'closed' end,
    'db_status', l.status,
    'reference', coalesce(l.reference, ''),
    'verified', 'verified' = any (l.badges),
    'submitted_ago', case when l.status = 'in_review' then 'submitted ' || public._ago(l.submitted_at) else '' end,
    'review_progress', case when l.status = 'in_review' then 0.35 else 0 end,
    'review_stage', case when l.status = 'in_review' then 'Waiting for review' else '' end,
    'review_note', coalesce(l.review_note, ''),
    'unavailable_reason', l.unavailable_reason,
    'views', (select count(*) from public.listing_events e where e.listing_id = l.id and e.kind = 'view'),
    'enquiries', (select count(*) from public.listing_events e where e.listing_id = l.id and e.kind <> 'view'),
    'saves', (select count(*) from public.saved_listings s where s.listing_id = l.id),
    'draft', jsonb_build_object(
      'id', l.id,
      'purpose', l.purpose,
      'segment', l.segment,
      'type', l.type,
      'country', l.market,
      'city', l.city,
      'community', l.area,
      'address', coalesce(pv.address, ''),
      'lat', pv.lat,
      'lng', pv.lng,
      'beds', l.beds,
      'baths', l.baths,
      'bua', coalesce(l.bua_value, l.bua_sqft),
      'area_unit', l.area_unit,
      'price', l.price,
      'currency', l.currency,
      'rent_period', l.rent_period,
      'furnishing', l.furnishing,
      'title', l.title,
      'description', l.description,
      'occupancy', l.occupancy,
      'age_years', l.age_years,
      'amenities', to_jsonb(l.amenities),
      'permit_no', l.permit_no,
      'photos', to_jsonb(l.photos),
      'video_url', l.video_url,
      'tour_requested', l.tour_requested,
      'reels_package', l.reels_package,
      'title_deed', pv.title_deed,
      'id_front', pv.id_front,
      'id_back', pv.id_back,
      'selfie', pv.selfie,
      'contact_phone', l.contact_phone,
      'contact_whatsapp', l.contact_whatsapp,
      'contact_email', l.contact_email))
  from public.listings l
  left join public.listing_private pv on pv.listing_id = l.id
  where l.id = p_id
$$;

-- -----------------------------------------------------------------------------
-- 9. Save / submit
-- -----------------------------------------------------------------------------
create or replace function public._seller_upsert(p jsonb, p_submit boolean)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_uid       text := public._require_uid();
  v_id        text := public._jtext(p, 'id', 64);
  v_old       public.listings;
  v_purpose   text := case when p ->> 'purpose' = 'sale' then 'sale' else 'rent' end;
  v_segment   text := case when p ->> 'segment' = 'commercial' then 'commercial' else 'residential' end;
  v_market    text := coalesce(upper(public._jtext(p, 'country', 2)), 'AE');
  v_unit      text := case when p ->> 'area_unit' = 'sqm' then 'sqm' else 'sqft' end;
  v_bua       bigint := public._jint(p, 'bua', 0, 10000000);
  v_bua_sqft  int;
  v_price     bigint := coalesce(public._jint(p, 'price', 0, 1000000000000), 0);
  v_period    text;
  v_lat       double precision;
  v_lng       double precision;
  v_photos    text[];
  v_video     text := public._jtext(p, 'video_url', 600);
  v_amen      text[];
  v_furnish   text := p ->> 'furnishing';
  v_email     text := public._jtext(p, 'contact_email', 120);
  v_lister    jsonb := coalesce(p -> 'lister', '{}'::jsonb);
  v_type_l    text := case when v_lister ->> 'type' in ('agent', 'company') then v_lister ->> 'type' else 'individual' end;
  v_agent_id  text;
  v_deed      jsonb := public._jdoc(p, 'title_deed', v_uid);
  v_id_front  jsonb := public._jdoc(p, 'id_front', v_uid);
  v_id_back   jsonb := public._jdoc(p, 'id_back', v_uid);
  v_selfie    jsonb := public._jdoc(p, 'selfie', v_uid);
  v_row       public.listings;
  v_missing   text[] := '{}';
begin
  if v_id is not null then
    select * into v_old from public.listings where id = v_id for update;
    if not found or v_old.owner_uid is distinct from v_uid then
      raise exception 'This listing no longer exists.' using errcode = 'P0002';
    end if;
  end if;

  v_bua_sqft := (case when v_unit = 'sqm' then round(coalesce(v_bua, 0) * 10.7639) else coalesce(v_bua, 0) end)::int;
  v_period := case when v_purpose = 'rent' then
                case when p ->> 'rent_period' in ('yearly', 'monthly', 'weekly', 'nightly')
                     then p ->> 'rent_period' else 'yearly' end end;

  if jsonb_typeof(p -> 'lat') = 'number' and jsonb_typeof(p -> 'lng') = 'number'
     and (p ->> 'lat')::float8 between -90 and 90 and (p ->> 'lng')::float8 between -180 and 180 then
    v_lat := (p ->> 'lat')::float8;
    v_lng := (p ->> 'lng')::float8;
  end if;

  select coalesce(array_agg(u order by n), '{}') into v_photos
  from (select u, n from jsonb_array_elements_text(coalesce(p -> 'photos', '[]')) with ordinality t(u, n)
        where public._own_media_url(u, 'listing-photos', v_uid) limit 30) x;

  if v_video is not null and not public._own_media_url(v_video, 'listing-videos', v_uid) then
    v_video := null;
  end if;

  select coalesce(array_agg(distinct a), '{}') into v_amen
  from (select left(btrim(a), 60) a
        from jsonb_array_elements_text(case when jsonb_typeof(p -> 'amenities') = 'array' then p -> 'amenities' else '[]' end) a
        where btrim(a) <> '' limit 40) x;

  if v_furnish not in ('Furnished', 'Unfurnished', 'Partly') then v_furnish := null; end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then v_email := null; end if;

  -- Server-side checks on submit — the same rules the app shows, so an old
  -- app version can't publish a half-empty listing.
  if p_submit then
    if public._jtext(p, 'type', 40) is null then v_missing := array_append(v_missing, 'property type'::text); end if;
    if coalesce(length(public._jtext(p, 'title', 70)), 0) < 5 then v_missing := array_append(v_missing, 'title'::text); end if;
    if coalesce(length(public._jtext(p, 'description', 4000)), 0) < 20 then v_missing := array_append(v_missing, 'description'::text); end if;
    if public._jtext(p, 'address', 300) is null or public._jtext(p, 'city', 80) is null then v_missing := array_append(v_missing, 'address'::text); end if;
    if v_lat is null then v_missing := array_append(v_missing, 'map pin'::text); end if;
    if v_bua_sqft <= 0 then v_missing := array_append(v_missing, 'area'::text); end if;
    if v_price <= 0 then v_missing := array_append(v_missing, 'price'::text); end if;
    if coalesce(array_length(v_photos, 1), 0) < 2 then v_missing := array_append(v_missing, 'at least 2 photos'::text); end if;
    if public._clean_phone(p ->> 'contact_phone') is null then v_missing := array_append(v_missing, 'contact number'::text); end if;
    if public._clean_phone(p ->> 'contact_whatsapp') is null then v_missing := array_append(v_missing, 'WhatsApp number'::text); end if;
    if v_market = 'AE' then
      if v_deed is null then v_missing := array_append(v_missing, 'title deed'::text); end if;
      if v_id_front is null or v_id_back is null then v_missing := array_append(v_missing, 'ID (front and back)'::text); end if;
      if public._jtext(p, 'permit_no', 40) is null then v_missing := array_append(v_missing, 'permit number'::text); end if;
    end if;
    if array_length(v_missing, 1) > 0 then
      raise exception 'Still needed: %', array_to_string(v_missing, ', ') using errcode = 'P0001';
    end if;

    -- The lister shown on the listing (agent card on the detail screen).
    insert into public.agents (firebase_uid, name, agency_name, avatar_url)
    values (v_uid,
            coalesce(public._jtext(v_lister, 'name', 80), 'Home8 member'),
            coalesce(public._jtext(v_lister, 'agency', 120),
                     case when v_type_l = 'individual' then 'Property owner' else '' end),
            public._jtext(v_lister, 'avatar_url', 600))
    on conflict (firebase_uid) do update
      set name = excluded.name, agency_name = excluded.agency_name,
          avatar_url = coalesce(excluded.avatar_url, public.agents.avatar_url)
    returning id into v_agent_id;
  end if;

  insert into public.listings as l (
    id, owner_uid, agent_id, market, status, purpose, segment, type,
    title, description, area, city, address, lat, lng,
    beds, baths, bua_sqft, bua_value, area_unit, occupancy, furnishing, age_years,
    price, previous_price, currency, rent_period,
    badges, permit_no, photos, amenities, fair_price,
    video_url, tour_requested, reels_package, contact_phone, contact_whatsapp, contact_email,
    submitted_at, review_note)
  values (
    coalesce(v_id, 'l_' || replace(gen_random_uuid()::text, '-', '')),
    v_uid,
    coalesce(v_agent_id, v_old.agent_id),
    v_market,
    case when p_submit then 'in_review' else 'draft' end,
    v_purpose, v_segment, public._jtext(p, 'type', 40),
    coalesce(public._jtext(p, 'title', 70), ''),
    coalesce(public._jtext(p, 'description', 4000), ''),
    coalesce(public._jtext(p, 'community', 120), ''),
    coalesce(public._jtext(p, 'city', 80), ''),
    -- Public address: community and city only. The exact one is private.
    concat_ws(', ', public._jtext(p, 'community', 120), public._jtext(p, 'city', 80)),
    -- Public pin: rounded to ~100 m. The exact one is private.
    round(v_lat::numeric, 3)::float8, round(v_lng::numeric, 3)::float8,
    coalesce(public._jint(p, 'beds', 0, 50), 0),
    coalesce(public._jint(p, 'baths', 0, 50), 0),
    v_bua_sqft, v_bua, v_unit,
    public._jint(p, 'occupancy', 1, 100),
    v_furnish,
    public._jint(p, 'age_years', 0, 200),
    v_price,
    -- A price cut on a listing that was live shows the "▼" badge.
    case when v_old.status in ('live', 'paused', 'rented', 'sold') and v_old.price > v_price
         then v_old.price else v_old.previous_price end,
    coalesce(upper(public._jtext(p, 'currency', 3)), 'AED'),
    v_period,
    case when p_submit then
      array(select distinct b from unnest(
        coalesce(v_old.badges, '{}') || case when v_type_l = 'individual' then array['owner'] else '{}'::text[] end) b
        where b <> 'owner' or v_type_l = 'individual')
    else coalesce(v_old.badges, '{}') end,
    public._jtext(p, 'permit_no', 40),
    v_photos, v_amen,
    case when p_submit then public._fair_price(v_market, v_purpose, v_segment, public._jtext(p, 'type', 40),
           coalesce(public._jint(p, 'beds', 0, 50), 0)::int, v_bua_sqft, v_price, v_period, v_id)
         else v_old.fair_price end,
    v_video,
    coalesce((p ->> 'tour_requested')::boolean, false),
    case when p ->> 'reels_package' in ('unlimited_30d', 'century') then p ->> 'reels_package' end,
    public._clean_phone(p ->> 'contact_phone'),
    public._clean_phone(p ->> 'contact_whatsapp'),
    v_email,
    case when p_submit then now() else v_old.submitted_at end,
    null)
  on conflict (id) do update set
    agent_id = excluded.agent_id, market = excluded.market, status = excluded.status,
    purpose = excluded.purpose, segment = excluded.segment, type = excluded.type,
    title = excluded.title, description = excluded.description, area = excluded.area,
    city = excluded.city, address = excluded.address, lat = excluded.lat, lng = excluded.lng,
    beds = excluded.beds, baths = excluded.baths, bua_sqft = excluded.bua_sqft,
    bua_value = excluded.bua_value, area_unit = excluded.area_unit, occupancy = excluded.occupancy,
    furnishing = excluded.furnishing, age_years = excluded.age_years, price = excluded.price,
    previous_price = excluded.previous_price, currency = excluded.currency,
    rent_period = excluded.rent_period, badges = excluded.badges, permit_no = excluded.permit_no,
    photos = excluded.photos, amenities = excluded.amenities, fair_price = excluded.fair_price,
    video_url = excluded.video_url, tour_requested = excluded.tour_requested,
    reels_package = excluded.reels_package,
    contact_phone = excluded.contact_phone, contact_whatsapp = excluded.contact_whatsapp,
    contact_email = excluded.contact_email, submitted_at = excluded.submitted_at,
    review_note = excluded.review_note,
    available = true, unavailable_reason = null
  returning * into v_row;

  insert into public.listing_private as pv (listing_id, owner_uid, address, lat, lng, lister_type,
                                            title_deed, id_front, id_back, selfie)
  values (v_row.id, v_uid, coalesce(public._jtext(p, 'address', 300), ''), v_lat, v_lng, v_type_l,
          v_deed, v_id_front, v_id_back, v_selfie)
  on conflict (listing_id) do update set
    address = excluded.address, lat = excluded.lat, lng = excluded.lng,
    lister_type = excluded.lister_type, title_deed = excluded.title_deed,
    id_front = excluded.id_front, id_back = excluded.id_back, selfie = excluded.selfie,
    updated_at = now();

  return v_row.id;
end $$;

-- "Save" / "Save as draft". Editing a listing that was live takes it back to
-- draft until it's submitted (and reviewed) again.
create or replace function public.save_listing(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id text;
begin
  -- Two statements on purpose: the read must see the row the write just made.
  v_id := public._seller_upsert(p, false);
  return public._my_listing_json(v_id);
end $$;

-- "Publish listing" → In review. Goes live when you approve it.
create or replace function public.submit_listing(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id text;
begin
  -- Two statements on purpose: the read must see the row the write just made.
  v_id := public._seller_upsert(p, true);
  return public._my_listing_json(v_id);
end $$;

create or replace function public.my_listings()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public._my_listing_json(l.id) order by l.updated_at desc), '[]'::jsonb)
  from public.listings l
  where l.owner_uid = public._require_uid()
$$;

-- Mark rented/sold ('closed'), pause, republish ('live' — only for a listing
-- that was approved before), or take back to 'draft'.
create or replace function public.set_my_listing_status(p_id text, p_status text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid text := public._require_uid();
  v_l public.listings;
begin
  select * into v_l from public.listings where id = p_id and owner_uid = v_uid for update;
  if not found then raise exception 'This listing no longer exists.' using errcode = 'P0002'; end if;

  if p_status = 'closed' then
    update public.listings set
      status = case when purpose = 'sale' then 'sold' else 'rented' end,
      available = false,
      unavailable_reason = case when purpose = 'sale' then 'SOLD' else 'RENTED' end
    where id = p_id;
  elsif p_status = 'paused' then
    update public.listings set status = 'paused', available = false, unavailable_reason = 'PAUSED'
    where id = p_id;
  elsif p_status = 'live' then
    if v_l.published_at is null or v_l.status not in ('paused', 'rented', 'sold', 'live') then
      raise exception 'This listing needs to be reviewed before it can go live.' using errcode = 'P0001';
    end if;
    update public.listings set status = 'live', available = true, unavailable_reason = null where id = p_id;
  elsif p_status = 'draft' then
    update public.listings set status = 'draft' where id = p_id;
  else
    raise exception 'Unknown status %', p_status using errcode = '22023';
  end if;
  return public._my_listing_json(p_id);
end $$;

-- Deletes the listing and returns the storage paths of its files so the app
-- can remove them from Storage too.
create or replace function public.delete_my_listing(p_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid text := public._require_uid();
  v_l public.listings;
  v_pv public.listing_private;
  v_paths jsonb := '[]';
begin
  select * into v_l from public.listings where id = p_id and owner_uid = v_uid;
  if not found then return v_paths; end if;
  select * into v_pv from public.listing_private where listing_id = p_id;

  select coalesce(jsonb_agg(jsonb_build_object('bucket', b, 'path', path)), '[]') into v_paths
  from (
    select 'listing-photos' b, split_part(u, '/listing-photos/', 2) path from unnest(v_l.photos) u
    union all
    select 'listing-videos', split_part(v_l.video_url, '/listing-videos/', 2) where v_l.video_url is not null
    union all
    select 'listing-private', d ->> 'path'
    from unnest(array[v_pv.title_deed, v_pv.id_front, v_pv.id_back, v_pv.selfie]) d where d is not null
  ) x
  where path <> '' and left(path, length(v_uid) + 1) = v_uid || '/';

  delete from public.listings where id = p_id;
  return v_paths;
end $$;

-- Boost is a paid feature with no payments yet: this records the request so
-- you can follow up, and the app says so.
create or replace function public.request_boost(p_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update public.listings set boost_requested_at = now()
  where id = p_id and owner_uid = public._require_uid() and status = 'live';
  if not found then raise exception 'Only live listings can be boosted.' using errcode = 'P0001'; end if;
  return public._my_listing_json(p_id);
end $$;

-- -----------------------------------------------------------------------------
-- 10. Views and contact taps, stats and performance
-- -----------------------------------------------------------------------------
-- Called when a buyer opens a listing (kind 'view') or taps Call / WhatsApp /
-- Email. The owner's own visits don't count.
create or replace function public.record_listing_event(p_id text, p_kind text, p_device text)
returns void language plpgsql security definer set search_path = public as $$
declare v_owner text;
begin
  if p_kind not in ('view', 'call', 'whatsapp', 'email') or coalesce(p_device, '') = '' then return; end if;
  select owner_uid into v_owner from public.listings where id = p_id and status = 'live';
  if not found or v_owner is not distinct from public.firebase_uid() then return; end if;
  insert into public.listing_events (listing_id, kind, device, hour)
  values (p_id, p_kind, left(p_device, 64), date_trunc('hour', now()))
  on conflict do nothing;
end $$;

create or replace function public.lister_stats()
returns jsonb language sql stable security definer set search_path = public as $$
  with me as (select public._require_uid() uid)
  select jsonb_build_object(
    'saved', (select count(*) from public.saved_listings s, me where s.user_uid = me.uid),
    'listings', (select count(*) from public.listings l, me where l.owner_uid = me.uid),
    'viewings', (select count(*) from public.listing_events e join public.listings l on l.id = e.listing_id, me
                 where l.owner_uid = me.uid and e.kind = 'view'),
    'rating', 0,
    'trust_score', null,
    'id_verified', exists (select 1 from public.agents a, me where a.firebase_uid = me.uid and a.verified)
                   or exists (select 1 from public.listings l, me
                              where l.owner_uid = me.uid and 'verified' = any (l.badges)))
$$;

-- Views over time for one listing. p_days: 30, 7, or 1 (hourly).
create or replace function public.listing_performance(p_id text, p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_uid text := public._require_uid();
  v_days int := case when p_days in (1, 7, 30) then p_days else 30 end;
  v_start timestamptz;
  v_step interval;
  v_series jsonb;
  v_views int; v_prev int; v_enq int; v_saves int;
begin
  if not exists (select 1 from public.listings where id = p_id and owner_uid = v_uid) then
    raise exception 'This listing no longer exists.' using errcode = 'P0002';
  end if;

  if v_days = 1 then
    v_step := interval '1 hour';
    v_start := date_trunc('hour', now()) - interval '23 hours';
  else
    v_step := interval '1 day';
    v_start := date_trunc('day', now()) - (v_days - 1) * interval '1 day';
  end if;

  select jsonb_agg(jsonb_build_object(
           'label', case when v_days = 1 then to_char(b, 'HH24:00') else to_char(b, 'DD Mon') end,
           'value', (select count(*) from public.listing_events e
                     where e.listing_id = p_id and e.kind = 'view' and e.hour >= b and e.hour < b + v_step))
         order by b)
    into v_series
  from generate_series(v_start, now(), v_step) b;

  select count(*) filter (where kind = 'view' and hour >= v_start),
         count(*) filter (where kind = 'view' and hour >= v_start - (now() - v_start) and hour < v_start),
         count(*) filter (where kind <> 'view' and hour >= v_start)
    into v_views, v_prev, v_enq
  from public.listing_events where listing_id = p_id;

  select count(*) into v_saves from public.saved_listings where listing_id = p_id;

  return jsonb_build_object(
    'series', coalesce(v_series, '[]'),
    'total_views', v_views,
    'enquiries', v_enq,
    'saves', v_saves,
    'views_change_pct', case when v_prev > 0 then round((v_views - v_prev) * 100.0 / v_prev, 1) end,
    'conversion_pct', case when v_views > 0 then round(v_enq * 100.0 / v_views, 1) else 0 end,
    'saves_rank', '',
    'boost_price', '');
end $$;

-- -----------------------------------------------------------------------------
-- 11. Agent / company verification (screen 29)
-- -----------------------------------------------------------------------------
create or replace function public.submit_verification(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid text := public._require_uid();
  v_licence jsonb := public._jdoc(p, 'trade_licence', v_uid);
begin
  if public._jtext(p, 'organisation', 120) is null or public._jtext(p, 'licence_number', 60) is null
     or v_licence is null then
    raise exception 'Add the name, licence number and licence document.' using errcode = 'P0001';
  end if;
  insert into public.lister_verifications (owner_uid, lister_type, organisation, licence_number,
                                           trade_licence, broker_card)
  values (v_uid,
          case when p ->> 'type' = 'company' then 'company' else 'agent' end,
          public._jtext(p, 'organisation', 120),
          public._jtext(p, 'licence_number', 60),
          v_licence,
          public._jdoc(p, 'broker_card', v_uid));
  return jsonb_build_object('status', 'pending');
end $$;

-- -----------------------------------------------------------------------------
-- 12. ADMIN — run these yourself in the SQL editor. Not callable from the app.
-- -----------------------------------------------------------------------------
-- Approve:  select public.review_listing('l_…', true);
-- Reject:   select public.review_listing('l_…', false, 'Photos are blurry');
-- p_verified: give the Verified badge when approving (default yes).
create or replace function public.review_listing(
  p_id text, p_approve boolean, p_note text default null, p_verified boolean default true)
returns text language plpgsql security definer set search_path = public as $$
declare v_l public.listings;
begin
  select * into v_l from public.listings where id = p_id for update;
  if not found then return 'not found'; end if;

  if p_approve then
    update public.listings set
      status = 'live',
      available = true,
      unavailable_reason = null,
      review_note = null,
      reference = coalesce(reference, 'H8-' || nextval('public.listing_ref_seq')),
      badges = case when p_verified
                    then array(select distinct b from unnest(badges || array['verified']) b)
                    else array_remove(badges, 'verified') end,
      fair_price = coalesce(public._fair_price(market, purpose, segment, type, beds, bua_sqft,
                                               price, rent_period, id), fair_price)
    where id = p_id;
    return 'approved: live now';
  else
    update public.listings set status = 'rejected', review_note = coalesce(p_note, 'Needs changes')
    where id = p_id;
    return 'rejected';
  end if;
end $$;

-- Approve an agent / company: marks their agent card Verified.
-- select public.review_verification('<firebase uid>', true);
create or replace function public.review_verification(p_uid text, p_approve boolean, p_note text default null)
returns text language plpgsql security definer set search_path = public as $$
begin
  update public.lister_verifications
     set status = case when p_approve then 'verified' else 'rejected' end, review_note = p_note
   where id = (select id from public.lister_verifications where owner_uid = p_uid order by created_at desc limit 1);
  if p_approve then
    update public.agents set verified = true where firebase_uid = p_uid;
  end if;
  return case when p_approve then 'verified' else 'rejected' end;
end $$;

-- -----------------------------------------------------------------------------
-- 13. Public listing JSON now carries video and contact details.
-- (Same as before plus 'video_url' and 'contact'.)
-- -----------------------------------------------------------------------------
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
    'segment', l.segment,
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
    'video_url', l.video_url,
    'contact', jsonb_strip_nulls(jsonb_build_object(
      'phone', l.contact_phone,
      'whatsapp', l.contact_whatsapp,
      'email', l.contact_email)),
    'agent', (
      select jsonb_build_object(
        'id', a.id, 'name', a.name, 'agency_name', a.agency_name,
        'avatar_url', a.avatar_url, 'verified', a.verified,
        'response_time', a.response_time)
      from public.agents a where a.id = l.agent_id)
  )
$$;

-- -----------------------------------------------------------------------------
-- 14. Who can call what
-- -----------------------------------------------------------------------------
revoke all on function
  public._require_uid(),
  public._fair_price(text, text, text, text, int, int, bigint, text, text),
  public._my_listing_json(text),
  public._seller_upsert(jsonb, boolean),
  public.review_listing(text, boolean, text, boolean),
  public.review_verification(text, boolean, text)
from public, anon, authenticated;

grant execute on function
  public.price_guidance(jsonb),
  public.save_listing(jsonb),
  public.submit_listing(jsonb),
  public.my_listings(),
  public.set_my_listing_status(text, text),
  public.delete_my_listing(text),
  public.request_boost(text),
  public.lister_stats(),
  public.listing_performance(text, int),
  public.submit_verification(jsonb)
to authenticated;

revoke execute on function
  public.price_guidance(jsonb),
  public.save_listing(jsonb),
  public.submit_listing(jsonb),
  public.my_listings(),
  public.set_my_listing_status(text, text),
  public.delete_my_listing(text),
  public.request_boost(text),
  public.lister_stats(),
  public.listing_performance(text, int),
  public.submit_verification(jsonb)
from public, anon;

grant execute on function public.record_listing_event(text, text, text) to anon, authenticated;
grant execute on function public.listing_json(public.listings) to anon, authenticated;
