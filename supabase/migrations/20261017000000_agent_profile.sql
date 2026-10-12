-- =============================================================================
-- Home8 — Agent / owner profile.
--
-- Run once in Supabase → SQL Editor (paste → Run). Safe to re-run.
--
-- agent_profile(agent_id) powers the "Agent profile" screen and the Chat
-- button. Signed-in users only (the app asks guests to sign in first).
--
-- Returns:
--   id, name, agency, avatar_url, verified, response_time,
--   kind            'agent' | 'company' | 'individual' | 'agency' (seeded agents)
--   licence         licence / RERA number when verified ('' otherwise)
--   member_since    year
--   chat_uid        the person's Firebase uid, or null when they don't use
--                   the app (seeded demo agents) → chat unavailable
--   active_count    live listings
--   closed_count    rented + sold
--   listings        up to 20 live listings (same JSON as search results)
-- =============================================================================

create or replace function public.agent_profile(p_agent_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid   text := public.firebase_uid();
  v_agent public.agents;
  v_ver   public.lister_verifications;
begin
  if v_uid is null then
    raise exception 'Please sign in to view this profile.' using errcode = '28000';
  end if;

  select * into v_agent from public.agents where id = p_agent_id;
  if not found then
    return null;
  end if;

  if v_agent.firebase_uid is not null then
    select * into v_ver
    from public.lister_verifications
    where owner_uid = v_agent.firebase_uid
    order by (status = 'verified') desc, created_at desc
    limit 1;
  end if;

  return jsonb_build_object(
    'id', v_agent.id,
    'name', v_agent.name,
    'agency_name', v_agent.agency_name,
    'avatar_url', v_agent.avatar_url,
    'verified', v_agent.verified,
    'response_time', v_agent.response_time,
    'kind', coalesce(v_ver.lister_type, case when v_agent.firebase_uid is null then 'agency' else 'individual' end),
    'licence', case when v_ver.status = 'verified' then coalesce(v_ver.licence_number, '') else '' end,
    'member_since', extract(year from v_agent.created_at)::int,
    'chat_uid', v_agent.firebase_uid,
    'active_count', (select count(*) from public.listings l
                      where l.agent_id = v_agent.id and l.status = 'live')::int,
    'closed_count', (select count(*) from public.listings l
                      where l.agent_id = v_agent.id and l.status in ('rented', 'sold'))::int,
    'listings', coalesce((
        select jsonb_agg(public.listing_json(x) order by x.featured desc, x.published_at desc nulls last)
        from (select * from public.listings l
               where l.agent_id = v_agent.id and l.status = 'live'
               order by l.featured desc, l.published_at desc nulls last
               limit 20) x),
      '[]'::jsonb)
  );
end $$;

revoke all on function public.agent_profile(text) from public, anon;
grant execute on function public.agent_profile(text) to authenticated;
