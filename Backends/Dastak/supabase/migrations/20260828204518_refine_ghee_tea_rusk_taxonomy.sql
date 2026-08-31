do $m$
declare
  v_actor uuid;
  v_category_id uuid;
begin
  select m.account_id into v_actor
  from private.account_memberships m
  where m.role='owner' and m.approved_at is not null
    and (m.suspended_until is null or m.suspended_until<=now())
  order by m.approved_at desc limit 1;
  if v_actor is null then raise exception 'approved owner account required'; end if;

  select c.id into v_category_id from dastak_v1.categories c where c.slug='ghee';
  insert into dastak_v1.subcategories(category_id,name,slug,status,sort_order,created_by)
  values(v_category_id,'Pure Ghee','pure-ghee','DRAFT',5,v_actor)
  on conflict (category_id,slug) do nothing;

  select c.id into v_category_id from dastak_v1.categories c where c.slug='tea';
  insert into dastak_v1.subcategories(category_id,name,slug,status,sort_order,created_by)
  values(v_category_id,'Instant Tea Mix','instant-tea-mix','DRAFT',90,v_actor)
  on conflict (category_id,slug) do nothing;

  select c.id into v_category_id from dastak_v1.categories c where c.slug='rusks-toasts';
  insert into dastak_v1.subcategories(category_id,name,slug,status,sort_order,created_by)
  values(v_category_id,'Tea Rusk','tea-rusk','DRAFT',5,v_actor)
  on conflict (category_id,slug) do nothing;
end $m$;;
