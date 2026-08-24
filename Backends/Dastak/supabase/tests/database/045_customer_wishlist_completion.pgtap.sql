begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(8);

select has_table(
  'dastak_v1',
  'customer_wishlist_items',
  'Wishlist storage exists in the unexposed V1 schema'
);
select col_is_pk(
  'dastak_v1',
  'customer_wishlist_items',
  array['account_id', 'item_kind', 'item_id'],
  'Wishlist desired state is unique per customer and item'
);
select table_privs_are(
  'dastak_v1',
  'customer_wishlist_items',
  'authenticated',
  array[]::text[],
  'Authenticated clients cannot access Wishlist storage directly'
);
select has_function(
  'public',
  'get_customer_wishlist',
  array['uuid'],
  'The authenticated Edge adapter has a snapshot contract'
);
select has_function(
  'public',
  'set_customer_wishlist_item',
  array['uuid', 'text', 'uuid', 'boolean'],
  'The authenticated Edge adapter has an idempotent desired-state contract'
);
select is(
  has_function_privilege('authenticated', 'public.get_customer_wishlist(uuid)', 'EXECUTE'),
  false,
  'Customers cannot forge another account through the RPC'
);
select is(
  has_function_privilege('service_role', 'public.get_customer_wishlist(uuid)', 'EXECUTE'),
  true,
  'Only the server-side adapter can execute the Wishlist snapshot RPC'
);
select ok(
  coalesce((
    select function_config.proconfig @> array['search_path=""']::text[]
    from pg_catalog.pg_proc function_config
    join pg_catalog.pg_namespace namespace
      on namespace.oid = function_config.pronamespace
    where namespace.nspname = 'private'
      and function_config.proname = 'set_customer_wishlist_item'
      and function_config.pronargs = 4
  ), false),
  'The privileged Wishlist mutation uses an empty search path'
);

select * from finish();
rollback;
