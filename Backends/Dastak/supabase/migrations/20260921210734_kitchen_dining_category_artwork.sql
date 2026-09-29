update dastak_v1.categories as c
set
  image_key = case c.slug
    when 'cookware' then 'local/kitchen-dining/cookware.avif'
    when 'bakeware' then 'local/kitchen-dining/bakeware.avif'
    when 'kitchen-tools' then 'local/kitchen-dining/kitchen-tools.avif'
    when 'food-storage' then 'local/kitchen-dining/food-storage.avif'
    when 'bottles-flasks' then 'local/kitchen-dining/bottles-flasks.avif'
    when 'dinnerware' then 'local/kitchen-dining/dinnerware.avif'
    when 'serveware' then 'local/kitchen-dining/serveware.avif'
    when 'disposable-tableware' then 'local/kitchen-dining/disposable-tableware.avif'
    when 'foil-wraps' then 'local/kitchen-dining/foil-wraps.avif'
  end,
  media_version = c.media_version + 1,
  version = c.version + 1,
  updated_at = now()
where c.category_type_id = (
  select ct.id from dastak_v1.category_types as ct where ct.slug = 'kitchen-dining'
)
and c.slug in (
  'cookware', 'bakeware', 'kitchen-tools', 'food-storage', 'bottles-flasks',
  'dinnerware', 'serveware', 'disposable-tableware', 'foil-wraps'
);
