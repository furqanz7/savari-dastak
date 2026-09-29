-- Use the owner-supplied Breakfast & Spreads artwork for each catalogue
-- subcategory. These keys are served from the versioned web asset bundle so
-- the same artwork is available to customer, merchant and admin surfaces.
update dastak_v1.subcategories as subcategory
set image_key = case subcategory.slug
  when 'breakfast-cereals' then 'local/breakfast-spreads/breakfast-cereals.avif'
  when 'oats' then 'local/breakfast-spreads/oats.avif'
  when 'muesli-granola' then 'local/breakfast-spreads/muesli-granola.avif'
  when 'instant-breakfast' then 'local/breakfast-spreads/instant-breakfast.avif'
  when 'spreads' then 'local/breakfast-spreads/spreads.avif'
  when 'honey-syrups' then 'local/breakfast-spreads/honey-syrups.avif'
  when 'pancake-baking-mixes' then 'local/breakfast-spreads/pancake-baking-mixes.avif'
  else subcategory.image_key
end,
media_version = subcategory.media_version + 1,
updated_at = now(),
version = subcategory.version + 1
from dastak_v1.categories as category
join dastak_v1.category_types as category_type on category_type.id = category.category_type_id
where subcategory.category_id = category.id
  and category_type.slug = 'breakfast-spreads'
  and subcategory.slug in (
    'breakfast-cereals', 'oats', 'muesli-granola', 'instant-breakfast',
    'spreads', 'honey-syrups', 'pancake-baking-mixes'
  );
