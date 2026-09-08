begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  (select count(*) from private.order_handoff_code_keys where singleton),
  1::bigint,
  'one durable order handoff key is configured'
);

select is(
  (select pg_catalog.char_length(secret)
   from private.order_handoff_code_keys where singleton),
  64,
  'the order handoff key has 256 bits of encoded key material'
);

select matches(
  private.dastak_v1_handoff_code(
    '70000000-0000-4000-8000-000000000001'::uuid,
    'MERCHANT_TO_RIDER',
    1
  ),
  '^[0-9]{6}$',
  'V1 pickup verification produces a six-digit code'
);

select is(
  pg_catalog.octet_length(private.dastak_v1_handoff_digest('123456')),
  32,
  'V1 pickup verification produces a non-null SHA-256 digest'
);

select has_trigger(
  'private',
  'order_handoff_code_keys',
  'order_handoff_code_keys_no_delete',
  'the durable handoff key cannot be deleted accidentally'
);

select throws_ok(
  'delete from private.order_handoff_code_keys where singleton',
  'P0001',
  'ORDER_HANDOFF_KEY_DELETE_FORBIDDEN',
  'deleting the durable handoff key is rejected'
);

select * from finish();
rollback;
