-- Keep contact in the existing access-controlled assigned-delivery projection.
do $$
declare definition text; old_pattern text := $pattern$'^\\+[1-9][0-9]{7,14}$'$pattern$;
begin
  definition:=pg_get_functiondef('dastak_v1_api.delivery_tracking_json(uuid)'::regprocedure);
  if (length(definition)-length(replace(definition,old_pattern,'')))/length(old_pattern)<>1 then
    raise exception 'Rider phone projection source drift';
  end if;
  execute replace(definition,old_pattern,$pattern$'^[+][1-9][0-9]{7,14}$'$pattern$);
  if has_function_privilege('anon','dastak_v1_api.delivery_tracking_json(uuid)','execute')
    or has_function_privilege('authenticated','dastak_v1_api.delivery_tracking_json(uuid)','execute') then
    raise exception 'Rider projection must not be callable directly';
  end if;
end;$$;
