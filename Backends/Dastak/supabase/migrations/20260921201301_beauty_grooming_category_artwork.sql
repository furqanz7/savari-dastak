update dastak_v1.categories as c
set
  image_key = case c.slug
    when 'makeup' then 'local/beauty-grooming/makeup.avif'
    when 'fragrance' then 'local/beauty-grooming/fragrance.avif'
    when 'mens-grooming' then 'local/beauty-grooming/mens-grooming.avif'
    when 'womens-grooming' then 'local/beauty-grooming/womens-grooming.avif'
    when 'beauty-tools' then 'local/beauty-grooming/beauty-tools.avif'
    when 'hair-styling' then 'local/beauty-grooming/hair-styling.avif'
  end,
  media_version = c.media_version + 1,
  version = c.version + 1,
  updated_at = now()
where c.category_type_id = (
  select ct.id from dastak_v1.category_types as ct where ct.slug = 'beauty-grooming'
)
and c.slug in ('makeup', 'fragrance', 'mens-grooming', 'womens-grooming', 'beauty-tools', 'hair-styling');
