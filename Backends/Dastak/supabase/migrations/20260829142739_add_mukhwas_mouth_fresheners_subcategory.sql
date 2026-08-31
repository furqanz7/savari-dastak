insert into dastak_v1.subcategories (category_id,name,slug,status,sort_order,created_by)
select c.id,'Mukhwas & Mouth Fresheners','mukhwas-mouth-fresheners','DRAFT'::dastak_v1.catalogue_status,0,'2cd659b9-3995-46a1-baac-8a735b7e8178'::uuid
from dastak_v1.categories c
where c.slug='traditional-snacks'
  and not exists (select 1 from dastak_v1.subcategories s where s.slug='mukhwas-mouth-fresheners');;
