-- Reference top-level Oils and Ghee is a department, not an Atta category.
-- Move the two existing category IDs as a unit; all subcategory, SKU and
-- merchant-selection IDs remain unchanged.
do $$
declare
  v_actor uuid;
  v_staples_id uuid;
  v_oils_id uuid;
begin
  select m.account_id into v_actor
  from private.account_memberships m
  where m.role = 'owner'
    and m.approved_at is not null
    and (m.suspended_until is null or m.suspended_until <= now())
  order by m.approved_at desc
  limit 1;
  if v_actor is null then
    raise exception 'Approved owner account required for Oils and Ghee taxonomy';
  end if;

  select id into strict v_staples_id
  from dastak_v1.category_types where slug = 'staples-pantry';

  insert into dastak_v1.category_types
    (name, slug, status, sort_order, created_by)
  values ('Oils and Ghee', 'oils-ghee', 'ACTIVE', 45, v_actor)
  on conflict (slug) do update
  set name = excluded.name,
      status = 'ACTIVE',
      sort_order = excluded.sort_order,
      updated_at = now(),
      version = dastak_v1.category_types.version + 1
  returning id into v_oils_id;

  if (select count(*) from dastak_v1.categories
      where slug in ('cooking-oils', 'ghee')) <> 2 then
    raise exception 'Expected existing Cooking Oils and Ghee categories';
  end if;
  if exists (
    select 1 from dastak_v1.categories
    where slug in ('cooking-oils', 'ghee')
      and category_type_id not in (v_staples_id, v_oils_id)
  ) then
    raise exception 'An Oils and Ghee category has an unexpected current parent';
  end if;

  update dastak_v1.categories
  set category_type_id = v_oils_id,
      updated_at = now(),
      version = version + 1
  where slug in ('cooking-oils', 'ghee')
    and category_type_id is distinct from v_oils_id;
end;
$$;

create or replace function dastak_v1_api.catalogue_navigation_section(
  p_category_type_slug text
)
returns jsonb
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when p_category_type_slug in ('fresh-produce', 'dairy-bread-eggs') then
      pg_catalog.jsonb_build_object('key', 'fresh-items', 'name', 'Fresh Items', 'sortOrder', 0)
    when p_category_type_slug in ('staples-pantry', 'masala-cooking', 'oils-ghee') then
      pg_catalog.jsonb_build_object('key', 'grocery-kitchen', 'name', 'Grocery & Kitchen', 'sortOrder', 10)
    when p_category_type_slug in (
      'breakfast-spreads', 'snacks-munchies', 'biscuits-bakery', 'beverages',
      'tea-coffee-drink-mixes', 'chocolates-sweets', 'instant-ready-frozen-food',
      'paan-corner'
    ) then
      pg_catalog.jsonb_build_object('key', 'snacks-drinks', 'name', 'Snacks & Drinks', 'sortOrder', 20)
    when p_category_type_slug in (
      'personal-care', 'beauty-grooming', 'health-hygiene', 'baby-care', 'pharmacy'
    ) then
      pg_catalog.jsonb_build_object('key', 'beauty-wellness', 'name', 'Beauty & Wellness', 'sortOrder', 30)
    else
      pg_catalog.jsonb_build_object('key', 'household-lifestyle', 'name', 'Household & Lifestyle', 'sortOrder', 40)
  end;
$$;
