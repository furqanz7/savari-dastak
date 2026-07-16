alter function public.accept_delivery_assignment(uuid, uuid, text, text)
  set schema private;
alter function private.accept_delivery_assignment(uuid, uuid, text, text)
  rename to accept_delivery_assignment_impl;

alter function public.decline_delivery_assignment(uuid, uuid, text, text, text)
  set schema private;
alter function private.decline_delivery_assignment(uuid, uuid, text, text, text)
  rename to decline_delivery_assignment_impl;

revoke execute on function private.accept_delivery_assignment_impl(
  uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function private.accept_delivery_assignment_impl(
  uuid, uuid, text, text
) to service_role;

revoke execute on function private.decline_delivery_assignment_impl(
  uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function private.decline_delivery_assignment_impl(
  uuid, uuid, text, text, text
) to service_role;

create function public.accept_delivery_assignment(
  p_account_id uuid,
  p_assignment_id uuid,
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
  v_function_name constant text := 'accept_delivery_assignment';
begin
  if p_account_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        p_account_id::text || ':' || v_function_name,
        0
      )
    );
  end if;

  return query
  select implementation.response_body, implementation.response_status
  from private.accept_delivery_assignment_impl(
    p_account_id,
    p_assignment_id,
    p_idempotency_key,
    p_request_digest
  ) as implementation;
end;
$$;

create function public.decline_delivery_assignment(
  p_account_id uuid,
  p_assignment_id uuid,
  p_reason text,
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
  v_function_name constant text := 'decline_delivery_assignment';
begin
  if p_account_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        p_account_id::text || ':' || v_function_name,
        0
      )
    );
  end if;

  return query
  select implementation.response_body, implementation.response_status
  from private.decline_delivery_assignment_impl(
    p_account_id,
    p_assignment_id,
    p_reason,
    p_idempotency_key,
    p_request_digest
  ) as implementation;
end;
$$;

revoke execute on function public.accept_delivery_assignment(
  uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.accept_delivery_assignment(
  uuid, uuid, text, text
) to service_role;

revoke execute on function public.decline_delivery_assignment(
  uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.decline_delivery_assignment(
  uuid, uuid, text, text, text
) to service_role;
