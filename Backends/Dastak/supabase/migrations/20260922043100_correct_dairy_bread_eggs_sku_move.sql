begin;

do $m$
declare
  v_target_subcategory uuid;
begin
  select sc.id into v_target_subcategory
  from dastak_v1.subcategories sc
  join dastak_v1.categories c on c.id = sc.category_id
  join dastak_v1.category_types ct on ct.id = c.category_type_id
  where ct.slug = 'breakfast-spreads' and sc.slug = 'fruit-muesli';

  if v_target_subcategory is null then
    raise exception 'Muesli & Granola subcategory missing';
  end if;

  update dastak_v1.skus s
  set subcategory_id = v_target_subcategory,
      updated_at = now(),
      version = s.version + 1
  where lower(s.canonical_name) like 'tata soulfull millet muesli%'
    and s.subcategory_id <> v_target_subcategory;
end $m$;

commit;
