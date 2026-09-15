-- Subcategory artwork is permanent taxonomy artwork, independent of SKU images.
update dastak_v1.subcategories s
set image_key = case s.slug
  when 'fresh-fruits' then 'canonical/taxonomy/subcategories/fresh-fruits.png'
  when 'fresh-vegetables' then 'canonical/taxonomy/subcategories/fresh-vegetables.png'
  when 'leafy-greens-herbs' then 'canonical/taxonomy/subcategories/coriander-others.png'
  when 'seasonal-fruits' then 'canonical/taxonomy/subcategories/seasonal.png'
  when 'fresh-cuts-sprouts' then 'canonical/taxonomy/subcategories/freshly-cut-sprouts.png'
  when 'exotic-premium-produce' then 'canonical/taxonomy/subcategories/exotics.png'
  when 'flowers-leaves' then 'canonical/taxonomy/subcategories/flowers-leaves.png'
  when 'trusted-organics' then 'canonical/taxonomy/subcategories/trusted-organics.png'
  when 'frozen-vegetables' then 'canonical/taxonomy/subcategories/frozen-veg.png'
  else null
end,
media_version = s.media_version + 1,
updated_at = now()
where exists (select 1 from dastak_v1.categories c join dastak_v1.category_types ct on ct.id = c.category_type_id where s.category_id = c.id and ct.slug = 'fresh-produce');
