insert into dastak_v1.subcategories(category_id,name,slug,status,created_by)
select c.id,v.name,v.slug,'DRAFT','2cd659b9-3995-46a1-baac-8a735b7e8178'::uuid
from dastak_v1.categories c
join (values
 ('curd-yogurt','Mishti Doi','mishti-doi'),
 ('curd-yogurt','High Protein Yogurt','high-protein-yogurt'),
 ('non-alcoholic-speciality-drinks','Yogurt Smoothies','yogurt-smoothies'),
 ('non-alcoholic-speciality-drinks','Dairy Milkshakes','dairy-milkshakes'),
 ('sports-functional-drinks','High Protein Milkshakes','high-protein-milkshakes')
) v(category_slug,name,slug) on v.category_slug=c.slug
where not exists (select 1 from dastak_v1.subcategories s where s.category_id=c.id and s.slug=v.slug);;
