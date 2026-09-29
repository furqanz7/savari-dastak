-- Bind supplied artwork to the existing Beverages category presentations.
update dastak_v1.categories as category
set image_key = case category.slug
  when 'water' then 'local/beverages/water.avif'
  when 'soft-drinks' then 'local/beverages/soft-drinks.avif'
  when 'fruit-juices' then 'local/beverages/fruit-juices.avif'
  when 'coconut-water' then 'local/beverages/coconut-water.avif'
  when 'energy-drinks' then 'local/beverages/energy-drinks.avif'
  when 'sports-functional-drinks' then 'local/beverages/sports-functional-drinks.avif'
  when 'soda-mixers' then 'local/beverages/soda-mixers.avif'
  when 'non-alcoholic-speciality-drinks' then 'local/beverages/non-alcoholic-speciality-drinks.avif'
  else category.image_key
end,
media_version = category.media_version + 1,
updated_at = now(),
version = category.version + 1
from dastak_v1.category_types as category_type
where category.category_type_id = category_type.id
  and category_type.slug = 'beverages'
  and category.slug in (
    'water', 'soft-drinks', 'fruit-juices', 'coconut-water', 'energy-drinks',
    'sports-functional-drinks', 'soda-mixers', 'non-alcoholic-speciality-drinks'
  );
