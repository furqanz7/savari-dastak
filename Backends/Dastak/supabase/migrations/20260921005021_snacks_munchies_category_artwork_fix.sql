-- Snacks & Munchies entries are catalogue categories (not subcategories).
-- Bind the supplied artwork at that presentation level.
update dastak_v1.categories as category
set image_key = case category.slug
  when 'chips' then 'local/snacks-munchies/chips.avif'
  when 'namkeen' then 'local/snacks-munchies/namkeen.avif'
  when 'extruded-snacks' then 'local/snacks-munchies/extruded-snacks.avif'
  when 'popcorn' then 'local/snacks-munchies/popcorn.avif'
  when 'nuts-trail-mixes' then 'local/snacks-munchies/nuts-trail-mixes.avif'
  when 'traditional-snacks' then 'local/snacks-munchies/traditional-snacks.avif'
  when 'papad-fryums' then 'local/snacks-munchies/papad-fryums.avif'
  when 'healthy-snacks' then 'local/snacks-munchies/healthy-snacks.avif'
  else category.image_key
end,
media_version = category.media_version + 1,
updated_at = now(),
version = category.version + 1
from dastak_v1.category_types as category_type
where category.category_type_id = category_type.id
  and category_type.slug = 'snacks-munchies'
  and category.slug in (
    'chips', 'namkeen', 'extruded-snacks', 'popcorn', 'nuts-trail-mixes',
    'traditional-snacks', 'papad-fryums', 'healthy-snacks'
  );
