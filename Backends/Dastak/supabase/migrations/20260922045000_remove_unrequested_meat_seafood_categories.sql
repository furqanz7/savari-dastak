begin;

update dastak_v1.subcategories sc
set status = 'INACTIVE',
    updated_at = now(),
    version = sc.version + 1
from dastak_v1.categories c
join dastak_v1.category_types ct on ct.id = c.category_type_id
where sc.category_id = c.id
  and ct.slug = 'fresh-produce'
  and c.slug = 'fresh-meat-seafood'
  and sc.slug in ('top-deals', 'meat-combos', 'eggs', 'plant-based-meat');

commit;
