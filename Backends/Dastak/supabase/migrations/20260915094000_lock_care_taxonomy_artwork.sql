-- Reassert the four customer-facing permanent care artwork keys. These are
-- governed taxonomy assets, not product/SKU images or mutable catalogue art.
do $$
declare
  r record;
  key text;
begin
  for r in
    select id, slug
      from dastak_v1.category_types
     where slug in ('personal-care', 'beauty-grooming', 'health-hygiene', 'pharmacy')
  loop
    key := case r.slug
      when 'personal-care' then 'canonical/taxonomy/personal-care-v2.png'
      when 'beauty-grooming' then 'canonical/taxonomy/beauty-grooming-skin-face-reference.png'
      when 'health-hygiene' then 'canonical/taxonomy/pharma-wellness-v2.png'
      when 'pharmacy' then 'canonical/taxonomy/pharmacy-wellness-reference.png'
    end;

    update dastak_v1.category_types
       set image_key = key,
           media_version = media_version + 1,
           updated_at = now()
     where id = r.id;

    update dastak_v1.categories
       set image_key = key,
           media_version = media_version + 1,
           updated_at = now()
     where category_type_id = r.id;

    update dastak_v1.subcategories s
       set image_key = key,
           media_version = s.media_version + 1,
           updated_at = now()
      from dastak_v1.categories c
     where s.category_id = c.id
       and c.category_type_id = r.id;
  end loop;
end $$;
