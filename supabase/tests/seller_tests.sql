\set ON_ERROR_STOP 1
create or replace function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FAIL: %', label; end if; raise notice 'ok - %', label; end $$;

-- ---------- seller A ----------
set role authenticated;
set request.jwt.claims = '{"iss":"https://securetoken.google.com/home8-61d48","aud":"home8-61d48","sub":"sellerA","role":"authenticated"}';

do $$ begin
  insert into public.listings (purpose, title, price) values ('rent', 'direct', 1);
  raise exception 'FAIL: direct insert allowed';
exception when insufficient_privilege then raise notice 'ok - direct insert blocked';
end $$;

create temp table t (k text primary key, v jsonb);
grant all on t to authenticated, anon;

insert into t values ('d1', public.save_listing('{"purpose":"rent","segment":"residential","title":"Half done","country":"AE","city":"Dubai"}'));
select pg_temp.check('draft saved with id', (select (v->>'id') like 'l_%' and v->>'status' = 'draft' from t where k='d1'));
select pg_temp.check('draft knows what is missing (no type)', (select v->'draft'->>'type' is null from t where k='d1'));

-- ---------- account verification gate ----------
select pg_temp.check('never verified -> none', (select public.my_verification()->>'status' = 'none'));
do $$ begin
  perform public.submit_listing('{"purpose":"rent"}');
  raise exception 'FAIL: unverified account published';
exception when raise_exception then
  if sqlerrm not like '%still being verified%' then raise exception 'FAIL: wrong message %', sqlerrm; end if;
  raise notice 'ok - unverified account cannot publish';
end $$;
do $$ begin
  perform public.submit_verification('{"type":"individual","legal_name":"Sara Owner"}');
  raise exception 'FAIL: verification without ID accepted';
exception when raise_exception then raise notice 'ok - individual needs ID front and back';
end $$;
select pg_temp.check('individual verification submitted', (select public.submit_verification(
  '{"type":"individual","legal_name":"Sara Owner","id_front":{"name":"f.jpg","bytes":5,"path":"sellerA/docs/vf.jpg"},"id_back":{"name":"b.jpg","bytes":5,"path":"sellerA/docs/vb.jpg"}}')->>'status' = 'pending'));
select pg_temp.check('pending', (select public.my_verification()->>'status' = 'pending' and public.my_verification()->>'type' = 'individual'));
select pg_temp.check('resubmitting while pending updates, not duplicates', (select public.submit_verification(
  '{"type":"individual","legal_name":"Sara A. Owner","id_front":{"name":"f.jpg","bytes":5,"path":"sellerA/docs/vf.jpg"},"id_back":{"name":"b.jpg","bytes":5,"path":"sellerA/docs/vb.jpg"}}')->>'status' = 'pending'));
do $$ begin
  perform public.review_verification('sellerA', true);
  raise exception 'FAIL: seller approved own account';
exception when insufficient_privilege then raise notice 'ok - seller cannot approve own account';
end $$;
reset role;
select pg_temp.check('one request row', (select count(*) = 1 from public.lister_verifications where owner_uid = 'sellerA'));
select pg_temp.check('admin rejects', (select public.review_verification('sellerA', false, 'ID is blurry') = 'rejected'));
set role authenticated;
set request.jwt.claims = '{"iss":"https://securetoken.google.com/home8-61d48","aud":"home8-61d48","sub":"sellerA","role":"authenticated"}';
select pg_temp.check('seller sees rejection + note', (select v->>'status' = 'rejected' and v->>'review_note' = 'ID is blurry' from (select public.my_verification() v) x));
select pg_temp.check('resubmit after rejection -> pending', (select public.submit_verification(
  '{"type":"individual","legal_name":"Sara Owner","id_front":{"name":"f.jpg","bytes":5,"path":"sellerA/docs/vf2.jpg"},"id_back":{"name":"b.jpg","bytes":5,"path":"sellerA/docs/vb2.jpg"}}')->>'status' = 'pending'));
reset role;
select pg_temp.check('admin approves', (select public.review_verification('sellerA', true) = 'verified'));
select pg_temp.check('agent card created verified', (select verified and agency_name = 'Property owner' from public.agents where firebase_uid = 'sellerA'));
set role authenticated;
set request.jwt.claims = '{"iss":"https://securetoken.google.com/home8-61d48","aud":"home8-61d48","sub":"sellerA","role":"authenticated"}';
select pg_temp.check('verified', (select public.my_verification()->>'status' = 'verified'));

do $$ begin
  perform public.submit_listing(jsonb_build_object('id', (select v->>'id' from t where k='d1'), 'purpose', 'rent', 'country', 'AE'));
  raise exception 'FAIL: incomplete submit accepted';
exception when raise_exception then
  if sqlerrm not like 'Still needed:%photos%' then raise exception 'FAIL: wrong message %', sqlerrm; end if;
  raise notice 'ok - incomplete submit refused: %', sqlerrm;
end $$;

-- A full listing, as the app sends it.
insert into t values ('full', jsonb_build_object(
  'id', (select v->>'id' from t where k='d1'),
  'purpose', 'rent', 'segment', 'residential', 'type', 'apartment',
  'country', 'AE', 'city', 'Dubai', 'community', 'Dubai Marina',
  'address', 'Flat 1203, Marina Gate 1, Dubai Marina', 'lat', 25.0861234, 'lng', 55.1472345,
  'beds', 2, 'baths', 2, 'bua', 1100, 'area_unit', 'sqft', 'price', 98000, 'currency', 'AED',
  'rent_period', 'yearly', 'furnishing', 'Furnished', 'title', 'Bright 2BR with full sea view',
  'description', 'Lovely bright flat with sea views, parking and gym.',
  'occupancy', 4, 'age_years', 6, 'amenities', '["Wifi","Shared Pool","Wifi"]'::jsonb, 'permit_no', '7145-22',
  'photos', jsonb_build_array(
     'https://x.supabase.co/storage/v1/object/public/listing-photos/sellerA/a.jpg',
     'https://x.supabase.co/storage/v1/object/public/listing-photos/sellerA/b.jpg',
     'https://evil.example.com/stolen.jpg',
     'https://x.supabase.co/storage/v1/object/public/listing-photos/sellerB/c.jpg'),
  'video_url', 'https://x.supabase.co/storage/v1/object/public/listing-videos/sellerA/v.mp4',
  'tour_requested', true, 'reels_package', 'century',
  'title_deed', '{"name":"deed.pdf","bytes":1200,"path":"sellerA/docs/deed.pdf"}'::jsonb,
  'id_front', '{"name":"f.jpg","bytes":10,"path":"sellerA/docs/f.jpg"}'::jsonb,
  'id_back', '{"name":"b.jpg","bytes":10,"path":"sellerA/docs/b.jpg"}'::jsonb,
  'selfie', '{"name":"s.jpg","bytes":10,"path":"sellerB/docs/s.jpg"}'::jsonb,
  'contact_phone', '+971 50 123 4567', 'contact_whatsapp', '+971501234567', 'contact_email', 'a@b.co',
  'lister', '{"name":"Sara Owner","type":"individual"}'::jsonb,
  -- Things a seller must NOT be able to set:
  'badges', '["verified"]'::jsonb, 'featured', true, 'rating', 5, 'status', 'live'));

insert into t values ('sub', public.submit_listing((select v from t where k='full')));
select pg_temp.check('submitted -> inReview', (select v->>'status' = 'inReview' from t where k='sub'));
select pg_temp.check('foreign photo URLs dropped (2 kept)', (select jsonb_array_length(v->'draft'->'photos') = 2 from t where k='sub'));
select pg_temp.check('selfie in someone else''s folder dropped', (select v->'draft'->'selfie' = 'null'::jsonb from t where k='sub'));
select pg_temp.check('amenities de-duplicated', (select jsonb_array_length(v->'draft'->'amenities') = 2 from t where k='sub'));
select pg_temp.check('owner sees exact address back', (select v->'draft'->>'address' = 'Flat 1203, Marina Gate 1, Dubai Marina' from t where k='sub'));
select pg_temp.check('owner sees exact pin', (select (v->'draft'->>'lat')::float8 = 25.0861234 from t where k='sub'));
select pg_temp.check('reels choice kept', (select v->'draft'->>'reels_package' = 'century' from t where k='sub'));
select pg_temp.check('phone cleaned', (select v->'draft'->>'contact_phone' = '+971501234567' from t where k='sub'));

select pg_temp.check('no self-granted badges', (select not ('verified' = any (badges)) and 'owner' = any (badges) and not featured and rating = 0
                                                from public.listings where id = (select v->>'id' from t where k='sub')));
select pg_temp.check('agent card created for the seller', (select a.name = 'Sara Owner' and a.agency_name = 'Property owner'
  from public.listings l join public.agents a on a.id = l.agent_id where l.id = (select v->>'id' from t where k='sub')));
select pg_temp.check('in review is not in search', (select (public.search_listings('{"purpose":"rent","segment":"residential"}')->>'total')::int = 5));
select pg_temp.check('my_listings has it', (select jsonb_array_length(public.my_listings()) = 1));

do $$ begin
  perform 1 from public.listing_private;
  raise exception 'FAIL: listing_private readable';
exception when insufficient_privilege then raise notice 'ok - private table not readable directly';
end $$;

do $$ begin
  perform public.review_listing((select v->>'id' from t where k='sub'), true);
  raise exception 'FAIL: seller approved own listing';
exception when insufficient_privilege then raise notice 'ok - seller cannot approve';
end $$;

select pg_temp.check('price guidance has a band from live comps',
  (select g is not null and (g->>'comparable_count')::int >= 3 and g->>'verdict' in ('low','fair','high')
   from (select public.price_guidance('{"purpose":"rent","segment":"residential","type":"apartment","country":"AE","beds":2,"bua":1100,"price":98000,"rent_period":"yearly"}') g) x));
select pg_temp.check('monthly price judged on same scale',
  (select public.price_guidance('{"purpose":"rent","type":"apartment","country":"AE","beds":2,"bua":1100,"price":8000,"rent_period":"monthly"}')->>'verdict'
        = public.price_guidance('{"purpose":"rent","type":"apartment","country":"AE","beds":2,"bua":1100,"price":96000,"rent_period":"yearly"}')->>'verdict'));
reset role;

-- ---------- admin approves (SQL editor = postgres) ----------
select pg_temp.check('approve', (select public.review_listing((select v->>'id' from t where k='sub'), true) like 'approved%'));
select pg_temp.check('live, verified, has reference and published_at', (select status = 'live' and 'verified' = any (badges) and reference like 'H8-%' and published_at is not null
  from public.listings where id = (select v->>'id' from t where k='sub')));

-- ---------- a buyer (anon) ----------
set role anon;
set request.jwt.claims = '{}';
select pg_temp.check('now in search', (select (public.search_listings('{"purpose":"rent","segment":"residential"}')->>'total')::int = 6));
select pg_temp.check('public JSON: no exact address, rounded pin, contact present',
  (select j->>'address' = 'Dubai Marina, Dubai' and (j->>'lat')::float8 = 25.086 and j->'contact'->>'phone' = '+971501234567'
          and j->>'video_url' like '%listing-videos%' and (j->>'occupancy')::int = 4 and (j->>'age_years')::int = 6
          and j->>'permit_no' = '7145-22' and j->'agent'->>'name' = 'Sara Owner'
   from (select public.listing_by_id((select v->>'id' from t where k='sub')) j) x));
select pg_temp.check('exact address not in any public column', (select count(*) = 0 from public.listings where address like '%1203%'));
select public.record_listing_event((select v->>'id' from t where k='sub'), 'view', 'dev1');
select public.record_listing_event((select v->>'id' from t where k='sub'), 'view', 'dev1');
select public.record_listing_event((select v->>'id' from t where k='sub'), 'view', 'dev2');
select public.record_listing_event((select v->>'id' from t where k='sub'), 'call', 'dev2');
do $$ begin
  perform public.my_listings();
  raise exception 'FAIL: anon called my_listings';
exception when insufficient_privilege then raise notice 'ok - anon cannot list seller data';
end $$;
reset role;

-- ---------- seller A again: numbers, status, delete ----------
set role authenticated;
set request.jwt.claims = '{"iss":"https://securetoken.google.com/home8-61d48","aud":"home8-61d48","sub":"sellerA","role":"authenticated"}';
select public.record_listing_event((select v->>'id' from t where k='sub'), 'view', 'owner-device');
select pg_temp.check('views 2 (deduped, owner not counted), enquiries 1',
  (select (m->>'views')::int = 2 and (m->>'enquiries')::int = 1 and m->>'status' = 'live' and m->>'reference' like 'H8-%'
   from (select public.my_listings()->0 m) x));
select pg_temp.check('performance: 30 points, 2 views',
  (select jsonb_array_length(p->'series') = 30 and (p->>'total_views')::int = 2
   from (select public.listing_performance((select v->>'id' from t where k='sub'), 30) p) x));
select pg_temp.check('performance 24h: 24 points', (select jsonb_array_length(public.listing_performance((select v->>'id' from t where k='sub'), 1)->'series') = 24));
select pg_temp.check('stats', (select (s->>'listings')::int = 1 and (s->>'viewings')::int = 2 and (s->>'id_verified')::boolean
   from (select public.lister_stats() s) x));
select pg_temp.check('boost request recorded', (select public.request_boost((select v->>'id' from t where k='sub'))->>'status' = 'live'));
select pg_temp.check('mark rented', (select public.set_my_listing_status((select v->>'id' from t where k='sub'), 'closed')->>'status' = 'closed'));
select pg_temp.check('rented hidden from search', (select (public.search_listings('{"purpose":"rent","segment":"residential"}')->>'total')::int = 5));
select pg_temp.check('republish', (select public.set_my_listing_status((select v->>'id' from t where k='sub'), 'live')->>'status' = 'live'));

-- Editing a live listing with a lower price: back to review, price-drop recorded.
select pg_temp.check('edit + resubmit -> in review with previous price',
  (select public.submit_listing((select v from t where k='full') || '{"price":90000}')->>'status' = 'inReview'));
select pg_temp.check('previous_price kept for the drop badge', (select previous_price = 98000 from public.listings where id = (select v->>'id' from t where k='sub')));
reset role;

-- ---------- seller B can't touch A's listing ----------
set role authenticated;
set request.jwt.claims = '{"iss":"https://securetoken.google.com/home8-61d48","aud":"home8-61d48","sub":"sellerB","role":"authenticated"}';
do $$ begin
  perform public.save_listing((select v from t where k='full'));
  raise exception 'FAIL: B overwrote A';
exception when no_data_found then raise notice 'ok - B cannot edit A''s listing';
end $$;
select pg_temp.check('B delete does nothing', (select public.delete_my_listing((select v->>'id' from t where k='sub')) = '[]'::jsonb));
select pg_temp.check('B sees no listings of its own', (select public.my_listings() = '[]'::jsonb));
select pg_temp.check('verification request', (select public.submit_verification(
  '{"type":"company","organisation":"Acme Realty","licence_number":"TL-1","trade_licence":{"name":"tl.pdf","bytes":5,"path":"sellerB/verification/tl.pdf"}}')->>'status' = 'pending'));
reset role;

-- ---------- A deletes: gets back the files to remove ----------
set role authenticated;
set request.jwt.claims = '{"iss":"https://securetoken.google.com/home8-61d48","aud":"home8-61d48","sub":"sellerA","role":"authenticated"}';
select pg_temp.check('delete returns own files only (2 photos + video + 3 docs)',
  (select jsonb_array_length(d) = 6 and not d::text like '%sellerB%'
   from (select public.delete_my_listing((select v->>'id' from t where k='sub')) d) x));
select pg_temp.check('gone', (select public.my_listings() = '[]'::jsonb));
reset role;
