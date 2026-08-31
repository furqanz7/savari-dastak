do $m$
declare
  v_actor uuid;
  v_type_id uuid;
  v_category_id uuid;
begin
  select m.account_id into v_actor
  from private.account_memberships m
  where m.role='owner' and m.approved_at is not null
    and (m.suspended_until is null or m.suspended_until<=now())
  order by m.approved_at desc limit 1;
  if v_actor is null then raise exception 'approved owner account required'; end if;

  select id into v_type_id from dastak_v1.category_types where slug='dairy-bread-eggs';
  if v_type_id is null then raise exception 'dairy-bread-eggs category type missing'; end if;

  insert into dastak_v1.categories(category_type_id,name,slug,status,sort_order,created_by)
  values(v_type_id,'Milk Powders & Creamers','milk-powders-creamers','DRAFT',95,v_actor)
  on conflict (slug) do update
    set category_type_id=excluded.category_type_id,
        name=excluded.name,
        sort_order=excluded.sort_order,
        updated_at=now(),
        version=dastak_v1.categories.version+1
  returning id into v_category_id;

  insert into dastak_v1.subcategories(category_id,name,slug,status,sort_order,created_by)
  values
    (v_category_id,'Milk Powder','milk-powder','DRAFT',10,v_actor),
    (v_category_id,'Dairy Whitener','dairy-whitener','DRAFT',20,v_actor),
    (v_category_id,'Sweetened Condensed Milk','sweetened-condensed-milk','DRAFT',30,v_actor),
    (v_category_id,'Dairy Creamer','dairy-creamer','DRAFT',40,v_actor),
    (v_category_id,'Infant Milk Formula','infant-milk-formula','DRAFT',50,v_actor)
  on conflict (category_id,slug) do update
    set name=excluded.name,
        sort_order=excluded.sort_order,
        updated_at=now(),
        version=dastak_v1.subcategories.version+1;
end $m$;;
