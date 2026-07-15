create schema if not exists private;
create schema if not exists audit;

create type public.phone_verification_state as enum ('unverified', 'verified');
create type private.membership_role as enum (
  'customer',
  'savari_driver',
  'dastak_partner',
  'merchant',
  'pharmacy',
  'owner'
);

create table public.accounts (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 80),
  phone_number text not null check (phone_number ~ '^\+[1-9][0-9]{7,14}$'),
  phone_verification_state public.phone_verification_state not null default 'unverified',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table private.account_memberships (
  account_id uuid not null references public.accounts(id) on delete cascade,
  role private.membership_role not null,
  approved_at timestamptz,
  suspended_until timestamptz,
  created_at timestamptz not null default now(),
  primary key (account_id, role)
);

create table private.request_deduplication (
  account_id uuid not null references public.accounts(id) on delete cascade,
  function_name text not null,
  idempotency_key text not null,
  request_digest text not null,
  response_body jsonb not null,
  response_status integer not null,
  created_at timestamptz not null default now(),
  primary key (account_id, function_name, idempotency_key)
);

alter table public.accounts enable row level security;
alter table private.account_memberships enable row level security;
alter table private.request_deduplication enable row level security;

revoke all on schema private from public, anon, authenticated;
revoke all on table public.accounts from anon, authenticated;
revoke all on table private.account_memberships from public, anon, authenticated;
revoke all on table private.request_deduplication from public, anon, authenticated;

grant select on public.accounts to authenticated;
grant usage on schema private to service_role;
grant select, insert, update on table public.accounts to service_role;
grant select, insert, update on table private.account_memberships to service_role;
grant select, insert, update on table private.request_deduplication to service_role;

create policy accounts_select_self on public.accounts
for select to authenticated using (id = auth.uid());

create or replace function public.bootstrap_account(
  p_account_id uuid,
  p_display_name text,
  p_phone_number text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (
  response_body jsonb,
  response_status integer
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'bootstrap_account';
  v_existing private.request_deduplication%rowtype;
  v_response_body jsonb;
begin
  -- Different idempotency keys must not race the initial account insert.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_account_id::text || ':' || v_function_name,
      0
    )
  );

  select *
  into v_existing
  from private.request_deduplication
  where account_id = p_account_id
    and function_name = v_function_name
    and idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
      return next;
      return;
    end if;

    response_body := pg_catalog.jsonb_build_object(
      'error',
      pg_catalog.jsonb_build_object(
        'code',
        'idempotency_conflict',
        'message',
        'The idempotency key was already used with a different request.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if exists (select 1 from public.accounts where id = p_account_id) then
    response_body := pg_catalog.jsonb_build_object(
      'error',
      pg_catalog.jsonb_build_object(
        'code',
        'account_already_exists',
        'message',
        'An account already exists for this authenticated user.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  insert into public.accounts (id, display_name, phone_number)
  values (p_account_id, p_display_name, p_phone_number);

  insert into private.account_memberships (account_id, role)
  values (p_account_id, 'customer');

  v_response_body := pg_catalog.jsonb_build_object(
    'accountId',
    p_account_id,
    'phoneState',
    'unverified'
  );

  insert into private.request_deduplication (
    account_id,
    function_name,
    idempotency_key,
    request_digest,
    response_body,
    response_status
  ) values (
    p_account_id,
    v_function_name,
    p_idempotency_key,
    p_request_digest,
    v_response_body,
    200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

revoke execute on function public.bootstrap_account(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function public.bootstrap_account(uuid, text, text, text, text) to service_role;
