create extension if not exists postgis with schema extensions;

create table audit.events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.accounts(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  reason text,
  before_state jsonb,
  after_state jsonb,
  created_at timestamptz not null default now()
);

create table private.safety_cases (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null,
  reporter_account_id uuid not null references public.accounts(id),
  incident_type text not null,
  report_text text not null check (char_length(report_text) between 1 and 1000),
  route_evidence_reference text,
  status text not null default 'open' check (status in ('open', 'under_review', 'resolved')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table public.service_zones (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  boundary extensions.geometry(Polygon, 4326) not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create index service_zones_boundary_gix on public.service_zones using gist (boundary);

alter table audit.events enable row level security;
alter table private.safety_cases enable row level security;
alter table public.service_zones enable row level security;

revoke all on schema audit from public, anon, authenticated;
revoke all on audit.events from anon, authenticated;
revoke all on private.safety_cases from anon, authenticated;
revoke insert, update, delete on public.service_zones from anon, authenticated;
grant select on public.service_zones to authenticated;

grant usage on schema audit to service_role;
grant insert on audit.events to service_role;
grant select, insert, update on public.service_zones to service_role;

create policy service_zones_select_active on public.service_zones
for select to authenticated
using (active = true);

create or replace function audit.reject_event_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'audit.events is append-only';
end;
$$;

revoke all on function audit.reject_event_mutation() from public, anon, authenticated;

create trigger audit_events_immutable
before update or delete on audit.events
for each row execute function audit.reject_event_mutation();

create or replace function public.is_active_owner(p_account_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select exists (
    select 1
    from private.account_memberships
    where account_id = p_account_id
      and role = 'owner'
      and approved_at is not null
      and (suspended_until is null or suspended_until <= now())
  );
$$;

revoke execute on function public.is_active_owner(uuid) from public, anon, authenticated;
grant execute on function public.is_active_owner(uuid) to service_role;

insert into storage.buckets (id, name, public)
values ('savari-evidence', 'savari-evidence', false)
on conflict (id) do update set public = excluded.public;

create policy savari_evidence_select_own on storage.objects
for select to authenticated
using (
  bucket_id = 'savari-evidence'
  and array_length(string_to_array(name, '/'), 1) = 3
  and split_part(name, '/', 1) = 'savari-driver'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and nullif(split_part(name, '/', 3), '') is not null
);

create policy savari_evidence_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'savari-evidence'
  and array_length(string_to_array(name, '/'), 1) = 3
  and split_part(name, '/', 1) = 'savari-driver'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and nullif(split_part(name, '/', 3), '') is not null
);

create policy savari_evidence_update_own on storage.objects
for update to authenticated
using (
  bucket_id = 'savari-evidence'
  and array_length(string_to_array(name, '/'), 1) = 3
  and split_part(name, '/', 1) = 'savari-driver'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and nullif(split_part(name, '/', 3), '') is not null
)
with check (
  bucket_id = 'savari-evidence'
  and array_length(string_to_array(name, '/'), 1) = 3
  and split_part(name, '/', 1) = 'savari-driver'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and nullif(split_part(name, '/', 3), '') is not null
);
