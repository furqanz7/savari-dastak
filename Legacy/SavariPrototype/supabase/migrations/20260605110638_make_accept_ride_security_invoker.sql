-- Remove SECURITY DEFINER advisor warnings for accept_ride while preserving
-- atomic driver acceptance through RLS.

drop policy if exists "rides_driver_accept_requested" on public.rides;

create policy "rides_driver_accept_requested"
on public.rides
for update
to authenticated
using (
  status = 'requested'
  and driver_id is null
  and assigned_driver_id is null
  and passenger_id <> (select auth.uid())
  and exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and lower(coalesce(p.role, '')) = 'driver'
  )
)
with check (
  status = 'assigned'
  and driver_id = (select auth.uid())
  and assigned_driver_id = (select auth.uid())
  and passenger_id <> (select auth.uid())
);

alter function public.accept_ride(uuid, uuid, text) security invoker;
alter function public.accept_ride(uuid, uuid, text) set search_path = public, pg_temp;

revoke all on function public.accept_ride(uuid, uuid, text) from public;
revoke all on function public.accept_ride(uuid, uuid, text) from anon;
revoke all on function public.accept_ride(uuid, uuid, text) from authenticated;
grant execute on function public.accept_ride(uuid, uuid, text) to authenticated;
