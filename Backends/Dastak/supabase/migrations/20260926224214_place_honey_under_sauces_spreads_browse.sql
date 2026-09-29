-- Correct the draft browse map only. Canonical SKU/category ownership is unchanged.
-- Honey's rail belongs under Sauces and Spreads, so its destination must too.
do $$
begin
  if not exists (
    select 1 from dastak_v1.catalogue_browse_versions
    where version = 1 and state = 'DRAFT'
  ) then
    raise exception 'Expected draft catalogue browse map version 1';
  end if;

  if not exists (
    select 1 from dastak_v1.catalogue_browse_nodes
    where version = 1 and node_key = 'sauces-spreads' and kind = 'DESTINATION'
  ) or not exists (
    select 1 from dastak_v1.catalogue_browse_nodes
    where version = 1 and node_key = 'honey-cider-vinegar'
      and kind = 'RAIL' and parent_key = 'sauces-spreads'
  ) then
    raise exception 'Expected Sauces and Spreads destination and honey rail';
  end if;

  if (select count(*) from dastak_v1.catalogue_browse_sources
      where version = 1 and node_key = 'cereals-breakfast'
        and source_order = 10 and type_slug = 'breakfast-spreads'
        and category_slug is null and subcategory_slug is null
        and excluded_category_slugs = array['spreads', 'pancake-baking-mixes']::text[]) <> 1
  then
    raise exception 'Unexpected Cereals and Breakfast source; review before changing it';
  end if;

  if exists (
    select 1 from dastak_v1.catalogue_browse_sources
    where version = 1 and node_key = 'sauces-spreads'
      and (source_order = 30 or
           (type_slug = 'breakfast-spreads' and category_slug = 'honey-syrups'))
  ) then
    raise exception 'Honey destination source already exists or source order is occupied';
  end if;

  update dastak_v1.catalogue_browse_sources
  set excluded_category_slugs = array_append(excluded_category_slugs, 'honey-syrups')
  where version = 1 and node_key = 'cereals-breakfast' and source_order = 10;

  insert into dastak_v1.catalogue_browse_sources
    (version, node_key, source_order, type_slug, category_slug, subcategory_slug)
  values (1, 'sauces-spreads', 30, 'breakfast-spreads', 'honey-syrups', null);
end;
$$;
