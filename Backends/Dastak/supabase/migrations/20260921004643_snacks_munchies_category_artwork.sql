-- Use the owner-supplied artwork for every Snacks & Munchies category.
-- The versioned local keys are shared by customer, merchant and admin reads.
update dastak_v1.subcategories as subcategory
set image_key = case subcategory.slug
  when 'chips' then 'local/snacks-munchies/chips.avif'
  when 'namkeen' then 'local/snacks-munchies/namkeen.avif'
  when 'extruded-snacks' then 'local/snacks-munchies/extruded-snacks.avif'
  when 'popcorn' then 'local/snacks-munchies/popcorn.avif'
  when 'nuts-trail-mixes' then 'local/snacks-munchies/nuts-trail-mixes.avif'
  when 'traditional-snacks' then 'local/snacks-munchies/traditional-snacks.avif'
  when 'papad-fryums' then 'local/snacks-munchies/papad-fryums.avif'
  when 'healthy-snacks' then 'local/snacks-munchies/healthy-snacks.avif'
  else subcategory.image_key
end,
media_version = subcategory.media_version + 1,
updated_at = now(),
version = subcategory.version + 1
from dastak_v1.categories as category
join dastak_v1.category_types as category_type on category_type.id = category.category_type_id
where subcategory.category_id = category.id
  and category_type.slug = 'snacks-munchies'
  and subcategory.slug in (
    'chips', 'namkeen', 'extruded-snacks', 'popcorn', 'nuts-trail-mixes',
    'traditional-snacks', 'papad-fryums', 'healthy-snacks'
  );
