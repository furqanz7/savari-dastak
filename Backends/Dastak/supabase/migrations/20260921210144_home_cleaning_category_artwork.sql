update dastak_v1.categories as c
set
  image_key = case c.slug
    when 'laundry' then 'local/home-cleaning/laundry.avif'
    when 'dishwashing' then 'local/home-cleaning/dishwashing.avif'
    when 'floor-cleaning' then 'local/home-cleaning/floor-cleaning.avif'
    when 'toilet-cleaning' then 'local/home-cleaning/toilet-cleaning.avif'
    when 'surface-cleaning' then 'local/home-cleaning/surface-cleaning.avif'
    when 'glass-metal-cleaning' then 'local/home-cleaning/glass-metal-cleaning.avif'
    when 'cleaning-tools' then 'local/home-cleaning/cleaning-tools.avif'
    when 'air-fresheners' then 'local/home-cleaning/air-fresheners.avif'
    when 'home-protection' then 'local/home-cleaning/home-protection.avif'
  end,
  media_version = c.media_version + 1,
  version = c.version + 1,
  updated_at = now()
where c.category_type_id = (
  select ct.id from dastak_v1.category_types as ct where ct.slug = 'home-cleaning'
)
and c.slug in (
  'laundry', 'dishwashing', 'floor-cleaning', 'toilet-cleaning',
  'surface-cleaning', 'glass-metal-cleaning', 'cleaning-tools',
  'air-fresheners', 'home-protection'
);
