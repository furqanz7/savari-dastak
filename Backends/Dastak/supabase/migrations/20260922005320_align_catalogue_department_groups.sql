-- Match the customer catalogue directory to the requested Instamart-style
-- department groups without changing category-type or SKU records.
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
    when p_category_type_slug in ('staples-pantry', 'masala-cooking') then
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
    when p_category_type_slug in (
      'home-cleaning', 'kitchen-dining', 'home-utility', 'electronics-accessories',
      'stationery-office-school', 'pet-care', 'puja-festive', 'toys-games-kids',
      'automotive-travel-utility', 'home-improvement-hardware'
    ) then
      pg_catalog.jsonb_build_object('key', 'household-lifestyle', 'name', 'Household & Lifestyle', 'sortOrder', 40)
    else
      pg_catalog.jsonb_build_object('key', 'household-lifestyle', 'name', 'Household & Lifestyle', 'sortOrder', 40)
  end;
$$;

revoke all on function dastak_v1_api.catalogue_navigation_section(text)
  from public, anon, authenticated;

grant execute on function dastak_v1_api.catalogue_navigation_section(text)
  to service_role;

comment on function dastak_v1_api.catalogue_navigation_section(text) is
  'Returns the five customer-facing department groups used by the catalogue directory.';
