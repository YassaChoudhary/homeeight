\set ON_ERROR_STOP 1
create or replace function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FAIL: %', label; end if; raise notice 'ok - %', label; end $$;
set role anon;
select pg_temp.check('marina -> Dubai Marina with real count',
  (select s->0->>'title' = 'Dubai Marina' and (s->0->>'count')::int >= 2 from (select public.suggest_places('marina') s) x));
select pg_temp.check('city suggestion from listings', (select public.suggest_places('dub')::text like '%"City"%'));
select pg_temp.check('no duplicates by name',
  (select count(*) = count(distinct lower(e->>'title')) from jsonb_array_elements(public.suggest_places('a')) e));
select pg_temp.check('empty term -> empty list', (select public.suggest_places('  ') = '[]'::jsonb));
select pg_temp.check('max 10', (select jsonb_array_length(public.suggest_places('a')) <= 10));
reset role;
-- an area only known from a live listing (not in places)
update public.listings set area = 'Zabeel Heights' where id = 'p7';
set role anon;
select pg_temp.check('community from a listing (not in places) is suggested',
  (select s->0->>'title' = 'Zabeel Heights' and (s->0->>'count')::int = 1 and s->0->>'subtitle' like 'Community%'
   from (select public.suggest_places('zabeel') s) x));
select pg_temp.check('bua filter works', (select (public.search_listings('{"purpose":"rent","bua_min":"1000","bua_max":"1200"}')->>'total')::int >= 1));
reset role;
-- smart search
reset role;
update public.listings set type = 'penthouse', title = 'Sky Residence', purpose = 'sale' where id = 'p3';
set role anon;
select pg_temp.check('plural folded', (select public._search_words('Penthouses in Marina') = array['penthouse','marina']));
select pg_temp.check('type match, sale', (select (public.search_listings('{"purpose":"sale","q":"penthouses"}')->>'total')::int >= 1));
select pg_temp.check('rent search reports sale matches in other_total',
  (select (r->>'total')::int = 0 and (r->>'other_total')::int >= 1
   from (select public.search_listings('{"purpose":"rent","q":"penthouse"}') r) x));
select pg_temp.check('type suggestion', (select public.suggest_places('pent')::text like '%"Property type"%'));
select pg_temp.check('listing title suggestion', (select public.suggest_places('sky resid')::text like '%"l:p3"%'));
select pg_temp.check('page size up to 300', (select (public.search_listings('{"purpose":"rent","page_size":"300"}')->>'page_size')::int = 300));
select pg_temp.check('empty q still returns all', (select (public.search_listings('{"purpose":"rent","q":"  "}')->>'total')::int > 0));
reset role;
