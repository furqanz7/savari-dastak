begin;

do $m$
declare
  v_actor uuid;
  v_batters_category uuid;
  v_breads_category uuid;
  v_cream_category uuid;
  v_batters_subcategory uuid;
  v_breads_subcategory uuid;
  v_cream_subcategory uuid;
begin
  select m.account_id into v_actor
  from private.account_memberships m
  where m.role = 'owner'
    and m.approved_at is not null
    and (m.suspended_until is null or m.suspended_until <= now())
  order by m.approved_at desc
  limit 1;
  if v_actor is null then raise exception 'approved owner account required'; end if;

  select id into v_batters_category from dastak_v1.categories where slug = 'batters-chutneys';
  select id into v_breads_category from dastak_v1.categories where slug = 'indian-breads';
  select id into v_cream_category from dastak_v1.categories where slug = 'cream-condensed-milk';
  if v_batters_category is null or v_breads_category is null or v_cream_category is null then
    raise exception 'target Dairy, Bread & Eggs categories are missing';
  end if;

  insert into dastak_v1.subcategories(category_id,name,slug,status,sort_order,created_by)
  values
    (v_batters_category,'Batters and Chutneys','batters-chutneys','ACTIVE',10,v_actor),
    (v_breads_category,'Indian Breads','indian-breads','ACTIVE',10,v_actor),
    (v_cream_category,'Cream and Condensed Milk','cream-condensed-milk','ACTIVE',10,v_actor)
  on conflict (category_id,slug) do update
    set name = excluded.name, status = 'ACTIVE', updated_at = now(), version = dastak_v1.subcategories.version + 1;

  select id into v_batters_subcategory from dastak_v1.subcategories where category_id = v_batters_category and slug = 'batters-chutneys';
  select id into v_breads_subcategory from dastak_v1.subcategories where category_id = v_breads_category and slug = 'indian-breads';
  select id into v_cream_subcategory from dastak_v1.subcategories where category_id = v_cream_category and slug = 'cream-condensed-milk';

  update dastak_v1.skus s
  set subcategory_id = v_batters_subcategory, updated_at = now(), version = s.version + 1
  where s.subcategory_id <> v_batters_subcategory
    and (lower(s.canonical_name) like '%batter%' or lower(s.canonical_name) like '%chutney%');

  update dastak_v1.skus s
  set subcategory_id = v_breads_subcategory, updated_at = now(), version = s.version + 1
  where s.subcategory_id <> v_breads_subcategory
    and (lower(s.canonical_name) like '%naan%'
      or lower(s.canonical_name) like '%roti%'
      or lower(s.canonical_name) like '%paratha%'
      or (lower(s.canonical_name) like '%bread%' and lower(s.canonical_name) not like '%bread halwa%'));

  update dastak_v1.skus s
  set subcategory_id = v_cream_subcategory, updated_at = now(), version = s.version + 1
  where s.subcategory_id <> v_cream_subcategory
    and (lower(s.canonical_name) like '%condensed milk%' or lower(s.canonical_name) like '%fresh cream%');
end $m$;

commit;
