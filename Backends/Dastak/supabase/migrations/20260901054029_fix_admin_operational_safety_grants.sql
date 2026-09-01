-- The public Admin safety wrappers are SECURITY INVOKER functions. Their
-- internal API targets therefore need the same narrow execute bridge used by
-- the other authenticated Admin projections. Authorization remains enforced
-- inside each target through the actor and named-permission assertions.

revoke all on function
  dastak_v1_api.admin_operational_safety(uuid),
  dastak_v1_api.manage_rider_escalation(uuid,uuid,text,text,bigint,text),
  dastak_v1_api.set_operational_pause(uuid,text,uuid,boolean,text,bigint,text)
from public, anon;

grant execute on function
  dastak_v1_api.admin_operational_safety(uuid),
  dastak_v1_api.manage_rider_escalation(uuid,uuid,text,text,bigint,text),
  dastak_v1_api.set_operational_pause(uuid,text,uuid,boolean,text,bigint,text)
to authenticated, service_role;

comment on function dastak_v1_api.admin_operational_safety(uuid) is
  'Permission-bound Admin operational-safety projection reached through its authenticated public wrapper.';
comment on function dastak_v1_api.manage_rider_escalation(uuid,uuid,text,text,bigint,text) is
  'Permission-bound, version-checked and idempotent Admin rider-escalation command.';
comment on function dastak_v1_api.set_operational_pause(uuid,text,uuid,boolean,text,bigint,text) is
  'Permission-bound, version-checked and idempotent Admin operational-pause command.';
