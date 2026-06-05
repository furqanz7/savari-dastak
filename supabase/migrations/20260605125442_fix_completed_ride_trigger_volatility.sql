-- The completed-ride trigger writes to history and wallet tables, so the
-- trigger function must be VOLATILE. Keep it hardened as owner-executed and
-- unavailable as a public RPC.

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
      and p.proname = 'move_completed_to_history'
  loop
    execute format(
      'alter function %I.%I(%s) volatile',
      target_function.schema_name,
      target_function.function_name,
      target_function.identity_arguments
    );

    execute format(
      'alter function %I.%I(%s) security definer',
      target_function.schema_name,
      target_function.function_name,
      target_function.identity_arguments
    );

    execute format(
      'alter function %I.%I(%s) set search_path = public, pg_temp',
      target_function.schema_name,
      target_function.function_name,
      target_function.identity_arguments
    );

    execute format(
      'revoke all on function %I.%I(%s) from public',
      target_function.schema_name,
      target_function.function_name,
      target_function.identity_arguments
    );

    execute format(
      'revoke all on function %I.%I(%s) from anon',
      target_function.schema_name,
      target_function.function_name,
      target_function.identity_arguments
    );

    execute format(
      'revoke all on function %I.%I(%s) from authenticated',
      target_function.schema_name,
      target_function.function_name,
      target_function.identity_arguments
    );
  end loop;
end $$;
