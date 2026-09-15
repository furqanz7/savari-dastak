-- Permanent taxonomy artwork is deliberately independent of SKU imagery.
-- The same governed asset is used by Customer, Merchant, Admin, Web and iOS.
do $$
declare
  r record;
  key text;
begin
  for r in select id, slug from dastak_v1.category_types loop
    key := case
      when r.slug in ('dairy-bread-eggs') then 'canonical/taxonomy/dairy-bread-eggs.png'
      when r.slug in ('fresh-produce','vegetables-fruits') then 'canonical/taxonomy/vegetables-fruits.png'
      when r.slug in ('beverages','drinks-juices','cold-drinks-juices') then 'canonical/taxonomy/drinks-juices.png'
      when r.slug in ('snacks-munchies','munchies') then 'canonical/taxonomy/snacks-munchies.png'
      when r.slug in ('breakfast-spreads','instant-ready-frozen-food','breakfast-instant-food') then 'canonical/taxonomy/breakfast-instant.png'
      when r.slug in ('chocolates-sweets','sweet-tooth') then 'canonical/taxonomy/sweet-tooth.png'
      when r.slug in ('biscuits-bakery','bakery-biscuits') then 'canonical/taxonomy/bakery-biscuits.png'
      when r.slug in ('tea-coffee-drink-mixes','tea-coffee-health-drinks') then 'canonical/taxonomy/tea-coffee.png'
      when r.slug in ('staples-pantry','atta-rice-dal') then 'canonical/taxonomy/atta-rice-dal.png'
      when r.slug in ('masala-cooking','masala-oil-more') then 'canonical/taxonomy/masala-oil.png'
      when r.slug in ('sauces-spreads') then 'canonical/taxonomy/sauces-spreads.png'
      when r.slug in ('chicken-meat-fish') then 'canonical/taxonomy/chicken-meat-fish.png'
      when r.slug in ('organic-gourmet','organic-healthy-living') then 'canonical/taxonomy/organic-healthy.png'
      when r.slug in ('baby-care') then 'canonical/taxonomy/baby-care.png'
      when r.slug in ('health-hygiene','pharmacy','pharma-wellness') then 'canonical/taxonomy/pharma-wellness.png'
      when r.slug in ('home-cleaning','cleaning-essentials') then 'canonical/taxonomy/cleaning-essentials.png'
      when r.slug in ('home-utility','home-office','kitchen-dining') then 'canonical/taxonomy/home-office.png'
      when r.slug in ('paan-corner') then 'canonical/taxonomy/paan-corner.png'
      else null
    end;
    update dastak_v1.category_types set image_key = key, media_version = media_version + 1, updated_at = now() where id = r.id;
    update dastak_v1.categories set image_key = key, media_version = media_version + 1, updated_at = now() where category_type_id = r.id;
    update dastak_v1.subcategories s set image_key = key, media_version = s.media_version + 1, updated_at = now()
      from dastak_v1.categories c where s.category_id = c.id and c.category_type_id = r.id;
  end loop;
end $$;
