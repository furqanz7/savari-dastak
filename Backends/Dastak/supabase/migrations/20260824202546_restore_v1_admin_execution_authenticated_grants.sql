-- The public Admin wrappers are SECURITY INVOKER functions. Their authenticated
-- caller therefore needs EXECUTE on the permission-checked internal functions
-- that the wrappers delegate to. The projection-contract migration accidentally
-- removed these two grants, causing PostgreSQL to reject the call before V1 RBAC
-- could evaluate the actor's explicit platform permission bundle.
--
-- These grants do not bypass authorization: both internal functions are
-- SECURITY DEFINER implementations that validate auth.uid() and require
-- platform.orders.trace before reading or auditing any order data.

grant execute on function dastak_v1_api.admin_execution_orders(uuid, integer)
  to authenticated;
grant execute on function dastak_v1_api.admin_execution_trace(uuid, uuid)
  to authenticated;

comment on function dastak_v1_api.admin_execution_orders(uuid, integer) is
  'Permission-checked Admin V1 order projection; callable only for the authenticated public wrapper and service operations.';
comment on function dastak_v1_api.admin_execution_trace(uuid, uuid) is
  'Permission-checked Admin V1 order trace; callable only for the authenticated public wrapper and service operations.';
