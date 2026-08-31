insert into dastak_v1.subcategories(category_id,name,slug,status,created_by)
select c.id,v.name,v.slug,'DRAFT','2cd659b9-3995-46a1-baac-8a735b7e8178'::uuid
from dastak_v1.categories c
join (values
 ('salt','Black Salt','black-salt'),
 ('atta-flours','Amaranth Flour','amaranth-flour'),
 ('millets-grains','Amaranth Seeds','amaranth-seeds'),
 ('rice','Black Rice','black-rice'),
 ('rice','Red Rice','red-rice'),
 ('rice','Broken Rice','broken-rice'),
 ('rice','Gobindobhog Rice','gobindobhog-rice'),
 ('atta-flours','Buckwheat Flour','buckwheat-flour'),
 ('powdered-spices','Cinnamon Powder','cinnamon-powder'),
 ('whole-spices','Kalonji / Nigella Seeds','kalonji'),
 ('atta-flours','Maize Flour / Makka Atta','maize-flour'),
 ('dals-pulses','Moth Beans','moth-beans'),
 ('rice','Puffed Rice','puffed-rice'),
 ('atta-flours','Quinoa Flour','quinoa-flour'),
 ('blended-masalas','Pav Bhaji Masala','pav-bhaji-masala'),
 ('blended-masalas','Rajma Masala','rajma-masala'),
 ('blended-masalas','Tandoori Masala','tandoori-masala'),
 ('blended-masalas','Sabzi Masala','sabzi-masala'),
 ('atta-flours','Sattu','sattu'),
 ('millets-grains','Wheat Dalia / Broken Wheat','wheat-dalia'),
 ('millets-grains','Ragi / Finger Millet','ragi-finger-millet'),
 ('rice','Rice Rava','rice-rava')
) v(category_slug,name,slug) on c.slug=v.category_slug
where not exists(select 1 from dastak_v1.subcategories s where s.category_id=c.id and s.slug=v.slug);;
