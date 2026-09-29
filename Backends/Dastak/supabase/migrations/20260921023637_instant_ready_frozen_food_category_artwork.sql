-- Bind supplied artwork to Instant, Ready & Frozen Food categories.
update dastak_v1.categories as category
set image_key = case category.slug
  when 'noodles' then 'local/instant-ready-frozen-food/noodles.avif'
  when 'pasta' then 'local/instant-ready-frozen-food/pasta.avif'
  when 'vermicelli' then 'local/instant-ready-frozen-food/vermicelli.avif'
  when 'ready-to-eat' then 'local/instant-ready-frozen-food/ready-to-eat.avif'
  when 'ready-to-cook' then 'local/instant-ready-frozen-food/ready-to-cook.avif'
  when 'frozen-snacks' then 'local/instant-ready-frozen-food/frozen-snacks.avif'
  when 'frozen-vegetables' then 'local/instant-ready-frozen-food/frozen-vegetables.avif'
  when 'ice-cream-frozen-desserts' then 'local/instant-ready-frozen-food/ice-cream-frozen-desserts.avif'
  when 'soups' then 'local/instant-ready-frozen-food/soups.avif'
  else category.image_key
end,
media_version = category.media_version + 1,
updated_at = now(),
version = category.version + 1
from dastak_v1.category_types as category_type
where category.category_type_id = category_type.id
  and category_type.slug = 'instant-ready-frozen-food'
  and category.slug in (
    'noodles', 'pasta', 'vermicelli', 'ready-to-eat', 'ready-to-cook',
    'frozen-snacks', 'frozen-vegetables', 'ice-cream-frozen-desserts', 'soups'
  );
