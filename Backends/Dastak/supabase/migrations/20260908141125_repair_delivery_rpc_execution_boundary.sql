-- Courier Dispatch authenticates the rider at the Edge boundary, then invokes
-- these commands with the service role. Their implementations were left as
-- security-invoker functions in the exposed public schema, so PostgREST ran
-- them without privileges on protected Dastak tables. Move the implementations
-- behind the established dastak_v1_api boundary and leave narrow public RPC
-- wrappers that cannot be called by anon or authenticated clients.

alter function public.dastak_v1_accept_delivery_offer(uuid, uuid, text, text)
  set schema dastak_v1_api;
alter function dastak_v1_api.dastak_v1_accept_delivery_offer(uuid, uuid, text, text)
  security definer;

alter function public.dastak_v1_decline_delivery_offer(uuid, uuid, text, text, text)
  set schema dastak_v1_api;
alter function dastak_v1_api.dastak_v1_decline_delivery_offer(uuid, uuid, text, text, text)
  security definer;

alter function public.dastak_v1_advance_delivery_mission(
  uuid, uuid, text, uuid, integer, text, text, text, text
) set schema dastak_v1_api;
alter function dastak_v1_api.dastak_v1_advance_delivery_mission(
  uuid, uuid, text, uuid, integer, text, text, text, text
) security definer;

alter function public.dastak_v1_advance_final_delivery(
  uuid, uuid, text, text, text, text, text
) set schema dastak_v1_api;
alter function dastak_v1_api.dastak_v1_advance_final_delivery(
  uuid, uuid, text, text, text, text, text
) security definer;

alter function public.dastak_v1_rider_heartbeat(uuid, uuid, bigint)
  set schema dastak_v1_api;
alter function dastak_v1_api.dastak_v1_rider_heartbeat(uuid, uuid, bigint)
  security definer;

alter function public.dastak_v1_record_launch_payment_collection(
  uuid, uuid, text, text, text, text, bigint, text
) set schema dastak_v1_api;
alter function dastak_v1_api.dastak_v1_record_launch_payment_collection(
  uuid, uuid, text, text, text, text, bigint, text
) security definer;

alter function public.dastak_v1_advance_return_mission(
  uuid, uuid, text, uuid, text, text, text
) set schema dastak_v1_api;
alter function dastak_v1_api.dastak_v1_advance_return_mission(
  uuid, uuid, text, uuid, text, text, text
) security definer;

revoke all on function dastak_v1_api.dastak_v1_accept_delivery_offer(
  uuid, uuid, text, text
) from public, anon, authenticated;
revoke all on function dastak_v1_api.dastak_v1_decline_delivery_offer(
  uuid, uuid, text, text, text
) from public, anon, authenticated;
revoke all on function dastak_v1_api.dastak_v1_advance_delivery_mission(
  uuid, uuid, text, uuid, integer, text, text, text, text
) from public, anon, authenticated;
revoke all on function dastak_v1_api.dastak_v1_advance_final_delivery(
  uuid, uuid, text, text, text, text, text
) from public, anon, authenticated;
revoke all on function dastak_v1_api.dastak_v1_rider_heartbeat(
  uuid, uuid, bigint
) from public, anon, authenticated;
revoke all on function dastak_v1_api.dastak_v1_record_launch_payment_collection(
  uuid, uuid, text, text, text, text, bigint, text
) from public, anon, authenticated;
revoke all on function dastak_v1_api.dastak_v1_advance_return_mission(
  uuid, uuid, text, uuid, text, text, text
) from public, anon, authenticated;

grant execute on function dastak_v1_api.dastak_v1_accept_delivery_offer(
  uuid, uuid, text, text
) to service_role;
grant execute on function dastak_v1_api.dastak_v1_decline_delivery_offer(
  uuid, uuid, text, text, text
) to service_role;
grant execute on function dastak_v1_api.dastak_v1_advance_delivery_mission(
  uuid, uuid, text, uuid, integer, text, text, text, text
) to service_role;
grant execute on function dastak_v1_api.dastak_v1_advance_final_delivery(
  uuid, uuid, text, text, text, text, text
) to service_role;
grant execute on function dastak_v1_api.dastak_v1_rider_heartbeat(
  uuid, uuid, bigint
) to service_role;
grant execute on function dastak_v1_api.dastak_v1_record_launch_payment_collection(
  uuid, uuid, text, text, text, text, bigint, text
) to service_role;
grant execute on function dastak_v1_api.dastak_v1_advance_return_mission(
  uuid, uuid, text, uuid, text, text, text
) to service_role;

create function public.dastak_v1_accept_delivery_offer(
  p_account_id uuid,
  p_offer_id uuid,
  p_idempotency_key text,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language sql
security invoker
set search_path = ''
as $$
  select result.response_body, result.response_status
  from dastak_v1_api.dastak_v1_accept_delivery_offer(
    p_account_id, p_offer_id, p_idempotency_key, p_request_digest
  ) result;
$$;

create function public.dastak_v1_decline_delivery_offer(
  p_account_id uuid,
  p_offer_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language sql
security invoker
set search_path = ''
as $$
  select result.response_body, result.response_status
  from dastak_v1_api.dastak_v1_decline_delivery_offer(
    p_account_id, p_offer_id, p_reason, p_idempotency_key, p_request_digest
  ) result;
$$;

create function public.dastak_v1_advance_delivery_mission(
  p_account_id uuid,
  p_mission_id uuid,
  p_action text,
  p_stop_id uuid,
  p_accounted_package_count integer,
  p_verification_code text,
  p_reason text,
  p_idempotency_key text,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language sql
security invoker
set search_path = ''
as $$
  select result.response_body, result.response_status
  from dastak_v1_api.dastak_v1_advance_delivery_mission(
    p_account_id, p_mission_id, p_action, p_stop_id,
    p_accounted_package_count, p_verification_code, p_reason,
    p_idempotency_key, p_request_digest
  ) result;
$$;

create function public.dastak_v1_advance_final_delivery(
  p_account_id uuid,
  p_mission_id uuid,
  p_action text,
  p_object_path text,
  p_verification_code text,
  p_idempotency_key text,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language sql
security invoker
set search_path = ''
as $$
  select result.response_body, result.response_status
  from dastak_v1_api.dastak_v1_advance_final_delivery(
    p_account_id, p_mission_id, p_action, p_object_path,
    p_verification_code, p_idempotency_key, p_request_digest
  ) result;
$$;

create function public.dastak_v1_rider_heartbeat(
  p_account_id uuid,
  p_mission_id uuid,
  p_expected_version bigint
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.dastak_v1_rider_heartbeat(
    p_account_id, p_mission_id, p_expected_version
  );
$$;

create function public.dastak_v1_record_launch_payment_collection(
  p_account_id uuid,
  p_mission_id uuid,
  p_outcome text,
  p_method text,
  p_collection_reference text,
  p_failure_reason text,
  p_expected_mission_version bigint,
  p_idempotency_key text
)
returns table(response_body jsonb, response_status integer)
language sql
security invoker
set search_path = ''
as $$
  select result.response_body, result.response_status
  from dastak_v1_api.dastak_v1_record_launch_payment_collection(
    p_account_id, p_mission_id, p_outcome, p_method,
    p_collection_reference, p_failure_reason,
    p_expected_mission_version, p_idempotency_key
  ) result;
$$;

create function public.dastak_v1_advance_return_mission(
  p_account_id uuid,
  p_return_mission_id uuid,
  p_action text,
  p_return_stop_id uuid,
  p_object_path text,
  p_verification_code text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.dastak_v1_advance_return_mission(
    p_account_id, p_return_mission_id, p_action, p_return_stop_id,
    p_object_path, p_verification_code, p_idempotency_key
  );
$$;

revoke all on function public.dastak_v1_accept_delivery_offer(
  uuid, uuid, text, text
) from public, anon, authenticated;
revoke all on function public.dastak_v1_decline_delivery_offer(
  uuid, uuid, text, text, text
) from public, anon, authenticated;
revoke all on function public.dastak_v1_advance_delivery_mission(
  uuid, uuid, text, uuid, integer, text, text, text, text
) from public, anon, authenticated;
revoke all on function public.dastak_v1_advance_final_delivery(
  uuid, uuid, text, text, text, text, text
) from public, anon, authenticated;
revoke all on function public.dastak_v1_rider_heartbeat(
  uuid, uuid, bigint
) from public, anon, authenticated;
revoke all on function public.dastak_v1_record_launch_payment_collection(
  uuid, uuid, text, text, text, text, bigint, text
) from public, anon, authenticated;
revoke all on function public.dastak_v1_advance_return_mission(
  uuid, uuid, text, uuid, text, text, text
) from public, anon, authenticated;

grant execute on function public.dastak_v1_accept_delivery_offer(
  uuid, uuid, text, text
) to service_role;
grant execute on function public.dastak_v1_decline_delivery_offer(
  uuid, uuid, text, text, text
) to service_role;
grant execute on function public.dastak_v1_advance_delivery_mission(
  uuid, uuid, text, uuid, integer, text, text, text, text
) to service_role;
grant execute on function public.dastak_v1_advance_final_delivery(
  uuid, uuid, text, text, text, text, text
) to service_role;
grant execute on function public.dastak_v1_rider_heartbeat(
  uuid, uuid, bigint
) to service_role;
grant execute on function public.dastak_v1_record_launch_payment_collection(
  uuid, uuid, text, text, text, text, bigint, text
) to service_role;
grant execute on function public.dastak_v1_advance_return_mission(
  uuid, uuid, text, uuid, text, text, text
) to service_role;

comment on function public.dastak_v1_accept_delivery_offer(uuid, uuid, text, text) is
  'Service-role Edge wrapper for the privileged V1 rider acceptance command.';
comment on function public.dastak_v1_advance_delivery_mission(
  uuid, uuid, text, uuid, integer, text, text, text, text
) is 'Service-role Edge wrapper for privileged V1 pickup mission commands.';
comment on function public.dastak_v1_advance_final_delivery(
  uuid, uuid, text, text, text, text, text
) is 'Service-role Edge wrapper for privileged V1 final-delivery commands.';

notify pgrst, 'reload schema';
