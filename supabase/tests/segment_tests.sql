\set ON_ERROR_STOP 1
create or replace function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin if not ok then raise exception 'FAIL: %', label; end if; raise notice 'ok - %', label; end $$;
set role anon;
select pg_temp.check('residential rent highlights: 5 homes, no commercial',
  (select jsonb_array_length(h) = 5 and not h @> '[{"type":"office"}]' from (select public.highlight_listings(p_limit => 8, p_market => 'AE', p_purpose => 'rent', p_segment => 'residential') h) x));
select pg_temp.check('commercial rent highlights: 3, featured office first',
  (select jsonb_array_length(h) = 3 and h->0->>'id' = 'c_1' from (select public.highlight_listings(p_limit => 8, p_market => 'AE', p_purpose => 'rent', p_segment => 'commercial') h) x));
select pg_temp.check('commercial sale highlights: 2',
  (select jsonb_array_length(public.highlight_listings(p_limit => 8, p_market => 'AE', p_purpose => 'sale', p_segment => 'commercial')) = 2));
select pg_temp.check('residential sale highlights: 2 (p6, p7)',
  (select jsonb_array_length(h) = 2 and h->0->>'id' = 'p6' from (select public.highlight_listings(p_limit => 8, p_market => 'AE', p_purpose => 'sale', p_segment => 'residential') h) x));
select pg_temp.check('commercial rent communities: exactly Business Bay, DIFC, Al Quoz (1 each)',
  (select jsonb_array_length(c) = 3 and (c->0->>'homes')::int = 1 and (c->2->>'homes')::int = 1
          and (select array_agg(e->>'name' order by e->>'name') from jsonb_array_elements(c) with ordinality t(e,n) where n <= 3) = array['Al Quoz','Business Bay','DIFC']
   from (select public.popular_communities(p_limit => 4, p_market => 'AE', p_purpose => 'rent', p_segment => 'commercial') c) x));
select pg_temp.check('residential rent communities: Dubai Marina 2 first, commercial not counted',
  (select c->0->>'name' = 'Dubai Marina' and (c->0->>'homes')::int = 2 from (select public.popular_communities(p_limit => 4, p_market => 'AE', p_purpose => 'rent', p_segment => 'residential') c) x));
select pg_temp.check('Business Bay residential sale counts only the studio (1), not the office',
  (select (e->>'homes')::int = 1 from jsonb_array_elements(public.popular_communities(p_limit => 20, p_market => 'AE', p_purpose => 'sale', p_segment => 'residential')) e where e->>'name' = 'Business Bay'));
select pg_temp.check('no filters: popular list, 4', (select jsonb_array_length(public.popular_communities(4)) = 4));
select pg_temp.check('commercial sale communities: Business Bay & DIFC only',
  (select jsonb_array_length(c) = 2 from (select public.popular_communities(p_limit => 4, p_market => 'AE', p_purpose => 'sale', p_segment => 'commercial') c) x));
select pg_temp.check('search segment=commercial respects it',
  (select (public.search_listings('{"purpose":"rent","segment":"commercial"}')->>'total')::int = 3));
select pg_temp.check('search type office rent -> 1',
  (select (public.search_listings('{"purpose":"rent","type":"office"}')->>'total')::int = 1));
reset role;
