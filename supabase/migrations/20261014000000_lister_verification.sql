-- =============================================================================
-- Home8 — only VERIFIED individuals, agents and companies can publish.
--
-- Run AFTER 20261013000000_seller_listings.sql, once, in Supabase → SQL Editor
-- (paste the whole file → Run). Safe to re-run.
--
--   * Individuals verify too now: legal name + ID card front and back.
--     Agents: associated company, RERA / licence number, trade licence.
--     Companies: company name, RERA / licence number, trade licence.
--   * my_verification() tells the app where the account stands:
--     none / pending / verified / rejected (+ your note).
--   * submit_listing() refuses until the account is verified. While pending,
--     sellers can still prepare listings and save drafts.
--
-- Approve or reject an account (SQL editor):
--   select public.review_verification('<firebase uid>', true);
--   select public.review_verification('<firebase uid>', false, 'ID is expired');
-- =============================================================================

alter table public.lister_verifications add column if not exists legal_name text not null default '';
alter table public.lister_verifications add column if not exists id_front   jsonb;
alter table public.lister_verifications add column if not exists id_back    jsonb;
alter table public.lister_verifications add column if not exists updated_at timestamptz not null default now();

alter table public.lister_verifications drop constraint if exists lister_verifications_lister_type_check;
alter table public.lister_verifications add constraint lister_verifications_lister_type_check
  check (lister_type in ('individual', 'agent', 'company'));

-- Is this account approved to publish?
create or replace function public._lister_verified(p_uid text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select v.status = 'verified'
    from public.lister_verifications v
    where v.owner_uid = p_uid
    order by v.created_at desc
    limit 1), false)
$$;

-- -----------------------------------------------------------------------------
-- Where the signed-in account stands. {status:'none'} when never submitted.
-- -----------------------------------------------------------------------------
create or replace function public.my_verification()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((
    select jsonb_build_object(
      'status', v.status,
      'type', v.lister_type,
      'legal_name', v.legal_name,
      'organisation', v.organisation,
      'licence_number', v.licence_number,
      'review_note', coalesce(v.review_note, ''),
      'submitted_at', v.created_at)
    from public.lister_verifications v
    where v.owner_uid = public._require_uid()
    order by v.created_at desc
    limit 1), jsonb_build_object('status', 'none'))
$$;

-- -----------------------------------------------------------------------------
-- Submit (or resubmit) verification. One open request per account: a pending
-- request is updated in place; after a rejection a new one is created.
-- -----------------------------------------------------------------------------
create or replace function public.submit_verification(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid     text := public._require_uid();
  v_type    text := case when p ->> 'type' in ('agent', 'company') then p ->> 'type' else 'individual' end;
  v_licence jsonb := public._jdoc(p, 'trade_licence', v_uid);
  v_front   jsonb := public._jdoc(p, 'id_front', v_uid);
  v_back    jsonb := public._jdoc(p, 'id_back', v_uid);
  v_last    public.lister_verifications;
begin
  if v_type = 'individual' then
    if public._jtext(p, 'legal_name', 120) is null or v_front is null or v_back is null then
      raise exception 'Add your legal name and both sides of your ID card.' using errcode = 'P0001';
    end if;
  else
    if public._jtext(p, 'organisation', 120) is null or public._jtext(p, 'licence_number', 60) is null
       or v_licence is null then
      raise exception 'Add the company name, RERA / licence number and trade licence.' using errcode = 'P0001';
    end if;
  end if;

  select * into v_last from public.lister_verifications
  where owner_uid = v_uid order by created_at desc limit 1;

  if found and v_last.status = 'verified' then
    return jsonb_build_object('status', 'verified');
  end if;

  if found and v_last.status = 'pending' then
    update public.lister_verifications set
      lister_type = v_type,
      legal_name = coalesce(public._jtext(p, 'legal_name', 120), ''),
      organisation = coalesce(public._jtext(p, 'organisation', 120), ''),
      licence_number = coalesce(public._jtext(p, 'licence_number', 60), ''),
      trade_licence = v_licence,
      broker_card = public._jdoc(p, 'broker_card', v_uid),
      id_front = v_front,
      id_back = v_back,
      updated_at = now()
    where id = v_last.id;
  else
    insert into public.lister_verifications (owner_uid, lister_type, legal_name, organisation,
      licence_number, trade_licence, broker_card, id_front, id_back)
    values (v_uid, v_type,
      coalesce(public._jtext(p, 'legal_name', 120), ''),
      coalesce(public._jtext(p, 'organisation', 120), ''),
      coalesce(public._jtext(p, 'licence_number', 60), ''),
      v_licence, public._jdoc(p, 'broker_card', v_uid), v_front, v_back);
  end if;

  return jsonb_build_object('status', 'pending');
end $$;

-- -----------------------------------------------------------------------------
-- Publishing needs a verified account. Drafts don't.
-- -----------------------------------------------------------------------------
create or replace function public.submit_listing(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id text;
begin
  if not public._lister_verified(public._require_uid()) then
    raise exception 'Your account is still being verified. Save this listing as a draft — you can publish it once you''re approved.'
      using errcode = 'P0001';
  end if;
  v_id := public._seller_upsert(p, true);
  return public._my_listing_json(v_id);
end $$;

-- -----------------------------------------------------------------------------
-- ADMIN: approve / reject an account. Approving also marks the lister's
-- agent card Verified (creating it if they haven't published yet).
-- -----------------------------------------------------------------------------
create or replace function public.review_verification(p_uid text, p_approve boolean, p_note text default null)
returns text language plpgsql security definer set search_path = public as $$
declare v public.lister_verifications;
begin
  select * into v from public.lister_verifications
  where owner_uid = p_uid order by created_at desc limit 1;
  if not found then return 'no verification request for this user'; end if;

  update public.lister_verifications
     set status = case when p_approve then 'verified' else 'rejected' end,
         review_note = case when p_approve then null else coalesce(p_note, 'Please check your documents and try again') end,
         updated_at = now()
   where id = v.id;

  if p_approve then
    insert into public.agents (firebase_uid, name, agency_name, verified)
    values (p_uid,
            coalesce(nullif(v.legal_name, ''), nullif(v.organisation, ''), 'Home8 member'),
            case when v.lister_type = 'individual' then 'Property owner' else v.organisation end,
            true)
    on conflict (firebase_uid) do update set verified = true;
  end if;

  return case when p_approve then 'verified' else 'rejected' end;
end $$;

revoke all on function public._lister_verified(text) from public, anon, authenticated;
revoke all on function public.review_verification(text, boolean, text) from public, anon, authenticated;
revoke execute on function public.my_verification() from public, anon;
revoke execute on function public.submit_verification(jsonb) from public, anon;
revoke execute on function public.submit_listing(jsonb) from public, anon;
grant execute on function public.my_verification() to authenticated;
grant execute on function public.submit_verification(jsonb) to authenticated;
grant execute on function public.submit_listing(jsonb) to authenticated;
