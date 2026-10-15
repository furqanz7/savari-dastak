-- Customer-facing category rename. Keep the stable key so existing navigation
-- and catalogue relationships continue to resolve in installed clients.
do $$
begin
  if (select count(*) from dastak_v1.catalogue_browse_nodes n
      join dastak_v1.catalogue_browse_versions v using (version)
      where v.state = 'ACTIVE' and n.node_key = 'pooja-store'
        and n.kind = 'DESTINATION' and n.parent_key = 'household-lifestyle'
        and n.label in ('Pooja Store', 'Janamaz and Tasbih')) <> 1 then
    raise exception 'Expected one active Pooja Store destination; review catalogue before renaming';
  end if;

  update dastak_v1.catalogue_browse_nodes n
  set label = 'Janamaz and Tasbih'
  from dastak_v1.catalogue_browse_versions v
  where n.version = v.version and v.state = 'ACTIVE'
    and n.node_key = 'pooja-store' and n.kind = 'DESTINATION'
    and n.parent_key = 'household-lifestyle'
    and n.label = 'Pooja Store';
end;
$$;
