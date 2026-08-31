insert into dastak_v1.subcategories(category_id,name,slug,status,sort_order,created_by)
select c.id,'Rice Masalas','rice-masala','DRAFT'::dastak_v1.catalogue_status,
       coalesce((select max(s.sort_order)+10 from dastak_v1.subcategories s where s.category_id=c.id),10),
       '2cd659b9-3995-46a1-baac-8a735b7e8178'::uuid
from dastak_v1.categories c
join dastak_v1.category_types ct on ct.id=c.category_type_id
where ct.slug='masala-cooking' and c.slug='blended-masalas'
  and not exists (select 1 from dastak_v1.subcategories s where s.category_id=c.id and s.slug='rice-masala');;
