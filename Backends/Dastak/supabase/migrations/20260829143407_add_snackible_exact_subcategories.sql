insert into dastak_v1.subcategories (category_id,name,slug,status,sort_order,created_by)
select c.id,'Rice Chips','rice-chips','DRAFT'::dastak_v1.catalogue_status,0,'2cd659b9-3995-46a1-baac-8a735b7e8178'::uuid
from dastak_v1.categories c where c.slug='chips'
and not exists (select 1 from dastak_v1.subcategories s where s.slug='rice-chips');

insert into dastak_v1.subcategories (category_id,name,slug,status,sort_order,created_by)
select c.id,'Flavoured Cookies','flavoured-cookies','DRAFT'::dastak_v1.catalogue_status,0,'2cd659b9-3995-46a1-baac-8a735b7e8178'::uuid
from dastak_v1.categories c where c.slug='cookies'
and not exists (select 1 from dastak_v1.subcategories s where s.slug='flavoured-cookies');

insert into dastak_v1.subcategories (category_id,name,slug,status,sort_order,created_by)
select c.id,v.name,v.slug,'DRAFT'::dastak_v1.catalogue_status,0,'2cd659b9-3995-46a1-baac-8a735b7e8178'::uuid
from dastak_v1.categories c
cross join (values ('Pistachio Spread','pistachio-spread'),('Hazelnut Spread','hazelnut-spread'),('Caramel Spread','caramel-spread'),('Vanilla Spread','vanilla-spread')) v(name,slug)
where c.slug='spreads'
and not exists (select 1 from dastak_v1.subcategories s where s.slug=v.slug);;
