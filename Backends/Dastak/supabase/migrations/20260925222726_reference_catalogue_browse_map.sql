-- The reference is a browse tree, not a replacement for a SKU's single
-- canonical subcategory. Sources can overlap; SKU records never need cloning.
create table dastak_v1.catalogue_browse_versions (
  version integer primary key check (version > 0),
  state text not null check (state in ('DRAFT', 'ACTIVE', 'RETIRED')),
  source_label text not null,
  created_at timestamptz not null default pg_catalog.now()
);
create unique index catalogue_browse_one_active_version
  on dastak_v1.catalogue_browse_versions(state) where state = 'ACTIVE';

create table dastak_v1.catalogue_browse_nodes (
  version integer not null references dastak_v1.catalogue_browse_versions(version),
  node_key text not null check (node_key ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  parent_key text,
  kind text not null check (kind in ('SECTION', 'DESTINATION', 'RAIL')),
  label text not null check (pg_catalog.length(pg_catalog.btrim(label)) > 0),
  sort_order integer not null check (sort_order >= 0),
  primary key (version, node_key),
  foreign key (version, parent_key)
    references dastak_v1.catalogue_browse_nodes(version, node_key)
    deferrable initially deferred,
  check ((kind = 'SECTION') = (parent_key is null))
);
create unique index catalogue_browse_nodes_sibling_order
  on dastak_v1.catalogue_browse_nodes(version, parent_key, sort_order);
create index catalogue_browse_nodes_parent_idx
  on dastak_v1.catalogue_browse_nodes(version, parent_key);

create table dastak_v1.catalogue_browse_sources (
  version integer not null,
  node_key text not null,
  source_order integer not null check (source_order >= 0),
  type_slug text not null,
  category_slug text,
  subcategory_slug text,
  excluded_category_slugs text[] not null default '{}',
  excluded_subcategory_slugs text[] not null default '{}',
  primary key (version, node_key, source_order),
  foreign key (version, node_key)
    references dastak_v1.catalogue_browse_nodes(version, node_key)
    on delete cascade,
  check (subcategory_slug is null or category_slug is not null),
  check (pg_catalog.array_position(excluded_category_slugs, null) is null),
  check (pg_catalog.array_position(excluded_subcategory_slugs, null) is null)
);
create index catalogue_browse_sources_path_idx
  on dastak_v1.catalogue_browse_sources(type_slug, category_slug, subcategory_slug);

-- Neither configuration table is exposed directly. The only consumer path is
-- the actor-checked, read-only RPC below.
alter table dastak_v1.catalogue_browse_versions enable row level security;
alter table dastak_v1.catalogue_browse_nodes enable row level security;
alter table dastak_v1.catalogue_browse_sources enable row level security;
revoke all on dastak_v1.catalogue_browse_versions from public, anon, authenticated;
revoke all on dastak_v1.catalogue_browse_nodes from public, anon, authenticated;
revoke all on dastak_v1.catalogue_browse_sources from public, anon, authenticated;

insert into dastak_v1.catalogue_browse_versions(version, state, source_label)
values (1, 'DRAFT', 'Catalogue Map Dastak reference and later user corrections');

-- First-level destinations are seeded even when Dastak currently has no SKU.
-- An empty destination is allowed; it must not fall back to a similarly named
-- canonical category elsewhere.
insert into dastak_v1.catalogue_browse_nodes
  (version, node_key, parent_key, kind, label, sort_order)
values
  (1,'fresh-items',null,'SECTION','Fresh Items',10),
  (1,'grocery-kitchen',null,'SECTION','Grocery & Kitchen',20),
  (1,'snacks-drinks',null,'SECTION','Snacks & Drinks',30),
  (1,'beauty-wellness',null,'SECTION','Beauty & Wellness',40),
  (1,'household-lifestyle',null,'SECTION','Household & Lifestyle',50),
  (1,'fresh-vegetables','fresh-items','DESTINATION','Fresh Vegetables',10),
  (1,'fresh-fruits','fresh-items','DESTINATION','Fresh Fruits',20),
  (1,'dairy-bread-eggs','fresh-items','DESTINATION','Dairy, Bread & Eggs',30),
  (1,'meat-seafood','fresh-items','DESTINATION','Meat and Seafood',40),
  (1,'atta-flour-dal','grocery-kitchen','DESTINATION','Atta, Flour & Dal',10),
  (1,'masalas','grocery-kitchen','DESTINATION','Masalas',20),
  (1,'oils-ghee','grocery-kitchen','DESTINATION','Oils and Ghee',30),
  (1,'cereals-breakfast','grocery-kitchen','DESTINATION','Cereals and Breakfast',40),
  (1,'cold-drinks-juices','snacks-drinks','DESTINATION','Cold Drinks and Juices',10),
  (1,'ice-creams','snacks-drinks','DESTINATION','Ice Creams and Frozen',20),
  (1,'chips-namkeens','snacks-drinks','DESTINATION','Chips and Namkeens',30),
  (1,'chocolates','snacks-drinks','DESTINATION','Chocolates',40),
  (1,'biscuits-cakes','snacks-drinks','DESTINATION','Biscuits and Cakes',50),
  (1,'tea-coffee-milk-drinks','snacks-drinks','DESTINATION','Tea Coffee and Milk Drinks',60),
  (1,'sauces-spreads','snacks-drinks','DESTINATION','Sauces and Spreads',70),
  (1,'sweet-corner','snacks-drinks','DESTINATION','Sweet Corner',80),
  (1,'noodles-pasta-vermicelli','snacks-drinks','DESTINATION','Noodles Pasta Vermicelli',90),
  (1,'frozen-food','snacks-drinks','DESTINATION','Frozen Food',100),
  (1,'dry-fruits-seeds-mix','snacks-drinks','DESTINATION','Dry Fruits and Seeds Mix',110),
  (1,'paan-corner','snacks-drinks','DESTINATION','Paan Corner',120),
  (1,'bath-body','beauty-wellness','DESTINATION','Bath and Body',10),
  (1,'hair-care','beauty-wellness','DESTINATION','Hair Care',20),
  (1,'skincare','beauty-wellness','DESTINATION','Skincare',30),
  (1,'makeup','beauty-wellness','DESTINATION','Makeup',40),
  (1,'feminine-hygiene','beauty-wellness','DESTINATION','Feminine Hygiene',50),
  (1,'sexual-wellness','beauty-wellness','DESTINATION','Sexual Wellness',60),
  (1,'health-pharma','beauty-wellness','DESTINATION','Health and Pharma',70),
  (1,'baby-care','beauty-wellness','DESTINATION','Baby Care',80),
  (1,'home-kitchen','household-lifestyle','DESTINATION','Home and Kitchen',10),
  (1,'pooja-store','household-lifestyle','DESTINATION','Pooja Store',20),
  (1,'cleaners-repellents','household-lifestyle','DESTINATION','Cleaners and Repellents',30),
  (1,'toys-stationery','household-lifestyle','DESTINATION','Toys and Stationery',40),
  (1,'electronics-appliances','household-lifestyle','DESTINATION','Electronics and Appliances',50),
  (1,'fashion','household-lifestyle','DESTINATION','Fashion',60),
  (1,'pet-supplies','household-lifestyle','DESTINATION','Pet Supplies',70),
  (1,'sports-fitness','household-lifestyle','DESTINATION','Sports and Fitness',80);

-- Explicit, parent-qualified sources. Multi-source destinations are a union
-- of existing SKU identities, not a copy. Unmapped reference destinations
-- (e.g. Fashion) remain empty until an approved catalogue source exists.
insert into dastak_v1.catalogue_browse_sources
  (version, node_key, source_order, type_slug, category_slug, subcategory_slug)
values
  (1,'fresh-vegetables',10,'fresh-produce','fresh-vegetables',null),
  (1,'fresh-fruits',10,'fresh-produce','fresh-fruits',null),
  (1,'dairy-bread-eggs',10,'dairy-bread-eggs',null,null),
  (1,'meat-seafood',10,'fresh-produce','fresh-meat-seafood',null),
  (1,'atta-flour-dal',10,'staples-pantry',null,null),
  (1,'masalas',10,'masala-cooking',null,null),
  (1,'oils-ghee',10,'oils-ghee',null,null),
  (1,'cereals-breakfast',10,'breakfast-spreads',null,null),
  (1,'cereals-breakfast',20,'snacks-munchies','healthy-snacks','protein-bars'),
  (1,'cold-drinks-juices',10,'beverages',null,null),
  (1,'ice-creams',10,'instant-ready-frozen-food','ice-cream-frozen-desserts',null),
  (1,'chips-namkeens',10,'snacks-munchies','chips',null),
  (1,'chips-namkeens',20,'snacks-munchies','namkeen',null),
  (1,'chips-namkeens',30,'snacks-munchies','extruded-snacks',null),
  (1,'chips-namkeens',40,'snacks-munchies','nuts-trail-mixes','flavoured-nuts'),
  (1,'chocolates',10,'chocolates-sweets','chocolates',null),
  (1,'biscuits-cakes',10,'biscuits-bakery',null,null),
  (1,'tea-coffee-milk-drinks',10,'tea-coffee-drink-mixes',null,null),
  (1,'sauces-spreads',10,'breakfast-spreads','spreads',null),
  (1,'sauces-spreads',20,'masala-cooking','sauces-condiments',null),
  (1,'sweet-corner',10,'chocolates-sweets','indian-sweets',null),
  (1,'sweet-corner',20,'breakfast-spreads','pancake-baking-mixes','dessert-mix'),
  (1,'noodles-pasta-vermicelli',10,'instant-ready-frozen-food','noodles',null),
  (1,'noodles-pasta-vermicelli',20,'instant-ready-frozen-food','pasta',null),
  (1,'noodles-pasta-vermicelli',30,'instant-ready-frozen-food','vermicelli',null),
  (1,'noodles-pasta-vermicelli',40,'instant-ready-frozen-food','ready-to-eat',null),
  (1,'noodles-pasta-vermicelli',50,'instant-ready-frozen-food','soups',null),
  (1,'frozen-food',10,'instant-ready-frozen-food','frozen-snacks',null),
  (1,'frozen-food',20,'instant-ready-frozen-food','frozen-vegetables',null),
  (1,'dry-fruits-seeds-mix',20,'staples-pantry','dry-fruits-nuts',null),
  (1,'dry-fruits-seeds-mix',30,'staples-pantry','seeds',null),
  (1,'paan-corner',10,'paan-corner',null,null),
  (1,'bath-body',10,'personal-care','bath-body',null),
  (1,'hair-care',10,'personal-care','hair-care',null),
  (1,'skincare',10,'personal-care','skin-care',null),
  (1,'makeup',10,'beauty-grooming','makeup',null),
  (1,'feminine-hygiene',10,'health-hygiene','feminine-care',null),
  (1,'health-pharma',10,'pharmacy',null,null),
  (1,'baby-care',10,'baby-care',null,null),
  (1,'home-kitchen',10,'kitchen-dining',null,null),
  (1,'home-kitchen',20,'home-utility',null,null),
  (1,'pooja-store',10,'puja-festive',null,null),
  (1,'cleaners-repellents',10,'home-cleaning',null,null),
  (1,'toys-stationery',10,'toys-games-kids',null,null),
  (1,'toys-stationery',20,'stationery-office-school',null,null),
  (1,'electronics-appliances',10,'electronics-accessories',null,null),
  (1,'pet-supplies',10,'pet-care',null,null);

-- Existing flour-based mixes have a clear reference shelf. The user chose
-- Rice for biryani kits; pani-puri kits remain unmapped pending a decision.
insert into dastak_v1.catalogue_browse_sources
  (version, node_key, source_order, type_slug, category_slug, subcategory_slug)
values
  (1,'atta-flour-dal',20,'instant-ready-frozen-food','ready-to-cook','adhirasam-mix'),
  (1,'atta-flour-dal',30,'instant-ready-frozen-food','ready-to-cook','bajji-bonda-mix'),
  (1,'atta-flour-dal',40,'instant-ready-frozen-food','ready-to-cook','murukku-mix'),
  (1,'atta-flour-dal',50,'instant-ready-frozen-food','ready-to-cook','biryani-kits');

-- Broad type sources must not double-list products in another reference
-- destination. These are browse exclusions only; canonical SKU paths stay put.
update dastak_v1.catalogue_browse_sources
set excluded_category_slugs = case node_key
  when 'atta-flour-dal' then array['dry-fruits-nuts','seeds']
  when 'masalas' then array['sauces-condiments']
  when 'cereals-breakfast' then array['spreads','pancake-baking-mixes']
end
where version = 1 and node_key in ('atta-flour-dal','masalas','cereals-breakfast');

-- Rails already confirmed in the reference. High Protein Atta is deliberately
-- absent per the user's later instruction.
insert into dastak_v1.catalogue_browse_nodes
  (version, node_key, parent_key, kind, label, sort_order)
values
  (1,'atta','atta-flour-dal','RAIL','Atta',10),
  (1,'rice','atta-flour-dal','RAIL','Rice',20),
  (1,'toor-moong-urad','atta-flour-dal','RAIL','Toor, Moong and Urad',30),
  (1,'basmati-rice','atta-flour-dal','RAIL','Basmati Rice',40),
  (1,'besan-sooji-maida','atta-flour-dal','RAIL','Besan, Sooji and Maida',50),
  (1,'rajma-chola-others','atta-flour-dal','RAIL','Rajma, Chola and Others',60),
  (1,'poha-puffed-rice','atta-flour-dal','RAIL','Poha & Puffed Rice',70),
  (1,'premium-brands','atta-flour-dal','RAIL','Premium Brands',80),
  (1,'soya-chunk-badi','atta-flour-dal','RAIL','Soya Chunk & Badi',90),
  (1,'other-flours','atta-flour-dal','RAIL','Other Flours',100),
  (1,'millets-daliya','atta-flour-dal','RAIL','Millets & Daliya',110),
  (1,'ready-cook-flour-mix','atta-flour-dal','RAIL','Ready to Cook Flour Mix',120),
  (1,'powdered-spices','masalas','RAIL','Powdered Spices',10),
  (1,'whole-spices','masalas','RAIL','Whole Spices',20),
  (1,'cold-grind','masalas','RAIL','Cold Grind',30),
  (1,'sugar-jaggery','masalas','RAIL','Sugar and Jaggery',40),
  (1,'papad-fryums','masalas','RAIL','Papad & Fryums',50),
  (1,'ready-masala','masalas','RAIL','Ready Masala',60),
  (1,'masala-salt','masalas','RAIL','Salt',70),
  (1,'paste-puree','masalas','RAIL','Paste and Puree',80),
  (1,'pickles-chutney','masalas','RAIL','Pickles & Chutney',90),
  (1,'herbs-seasoning','masalas','RAIL','Herbs & Seasoning',100),
  (1,'coconut-milk-powder','masalas','RAIL','Coconut Milk & Powder',110);

-- Dairy rails are taken from the reference. Unstocked rails stay empty;
-- existing SKU identities are only exposed through their canonical paths.
insert into dastak_v1.catalogue_browse_nodes
  (version, node_key, parent_key, kind, label, sort_order)
values
  (1,'dairy-milk','dairy-bread-eggs','RAIL','Milk',10),
  (1,'bread-buns','dairy-bread-eggs','RAIL','Bread and Buns',20),
  (1,'paneer-tofu','dairy-bread-eggs','RAIL','Paneer and Tofu',30),
  (1,'dairy-cheese','dairy-bread-eggs','RAIL','Cheese',40),
  (1,'dairy-eggs','dairy-bread-eggs','RAIL','Eggs',50),
  (1,'curd-yogurts','dairy-bread-eggs','RAIL','Curd and Yogurts',60),
  (1,'dairy-butter','dairy-bread-eggs','RAIL','Butter',70),
  (1,'batters-chutneys','dairy-bread-eggs','RAIL','Batters and Chutneys',80),
  (1,'lassi-buttermilk','dairy-bread-eggs','RAIL','Lassi and Buttermilk',90),
  (1,'indian-breads','dairy-bread-eggs','RAIL','Indian Breads',100),
  (1,'cream-condensed-milk','dairy-bread-eggs','RAIL','Cream and Condensed Milk',110),
  (1,'dairy-alternatives','dairy-bread-eggs','RAIL','Dairy Alternatives',120),
  (1,'milkshakes-more','dairy-bread-eggs','RAIL','Milkshakes and More',130);

insert into dastak_v1.catalogue_browse_sources
  (version, node_key, source_order, type_slug, category_slug, subcategory_slug)
values
  (1,'dairy-milk',10,'dairy-bread-eggs','milk',null),
  (1,'bread-buns',10,'dairy-bread-eggs','bread-buns',null),
  (1,'paneer-tofu',10,'dairy-bread-eggs','paneer-cream',null),
  (1,'dairy-cheese',10,'dairy-bread-eggs','cheese',null),
  (1,'dairy-eggs',10,'dairy-bread-eggs','eggs',null),
  (1,'curd-yogurts',10,'dairy-bread-eggs','curd-yogurt',null),
  (1,'dairy-butter',10,'dairy-bread-eggs','butter-margarine',null),
  (1,'batters-chutneys',10,'dairy-bread-eggs','batters-chutneys',null),
  (1,'indian-breads',10,'dairy-bread-eggs','indian-breads',null),
  (1,'cream-condensed-milk',10,'dairy-bread-eggs','cream-condensed-milk',null);

-- Only stocked, unambiguous reference shelves are mapped here. Additional
-- reference shelves can remain visible without inheriting unrelated SKUs.
insert into dastak_v1.catalogue_browse_nodes
  (version, node_key, parent_key, kind, label, sort_order)
values
  (1,'sunflower-oils','oils-ghee','RAIL','Sunflower Oils',10),
  (1,'pure-ghee','oils-ghee','RAIL','Ghee',20),
  (1,'tea','tea-coffee-milk-drinks','RAIL','Tea',10),
  (1,'green-herbal-tea','tea-coffee-milk-drinks','RAIL','Green & Herbal Tea',20),
  (1,'tea-drink-mixes','tea-coffee-milk-drinks','RAIL','Drink Mixes',30);

insert into dastak_v1.catalogue_browse_sources
  (version, node_key, source_order, type_slug, category_slug, subcategory_slug, excluded_subcategory_slugs)
values
  (1,'sunflower-oils',10,'oils-ghee','cooking-oils','sunflower-oil','{}'),
  (1,'pure-ghee',10,'oils-ghee','ghee','pure-ghee','{}'),
  (1,'tea',10,'tea-coffee-drink-mixes','tea',null,array['green-tea']),
  (1,'green-herbal-tea',10,'tea-coffee-drink-mixes','tea','green-tea','{}'),
  (1,'tea-drink-mixes',10,'tea-coffee-drink-mixes','drink-mixes',null,'{}');

insert into dastak_v1.catalogue_browse_nodes
  (version, node_key, parent_key, kind, label, sort_order)
values
  (1,'breakfast-oats','cereals-breakfast','RAIL','Oats',10),
  (1,'muesli-granola','cereals-breakfast','RAIL','Muesli & Granola',20),
  (1,'high-protein-oats-muesli','cereals-breakfast','RAIL','High protein oats & muesli',30),
  (1,'breakfast-ready-mixes','cereals-breakfast','RAIL','Ready Mixes',40),
  (1,'kids-cereals','cereals-breakfast','RAIL','Kids Cereals',50),
  (1,'masala-oats','cereals-breakfast','RAIL','Masala Oats',60),
  (1,'dessert-mixes','sweet-corner','RAIL','Dessert Mixes',10),
  (1,'chocolate-spreads','sauces-spreads','RAIL','Chocolate Spreads',10),
  (1,'peanut-butters','sauces-spreads','RAIL','Peanut Butters',20),
  (1,'jams','sauces-spreads','RAIL','Jams',30),
  (1,'mayo-spreads','sauces-spreads','RAIL','Mayo & Spreads',40),
  (1,'cooking-sauces','sauces-spreads','RAIL','Cooking Sauces',50),
  (1,'asian-sauces','sauces-spreads','RAIL','Asian Sauces',60),
  (1,'honey-cider-vinegar','sauces-spreads','RAIL','Honey and Cider Vinegar',70);

insert into dastak_v1.catalogue_browse_sources
  (version, node_key, source_order, type_slug, category_slug, subcategory_slug, excluded_subcategory_slugs)
values
  (1,'breakfast-oats',10,'breakfast-spreads','oats',null,array['protein-oats','masala-oats']),
  (1,'muesli-granola',10,'breakfast-spreads','muesli-granola',null,array['protein-granola']),
  (1,'high-protein-oats-muesli',10,'breakfast-spreads','oats','protein-oats','{}'),
  (1,'high-protein-oats-muesli',20,'breakfast-spreads','muesli-granola','protein-granola','{}'),
  (1,'breakfast-ready-mixes',10,'breakfast-spreads','instant-breakfast',null,'{}'),
  (1,'kids-cereals',10,'breakfast-spreads','breakfast-cereals',null,'{}'),
  (1,'masala-oats',10,'breakfast-spreads','oats','masala-oats','{}'),
  (1,'dessert-mixes',10,'breakfast-spreads','pancake-baking-mixes','dessert-mix','{}'),
  (1,'chocolate-spreads',10,'breakfast-spreads','spreads','chocolate-spread','{}'),
  (1,'peanut-butters',10,'breakfast-spreads','spreads','peanut-butter','{}'),
  (1,'jams',10,'breakfast-spreads','spreads','jam','{}'),
  (1,'mayo-spreads',10,'breakfast-spreads','spreads',null,
    array['chocolate-spread','peanut-butter','jam']),
  (1,'cooking-sauces',10,'masala-cooking','sauces-condiments','chilli-sauce','{}'),
  (1,'asian-sauces',10,'masala-cooking','sauces-condiments','asian-cooking-sauces','{}'),
  (1,'asian-sauces',20,'masala-cooking','sauces-condiments','soy-sauce','{}'),
  (1,'honey-cider-vinegar',10,'breakfast-spreads','honey-syrups',null,'{}');

insert into dastak_v1.catalogue_browse_nodes
  (version, node_key, parent_key, kind, label, sort_order)
values
  (1,'energy-bars','cereals-breakfast','RAIL','Energy Bars',70),
  (1,'caffeinated-beverages','cold-drinks-juices','RAIL','Caffeinated Beverages',10),
  (1,'chips-crisps','chips-namkeens','RAIL','Chips and Crisps',10),
  (1,'bhujia-namkeens','chips-namkeens','RAIL','Bhujia and Namkeens',20),
  (1,'chips-nuts','chips-namkeens','RAIL','Nuts',30),
  (1,'cookies','biscuits-cakes','RAIL','Cookies',10),
  (1,'wafers-rusk-crackers','biscuits-cakes','RAIL','Wafers, Rusk & Crackers',20);

insert into dastak_v1.catalogue_browse_sources
  (version, node_key, source_order, type_slug, category_slug, subcategory_slug)
values
  (1,'energy-bars',10,'snacks-munchies','healthy-snacks','protein-bars'),
  (1,'caffeinated-beverages',10,'beverages','energy-drinks','caffeinated-energy-drinks'),
  (1,'chips-crisps',10,'snacks-munchies','chips',null),
  (1,'bhujia-namkeens',10,'snacks-munchies','namkeen',null),
  (1,'chips-nuts',10,'snacks-munchies','nuts-trail-mixes','flavoured-nuts'),
  (1,'cookies',10,'biscuits-bakery','cookies',null),
  (1,'wafers-rusk-crackers',10,'biscuits-bakery','rusks-toasts',null);

-- The reference's Noodles/Pasta/Vermicelli shelf also contains Ready to eat
-- and Soups. Keep unstocked reference rails visible without borrowing SKUs.
insert into dastak_v1.catalogue_browse_nodes
  (version, node_key, parent_key, kind, label, sort_order)
values
  (1,'instant-noodles','noodles-pasta-vermicelli','RAIL','Instant Noodles',10),
  (1,'korean-noodles','noodles-pasta-vermicelli','RAIL','Korean Noodles',20),
  (1,'cup-noodles','noodles-pasta-vermicelli','RAIL','Cup Noodles',30),
  (1,'instant-pasta','noodles-pasta-vermicelli','RAIL','Instant Pasta',40),
  (1,'vermicelli','noodles-pasta-vermicelli','RAIL','Vermicelli',50),
  (1,'cooking-pasta','noodles-pasta-vermicelli','RAIL','Cooking Pasta',60),
  (1,'hakka-noodles','noodles-pasta-vermicelli','RAIL','Hakka Noodles',70),
  (1,'ready-to-eat','noodles-pasta-vermicelli','RAIL','Ready to eat',80),
  (1,'soups','noodles-pasta-vermicelli','RAIL','Soups',90);

insert into dastak_v1.catalogue_browse_sources
  (version, node_key, source_order, type_slug, category_slug, subcategory_slug, excluded_subcategory_slugs)
values
  (1,'atta',10,'staples-pantry','atta-flours',null,
    array['besan-sooji-maida','premium-brands','other-flours','ready-to-cook-flour-mix']),
  (1,'rice',10,'staples-pantry','rice',null,array['basmati-rice','poha-puffed-rice']),
  (1,'toor-moong-urad',10,'staples-pantry','dals-pulses',null,
    array['rajma-chola-others','soya-chunk-badi']),
  (1,'basmati-rice',10,'staples-pantry','rice','basmati-rice','{}'),
  (1,'besan-sooji-maida',10,'staples-pantry','atta-flours','besan-sooji-maida','{}'),
  (1,'rajma-chola-others',10,'staples-pantry','dals-pulses','rajma-chola-others','{}'),
  (1,'poha-puffed-rice',10,'staples-pantry','rice','poha-puffed-rice','{}'),
  (1,'premium-brands',10,'staples-pantry','atta-flours','premium-brands','{}'),
  (1,'soya-chunk-badi',10,'staples-pantry','dals-pulses','soya-chunk-badi','{}'),
  (1,'other-flours',10,'staples-pantry','atta-flours','other-flours','{}'),
  (1,'millets-daliya',10,'staples-pantry','millets-grains','millets-daliya','{}'),
  (1,'ready-cook-flour-mix',10,'staples-pantry','atta-flours','ready-to-cook-flour-mix','{}'),
  (1,'powdered-spices',10,'masala-cooking','powdered-spices',null,'{}'),
  (1,'whole-spices',10,'masala-cooking','whole-spices',null,'{}'),
  (1,'cold-grind',10,'masala-cooking','cold-grind',null,'{}'),
  (1,'sugar-jaggery',10,'masala-cooking','sugar-sweeteners',null,'{}'),
  (1,'papad-fryums',10,'masala-cooking','papad-fryums',null,'{}'),
  (1,'ready-masala',10,'masala-cooking','blended-masalas',null,'{}'),
  (1,'masala-salt',10,'masala-cooking','salt',null,'{}'),
  (1,'paste-puree',10,'masala-cooking','cooking-pastes',null,'{}'),
  (1,'pickles-chutney',10,'masala-cooking','pickles-chutneys',null,'{}'),
  (1,'herbs-seasoning',10,'masala-cooking','herbs-seasoning',null,'{}'),
  (1,'coconut-milk-powder',10,'masala-cooking','coconut-products',null,'{}');

-- Biryani kits deliberately appear in the broad Rice rail, not Basmati Rice.
insert into dastak_v1.catalogue_browse_sources
  (version, node_key, source_order, type_slug, category_slug, subcategory_slug)
values
  (1,'rice',20,'instant-ready-frozen-food','ready-to-cook','biryani-kits');

insert into dastak_v1.catalogue_browse_sources
  (version, node_key, source_order, type_slug, category_slug, subcategory_slug)
values
  (1,'ready-cook-flour-mix',20,'instant-ready-frozen-food','ready-to-cook','adhirasam-mix'),
  (1,'ready-cook-flour-mix',30,'instant-ready-frozen-food','ready-to-cook','bajji-bonda-mix'),
  (1,'ready-cook-flour-mix',40,'instant-ready-frozen-food','ready-to-cook','murukku-mix');

insert into dastak_v1.catalogue_browse_sources
  (version, node_key, source_order, type_slug, category_slug, subcategory_slug)
values
  (1,'instant-noodles',10,'instant-ready-frozen-food','noodles','instant-noodles'),
  (1,'instant-noodles',20,'instant-ready-frozen-food','noodles','shirataki-noodles'),
  (1,'vermicelli',10,'instant-ready-frozen-food','vermicelli',null),
  (1,'cooking-pasta',10,'instant-ready-frozen-food','pasta',null),
  (1,'hakka-noodles',10,'instant-ready-frozen-food','noodles','hakka-noodles'),
  (1,'ready-to-eat',10,'instant-ready-frozen-food','ready-to-eat',null),
  (1,'soups',10,'instant-ready-frozen-food','soups',null);

-- A source path can be missing in an environment with only draft taxonomy,
-- but a path resolving to multiple targets is never acceptable.
create or replace function dastak_v1_api.catalogue_browse_map(p_actor_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  return (
    select pg_catalog.jsonb_build_object(
      'version', v.version,
      'state', v.state,
      'nodes', coalesce(pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'key', n.node_key, 'parentKey', n.parent_key,
          'kind', n.kind, 'label', n.label, 'sortOrder', n.sort_order,
          'sources', coalesce((
            select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
              'typeSlug', source.type_slug,
              'categorySlug', source.category_slug,
              'subcategorySlug', source.subcategory_slug,
              'excludedCategorySlugs', source.excluded_category_slugs,
              'excludedSubcategorySlugs', source.excluded_subcategory_slugs
            ) order by source.source_order)
            from dastak_v1.catalogue_browse_sources source
            where source.version = n.version and source.node_key = n.node_key
          ), '[]'::jsonb)
        ) order by n.kind, n.parent_key nulls first, n.sort_order, n.node_key
      ), '[]'::jsonb)
    )
    from dastak_v1.catalogue_browse_versions v
    join dastak_v1.catalogue_browse_nodes n on n.version = v.version
    where v.state = 'ACTIVE'
    group by v.version, v.state
  );
end;
$$;
revoke all on function dastak_v1_api.catalogue_browse_map(uuid) from public, anon;
grant execute on function dastak_v1_api.catalogue_browse_map(uuid) to authenticated;

create or replace function public.dastak_v1_catalogue_browse_map()
returns jsonb language sql stable security invoker set search_path = ''
as $$
  select dastak_v1_api.catalogue_browse_map(auth.uid());
$$;
revoke all on function public.dastak_v1_catalogue_browse_map() from public, anon;
grant execute on function public.dastak_v1_catalogue_browse_map() to authenticated;

-- Each SKU still belongs to exactly one canonical leaf. DISTINCT prevents a
-- product from being duplicated when two browse sources overlap.
create or replace function dastak_v1_api.catalogue_browse_sku_ids(
  p_actor_id uuid, p_node_key text
)
returns uuid[] language plpgsql stable security definer set search_path = ''
as $$
declare
  v_version integer;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  v_version := (
    select version from dastak_v1.catalogue_browse_versions where state = 'ACTIVE'
  );
  if not exists (
    select 1 from dastak_v1.catalogue_browse_nodes n
    where n.version = v_version and n.node_key = p_node_key
  ) then
    return '{}'::uuid[];
  end if;
  return coalesce((
    select pg_catalog.array_agg(distinct sku.id order by sku.id)
    from dastak_v1.skus sku
    join dastak_v1.subcategories subcategory on subcategory.id = sku.subcategory_id
    join dastak_v1.categories category on category.id = subcategory.category_id
    join dastak_v1.category_types category_type on category_type.id = category.category_type_id
    left join dastak_v1.brands brand on brand.id = sku.brand_id
    where sku.status = 'ACTIVE' and subcategory.status = 'ACTIVE'
      and category.status = 'ACTIVE' and category_type.status = 'ACTIVE'
      and (brand.id is null or brand.status = 'ACTIVE')
      and exists (
        select 1 from dastak_v1.catalogue_browse_sources source
        where source.version = v_version and source.node_key = p_node_key
          and source.type_slug = category_type.slug
          and (source.category_slug is null or source.category_slug = category.slug)
          and (source.subcategory_slug is null or source.subcategory_slug = subcategory.slug)
          and not (category.slug = any(source.excluded_category_slugs))
          and not (subcategory.slug = any(source.excluded_subcategory_slugs))
      )
  ), '{}'::uuid[]);
end;
$$;
revoke all on function dastak_v1_api.catalogue_browse_sku_ids(uuid,text)
  from public, anon;
grant execute on function dastak_v1_api.catalogue_browse_sku_ids(uuid,text)
  to authenticated;

create or replace function public.dastak_v1_catalogue_browse_sku_ids(p_node_key text)
returns uuid[] language sql stable security invoker set search_path = ''
as $$
  select coalesce(dastak_v1_api.catalogue_browse_sku_ids(
    auth.uid(), p_node_key
  ), '{}'::uuid[]);
$$;
revoke all on function public.dastak_v1_catalogue_browse_sku_ids(text) from public, anon;
grant execute on function public.dastak_v1_catalogue_browse_sku_ids(text) to authenticated;
