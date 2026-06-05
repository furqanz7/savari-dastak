-- Harden driver ride acceptance.
-- Client code also filters self-created rides, but the database must enforce it.

alter table if exists public.rides
  add column if not exists assigned_driver_id uuid;

create index if not exists rides_assigned_driver_id_idx
on public.rides (assigned_driver_id);

do $$
declare
  target_function record;
begin
  for target_function in
    select
      n.nspname as schema_name,
      p.proname as function_name,
      pg_get_function_identity_arguments(p.oid) as identity_arguments
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'accept_ride'
  loop
    execute format(
      'drop function if exists %I.%I(%s)',
      target_function.schema_name,
      target_function.function_name,
      target_function.identity_arguments
    );
  end loop;
end $$;

create function public.accept_ride(
  p_ride_id uuid,
  p_driver_id uuid,
  p_boarding_code text
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_updated_count integer := 0;
begin
  if (select auth.uid()) is null or (select auth.uid()) <> p_driver_id then
    return false;
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = p_driver_id
      and lower(coalesce(p.role, '')) = 'driver'
  ) then
    return false;
  end if;

  update public.rides
  set
    driver_id = p_driver_id,
    assigned_driver_id = p_driver_id,
    status = 'assigned',
    boarding_code = p_boarding_code,
    boarding_code_ttl = coalesce(boarding_code_ttl, 300)
  where id = p_ride_id
    and status = 'requested'
    and passenger_id <> p_driver_id
    and driver_id is null
    and assigned_driver_id is null;

  get diagnostics v_updated_count = row_count;
  return v_updated_count = 1;
end;
$$;

revoke execute on function public.accept_ride(uuid, uuid, text) from anon;
grant execute on function public.accept_ride(uuid, uuid, text) to authenticated;

do $$
declare
  target_function record;
begin
  for target_function in
    select
      n.nspname as schema_name,
      p.proname as function_name,
      pg_get_function_identity_arguments(p.oid) as identity_arguments
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'accept_ride_request'
  loop
    execute format(
      'revoke execute on function %I.%I(%s) from anon, authenticated',
      target_function.schema_name,
      target_function.function_name,
      target_function.identity_arguments
    );
  end loop;
end $$;
