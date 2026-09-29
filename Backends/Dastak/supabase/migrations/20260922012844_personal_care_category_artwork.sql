update dastak_v1.categories as c
set
  image_key = case c.slug
    when 'bath-body' then 'local/personal-care/bath-body.avif'
    when 'hair-care' then 'local/personal-care/hair-care.avif'
    when 'oral-care' then 'local/personal-care/oral-care.avif'
    when 'skin-care' then 'local/personal-care/skin-care.avif'
    when 'deodorants' then 'local/personal-care/deodorants.avif'
    when 'shaving' then 'local/personal-care/shaving.avif'
    when 'hand-foot-care' then 'local/personal-care/hand-foot-care.avif'
  end,
  media_version = c.media_version + 1,
  version = c.version + 1,
  updated_at = now()
where c.category_type_id = (
  select ct.id from dastak_v1.category_types as ct where ct.slug = 'personal-care'
)
and c.slug in (
  'bath-body', 'hair-care', 'oral-care', 'skin-care',
  'deodorants', 'shaving', 'hand-foot-care'
);
