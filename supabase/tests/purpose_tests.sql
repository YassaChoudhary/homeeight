\set ON_ERROR_STOP 1
create or replace function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin if not ok then raise exception 'FAIL: %', label; end if; raise notice 'ok - %', label; end $$;
set role anon;
select pg_temp.check('highlights rent: 5, all rent', (select jsonb_array_length(h) = 5 and not h @> '[{"purpose":"sale"}]' from (select public.highlight_listings(8, 'AE', 'rent') h) x));
select pg_temp.check('highlights sale: 2, all sale, featured first', (select jsonb_array_length(h) = 2 and h->0->>'id' = 'p6' and not h @> '[{"purpose":"rent"}]' from (select public.highlight_listings(8, 'AE', 'sale') h) x));
select pg_temp.check('highlights no purpose: 7', (select jsonb_array_length(public.highlight_listings(8)) = 7));
select pg_temp.check('highlights named args like the app sends', (select jsonb_array_length(public.highlight_listings(p_limit => 8, p_market => 'AE', p_purpose => 'sale')) = 2));
select pg_temp.check('communities rent: Dubai Marina (2) first, counts rent only',
  (select c->0->>'name' = 'Dubai Marina' and (c->0->>'homes')::int = 2 and jsonb_array_length(c) = 4 from (select public.popular_communities(4, 'AE', 'rent') c) x));
select pg_temp.check('communities sale: only Bluewaters & Business Bay (1 each), no 0-home tiles',
  (select jsonb_array_length(c) = 2 and (c->0->>'name') in ('Bluewaters','Business Bay') and (c->1->>'name') in ('Bluewaters','Business Bay') and (c->1->>'homes')::int = 1 from (select public.popular_communities(4, 'AE', 'sale') c) x));
select pg_temp.check('communities no purpose: popular 4, same as before',
  (select jsonb_array_length(c) = 4 and c->0->>'name' = 'Dubai Marina' from (select public.popular_communities(4) c) x));
select pg_temp.check('null purpose explicit = no filter', (select jsonb_array_length(public.highlight_listings(p_limit => 8, p_market => 'AE', p_purpose => null)) = 7));
reset role;
