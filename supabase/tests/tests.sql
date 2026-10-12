\set ON_ERROR_STOP 1
create or replace function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin if not ok then raise exception 'FAIL: %', label; end if; raise notice 'ok - %', label; end $$;

-- ---------- as an anonymous visitor ----------
set role anon;
select pg_temp.check('rent default returns 5 rent listings',
  (select (public.search_listings('{"purpose":"rent"}')->>'total')::int = 5));
select pg_temp.check('sale returns 2',
  (select (public.search_listings('{"purpose":"sale"}')->>'total')::int = 2));
select pg_temp.check('relevance: featured first (p3)',
  (select public.search_listings('{"purpose":"rent","sort":"relevance"}')->'results'->0->>'id' = 'p3'));
select pg_temp.check('price_asc first is cheapest (p1 96000)',
  (select public.search_listings('{"purpose":"rent","sort":"price_asc"}')->'results'->0->>'id' = 'p1'));
select pg_temp.check('price_desc first is p2',
  (select public.search_listings('{"purpose":"rent","sort":"price_desc"}')->'results'->0->>'id' = 'p2'));
select pg_temp.check('newest first is p5',
  (select public.search_listings('{"purpose":"rent","sort":"newest"}')->'results'->0->>'id' = 'p5'));
select pg_temp.check('bua_desc first is 1420 sqft',
  (select (public.search_listings('{"purpose":"rent","sort":"bua_desc"}')->'results'->0->>'bua_sqft')::int = 1420));
select pg_temp.check('price_per_sqft_asc first is p1',
  (select public.search_listings('{"purpose":"rent","sort":"price_per_sqft_asc"}')->'results'->0->>'id' = 'p1'));
select pg_temp.check('text search "marina" -> 2',
  (select (public.search_listings('{"purpose":"rent","q":"marina"}')->>'total')::int = 2));
select pg_temp.check('area filter Downtown -> p2',
  (select public.search_listings('{"purpose":"rent","area":"downtown"}')->'results'->0->>'id' = 'p2'));
select pg_temp.check('price range 100k-140k -> 3',
  (select (public.search_listings('{"purpose":"rent","price_min":"100000","price_max":"140000"}')->>'total')::int = 3));
select pg_temp.check('beds >= 3 -> 1',
  (select (public.search_listings('{"purpose":"rent","beds":"3"}')->>'total')::int = 1));
select pg_temp.check('bua 1100-1200 -> 2',
  (select (public.search_listings('{"purpose":"rent","bua_min":"1100","bua_max":"1200"}')->>'total')::int = 2));
select pg_temp.check('furnishing Unfurnished -> 2',
  (select (public.search_listings('{"purpose":"rent","furnishing":"Unfurnished"}')->>'total')::int = 2));
select pg_temp.check('furnishing Any ignored -> 5',
  (select (public.search_listings('{"purpose":"rent","furnishing":"Any"}')->>'total')::int = 5));
select pg_temp.check('amenities Sea View,Wifi -> 2',
  (select (public.search_listings('{"purpose":"rent","amenities":"Sea View,Wifi"}')->>'total')::int = 2));
select pg_temp.check('type villa -> 1',
  (select (public.search_listings('{"purpose":"rent","type":"villa"}')->>'total')::int = 1));
select pg_temp.check('off-plan -> 0',
  (select (public.search_listings('{"purpose":"rent","type":"Off-Plan Homes"}')->>'total')::int = 0));
select pg_temp.check('verified only (sale) -> 1',
  (select (public.search_listings('{"purpose":"sale","verified":"true"}')->>'total')::int = 1));
select pg_temp.check('map bounds around Downtown -> 1',
  (select (public.search_listings('{"purpose":"rent","min_lat":"25.19","max_lat":"25.20","min_lng":"55.27","max_lng":"55.28"}')->>'total')::int = 1));
select pg_temp.check('paging: page 2 size 2 has 2, total 5',
  (select jsonb_array_length(r->'results') = 2 and (r->>'total')::int = 5 and (r->>'page')::int = 2
   from (select public.search_listings('{"purpose":"rent","page":"2","page_size":"2"}') r) x));
select pg_temp.check('paging: page 3 size 2 has 1',
  (select jsonb_array_length(public.search_listings('{"purpose":"rent","page":"3","page_size":"2"}')->'results') = 1));
select pg_temp.check('pages do not overlap',
  (select count(distinct id) = 5 from (
     select jsonb_array_elements(public.search_listings(jsonb_build_object('purpose','rent','page',n::text,'page_size','2','sort','price_asc'))->'results')->>'id' id
     from generate_series(1,3) n) z));
select pg_temp.check('no results -> empty array',
  (select public.search_listings('{"purpose":"rent","q":"zzzz"}') = '{"page": 1, "total": 0, "other_total": 0, "results": [], "page_size": 20}'::jsonb));
select pg_temp.check('card JSON has agent object + badges',
  (select j->'agent'->>'name' = 'Tarik Abdullah' and j->'badges' ? 'guest_favourite' and j->'fair_price'->>'verdict' = 'fair'
   from (select public.listing_by_id('p1') j) x));
select pg_temp.check('similar to p1 excludes p1, 4 rent results',
  (select jsonb_array_length(s) = 4 and not s @> '[{"id":"p1"}]' from (select public.similar_listings('p1') s) x));
select pg_temp.check('comparables for p1 are apartments within 1 bed',
  (select jsonb_array_length(c) = 3 from (select public.comparable_listings('p1') c) x));
select pg_temp.check('highlights: featured first, 7 total',
  (select jsonb_array_length(h) = 7 and h->0->>'featured' = 'true' from (select public.highlight_listings(8) h) x));
select pg_temp.check('popular communities: 4, Dubai Marina has 2 homes',
  (select jsonb_array_length(c) = 4 and c->0->>'name' = 'Dubai Marina' and (c->0->>'homes')::int = 2
   from (select public.popular_communities(4) c) x));
select pg_temp.check('suggest "mar": Dubai Marina + towers',
  (select s->0->>'title' = 'Dubai Marina' and s::text like '%Marina Gate Tower%' and s::text like '%"l:p5"%' from (select public.suggest_places('mar') s) x));
select pg_temp.check('suggest empty -> []', (select public.suggest_places('  ') = '[]'::jsonb));
select pg_temp.check('reels feed: 5, saved false for anon',
  (select jsonb_array_length(r) = 5 and r->0->>'saved' = 'false' and r->0->'agent'->>'name' is not null from (select public.reels_feed() r) x));
select pg_temp.check('anon firebase_uid is null', (select public.firebase_uid() is null));
reset role;

-- anon cannot write
set role anon;
do $$ begin
  insert into public.saved_listings (listing_id) values ('p1');
  raise exception 'FAIL: anon could save';
exception when insufficient_privilege or check_violation or not_null_violation then raise notice 'ok - anon cannot save';
end $$;
do $$ begin
  update public.listings set price = 1 where id = 'p1';
  if exists (select 1 from public.listings where id='p1' and price = 1) then raise exception 'FAIL: anon updated'; end if;
  raise notice 'ok - anon cannot edit listings';
exception when insufficient_privilege then raise notice 'ok - anon cannot edit listings (refused)';
end $$;
reset role;

-- ---------- token from ANOTHER Firebase project is rejected ----------
set role authenticated;
set request.jwt.claims = '{"iss":"https://securetoken.google.com/evil-proj","aud":"evil-proj","sub":"hacker","role":"authenticated"}';
select pg_temp.check('foreign-project token gets no uid', (select public.firebase_uid() is null));
do $$ begin
  insert into public.saved_listings (listing_id) values ('p1');
  raise exception 'FAIL: foreign token could save';
exception when insufficient_privilege or check_violation or not_null_violation then raise notice 'ok - foreign token cannot save';
end $$;
reset role;

-- ---------- signed-in Firebase user A ----------
set role authenticated;
set request.jwt.claims = '{"iss":"https://securetoken.google.com/home8-61d48","aud":"home8-61d48","sub":"userA","role":"authenticated"}';
select pg_temp.check('user A uid', (select public.firebase_uid() = 'userA'));
insert into public.saved_listings (listing_id) values ('p1'), ('p6');
select pg_temp.check('A saved 2', (select count(*) = 2 from public.saved_listings));
select pg_temp.check('reels show saved for A', (select (public.reels_feed()->0->>'saved')::boolean from (select 1) x));
-- A creates a draft listing. Since the seller migration, writes go through
-- save_listing() (direct table writes are blocked); the owner comes from the token.
create temp table mine (id text);
grant all on mine to authenticated;
insert into mine select public.save_listing('{"purpose":"rent","title":"A draft","price":50000}')->>'id';
select pg_temp.check('owner_uid auto-filled', (select owner_uid = 'userA' from public.listings where id=(select id from mine)));
select pg_temp.check('A sees own draft', (select count(*) = 1 from public.listings where id=(select id from mine)));
select pg_temp.check('draft not in search', (select (public.search_listings('{"purpose":"rent","segment":"residential"}')->>'total')::int = 5));
select public.save_listing(jsonb_build_object('id', (select id from mine), 'purpose', 'rent', 'title', 'A draft edited', 'price', 50000));
select pg_temp.check('A edited own', (select title = 'A draft edited' from public.listings where id=(select id from mine)));
do $$ begin
  update public.listings set status = 'live' where id = (select id from mine);
  raise exception 'FAIL: owner self-published';
exception when check_violation or insufficient_privilege then raise notice 'ok - owner cannot self-publish';
end $$;
do $$ begin
  insert into public.listings (id, owner_uid, purpose, title, price) values ('fake', 'userB', 'rent', 'x', 1);
  raise exception 'FAIL: inserted as someone else';
exception when check_violation or insufficient_privilege then raise notice 'ok - cannot insert as another user';
end $$;
reset role;

-- ---------- user B ----------
set role authenticated;
set request.jwt.claims = '{"iss":"https://securetoken.google.com/home8-61d48","aud":"home8-61d48","sub":"userB","role":"authenticated"}';
select pg_temp.check('B sees none of A saved', (select count(*) = 0 from public.saved_listings));
select pg_temp.check('B cannot see A draft', (select count(*) = 0 from public.listings where id=(select id from mine)));
select public.delete_my_listing((select id from mine));
delete from public.saved_listings where user_uid = 'userA';
reset role;
select pg_temp.check('B could not touch A data',
  (select title = 'A draft edited' from public.listings where id=(select id from mine)) and (select count(*) = 2 from public.saved_listings where user_uid='userA'));

-- ---------- A unsaves and deletes ----------
set role authenticated;
set request.jwt.claims = '{"iss":"https://securetoken.google.com/home8-61d48","aud":"home8-61d48","sub":"userA","role":"authenticated"}';
delete from public.saved_listings where listing_id = 'p1';
select public.delete_my_listing((select id from mine));
reset role;
select pg_temp.check('A unsaved p1 and deleted draft',
  (select count(*) = 1 from public.saved_listings where user_uid='userA') and not exists (select 1 from public.listings where id=(select id from mine)));
