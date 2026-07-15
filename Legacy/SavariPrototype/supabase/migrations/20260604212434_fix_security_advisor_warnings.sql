-- Fix Supabase advisor findings that can be addressed safely by SQL.
-- Savari uses PostgREST/Supabase Swift, not pg_graphql.

drop extension if exists pg_graphql;

revoke select, insert, update, delete on table
  public.driver_locations,
  public.driver_onboarding,
  public.driver_wallet_transactions,
  public.payment_methods,
  public.profiles,
  public.ride_history,
  public.rides,
  public.user_onboarding,
  public.users
from anon;

do $$
declare
  target_function record;
begin
  for target_function in
    select
      n.nspname as schema_name,
      p.proname as function_name,
      pg_get_function_identity_arguments(p.oid) as identity_arguments
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = any (array[
        'accept_ride',
        'driver_cancel_ride',
        'apply_waiting_charge',
        'cancel_ride',
        'set_updated_at',
        'move_completed_to_history',
        'accept_ride_request',
        'driver_cancel_before_arrival',
        'passenger_cancel'
      ])
  loop
    execute format(
      'alter function %I.%I(%s) set search_path = public, pg_temp',
      target_function.schema_name,
      target_function.function_name,
      target_function.identity_arguments
    );

    execute format(
      'revoke execute on function %I.%I(%s) from anon',
      target_function.schema_name,
      target_function.function_name,
      target_function.identity_arguments
    );
  end loop;
end $$;

do $$
declare
  target_function record;
begin
  for target_function in
    select
      n.nspname as schema_name,
      p.proname as function_name,
      pg_get_function_identity_arguments(p.oid) as identity_arguments
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'apply_waiting_charge'
  loop
    execute format(
      'alter function %I.%I(%s) security invoker',
      target_function.schema_name,
      target_function.function_name,
      target_function.identity_arguments
    );
  end loop;
end $$;

drop index if exists public.rides_status_idx;
