do $$
declare
  violations text;
begin
  select string_agg(format('%I.%I', table_schema, table_name), ', ' order by table_schema, table_name)
  into violations
  from information_schema.tables
  where table_type = 'BASE TABLE'
    and table_schema not in ('information_schema', 'pg_catalog', 'pg_toast')
    and (has_table_privilege('authenticated', format('%I.%I', table_schema, table_name), 'INSERT')
      or has_table_privilege('authenticated', format('%I.%I', table_schema, table_name), 'UPDATE')
      or has_table_privilege('authenticated', format('%I.%I', table_schema, table_name), 'DELETE'))
    and not (table_schema = 'storage' and table_name = 'objects');

  if violations is not null then
    raise exception 'authenticated has unauthorized data-mutation privileges: %', violations;
  end if;
end;
$$;
