-- Pickup and delivery codes depend on one durable server-side HMAC key. The
-- production singleton was missing, causing Ready to roll back when rider
-- matching attempted to create a verification handoff with a null digest.
insert into private.order_handoff_code_keys (singleton, secret)
values (
  true,
  pg_catalog.encode(extensions.gen_random_bytes(32), 'hex')
)
on conflict (singleton) do nothing;

create or replace function private.order_handoff_secret()
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_secret text;
begin
  select key.secret into v_secret
  from private.order_handoff_code_keys key
  where key.singleton;

  if v_secret is null then
    raise exception using
      errcode = 'P0001',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'The order handoff secret is missing.';
  end if;

  return v_secret;
end;
$$;

create or replace function private.reject_order_handoff_key_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception using
    errcode = 'P0001',
    message = 'ORDER_HANDOFF_KEY_DELETE_FORBIDDEN',
    detail = 'Rotate the handoff key through an audited operation; do not delete it.';
end;
$$;

drop trigger if exists order_handoff_code_keys_no_delete
  on private.order_handoff_code_keys;
create trigger order_handoff_code_keys_no_delete
before delete on private.order_handoff_code_keys
for each row execute function private.reject_order_handoff_key_delete();

revoke execute on function private.order_handoff_secret()
  from public, anon, authenticated;
grant execute on function private.order_handoff_secret() to service_role;
revoke all on function private.reject_order_handoff_key_delete()
  from public, anon, authenticated;

comment on function private.order_handoff_secret() is
  'Returns the durable handoff HMAC key and fails explicitly if configuration is missing.';
comment on function private.reject_order_handoff_key_delete() is
  'Prevents deletion of the singleton key that secures pickup and delivery verification codes.';
