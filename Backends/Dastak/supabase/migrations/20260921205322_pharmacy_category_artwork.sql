update dastak_v1.categories as c
set
  image_key = case c.slug
    when 'vitamins-supplements' then 'local/pharmacy/vitamins-supplements.avif'
    when 'medicines' then 'local/pharmacy/medicines.avif'
    when 'first-aid-medical-supplies' then 'local/pharmacy/first-aid-medical-supplies.avif'
  end,
  media_version = c.media_version + 1,
  version = c.version + 1,
  updated_at = now()
where c.category_type_id = (
  select ct.id from dastak_v1.category_types as ct where ct.slug = 'pharmacy'
)
and c.slug in ('vitamins-supplements', 'medicines', 'first-aid-medical-supplies');
