\set ON_ERROR_STOP 1
create or replace function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FAIL: %', label; end if; raise notice 'ok - %', label; end $$;
reset role;
update public.agents set firebase_uid = 'agentUid0' where id = 'ag_0';
insert into public.lister_verifications (owner_uid, lister_type, organisation, licence_number, status)
  values ('agentUid0', 'agent', 'Prime Realty', 'RERA-44921', 'verified');
set role anon;
do $$ begin
  perform public.agent_profile('ag_0');
  raise exception 'FAIL: anon allowed';
exception when insufficient_privilege then raise notice 'ok - anon cannot call';
end $$;
set role authenticated;
set request.jwt.claims = '{"iss":"https://securetoken.google.com/home8-61d48","aud":"home8-61d48","sub":"buyer1","role":"authenticated"}';
select pg_temp.check('profile basics',
  (select p->>'name' = 'Tarik Abdullah' and p->>'chat_uid' = 'agentUid0' and p->>'kind' = 'agent'
      and p->>'licence' = 'RERA-44921' and (p->>'active_count')::int = jsonb_array_length(p->'listings')
   from (select public.agent_profile('ag_0') p) x));
select pg_temp.check('seed agent without app account has no chat uid',
  (select p->'chat_uid' = 'null'::jsonb and p->>'kind' = 'agency' from (select public.agent_profile('ag_1') p) x));
select pg_temp.check('unknown agent -> null', (select public.agent_profile('nope') is null));
reset role;
