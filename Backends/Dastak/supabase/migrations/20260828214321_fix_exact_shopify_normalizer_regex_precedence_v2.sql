do $patch$
declare
  v_definition text;
  v_start text := 'v_canonical !~* ''(pack';
  v_start_fixed text := 'v_canonical !~* (''(pack';
  v_end text := 'v_pack_count::text || '')'' then';
  v_end_fixed text := 'v_pack_count::text || '')'') then';
begin
  select pg_get_functiondef(p.oid)
    into v_definition
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='dastak_v1_api'
    and p.proname='normalize_shopify_items_by_exact_rules'
    and pg_get_function_identity_arguments(p.oid)='p_limit integer';

  if v_definition is null then raise exception 'normalizer function not found'; end if;
  if strpos(v_definition,v_start)=0 or strpos(v_definition,v_end)=0 then
    raise exception 'expected normalizer fragments not found';
  end if;

  v_definition := replace(v_definition,v_start,v_start_fixed);
  v_definition := replace(v_definition,v_end,v_end_fixed);
  execute v_definition;
end
$patch$;

revoke all on function dastak_v1_api.normalize_shopify_items_by_exact_rules(integer) from public,anon,authenticated;
grant execute on function dastak_v1_api.normalize_shopify_items_by_exact_rules(integer) to service_role;;
