-- Permanent artwork for hobby and utility taxonomy categories.
do $$
declare
  r record;
  key text;
begin
  for r in
    select id, slug
      from dastak_v1.category_types
     where slug in ('toys-games-kids', 'automotive-travel-utility', 'home-improvement-hardware')
  loop
    key := case r.slug
      when 'toys-games-kids' then 'canonical/taxonomy/toys-games-kids-v2.png'
      when 'automotive-travel-utility' then 'canonical/taxonomy/automotive-travel-utility-v2.png'
      when 'home-improvement-hardware' then 'canonical/taxonomy/home-improvement-hardware-v2.png'
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
