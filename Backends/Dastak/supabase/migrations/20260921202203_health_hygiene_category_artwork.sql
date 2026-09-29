update dastak_v1.categories as c
set
  image_key = case c.slug
    when 'feminine-care' then 'local/health-hygiene/feminine-care.avif'
    when 'first-aid' then 'local/health-hygiene/first-aid.avif'
    when 'masks-sanitizers' then 'local/health-hygiene/masks-sanitizers.avif'
    when 'adult-care' then 'local/health-hygiene/adult-care.avif'
    when 'cotton-dressing' then 'local/health-hygiene/cotton-dressing.avif'
    when 'wellness-accessories' then 'local/health-hygiene/wellness-accessories.avif'
    when 'eye-ear-care' then 'local/health-hygiene/eye-ear-care.avif'
  end,
  media_version = c.media_version + 1,
  version = c.version + 1,
  updated_at = now()
where c.category_type_id = (
  select ct.id from dastak_v1.category_types as ct where ct.slug = 'health-hygiene'
)
and c.slug in (
  'feminine-care', 'first-aid', 'masks-sanitizers', 'adult-care',
  'cotton-dressing', 'wellness-accessories', 'eye-ear-care'
);
