begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

with expected(name, arguments) as (
  values
    ('dastak_v1_accept_delivery_offer', 'uuid, uuid, text, text'),
    ('dastak_v1_decline_delivery_offer', 'uuid, uuid, text, text, text'),
    ('dastak_v1_advance_delivery_mission', 'uuid, uuid, text, uuid, integer, text, text, text, text'),
    ('dastak_v1_advance_final_delivery', 'uuid, uuid, text, text, text, text, text'),
    ('dastak_v1_rider_heartbeat', 'uuid, uuid, bigint'),
    ('dastak_v1_record_launch_payment_collection', 'uuid, uuid, text, text, text, text, bigint, text'),
    ('dastak_v1_advance_return_mission', 'uuid, uuid, text, uuid, text, text, text')
), implementations as (
  select procedure.oid
  from expected
  join pg_catalog.pg_namespace namespace
    on namespace.nspname = 'dastak_v1_api'
  join pg_catalog.pg_proc procedure
    on procedure.pronamespace = namespace.oid
   and procedure.proname = expected.name
   and pg_catalog.oidvectortypes(procedure.proargtypes) = expected.arguments
)
select is(
  (select count(*) from implementations),
  7::bigint,
  'all courier command implementations live behind the internal API boundary'
);

with expected(name, arguments) as (
  values
    ('dastak_v1_accept_delivery_offer', 'uuid, uuid, text, text'),
    ('dastak_v1_decline_delivery_offer', 'uuid, uuid, text, text, text'),
    ('dastak_v1_advance_delivery_mission', 'uuid, uuid, text, uuid, integer, text, text, text, text'),
    ('dastak_v1_advance_final_delivery', 'uuid, uuid, text, text, text, text, text'),
    ('dastak_v1_rider_heartbeat', 'uuid, uuid, bigint'),
    ('dastak_v1_record_launch_payment_collection', 'uuid, uuid, text, text, text, text, bigint, text'),
    ('dastak_v1_advance_return_mission', 'uuid, uuid, text, uuid, text, text, text')
), functions as (
  select namespace.nspname, procedure.oid, procedure.prosecdef
  from expected
  join pg_catalog.pg_proc procedure
    on procedure.proname = expected.name
   and pg_catalog.oidvectortypes(procedure.proargtypes) = expected.arguments
  join pg_catalog.pg_namespace namespace
    on namespace.oid = procedure.pronamespace
   and namespace.nspname in ('public', 'dastak_v1_api')
)
select is(
  (select count(*) from functions
   where nspname = 'dastak_v1_api' and prosecdef),
  7::bigint,
  'all internal courier executors run with their constrained owner privileges'
);

with expected(name, arguments) as (
  values
    ('dastak_v1_accept_delivery_offer', 'uuid, uuid, text, text'),
    ('dastak_v1_decline_delivery_offer', 'uuid, uuid, text, text, text'),
    ('dastak_v1_advance_delivery_mission', 'uuid, uuid, text, uuid, integer, text, text, text, text'),
    ('dastak_v1_advance_final_delivery', 'uuid, uuid, text, text, text, text, text'),
    ('dastak_v1_rider_heartbeat', 'uuid, uuid, bigint'),
    ('dastak_v1_record_launch_payment_collection', 'uuid, uuid, text, text, text, text, bigint, text'),
    ('dastak_v1_advance_return_mission', 'uuid, uuid, text, uuid, text, text, text')
), functions as (
  select namespace.nspname, procedure.oid, procedure.prosecdef
  from expected
  join pg_catalog.pg_proc procedure
    on procedure.proname = expected.name
   and pg_catalog.oidvectortypes(procedure.proargtypes) = expected.arguments
  join pg_catalog.pg_namespace namespace
    on namespace.oid = procedure.pronamespace
   and namespace.nspname in ('public', 'dastak_v1_api')
)
select is(
  (select count(*) from functions
   where nspname = 'public' and not prosecdef),
  7::bigint,
  'all exposed courier RPCs remain security-invoker wrappers'
);

with expected(name, arguments) as (
  values
    ('dastak_v1_accept_delivery_offer', 'uuid, uuid, text, text'),
    ('dastak_v1_decline_delivery_offer', 'uuid, uuid, text, text, text'),
    ('dastak_v1_advance_delivery_mission', 'uuid, uuid, text, uuid, integer, text, text, text, text'),
    ('dastak_v1_advance_final_delivery', 'uuid, uuid, text, text, text, text, text'),
    ('dastak_v1_rider_heartbeat', 'uuid, uuid, bigint'),
    ('dastak_v1_record_launch_payment_collection', 'uuid, uuid, text, text, text, text, bigint, text'),
    ('dastak_v1_advance_return_mission', 'uuid, uuid, text, uuid, text, text, text')
), functions as (
  select namespace.nspname, procedure.oid
  from expected
  join pg_catalog.pg_proc procedure
    on procedure.proname = expected.name
   and pg_catalog.oidvectortypes(procedure.proargtypes) = expected.arguments
  join pg_catalog.pg_namespace namespace
    on namespace.oid = procedure.pronamespace
   and namespace.nspname in ('public', 'dastak_v1_api')
)
select is(
  (select count(*) from functions
   where pg_catalog.has_function_privilege('service_role', oid, 'EXECUTE')),
  14::bigint,
  'the authenticated Edge boundary can execute every wrapper and executor'
);

with expected(name, arguments) as (
  values
    ('dastak_v1_accept_delivery_offer', 'uuid, uuid, text, text'),
    ('dastak_v1_decline_delivery_offer', 'uuid, uuid, text, text, text'),
    ('dastak_v1_advance_delivery_mission', 'uuid, uuid, text, uuid, integer, text, text, text, text'),
    ('dastak_v1_advance_final_delivery', 'uuid, uuid, text, text, text, text, text'),
    ('dastak_v1_rider_heartbeat', 'uuid, uuid, bigint'),
    ('dastak_v1_record_launch_payment_collection', 'uuid, uuid, text, text, text, text, bigint, text'),
    ('dastak_v1_advance_return_mission', 'uuid, uuid, text, uuid, text, text, text')
), functions as (
  select procedure.oid
  from expected
  join pg_catalog.pg_proc procedure
    on procedure.proname = expected.name
   and pg_catalog.oidvectortypes(procedure.proargtypes) = expected.arguments
  join pg_catalog.pg_namespace namespace
    on namespace.oid = procedure.pronamespace
   and namespace.nspname in ('public', 'dastak_v1_api')
)
select is(
  (select count(*) from functions
   where pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')
      or pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')),
  0::bigint,
  'clients cannot bypass courier authentication through either function layer'
);

select * from finish();
rollback;
