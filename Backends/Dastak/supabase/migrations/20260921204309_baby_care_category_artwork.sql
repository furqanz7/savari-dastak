update dastak_v1.categories as c
set
  image_key = case c.slug
    when 'diapers' then 'local/baby-care/diapers.avif'
    when 'baby-wipes' then 'local/baby-care/baby-wipes.avif'
    when 'baby-food' then 'local/baby-care/baby-food.avif'
    when 'baby-feeding' then 'local/baby-care/baby-feeding.avif'
    when 'baby-bath' then 'local/baby-care/baby-bath.avif'
    when 'baby-skin-care' then 'local/baby-care/baby-skin-care.avif'
    when 'baby-oral-care' then 'local/baby-care/baby-oral-care.avif'
    when 'baby-accessories' then 'local/baby-care/baby-accessories.avif'
  end,
  media_version = c.media_version + 1,
  version = c.version + 1,
  updated_at = now()
where c.category_type_id = (
  select ct.id from dastak_v1.category_types as ct where ct.slug = 'baby-care'
)
and c.slug in (
  'diapers', 'baby-wipes', 'baby-food', 'baby-feeding',
  'baby-bath', 'baby-skin-care', 'baby-oral-care', 'baby-accessories'
);
