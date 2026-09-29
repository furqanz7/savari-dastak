-- Remove the two empty Fresh Produce categories from all catalogue views while
-- retaining their records for audit/history.
update dastak_v1.categories c
set status = 'INACTIVE', updated_at = now(), version = c.version + 1
from dastak_v1.category_types t
where c.category_type_id = t.id
  and t.slug = 'fresh-produce'
  and c.slug in ('fresh-pooja-festive', 'fresh-certified-organics')
  and not exists (
    select 1
    from dastak_v1.subcategories s
    join dastak_v1.skus sku on sku.subcategory_id = s.id
    where s.category_id = c.id
      and sku.status <> 'INACTIVE'
  );
