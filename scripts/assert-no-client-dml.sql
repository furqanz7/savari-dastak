do $$
declare
  violations text;
begin
  select string_agg(
    format('%I:%I.%I', client_role, table_schema, table_name),
    ', '
    order by client_role, table_schema, table_name
  )
  into violations
  from information_schema.tables
  cross join (
    values ('anon'::name), ('authenticated'::name)
  ) as client_roles(client_role)
  where table_type = 'BASE TABLE'
    and table_schema in ('public', 'private', 'audit')
    and (
      has_table_privilege(client_role, format('%I.%I', table_schema, table_name), 'INSERT')
      or has_table_privilege(client_role, format('%I.%I', table_schema, table_name), 'UPDATE')
      or has_table_privilege(client_role, format('%I.%I', table_schema, table_name), 'DELETE')
      or has_table_privilege(client_role, format('%I.%I', table_schema, table_name), 'TRUNCATE')
      or has_table_privilege(client_role, format('%I.%I', table_schema, table_name), 'REFERENCES')
      or has_table_privilege(client_role, format('%I.%I', table_schema, table_name), 'TRIGGER')
    );

  if violations is not null then
    raise exception 'client roles have unauthorized mutation or table-control privileges: %', violations;
  end if;
end;
$$;
