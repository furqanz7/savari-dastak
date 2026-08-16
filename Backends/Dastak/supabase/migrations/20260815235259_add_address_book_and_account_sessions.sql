alter table private.customer_delivery_addresses
  add column building text,
  add column floor text,
  add column landmark text,
  add column delivery_notes text,
  add column archived_at timestamptz;

update private.customer_delivery_addresses
set building = details
where building is null;

alter table private.customer_delivery_addresses
  alter column building set not null,
  drop constraint if exists customer_delivery_addresses_details_check,
  add constraint customer_delivery_addresses_details_check check (
    pg_catalog.char_length(pg_catalog.btrim(details)) between 1 and 700
  ),
  add constraint customer_delivery_addresses_building_check check (
    pg_catalog.char_length(pg_catalog.btrim(building)) between 1 and 180
  ),
  add constraint customer_delivery_addresses_floor_check check (
    floor is null or pg_catalog.char_length(pg_catalog.btrim(floor)) between 1 and 80
  ),
  add constraint customer_delivery_addresses_landmark_check check (
    landmark is null or pg_catalog.char_length(pg_catalog.btrim(landmark)) between 1 and 110
  ),
  add constraint customer_delivery_addresses_delivery_notes_check check (
    delivery_notes is null or pg_catalog.char_length(pg_catalog.btrim(delivery_notes)) between 1 and 240
  );

create or replace function private.customer_delivery_address_json(
  address_row private.customer_delivery_addresses
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when (address_row).id is null then null
    else pg_catalog.jsonb_build_object(
      'addressId', (address_row).id,
      'label', (address_row).label,
      'address', (address_row).address,
      'building', (address_row).building,
      'floor', (address_row).floor,
      'landmark', (address_row).landmark,
      'deliveryNotes', (address_row).delivery_notes,
      'details', (address_row).details,
      'displayAddress', pg_catalog.concat_ws(
        ', ',
        (address_row).building,
        (address_row).floor,
        (address_row).landmark,
        (address_row).address
      ),
      'location', pg_catalog.jsonb_build_object(
        'latitude', extensions.st_y((address_row).location),
        'longitude', extensions.st_x((address_row).location)
      ),
      'isDefault', (address_row).is_default,
      'updatedAt', (address_row).updated_at
    )
  end;
$$;

create function private.customer_delivery_addresses_json(p_account_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'addresses', coalesce(
      (
        select pg_catalog.jsonb_agg(
          private.customer_delivery_address_json(address_row)
          order by address_row.is_default desc, address_row.updated_at desc, address_row.id
        )
        from private.customer_delivery_addresses as address_row
        where address_row.account_id = p_account_id
          and address_row.archived_at is null
      ),
      '[]'::jsonb
    )
  );
$$;

create or replace function public.get_customer_delivery_addresses(p_account_id uuid)
returns table (response_body jsonb, response_status integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.accounts as account where account.id = p_account_id
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'profile_required',
        'message', 'Complete your Dastak profile before saving an address.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  response_body := private.customer_delivery_addresses_json(p_account_id);
  response_status := 200;
  return next;
end;
$$;

create function public.save_customer_delivery_address(
  p_account_id uuid,
  p_address_id uuid,
  p_label text,
  p_address text,
  p_building text,
  p_floor text,
  p_landmark text,
  p_delivery_notes text,
  p_latitude double precision,
  p_longitude double precision,
  p_make_default boolean,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_address private.customer_delivery_addresses%rowtype;
  v_existing private.request_deduplication%rowtype;
  v_function_name constant text := 'save_customer_delivery_address';
  v_location extensions.geometry(Point, 4326);
  v_details text;
  v_make_default boolean;
begin
  if p_account_id is null
    or nullif(pg_catalog.btrim(p_label), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_label)) > 40
    or nullif(pg_catalog.btrim(p_address), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_address)) > 300
    or nullif(pg_catalog.btrim(p_building), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_building)) > 180
    or (nullif(pg_catalog.btrim(p_floor), '') is not null and pg_catalog.char_length(pg_catalog.btrim(p_floor)) > 80)
    or (nullif(pg_catalog.btrim(p_landmark), '') is not null and pg_catalog.char_length(pg_catalog.btrim(p_landmark)) > 110)
    or (nullif(pg_catalog.btrim(p_delivery_notes), '') is not null and pg_catalog.char_length(pg_catalog.btrim(p_delivery_notes)) > 240)
    or p_latitude is null or p_latitude not between -90 and 90
    or p_longitude is null or p_longitude not between -180 and 180
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A complete delivery address is required.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);

  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used for another address.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  if not exists (
    select 1 from public.accounts as account where account.id = p_account_id
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'profile_required',
        'message', 'Complete your Dastak profile before saving an address.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if p_address_id is null and (
    select pg_catalog.count(*)
    from private.customer_delivery_addresses as address
    where address.account_id = p_account_id
      and address.archived_at is null
  ) >= 10 then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'address_limit_reached',
        'message', 'You can save up to 10 delivery addresses.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if p_address_id is not null and not exists (
    select 1
    from private.customer_delivery_addresses as address
    where address.id = p_address_id
      and address.account_id = p_account_id
      and address.archived_at is null
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'address_not_found',
        'message', 'That saved address is no longer available.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  v_make_default := coalesce(p_make_default, false) or not exists (
    select 1
    from private.customer_delivery_addresses as address
    where address.account_id = p_account_id
      and address.archived_at is null
      and address.is_default
  );

  if v_make_default then
    update private.customer_delivery_addresses as address
    set is_default = false
    where address.account_id = p_account_id
      and address.archived_at is null
      and address.is_default;
  end if;

  v_location := extensions.st_setsrid(
    extensions.st_makepoint(p_longitude, p_latitude),
    4326
  );
  v_details := pg_catalog.concat_ws(
    ' • ',
    pg_catalog.btrim(p_building),
    nullif(pg_catalog.btrim(p_floor), ''),
    nullif(pg_catalog.btrim(p_landmark), ''),
    nullif(pg_catalog.btrim(p_delivery_notes), '')
  );

  if p_address_id is null then
    insert into private.customer_delivery_addresses (
      account_id, label, address, details, building, floor, landmark,
      delivery_notes, location, is_default
    ) values (
      p_account_id,
      pg_catalog.btrim(p_label),
      pg_catalog.btrim(p_address),
      v_details,
      pg_catalog.btrim(p_building),
      nullif(pg_catalog.btrim(p_floor), ''),
      nullif(pg_catalog.btrim(p_landmark), ''),
      nullif(pg_catalog.btrim(p_delivery_notes), ''),
      v_location,
      v_make_default
    ) returning * into v_address;
  else
    update private.customer_delivery_addresses as address
    set label = pg_catalog.btrim(p_label),
        address = pg_catalog.btrim(p_address),
        details = v_details,
        building = pg_catalog.btrim(p_building),
        floor = nullif(pg_catalog.btrim(p_floor), ''),
        landmark = nullif(pg_catalog.btrim(p_landmark), ''),
        delivery_notes = nullif(pg_catalog.btrim(p_delivery_notes), ''),
        location = v_location,
        is_default = case when v_make_default then true else address.is_default end,
        updated_at = pg_catalog.now()
    where address.id = p_address_id
      and address.account_id = p_account_id
      and address.archived_at is null
    returning address.* into v_address;
  end if;

  response_body := private.customer_delivery_addresses_json(p_account_id);
  response_status := 200;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    p_request_digest, response_body, response_status
  );

  insert into audit.events (
    actor_id, action, entity_type, entity_id, after_state
  ) values (
    p_account_id,
    case when p_address_id is null then 'customer_delivery_address_created' else 'customer_delivery_address_updated' end,
    'customer_delivery_address', v_address.id,
    private.customer_delivery_address_json(v_address)
  );

  return next;
end;
$$;

create function public.set_default_customer_delivery_address(
  p_account_id uuid,
  p_address_id uuid,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_existing private.request_deduplication%rowtype;
  v_function_name constant text := 'set_default_customer_delivery_address';
begin
  if p_account_id is null or p_address_id is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Choose a valid saved address.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);

  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used for another address.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  if not exists (
    select 1
    from private.customer_delivery_addresses as address
    where address.id = p_address_id
      and address.account_id = p_account_id
      and address.archived_at is null
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'address_not_found',
        'message', 'That saved address is no longer available.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  update private.customer_delivery_addresses as address
  set is_default = false
  where address.account_id = p_account_id and address.is_default;

  update private.customer_delivery_addresses as address
  set is_default = true,
      updated_at = pg_catalog.now()
  where address.id = p_address_id
    and address.account_id = p_account_id
    and address.archived_at is null;

  response_body := private.customer_delivery_addresses_json(p_account_id);
  response_status := 200;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    p_request_digest, response_body, response_status
  );

  insert into audit.events (actor_id, action, entity_type, entity_id)
  values (p_account_id, 'customer_delivery_address_selected', 'customer_delivery_address', p_address_id);

  return next;
end;
$$;

create function public.delete_customer_delivery_address(
  p_account_id uuid,
  p_address_id uuid,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_existing private.request_deduplication%rowtype;
  v_function_name constant text := 'delete_customer_delivery_address';
  v_was_default boolean;
begin
  if p_account_id is null or p_address_id is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Choose a valid saved address.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);

  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used for another address.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  select address.is_default into v_was_default
  from private.customer_delivery_addresses as address
  where address.id = p_address_id
    and address.account_id = p_account_id
    and address.archived_at is null
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'address_not_found',
        'message', 'That saved address is no longer available.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  update private.customer_delivery_addresses as address
  set archived_at = pg_catalog.now(),
      is_default = false,
      updated_at = pg_catalog.now()
  where address.id = p_address_id and address.account_id = p_account_id;

  if v_was_default then
    update private.customer_delivery_addresses as address
    set is_default = true,
        updated_at = pg_catalog.now()
    where address.id = (
      select remaining.id
      from private.customer_delivery_addresses as remaining
      where remaining.account_id = p_account_id
        and remaining.archived_at is null
      order by remaining.updated_at desc, remaining.id
      limit 1
    );
  end if;

  response_body := private.customer_delivery_addresses_json(p_account_id);
  response_status := 200;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    p_request_digest, response_body, response_status
  );

  insert into audit.events (actor_id, action, entity_type, entity_id)
  values (p_account_id, 'customer_delivery_address_deleted', 'customer_delivery_address', p_address_id);

  return next;
end;
$$;

create or replace function public.save_default_customer_delivery_address(
  p_account_id uuid,
  p_label text,
  p_address text,
  p_details text,
  p_latitude double precision,
  p_longitude double precision,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_address_id uuid;
begin
  select address.id into v_address_id
  from private.customer_delivery_addresses as address
  where address.account_id = p_account_id
    and address.archived_at is null
    and address.is_default
  limit 1;

  return query
  select result.response_body, result.response_status
  from public.save_customer_delivery_address(
    p_account_id,
    v_address_id,
    p_label,
    p_address,
    p_details,
    null,
    null,
    null,
    p_latitude,
    p_longitude,
    true,
    p_idempotency_key,
    p_request_digest
  ) as result;
end;
$$;

create table private.account_sessions (
  session_id uuid primary key,
  account_id uuid not null references public.accounts(id) on delete cascade,
  device_name text not null check (
    pg_catalog.char_length(pg_catalog.btrim(device_name)) between 1 and 80
  ),
  platform text not null check (
    platform in ('ios', 'web')
  ),
  app_name text not null check (
    pg_catalog.char_length(pg_catalog.btrim(app_name)) between 1 and 40
  ),
  user_agent text check (
    user_agent is null or pg_catalog.char_length(user_agent) between 1 and 500
  ),
  created_at timestamptz not null default pg_catalog.now(),
  last_seen_at timestamptz not null default pg_catalog.now(),
  ended_at timestamptz
);

create index account_sessions_account_last_seen_idx
  on private.account_sessions(account_id, last_seen_at desc);

alter table private.account_sessions enable row level security;
revoke all on table private.account_sessions from public, anon, authenticated;
grant select, insert, update, delete on table private.account_sessions to service_role;

create function public.touch_account_session(
  p_account_id uuid,
  p_session_id uuid,
  p_device_name text,
  p_platform text,
  p_app_name text,
  p_user_agent text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  if p_account_id is null or p_session_id is null
    or nullif(pg_catalog.btrim(p_device_name), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_device_name)) > 80
    or p_platform not in ('ios', 'web')
    or nullif(pg_catalog.btrim(p_app_name), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_app_name)) > 40
    or (nullif(pg_catalog.btrim(p_user_agent), '') is not null and pg_catalog.char_length(p_user_agent) > 500)
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Valid session details are required.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if not exists (
    select 1 from public.accounts as account where account.id = p_account_id
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'profile_required',
        'message', 'Complete your Dastak profile before managing sessions.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  insert into private.account_sessions (
    session_id, account_id, device_name, platform, app_name, user_agent
  ) values (
    p_session_id,
    p_account_id,
    pg_catalog.btrim(p_device_name),
    p_platform,
    pg_catalog.btrim(p_app_name),
    nullif(pg_catalog.btrim(p_user_agent), '')
  )
  on conflict (session_id) do update
  set device_name = excluded.device_name,
      platform = excluded.platform,
      app_name = excluded.app_name,
      user_agent = excluded.user_agent,
      last_seen_at = pg_catalog.now()
  where private.account_sessions.account_id = excluded.account_id
    and private.account_sessions.ended_at is null;

  response_body := pg_catalog.jsonb_build_object('registered', true);
  response_status := 200;
  return next;
end;
$$;

create function public.get_account_sessions(
  p_account_id uuid,
  p_current_session_id uuid
)
returns table (response_body jsonb, response_status integer)
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'sessions', coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'sessionId', session.session_id,
            'deviceName', session.device_name,
            'platform', session.platform,
            'appName', session.app_name,
            'createdAt', session.created_at,
            'lastSeenAt', session.last_seen_at,
            'isCurrent', session.session_id = p_current_session_id
          )
          order by (session.session_id = p_current_session_id) desc,
            session.last_seen_at desc,
            session.session_id
        )
        from private.account_sessions as session
        where session.account_id = p_account_id
          and session.ended_at is null
          and session.last_seen_at > pg_catalog.now() - interval '90 days'
      ),
      '[]'::jsonb
    )
  ), 200;
$$;

create function public.end_account_session(
  p_account_id uuid,
  p_session_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  update private.account_sessions as session
  set ended_at = coalesce(session.ended_at, pg_catalog.now())
  where session.account_id = p_account_id and session.session_id = p_session_id;

  response_body := pg_catalog.jsonb_build_object('ended', true);
  response_status := 200;
  return next;
end;
$$;

create function public.end_other_account_sessions(
  p_account_id uuid,
  p_current_session_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  update private.account_sessions as session
  set ended_at = coalesce(session.ended_at, pg_catalog.now())
  where session.account_id = p_account_id
    and session.session_id <> p_current_session_id
    and session.ended_at is null;

  insert into audit.events (actor_id, action, entity_type, entity_id)
  values (p_account_id, 'other_account_sessions_ended', 'account', p_account_id);

  response_body := pg_catalog.jsonb_build_object('ended', true);
  response_status := 200;
  return next;
end;
$$;

revoke execute on function private.customer_delivery_addresses_json(uuid)
  from public, anon, authenticated;
revoke execute on function public.save_customer_delivery_address(
  uuid, uuid, text, text, text, text, text, text,
  double precision, double precision, boolean, text, text
) from public, anon, authenticated;
revoke execute on function public.set_default_customer_delivery_address(
  uuid, uuid, text, text
) from public, anon, authenticated;
revoke execute on function public.delete_customer_delivery_address(
  uuid, uuid, text, text
) from public, anon, authenticated;
revoke execute on function public.touch_account_session(
  uuid, uuid, text, text, text, text
) from public, anon, authenticated;
revoke execute on function public.get_account_sessions(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.end_account_session(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.end_other_account_sessions(uuid, uuid)
  from public, anon, authenticated;

grant execute on function private.customer_delivery_addresses_json(uuid)
  to service_role;
grant execute on function public.save_customer_delivery_address(
  uuid, uuid, text, text, text, text, text, text,
  double precision, double precision, boolean, text, text
) to service_role;
grant execute on function public.set_default_customer_delivery_address(
  uuid, uuid, text, text
) to service_role;
grant execute on function public.delete_customer_delivery_address(
  uuid, uuid, text, text
) to service_role;
grant execute on function public.touch_account_session(
  uuid, uuid, text, text, text, text
) to service_role;
grant execute on function public.get_account_sessions(uuid, uuid)
  to service_role;
grant execute on function public.end_account_session(uuid, uuid)
  to service_role;
grant execute on function public.end_other_account_sessions(uuid, uuid)
  to service_role;
