begin;

insert into private.account_memberships (account_id, role, approved_at)
values (:'owner_id'::uuid, 'owner', now())
on conflict (account_id, role) do update set approved_at = excluded.approved_at;

insert into audit.events (actor_id, action, entity_type, entity_id, reason, after_state)
values (
  :'owner_id'::uuid,
  'bootstrap_owner_granted',
  'account_membership',
  :'owner_id'::uuid,
  'initial product owner provisioned by database administrator',
  jsonb_build_object('role', 'owner')
);

commit;
