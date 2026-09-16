update dastak_v1.subcategories sc
set image_key = case c.slug
  when 'fresh-fruits' then 'canonical/taxonomy/subcategories/fresh-fruits-provided.png'
  when 'fresh-vegetables' then 'canonical/taxonomy/subcategories/fresh-vegetables-provided.png'
  when 'leafy-greens-herbs' then 'canonical/taxonomy/subcategories/leafy-greens-herbs-provided.png'
  when 'seasonal-fruits' then 'canonical/taxonomy/subcategories/seasonal-fruits-provided.png'
  when 'fresh-cuts-sprouts' then 'canonical/taxonomy/subcategories/fresh-cuts-sprouts-provided.png'
  when 'exotic-premium-produce' then 'canonical/taxonomy/subcategories/exotic-premium-produce-provided.png'
  when 'flowers-leaves' then 'canonical/taxonomy/subcategories/flowers-leaves-provided.png'
end,
media_version = sc.media_version + 1,
updated_at = now(),
version = sc.version + 1
from dastak_v1.categories c
join dastak_v1.category_types ct on ct.id = c.category_type_id
where sc.category_id = c.id and ct.slug = 'fresh-produce';
