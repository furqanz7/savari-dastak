-- Consolidate public.rides UPDATE policies to avoid multiple permissive
-- policies for authenticated users while preserving participant updates
-- and driver ride acceptance.

drop policy if exists "rides_update_participant" on public.rides;
drop policy if exists "rides_driver_accept_requested" on public.rides;
drop policy if exists "rides_update_authenticated" on public.rides;

create policy "rides_update_authenticated"
on public.rides
for update
to authenticated
using (
  -- Existing ride participants can update their own ride.
  passenger_id = (select auth.uid())
  or driver_id = (select auth.uid())
  or assigned_driver_id = (select auth.uid())
  or (
    -- A driver can atomically claim an unassigned requested ride.
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
)
with check (
  -- Existing ride participants remain attached to the updated row.
  passenger_id = (select auth.uid())
  or driver_id = (select auth.uid())
  or assigned_driver_id = (select auth.uid())
  or (
    -- Resulting row after acceptance must be assigned to this driver.
    status = 'assigned'
    and driver_id = (select auth.uid())
    and assigned_driver_id = (select auth.uid())
    and passenger_id <> (select auth.uid())
  )
);
