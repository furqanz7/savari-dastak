-- Production already had an approved owner when this historical taxonomy seed
-- ran. Fresh database replays do not. Keep an inert, deleted audit principal
-- with no Auth credential or product persona so the migration chain remains
-- reconstructable without creating a sign-in identity.
insert into public.accounts (
  id, display_name, phone_number, phone_verification_state, account_state,
  deletion_requested_at, anonymized_at, deleted_at
) values (
  '2cd659b9-3995-46a1-baac-8a735b7e8178',
  'Catalogue migration actor', '+919999999998', 'unverified', 'DELETED',
  pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
)
on conflict (id) do nothing;

insert into private.account_memberships (
  account_id, role, approved_at, suspended_until
) values (
  '2cd659b9-3995-46a1-baac-8a735b7e8178', 'owner',
  pg_catalog.now(), null
)
on conflict (account_id, role) do nothing;

insert into dastak_v1.platform_permission_grants (
  account_id, bundle_id, granted_by, grant_reason
) values (
  '2cd659b9-3995-46a1-baac-8a735b7e8178',
  '10000000-0000-4000-8000-00000000000c',
  '2cd659b9-3995-46a1-baac-8a735b7e8178',
  'Historical catalogue migration audit actor'
)
on conflict (account_id, bundle_id) where revoked_at is null do nothing;

with actor as (
  select g.account_id
  from dastak_v1.platform_permission_grants g
  join dastak_v1.permission_bundles b on b.id=g.bundle_id
  where b.bundle_key='platform_super_admin' and g.revoked_at is null
  order by g.granted_at
  limit 1
), seed_type(name,slug,sort_order) as (
  values
  ('Fresh Produce','fresh-produce',10),
  ('Dairy, Bread & Eggs','dairy-bread-eggs',20),
  ('Staples & Pantry','staples-pantry',30),
  ('Masala & Cooking','masala-cooking',40),
  ('Breakfast & Spreads','breakfast-spreads',50),
  ('Snacks & Munchies','snacks-munchies',60),
  ('Biscuits & Bakery','biscuits-bakery',70),
  ('Beverages','beverages',80),
  ('Tea, Coffee & Drink Mixes','tea-coffee-drink-mixes',90),
  ('Chocolates & Sweets','chocolates-sweets',100),
  ('Instant, Ready & Frozen Food','instant-ready-frozen-food',110),
  ('Personal Care','personal-care',120),
  ('Beauty & Grooming','beauty-grooming',130),
  ('Health & Hygiene','health-hygiene',140),
  ('Baby Care','baby-care',150),
  ('Home Cleaning','home-cleaning',160),
  ('Kitchen & Dining','kitchen-dining',170),
  ('Home & Utility','home-utility',180),
  ('Electronics & Accessories','electronics-accessories',190),
  ('Stationery, Office & School','stationery-office-school',200),
  ('Pet Care','pet-care',210),
  ('Puja & Festive','puja-festive',220),
  ('Toys, Games & Kids','toys-games-kids',230),
  ('Automotive & Travel Utility','automotive-travel-utility',240),
  ('Home Improvement & Hardware','home-improvement-hardware',250)
)
insert into dastak_v1.category_types(name,slug,status,sort_order,created_by)
select s.name,s.slug,'DRAFT',s.sort_order,a.account_id
from seed_type s cross join actor a
on conflict(slug) do update set
  name=excluded.name,
  sort_order=excluded.sort_order,
  updated_at=now(),
  version=dastak_v1.category_types.version+1;

with actor as (
  select g.account_id
  from dastak_v1.platform_permission_grants g
  join dastak_v1.permission_bundles b on b.id=g.bundle_id
  where b.bundle_key='platform_super_admin' and g.revoked_at is null
  order by g.granted_at limit 1
), seed(type_slug,name,slug,sort_order) as (
  values
  ('fresh-produce','Fresh Fruits','fresh-fruits',10),('fresh-produce','Fresh Vegetables','fresh-vegetables',20),('fresh-produce','Leafy Greens & Herbs','leafy-greens-herbs',30),('fresh-produce','Seasonal Fruits','seasonal-fruits',40),('fresh-produce','Fresh Cuts & Sprouts','fresh-cuts-sprouts',50),('fresh-produce','Exotic & Premium Produce','exotic-premium-produce',60),('fresh-produce','Flowers & Leaves','flowers-leaves',70),
  ('dairy-bread-eggs','Milk','milk',10),('dairy-bread-eggs','Curd & Yogurt','curd-yogurt',20),('dairy-bread-eggs','Paneer & Cream','paneer-cream',30),('dairy-bread-eggs','Butter & Margarine','butter-margarine',40),('dairy-bread-eggs','Cheese','cheese',50),('dairy-bread-eggs','Eggs','eggs',60),('dairy-bread-eggs','Bread & Buns','bread-buns',70),('dairy-bread-eggs','Bakery Essentials','bakery-essentials',80),('dairy-bread-eggs','Dairy Alternatives','dairy-alternatives',90),
  ('staples-pantry','Rice','rice',10),('staples-pantry','Atta & Flours','atta-flours',20),('staples-pantry','Dals & Pulses','dals-pulses',30),('staples-pantry','Cooking Oils','cooking-oils',40),('staples-pantry','Ghee','ghee',50),('staples-pantry','Sugar & Sweeteners','sugar-sweeteners',60),('staples-pantry','Salt','salt',70),('staples-pantry','Dry Fruits & Nuts','dry-fruits-nuts',80),('staples-pantry','Seeds','seeds',90),('staples-pantry','Millets & Grains','millets-grains',100),
  ('masala-cooking','Whole Spices','whole-spices',10),('masala-cooking','Powdered Spices','powdered-spices',20),('masala-cooking','Blended Masalas','blended-masalas',30),('masala-cooking','Cooking Pastes','cooking-pastes',40),('masala-cooking','Sauces & Condiments','sauces-condiments',50),('masala-cooking','Cooking Ingredients','cooking-ingredients',60),('masala-cooking','Pickles & Chutneys','pickles-chutneys',70),('masala-cooking','Coconut Products','coconut-products',80),
  ('breakfast-spreads','Breakfast Cereals','breakfast-cereals',10),('breakfast-spreads','Oats','oats',20),('breakfast-spreads','Muesli & Granola','muesli-granola',30),('breakfast-spreads','Instant Breakfast','instant-breakfast',40),('breakfast-spreads','Spreads','spreads',50),('breakfast-spreads','Honey & Syrups','honey-syrups',60),('breakfast-spreads','Pancake & Baking Mixes','pancake-baking-mixes',70),
  ('snacks-munchies','Chips','chips',10),('snacks-munchies','Namkeen','namkeen',20),('snacks-munchies','Extruded Snacks','extruded-snacks',30),('snacks-munchies','Popcorn','popcorn',40),('snacks-munchies','Nuts & Trail Mixes','nuts-trail-mixes',50),('snacks-munchies','Traditional Snacks','traditional-snacks',60),('snacks-munchies','Papad & Fryums','papad-fryums',70),('snacks-munchies','Healthy Snacks','healthy-snacks',80),
  ('biscuits-bakery','Biscuits','biscuits',10),('biscuits-bakery','Cookies','cookies',20),('biscuits-bakery','Crackers','crackers',30),('biscuits-bakery','Cakes & Muffins','cakes-muffins',40),('biscuits-bakery','Rusks & Toasts','rusks-toasts',50),('biscuits-bakery','Bakery Snacks','bakery-snacks',60),
  ('beverages','Water','water',10),('beverages','Soft Drinks','soft-drinks',20),('beverages','Fruit Juices','fruit-juices',30),('beverages','Coconut Water','coconut-water',40),('beverages','Energy Drinks','energy-drinks',50),('beverages','Sports & Functional Drinks','sports-functional-drinks',60),('beverages','Soda & Mixers','soda-mixers',70),('beverages','Non-Alcoholic Speciality Drinks','non-alcoholic-speciality-drinks',80),
  ('tea-coffee-drink-mixes','Tea','tea',10),('tea-coffee-drink-mixes','Coffee','coffee',20),('tea-coffee-drink-mixes','Health Drinks','health-drinks',30),('tea-coffee-drink-mixes','Malt & Cocoa','malt-cocoa',40),('tea-coffee-drink-mixes','Drink Mixes','drink-mixes',50),
  ('chocolates-sweets','Chocolates','chocolates',10),('chocolates-sweets','Candy','candy',20),('chocolates-sweets','Gum & Mints','gum-mints',30),('chocolates-sweets','Indian Sweets','indian-sweets',40),('chocolates-sweets','Sweet Snacks','sweet-snacks',50),
  ('instant-ready-frozen-food','Noodles','noodles',10),('instant-ready-frozen-food','Pasta','pasta',20),('instant-ready-frozen-food','Vermicelli','vermicelli',30),('instant-ready-frozen-food','Ready to Eat','ready-to-eat',40),('instant-ready-frozen-food','Ready to Cook','ready-to-cook',50),('instant-ready-frozen-food','Frozen Snacks','frozen-snacks',60),('instant-ready-frozen-food','Frozen Vegetables','frozen-vegetables',70),('instant-ready-frozen-food','Ice Cream & Frozen Desserts','ice-cream-frozen-desserts',80),('instant-ready-frozen-food','Soups','soups',90),
  ('personal-care','Bath & Body','bath-body',10),('personal-care','Hair Care','hair-care',20),('personal-care','Oral Care','oral-care',30),('personal-care','Skin Care','skin-care',40),('personal-care','Deodorants','deodorants',50),('personal-care','Hand & Foot Care','hand-foot-care',60),('personal-care','Shaving','shaving',70),
  ('beauty-grooming','Makeup','makeup',10),('beauty-grooming','Fragrance','fragrance',20),('beauty-grooming','Men''s Grooming','mens-grooming',30),('beauty-grooming','Women''s Grooming','womens-grooming',40),('beauty-grooming','Beauty Tools','beauty-tools',50),('beauty-grooming','Hair Styling','hair-styling',60),
  ('health-hygiene','Feminine Care','feminine-care',10),('health-hygiene','First Aid','first-aid',20),('health-hygiene','Masks & Sanitizers','masks-sanitizers',30),('health-hygiene','Adult Care','adult-care',40),('health-hygiene','Cotton & Dressing','cotton-dressing',50),('health-hygiene','Wellness Accessories','wellness-accessories',60),('health-hygiene','Eye & Ear Care','eye-ear-care',70),
  ('baby-care','Diapers','diapers',10),('baby-care','Baby Wipes','baby-wipes',20),('baby-care','Baby Food','baby-food',30),('baby-care','Baby Feeding','baby-feeding',40),('baby-care','Baby Bath','baby-bath',50),('baby-care','Baby Skin Care','baby-skin-care',60),('baby-care','Baby Oral Care','baby-oral-care',70),('baby-care','Baby Accessories','baby-accessories',80),
  ('home-cleaning','Laundry','laundry',10),('home-cleaning','Dishwashing','dishwashing',20),('home-cleaning','Floor Cleaning','floor-cleaning',30),('home-cleaning','Toilet Cleaning','toilet-cleaning',40),('home-cleaning','Surface Cleaning','surface-cleaning',50),('home-cleaning','Glass & Metal Cleaning','glass-metal-cleaning',60),('home-cleaning','Cleaning Tools','cleaning-tools',70),('home-cleaning','Air Fresheners','air-fresheners',80),('home-cleaning','Home Protection','home-protection',90),
  ('kitchen-dining','Cookware','cookware',10),('kitchen-dining','Bakeware','bakeware',20),('kitchen-dining','Kitchen Tools','kitchen-tools',30),('kitchen-dining','Food Storage','food-storage',40),('kitchen-dining','Bottles & Flasks','bottles-flasks',50),('kitchen-dining','Dinnerware','dinnerware',60),('kitchen-dining','Serveware','serveware',70),('kitchen-dining','Disposable Tableware','disposable-tableware',80),('kitchen-dining','Foil & Wraps','foil-wraps',90),
  ('home-utility','Electrical Essentials','electrical-essentials',10),('home-utility','Lighting','lighting',20),('home-utility','Batteries','batteries',30),('home-utility','Adhesives & Tapes','adhesives-tapes',40),('home-utility','Hooks & Organizers','hooks-organizers',50),('home-utility','Bathroom Utility','bathroom-utility',60),('home-utility','Home Furnishing Basics','home-furnishing-basics',70),('home-utility','Rain Essentials','rain-essentials',80),('home-utility','Travel Utility','travel-utility',90),
  ('electronics-accessories','Mobile Chargers','mobile-chargers',10),('electronics-accessories','Cables','cables',20),('electronics-accessories','Power Banks','power-banks',30),('electronics-accessories','Earphones & Audio','earphones-audio',40),('electronics-accessories','Mobile Accessories','mobile-accessories',50),('electronics-accessories','Computer Accessories','computer-accessories',60),('electronics-accessories','Small Appliances','small-appliances',70),('electronics-accessories','Smart Accessories','smart-accessories',80),
  ('stationery-office-school','Pens','pens',10),('stationery-office-school','Pencils & Erasers','pencils-erasers',20),('stationery-office-school','Markers & Highlighters','markers-highlighters',30),('stationery-office-school','Notebooks','notebooks',40),('stationery-office-school','Paper','paper',50),('stationery-office-school','Art & Craft','art-craft',60),('stationery-office-school','School Supplies','school-supplies',70),('stationery-office-school','Office Supplies','office-supplies',80),('stationery-office-school','Adhesives','stationery-adhesives',90),('stationery-office-school','Calculators','calculators',100),
  ('pet-care','Dog Food','dog-food',10),('pet-care','Cat Food','cat-food',20),('pet-care','Pet Treats','pet-treats',30),('pet-care','Pet Hygiene','pet-hygiene',40),('pet-care','Pet Accessories','pet-accessories',50),('pet-care','Aquarium Care','aquarium-care',60),('pet-care','Bird Care','bird-care',70),
  ('puja-festive','Incense','incense',10),('puja-festive','Camphor','camphor',20),('puja-festive','Diyas & Lamps','diyas-lamps',30),('puja-festive','Puja Oils','puja-oils',40),('puja-festive','Puja Kits','puja-kits',50),('puja-festive','Religious Accessories','religious-accessories',60),('puja-festive','Festive Decor','festive-decor',70),('puja-festive','Candles','candles',80),('puja-festive','Rangoli','rangoli',90),
  ('toys-games-kids','Baby Toys','baby-toys',10),('toys-games-kids','Pretend Play','pretend-play',20),('toys-games-kids','Toy Vehicles','toy-vehicles',30),('toys-games-kids','Dolls & Figures','dolls-figures',40),('toys-games-kids','Board Games','board-games',50),('toys-games-kids','Puzzles','puzzles',60),('toys-games-kids','Outdoor Toys','outdoor-toys',70),('toys-games-kids','Educational Toys','educational-toys',80),('toys-games-kids','Art & Activity','art-activity',90),
  ('automotive-travel-utility','Car Care','car-care',10),('automotive-travel-utility','Bike Care','bike-care',20),('automotive-travel-utility','Cleaning Accessories','automotive-cleaning-accessories',30),('automotive-travel-utility','Car Accessories','car-accessories',40),('automotive-travel-utility','Bike Accessories','bike-accessories',50),('automotive-travel-utility','Travel Accessories','travel-accessories',60),('automotive-travel-utility','Emergency Essentials','emergency-essentials',70),
  ('home-improvement-hardware','Basic Tools','basic-tools',10),('home-improvement-hardware','Fasteners','fasteners',20),('home-improvement-hardware','Plumbing Utility','plumbing-utility',30),('home-improvement-hardware','Safety & Protection','safety-protection',40),('home-improvement-hardware','Home Repair','home-repair',50)
)
insert into dastak_v1.categories(category_type_id,name,slug,status,sort_order,created_by)
select ct.id,s.name,s.slug,'DRAFT',s.sort_order,a.account_id
from seed s
join dastak_v1.category_types ct on ct.slug=s.type_slug
cross join actor a
on conflict(slug) do update set
  category_type_id=excluded.category_type_id,
  name=excluded.name,
  sort_order=excluded.sort_order,
  updated_at=now(),
  version=dastak_v1.categories.version+1;;
