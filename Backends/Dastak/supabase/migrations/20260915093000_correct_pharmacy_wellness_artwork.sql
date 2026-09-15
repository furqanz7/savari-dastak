-- Correct Pharmacy to the permanent Pharmacy & Wellness artwork from the
-- approved customer reference. Health & Hygiene remains on its own artwork.
do $$
declare
  v_type_id uuid;
begin
  select id into v_type_id
    from dastak_v1.category_types
   where slug = 'pharmacy';

  if v_type_id is null then
    return;
  end if;

  update dastak_v1.category_types
     set image_key = 'canonical/taxonomy/pharmacy-wellness-reference.png',
         media_version = media_version + 1,
         updated_at = now()
   where id = v_type_id;

  update dastak_v1.categories
     set image_key = 'canonical/taxonomy/pharmacy-wellness-reference.png',
         media_version = media_version + 1,
         updated_at = now()
   where category_type_id = v_type_id;

  update dastak_v1.subcategories s
     set image_key = 'canonical/taxonomy/pharmacy-wellness-reference.png',
         media_version = s.media_version + 1,
         updated_at = now()
    from dastak_v1.categories c
   where s.category_id = c.id
     and c.category_type_id = v_type_id;
end $$;
