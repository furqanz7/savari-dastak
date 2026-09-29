-- Bind supplied artwork to Chocolates & Sweets category presentations.
update dastak_v1.categories as category
set image_key = case category.slug
  when 'chocolates' then 'local/chocolates-sweets/chocolates.avif'
  when 'candy' then 'local/chocolates-sweets/candy.avif'
  when 'gum-mints' then 'local/chocolates-sweets/gum-mints.avif'
  when 'indian-sweets' then 'local/chocolates-sweets/indian-sweets.avif'
  when 'sweet-snacks' then 'local/chocolates-sweets/sweet-snacks.avif'
  else category.image_key
end,
media_version = category.media_version + 1,
updated_at = now(),
version = category.version + 1
from dastak_v1.category_types as category_type
where category.category_type_id = category_type.id
  and category_type.slug = 'chocolates-sweets'
  and category.slug in ('chocolates', 'candy', 'gum-mints', 'indian-sweets', 'sweet-snacks');
