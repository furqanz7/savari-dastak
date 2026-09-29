-- Retire the misleading High Protein Atta bucket created by the earlier
-- curated-rail migration. Only the four previously audited, existing SKUs
-- may move; their IDs and all order/merchant references remain unchanged.
do $$
declare
  v_high_protein uuid;
  v_multigrain uuid;
begin
  select sc.id into v_high_protein
  from dastak_v1.subcategories sc
  join dastak_v1.categories c on c.id = sc.category_id
  join dastak_v1.category_types ct on ct.id = c.category_type_id
  where ct.slug = 'staples-pantry' and c.slug = 'atta-flours'
    and sc.slug = 'high-protein-atta';

  if v_high_protein is null then
    return;
  end if;

  if exists (
    select 1 from dastak_v1.skus s
    where s.subcategory_id = v_high_protein
      and s.id not in (
        '393af427-fc89-44b2-8b13-95023abb7ee3'::uuid,
        '51524c16-27d2-426e-99f9-9d871f659022'::uuid,
        '8cfa8c9f-5a52-4874-b9c6-776bfdef04dc'::uuid,
        'f2625c32-2085-40b5-ac6d-0d4181641848'::uuid
      )
  ) then
    raise exception 'High Protein Atta contains an unaudited SKU; review it before retiring this bucket';
  end if;

  select sc.id into v_multigrain
  from dastak_v1.subcategories sc
  join dastak_v1.categories c on c.id = sc.category_id
  join dastak_v1.category_types ct on ct.id = c.category_type_id
  where ct.slug = 'staples-pantry' and c.slug = 'atta-flours'
    and sc.slug = 'multigrain-atta';

  if v_multigrain is null then
    raise exception 'Multigrain Atta destination is missing';
  end if;

  update dastak_v1.skus
  set subcategory_id = v_multigrain,
      updated_at = now(),
      version = version + 1
  where subcategory_id = v_high_protein;

  if exists (select 1 from dastak_v1.skus where subcategory_id = v_high_protein) then
    raise exception 'High Protein Atta still has SKUs after reclassification';
  end if;

  update dastak_v1.subcategories
  set status = 'INACTIVE', updated_at = now(), version = version + 1
  where id = v_high_protein and status <> 'INACTIVE';
end;
$$;
