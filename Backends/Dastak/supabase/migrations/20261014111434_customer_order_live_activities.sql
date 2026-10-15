-- Private, service-only ActivityKit registrations. Ordinary device tokens remain separate.
create table dastak_v1.order_live_activities (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts(id) on delete cascade,
  session_id uuid not null,
  order_id uuid not null references dastak_v1.orders(id) on delete cascade,
  activity_id text not null check (length(activity_id) between 1 and 200),
  push_token text not null check (length(push_token) between 32 and 512 and push_token ~ '^[0-9a-f]+$'),
  environment text not null check (environment in ('sandbox','production')),
  token_version bigint not null default 1,
  last_status text,
  last_sent_at timestamptz,
  expires_at timestamptz not null default now() + interval '8 hours',
  ended_at timestamptz,
  lease_id uuid,
  lease_until timestamptz,
  unique (activity_id, environment),
  unique (push_token, environment)
);
alter table dastak_v1.order_live_activities enable row level security;
revoke all on dastak_v1.order_live_activities from public, anon, authenticated;
create index order_live_activities_pending_idx on dastak_v1.order_live_activities(last_sent_at)
  where ended_at is null;
create index order_live_activities_account_idx on dastak_v1.order_live_activities(account_id);
create index order_live_activities_order_idx on dastak_v1.order_live_activities(order_id);

create function dastak_v1_api.register_order_live_activity(
  p_account_id uuid, p_session_id uuid, p_order_id uuid,
  p_activity_id text, p_token text, p_environment text
) returns void language plpgsql security definer set search_path = '' as $$
begin
  -- This service-only RPC receives the actor from verifyBearerSession; unlike
  -- user-JWT RPCs, auth.uid() is intentionally absent on the service connection.
  if not exists (select 1 from private.account_memberships where account_id = p_account_id
      and role = 'customer' and (suspended_until is null or suspended_until <= now())) then
    raise exception using errcode = '42501', message = 'Active customer access required';
  end if;
  if not exists (select 1 from auth.sessions where id = p_session_id and user_id = p_account_id)
     or exists (select 1 from private.revoked_account_sessions where session_id = p_session_id and account_id = p_account_id)
     or not exists (select 1 from dastak_v1.orders where id = p_order_id and customer_id = p_account_id)
     or p_activity_id is null or length(p_activity_id) not between 1 and 200
     or p_token is null or length(p_token) not between 32 and 512 or p_token !~ '^[0-9a-f]+$'
     or p_environment is null or p_environment not in ('sandbox','production') then
    raise exception using errcode = '42501', message = 'Live Activity registration rejected';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text, 27));
  if not exists (select 1 from dastak_v1.order_live_activities where activity_id = p_activity_id and environment = p_environment)
     and (select count(*) from dastak_v1.order_live_activities where session_id = p_session_id
          and ended_at is null and expires_at > now()) >= 8 then
    raise exception using errcode = '54000', message = 'Live Activity limit reached';
  end if;
  -- A known activity can rotate its token, never its customer or order.
  insert into dastak_v1.order_live_activities(account_id, session_id, order_id, activity_id, push_token, environment)
  values(p_account_id, p_session_id, p_order_id, p_activity_id, p_token, p_environment)
  on conflict(activity_id, environment) do update
    set push_token = excluded.push_token, session_id = excluded.session_id,
        token_version = dastak_v1.order_live_activities.token_version + 1,
        lease_id = null, lease_until = null, last_sent_at = null
    where dastak_v1.order_live_activities.account_id = excluded.account_id
      and dastak_v1.order_live_activities.order_id = excluded.order_id
      and dastak_v1.order_live_activities.ended_at is null;
  if not found then raise exception using errcode = '42501', message = 'Live Activity registration rejected'; end if;
end $$;

create function public.dastak_register_order_live_activity(
  p_account_id uuid, p_session_id uuid, p_order_id uuid,
  p_activity_id text, p_token text, p_environment text
) returns void language sql security invoker set search_path = '' as $$
  select dastak_v1_api.register_order_live_activity(p_account_id,p_session_id,p_order_id,p_activity_id,p_token,p_environment);
$$;

create function dastak_v1_api.claim_order_live_activities() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_jobs jsonb;
begin
  delete from dastak_v1.order_live_activities
    where ended_at < now() - interval '1 day' or expires_at < now() - interval '1 day';
  with candidates as (
    select a.id from dastak_v1.order_live_activities a join dastak_v1.orders o on o.id = a.order_id
    where a.ended_at is null and (a.lease_until is null or a.lease_until < now())
      and (a.last_sent_at is null or a.last_sent_at < now() - interval '90 seconds'
           or a.last_status is distinct from o.status::text or a.expires_at <= now())
    order by a.last_sent_at nulls first limit 20 for update of a skip locked
  ), claimed as (
    update dastak_v1.order_live_activities a set lease_id = gen_random_uuid(), lease_until = now() + interval '60 seconds'
    from candidates c where a.id = c.id returning a.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id, 'leaseId', a.lease_id, 'tokenVersion', a.token_version,
    'token', a.push_token, 'environment', a.environment,
    'status', case when a.expires_at <= now() or s.id is null
      or exists(select 1 from private.revoked_account_sessions r where r.session_id = a.session_id and r.account_id = a.account_id)
      or not exists(select 1 from private.account_memberships m where m.account_id = a.account_id and m.role = 'customer'
        and (m.suspended_until is null or m.suspended_until <= now()))
      then 'ENDED' else o.status::text end,
    'version', o.version, 'updatedAt', extract(epoch from o.updated_at),
    'timestamp', floor(extract(epoch from now()))
  )), '[]'::jsonb) into v_jobs
  from claimed a join dastak_v1.orders o on o.id = a.order_id
  left join auth.sessions s on s.id = a.session_id and s.user_id = a.account_id;
  return v_jobs;
end $$;
create function public.dastak_claim_order_live_activities() returns jsonb
language sql security invoker set search_path = '' as $$ select dastak_v1_api.claim_order_live_activities(); $$;

create function dastak_v1_api.complete_order_live_activity(
  p_id uuid, p_lease_id uuid, p_token_version bigint, p_status text, p_succeeded boolean, p_retire boolean
) returns void language sql security definer set search_path = '' as $$
  update dastak_v1.order_live_activities set
    last_status = case when p_succeeded then p_status else last_status end,
    last_sent_at = case when p_succeeded then now() else last_sent_at end,
    ended_at = case when p_retire then now() else ended_at end,
    lease_id = null,
    lease_until = case when p_succeeded then null else now() + interval '60 seconds' end
  where id = p_id and lease_id = p_lease_id and token_version = p_token_version;
$$;
create function public.dastak_complete_order_live_activity(
  p_id uuid, p_lease_id uuid, p_token_version bigint, p_status text, p_succeeded boolean, p_retire boolean
) returns void language sql security invoker set search_path = '' as $$
  select dastak_v1_api.complete_order_live_activity(p_id,p_lease_id,p_token_version,p_status,p_succeeded,p_retire);
$$;
revoke all on function dastak_v1_api.register_order_live_activity(uuid,uuid,uuid,text,text,text),
 public.dastak_register_order_live_activity(uuid,uuid,uuid,text,text,text),
 dastak_v1_api.claim_order_live_activities(), public.dastak_claim_order_live_activities(),
 dastak_v1_api.complete_order_live_activity(uuid,uuid,bigint,text,boolean,boolean),
 public.dastak_complete_order_live_activity(uuid,uuid,bigint,text,boolean,boolean) from public, anon, authenticated;
grant execute on function dastak_v1_api.register_order_live_activity(uuid,uuid,uuid,text,text,text),
 public.dastak_register_order_live_activity(uuid,uuid,uuid,text,text,text),
 dastak_v1_api.claim_order_live_activities(), public.dastak_claim_order_live_activities(),
 dastak_v1_api.complete_order_live_activity(uuid,uuid,bigint,text,boolean,boolean),
 public.dastak_complete_order_live_activity(uuid,uuid,bigint,text,boolean,boolean) to service_role;
