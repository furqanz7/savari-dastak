-- COALESCE, NULLIF, GREATEST, and LEAST are SQL expressions, not schema-qualified
-- functions. Mechanically repair affected stored function bodies already deployed.
do $$
declare
  v_function_oid oid;
  v_definition text;
begin
  for v_function_oid in
    select routine.oid
    from pg_catalog.pg_proc as routine
    join pg_catalog.pg_namespace as namespace on namespace.oid = routine.pronamespace
    where namespace.nspname in ('public', 'private')
      and routine.prokind = 'f'
      and (
        pg_catalog.pg_get_functiondef(routine.oid) like '%' || 'pg_catalog.' || 'coalesce(' || '%'
        or pg_catalog.pg_get_functiondef(routine.oid) like '%' || 'pg_catalog.' || 'nullif(' || '%'
        or pg_catalog.pg_get_functiondef(routine.oid) like '%' || 'pg_catalog.' || 'greatest(' || '%'
        or pg_catalog.pg_get_functiondef(routine.oid) like '%' || 'pg_catalog.' || 'least(' || '%'
      )
  loop
    v_definition := pg_catalog.pg_get_functiondef(v_function_oid);
    v_definition := pg_catalog.replace(v_definition, 'pg_catalog.' || 'coalesce(', 'coalesce(');
    v_definition := pg_catalog.replace(v_definition, 'pg_catalog.' || 'nullif(', 'nullif(');
    v_definition := pg_catalog.replace(v_definition, 'pg_catalog.' || 'greatest(', 'greatest(');
    v_definition := pg_catalog.replace(v_definition, 'pg_catalog.' || 'least(', 'least(');
    execute v_definition;
  end loop;
end;
$$;

notify pgrst, 'reload schema';
