-- The Edge earnings boundary invokes the public security-invoker wrapper with
-- the service role. That wrapper delegates to this unexposed security-definer
-- function, so the service role needs the matching narrow internal EXECUTE
-- privilege. Browser roles remain unable to call either boundary directly.
revoke execute on function dastak_v1_api.razorpayx_admin_snapshot(uuid, integer)
  from public, anon, authenticated;
grant execute on function dastak_v1_api.razorpayx_admin_snapshot(uuid, integer)
  to service_role;
