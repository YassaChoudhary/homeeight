-- =============================================================================
-- Home8 — email one-time codes (used by the `email-auth` Edge Function).
--
-- Run in Supabase → SQL Editor after the listings migration. Safe to re-run.
--
-- The app can't touch any of this: the table has RLS on and NO policies, and
-- the functions are only executable by service_role (the Edge Function).
-- Codes are stored only as salted SHA-256 hashes, keyed by a hash of the
-- email, so a database leak reveals neither working codes nor addresses.
-- =============================================================================

create table if not exists public.email_otps (
  id            text primary key,                 -- sha256(lower(email)), computed by the Edge Function
  code_hash     text,
  salt          text,
  expires_at    timestamptz,
  attempts      int not null default 0,
  last_sent_at  timestamptz,
  window_start  timestamptz,
  send_count    int not null default 0
);
alter table public.email_otps enable row level security;
revoke all on public.email_otps from anon, authenticated;

-- Rules, in one place:
--   code valid 10 minutes · single use · 5 wrong attempts locks it
--   one email per 30 seconds and at most 5 per hour, per address

-- -----------------------------------------------------------------------------
-- Before sending: may this address get another email now?
-- Returns {"ok": true} or {"ok": false, "error": "wait"|"hourly", "wait": seconds}
-- -----------------------------------------------------------------------------
create or replace function public.otp_rate_check(p_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.email_otps;
  v_wait int;
begin
  select * into r from public.email_otps where id = p_id;
  if not found then
    return jsonb_build_object('ok', true);
  end if;
  if r.last_sent_at is not null and now() - r.last_sent_at < interval '30 seconds' then
    v_wait := ceil(extract(epoch from (r.last_sent_at + interval '30 seconds' - now())))::int;
    return jsonb_build_object('ok', false, 'error', 'wait', 'wait', greatest(v_wait, 1));
  end if;
  if r.window_start is not null and now() - r.window_start < interval '1 hour' and r.send_count >= 5 then
    return jsonb_build_object('ok', false, 'error', 'hourly');
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- -----------------------------------------------------------------------------
-- After the email went out: store the new code (hashed) and count the send.
-- -----------------------------------------------------------------------------
create or replace function public.otp_store(p_id text, p_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_salt text := replace(gen_random_uuid()::text, '-', '');
begin
  insert into public.email_otps as o
    (id, code_hash, salt, expires_at, attempts, last_sent_at, window_start, send_count)
  values
    (p_id, encode(sha256(convert_to(v_salt || ':' || p_code, 'UTF8')), 'hex'), v_salt,
     now() + interval '10 minutes', 0, now(), now(), 1)
  on conflict (id) do update set
    code_hash    = excluded.code_hash,
    salt         = excluded.salt,
    expires_at   = excluded.expires_at,
    attempts     = 0,
    last_sent_at = now(),
    window_start = case when o.window_start is null or now() - o.window_start >= interval '1 hour'
                        then now() else o.window_start end,
    send_count   = case when o.window_start is null or now() - o.window_start >= interval '1 hour'
                        then 1 else o.send_count + 1 end;
end $$;

-- -----------------------------------------------------------------------------
-- Check a code. Row-locked, so parallel guesses can't skip the attempt count.
-- Returns {"result": "ok"|"missing"|"expired"|"locked"|"wrong", "left": n}
-- -----------------------------------------------------------------------------
create or replace function public.otp_verify(p_id text, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.email_otps;
begin
  select * into r from public.email_otps where id = p_id for update;
  if not found or r.code_hash is null then
    return jsonb_build_object('result', 'missing');
  end if;
  if now() > r.expires_at then
    return jsonb_build_object('result', 'expired');
  end if;
  if r.attempts >= 5 then
    return jsonb_build_object('result', 'locked');
  end if;
  if encode(sha256(convert_to(r.salt || ':' || p_code, 'UTF8')), 'hex') <> r.code_hash then
    update public.email_otps set attempts = attempts + 1 where id = p_id;
    return jsonb_build_object('result', 'wrong', 'left', 5 - (r.attempts + 1));
  end if;
  -- Single use: clear the code, keep the send counters for rate limiting.
  update public.email_otps
     set code_hash = null, salt = null, expires_at = null, attempts = 0
   where id = p_id;
  return jsonb_build_object('result', 'ok');
end $$;

revoke all on function public.otp_rate_check(text) from public, anon, authenticated;
revoke all on function public.otp_store(text, text) from public, anon, authenticated;
revoke all on function public.otp_verify(text, text) from public, anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.otp_rate_check(text) to service_role;
    grant execute on function public.otp_store(text, text) to service_role;
    grant execute on function public.otp_verify(text, text) to service_role;
    grant select, insert, update, delete on public.email_otps to service_role;
  end if;
end $$;
