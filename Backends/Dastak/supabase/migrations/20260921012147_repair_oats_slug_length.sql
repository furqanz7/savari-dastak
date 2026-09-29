-- Keep the exact SKU identity intact while bringing its public slug within
-- the 160-character API contract consumed by customer and admin clients.
update dastak_v1.skus
set slug = left(slug, 160),
    updated_at = now(),
    version = version + 1
where id = '6b137d0d-cbc0-489a-afea-58682ca3d813'::uuid
  and char_length(slug) > 160;
