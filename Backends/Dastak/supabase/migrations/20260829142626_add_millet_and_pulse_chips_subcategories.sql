insert into dastak_v1.subcategories (category_id,name,slug,status,sort_order,created_by)
select c.id,'Millet Chips','millet-chips','DRAFT'::dastak_v1.catalogue_status,0,'2cd659b9-3995-46a1-baac-8a735b7e8178'::uuid
from dastak_v1.categories c
where c.slug='chips'
  and not exists (select 1 from dastak_v1.subcategories s where s.slug='millet-chips');

insert into dastak_v1.subcategories (category_id,name,slug,status,sort_order,created_by)
select c.id,'Pulse Chips','pulse-chips','DRAFT'::dastak_v1.catalogue_status,0,'2cd659b9-3995-46a1-baac-8a735b7e8178'::uuid
from dastak_v1.categories c
where c.slug='chips'
  and not exists (select 1 from dastak_v1.subcategories s where s.slug='pulse-chips');;
