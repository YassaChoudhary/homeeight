\set ON_ERROR_STOP 1
create or replace function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin if not ok then raise exception 'FAIL: %', label; end if; raise notice 'ok - %', label; end $$;

-- the app's roles can't reach any of it
set role anon;
do $$ begin perform public.otp_verify('x','123456'); raise exception 'FAIL: anon ran otp_verify';
exception when insufficient_privilege then raise notice 'ok - anon cannot call otp_verify'; end $$;
do $$ begin perform 1 from public.email_otps; raise exception 'FAIL: anon read email_otps';
exception when insufficient_privilege then raise notice 'ok - anon cannot read codes'; end $$;
reset role;
set role authenticated;
do $$ begin perform public.otp_store('x','123456'); raise exception 'FAIL: authenticated ran otp_store';
exception when insufficient_privilege then raise notice 'ok - signed-in users cannot store codes'; end $$;
reset role;

set role service_role;
select pg_temp.check('first send allowed', (public.otp_rate_check('e1')->>'ok')::boolean);
select public.otp_store('e1', '123456');
select pg_temp.check('code stored hashed, not plain', (select code_hash <> '123456' and length(code_hash) = 64 from public.email_otps where id='e1'));
select pg_temp.check('resend within 30s refused', (select r->>'error' = 'wait' and (r->>'wait')::int between 1 and 30 from (select public.otp_rate_check('e1') r) x));
select pg_temp.check('wrong code -> 4 left', (select r->>'result' = 'wrong' and (r->>'left')::int = 4 from (select public.otp_verify('e1','000000') r) x));
select pg_temp.check('right code -> ok', (public.otp_verify('e1','123456')->>'result') = 'ok');
select pg_temp.check('single use -> missing', (public.otp_verify('e1','123456')->>'result') = 'missing');
select pg_temp.check('unknown address -> missing', (public.otp_verify('nobody','123456')->>'result') = 'missing');

-- lockout
select public.otp_store('e2', '654321');
select public.otp_verify('e2', '000000') from generate_series(1,5);
select pg_temp.check('locked after 5 wrong', (public.otp_verify('e2','654321')->>'result') = 'locked');

-- expiry (simulate time passing)
select public.otp_store('e3', '111111');
update public.email_otps set expires_at = now() - interval '1 second' where id = 'e3';
select pg_temp.check('expired code refused', (public.otp_verify('e3','111111')->>'result') = 'expired');

-- new code replaces old one and resets attempts
select public.otp_store('e4', '222222');
select public.otp_verify('e4','999999');
update public.email_otps set last_sent_at = now() - interval '31 seconds' where id = 'e4';
select pg_temp.check('resend allowed after 30s', (public.otp_rate_check('e4')->>'ok')::boolean);
select public.otp_store('e4', '333333');
select pg_temp.check('old code dead after resend', (public.otp_verify('e4','222222')->>'result') = 'wrong');
select pg_temp.check('new code works', (public.otp_verify('e4','333333')->>'result') = 'ok');

-- hourly cap: 5 sends per hour
select public.otp_store('e5', '000001');
update public.email_otps set send_count = 5, last_sent_at = now() - interval '5 minutes' where id = 'e5';
select pg_temp.check('6th send in an hour refused', (public.otp_rate_check('e5')->>'error') = 'hourly');
update public.email_otps set window_start = now() - interval '61 minutes' where id = 'e5';
select pg_temp.check('allowed again after the hour', (public.otp_rate_check('e5')->>'ok')::boolean);
select public.otp_store('e5', '000002');
select pg_temp.check('counter reset to 1', (select send_count = 1 from public.email_otps where id='e5'));
reset role;
