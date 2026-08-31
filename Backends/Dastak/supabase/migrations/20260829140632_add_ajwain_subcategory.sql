insert into dastak_v1.subcategories(category_id,name,slug,status,created_by)
select c.id,'Ajwain / Carom Seeds','ajwain','DRAFT','2cd659b9-3995-46a1-baac-8a735b7e8178'::uuid
from dastak_v1.categories c where c.slug='whole-spices'
and not exists(select 1 from dastak_v1.subcategories s where s.category_id=c.id and s.slug='ajwain');;
