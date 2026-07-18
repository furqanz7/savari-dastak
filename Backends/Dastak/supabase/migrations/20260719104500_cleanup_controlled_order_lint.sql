do $migration$
declare
  v_function regprocedure := pg_catalog.to_regprocedure(
    'public.create_controlled_merchant_order(uuid,uuid,text,text)'
  );
  v_definition text;
  v_original constant text := $body$
  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'catalogue_changed',
$body$;
  v_replacement constant text := $body$
  if not found or v_rate.id is null then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'catalogue_changed',
$body$;
begin
  if v_function is null then
    raise exception 'create_controlled_merchant_order is missing';
  end if;

  select pg_catalog.pg_get_functiondef(v_function) into v_definition;
  if pg_catalog.strpos(v_definition, v_original) = 0
    or pg_catalog.strpos(
      pg_catalog.replace(v_definition, v_original, ''),
      v_original
    ) > 0
  then
    raise exception 'create_controlled_merchant_order body did not match once';
  end if;

  execute pg_catalog.replace(v_definition, v_original, v_replacement);
end;
$migration$;
