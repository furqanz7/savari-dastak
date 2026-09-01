begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_admin_catalogue_page(text,uuid,uuid,uuid,text,text,integer,text,uuid)',
    'EXECUTE'
  ),
  true,
  'authenticated Admin sessions retain access to the permission-bound catalogue wrapper'
);
select is(
  has_function_privilege(
    'anon',
    'public.dastak_v1_admin_catalogue_page(text,uuid,uuid,uuid,text,text,integer,text,uuid)',
    'EXECUTE'
  ),
  false,
  'anonymous sessions cannot execute the Admin catalogue wrapper'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.skus', 'SELECT'),
  false,
  'Admin clients cannot bypass the safe catalogue projection to read raw SKUs'
);
select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.admin_catalogue_page(uuid,text,uuid,uuid,uuid,text,text,integer,text,uuid)'::regprocedure
  ),
  'categoryTypeName[\s\S]*categoryName[\s\S]*subcategoryName',
  'the installed page returns the complete human-readable hierarchy'
);
select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.admin_catalogue_page(uuid,text,uuid,uuid,uuid,text,text,integer,text,uuid)'::regprocedure
  ),
  'description[\s\S]*imageKey[\s\S]*manufacturerName[\s\S]*dietType',
  'the installed page returns customer presentation and product detail fields'
);
select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.catalogue_taxonomy_snapshot(uuid)'::regprocedure
  ),
  'updatedAt',
  'the installed taxonomy snapshot carries refresh-safe entity timestamps'
);

select * from finish();
rollback;
