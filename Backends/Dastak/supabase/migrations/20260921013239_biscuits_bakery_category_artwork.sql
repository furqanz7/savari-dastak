-- Bind the supplied Biscuits & Bakery artwork to the existing category
-- presentations. Product/SKU identities remain unchanged.
update dastak_v1.categories as category
set image_key = case category.slug
  when 'biscuits' then 'local/biscuits-bakery/biscuits.avif'
  when 'cookies' then 'local/biscuits-bakery/cookies.avif'
  when 'crackers' then 'local/biscuits-bakery/crackers.avif'
  when 'cakes-muffins' then 'local/biscuits-bakery/cakes-muffins.avif'
  when 'rusks-toasts' then 'local/biscuits-bakery/rusks-toasts.avif'
  when 'bakery-snacks' then 'local/biscuits-bakery/bakery-snacks.avif'
  else category.image_key
end,
media_version = category.media_version + 1,
updated_at = now(),
version = category.version + 1
from dastak_v1.category_types as category_type
where category.category_type_id = category_type.id
  and category_type.slug = 'biscuits-bakery'
  and category.slug in ('biscuits', 'cookies', 'crackers', 'cakes-muffins', 'rusks-toasts', 'bakery-snacks');
