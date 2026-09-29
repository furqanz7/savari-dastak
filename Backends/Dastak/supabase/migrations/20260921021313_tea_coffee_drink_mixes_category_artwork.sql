-- Bind supplied artwork to Tea, Coffee & Drink Mixes categories.
update dastak_v1.categories as category
set image_key = case category.slug
  when 'tea' then 'local/tea-coffee-drink-mixes/tea.avif'
  when 'coffee' then 'local/tea-coffee-drink-mixes/coffee.avif'
  when 'health-drinks' then 'local/tea-coffee-drink-mixes/health-drinks.avif'
  when 'malt-cocoa' then 'local/tea-coffee-drink-mixes/malt-cocoa.avif'
  when 'drink-mixes' then 'local/tea-coffee-drink-mixes/drink-mixes.avif'
  else category.image_key
end,
media_version = category.media_version + 1,
updated_at = now(),
version = category.version + 1
from dastak_v1.category_types as category_type
where category.category_type_id = category_type.id
  and category_type.slug = 'tea-coffee-drink-mixes'
  and category.slug in ('tea', 'coffee', 'health-drinks', 'malt-cocoa', 'drink-mixes');
