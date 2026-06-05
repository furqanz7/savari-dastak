-- Harden the iOS/Supabase contract for the Savari app.
-- This migration assumes the mobile app uses Supabase Auth user IDs as
-- profile/ride owner IDs.

alter table if exists public.rides
  add column if not exists boarded_at timestamptz,
  add column if not exists started_at timestamptz,
  add column if not exists ended_at timestamptz,
  add column if not exists fare_unlocked boolean not null default false,
  add column if not exists boarding_code_ttl integer;

alter table if exists public.ride_history
  add column if not exists boarded_at timestamptz,
  add column if not exists started_at timestamptz,
  add column if not exists ended_at timestamptz,
  add column if not exists fare_unlocked boolean not null default false,
  add column if not exists boarding_code_ttl integer;

create index if not exists rides_passenger_id_idx on public.rides (passenger_id);
create index if not exists rides_driver_id_idx on public.rides (driver_id);
create index if not exists rides_status_idx on public.rides (status);
create index if not exists driver_locations_driver_id_idx on public.driver_locations (driver_id);
create index if not exists driver_onboarding_profile_id_idx on public.driver_onboarding (profile_id);
create index if not exists payment_methods_profile_id_idx on public.payment_methods (profile_id);

alter table if exists public.profiles enable row level security;
alter table if exists public.rides enable row level security;
alter table if exists public.ride_history enable row level security;
alter table if exists public.driver_locations enable row level security;
alter table if exists public.driver_onboarding enable row level security;
alter table if exists public.payment_methods enable row level security;
alter table if exists public.users enable row level security;
alter table if exists public.user_onboarding enable row level security;
alter table if exists public.driver_wallet_transactions enable row level security;

do $$
declare
  target_table text;
  policy record;
begin
  foreach target_table in array array[
    'profiles',
    'rides',
    'ride_history',
    'driver_locations',
    'driver_onboarding',
    'payment_methods',
    'users',
    'user_onboarding',
    'driver_wallet_transactions'
  ]
  loop
    if to_regclass('public.' || target_table) is not null then
      for policy in
        select policyname
        from pg_policies
        where schemaname = 'public'
          and tablename = target_table
      loop
        execute format('drop policy if exists %I on public.%I', policy.policyname, target_table);
      end loop;
    end if;
  end loop;
end $$;

create policy "profiles_select_own"
on public.profiles
for select
to authenticated
using (id = (select auth.uid()));

create policy "profiles_insert_own"
on public.profiles
for insert
to authenticated
with check (id = (select auth.uid()));

create policy "profiles_update_own"
on public.profiles
for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy "rides_select_participant_or_driver_pool"
on public.rides
for select
to authenticated
using (
  passenger_id = (select auth.uid())
  or driver_id = (select auth.uid())
  or (
    status = 'requested'
    and exists (
      select 1
      from public.profiles p
      where p.id = (select auth.uid())
        and lower(coalesce(p.role, '')) = 'driver'
    )
  )
);

create policy "rides_insert_own_passenger"
on public.rides
for insert
to authenticated
with check (passenger_id = (select auth.uid()));

create policy "rides_update_participant"
on public.rides
for update
to authenticated
using (passenger_id = (select auth.uid()) or driver_id = (select auth.uid()))
with check (passenger_id = (select auth.uid()) or driver_id = (select auth.uid()));

create policy "ride_history_select_participant"
on public.ride_history
for select
to authenticated
using (passenger_id = (select auth.uid()) or driver_id = (select auth.uid()));

create policy "driver_locations_select_authenticated"
on public.driver_locations
for select
to authenticated
using (true);

create policy "driver_locations_insert_own_driver"
on public.driver_locations
for insert
to authenticated
with check (
  driver_id = (select auth.uid())
  and exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and lower(coalesce(p.role, '')) = 'driver'
  )
);

create policy "driver_locations_update_own_driver"
on public.driver_locations
for update
to authenticated
using (driver_id = (select auth.uid()))
with check (
  driver_id = (select auth.uid())
  and exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and lower(coalesce(p.role, '')) = 'driver'
  )
);

create policy "driver_locations_delete_own_driver"
on public.driver_locations
for delete
to authenticated
using (driver_id = (select auth.uid()));

create policy "driver_onboarding_select_own"
on public.driver_onboarding
for select
to authenticated
using (profile_id = (select auth.uid()));

create policy "driver_onboarding_insert_own"
on public.driver_onboarding
for insert
to authenticated
with check (profile_id = (select auth.uid()));

create policy "driver_onboarding_update_own"
on public.driver_onboarding
for update
to authenticated
using (profile_id = (select auth.uid()))
with check (profile_id = (select auth.uid()));

create policy "payment_methods_select_own"
on public.payment_methods
for select
to authenticated
using (profile_id = (select auth.uid()));

create policy "payment_methods_insert_own"
on public.payment_methods
for insert
to authenticated
with check (profile_id = (select auth.uid()));

create policy "payment_methods_update_own"
on public.payment_methods
for update
to authenticated
using (profile_id = (select auth.uid()))
with check (profile_id = (select auth.uid()));

create policy "payment_methods_delete_own"
on public.payment_methods
for delete
to authenticated
using (profile_id = (select auth.uid()));

create policy "users_select_own"
on public.users
for select
to authenticated
using (profile_id = (select auth.uid()));

create policy "users_insert_own"
on public.users
for insert
to authenticated
with check (profile_id = (select auth.uid()));

create policy "users_update_own"
on public.users
for update
to authenticated
using (profile_id = (select auth.uid()))
with check (profile_id = (select auth.uid()));

create policy "user_onboarding_select_own"
on public.user_onboarding
for select
to authenticated
using (profile_id = (select auth.uid()));

create policy "user_onboarding_insert_own"
on public.user_onboarding
for insert
to authenticated
with check (profile_id = (select auth.uid()));

create policy "user_onboarding_update_own"
on public.user_onboarding
for update
to authenticated
using (profile_id = (select auth.uid()))
with check (profile_id = (select auth.uid()));

create policy "driver_wallet_transactions_select_ride_participant"
on public.driver_wallet_transactions
for select
to authenticated
using (
  exists (
    select 1
    from public.rides r
    where r.id = driver_wallet_transactions.ride_id
      and (r.passenger_id = (select auth.uid()) or r.driver_id = (select auth.uid()))
  )
);

do $$
declare
  policy record;
begin
  for policy in
    select policyname
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'savari_%'
  loop
    execute format('drop policy if exists %I on storage.objects', policy.policyname);
  end loop;
end $$;

create policy "savari_storage_select_own_driver_docs"
on storage.objects
for select
to authenticated
using (
  bucket_id in ('driver_docs', 'selfie', 'vehicle_docs')
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "savari_storage_insert_own_driver_docs"
on storage.objects
for insert
to authenticated
with check (
  bucket_id in ('driver_docs', 'selfie', 'vehicle_docs')
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "savari_storage_update_own_driver_docs"
on storage.objects
for update
to authenticated
using (
  bucket_id in ('driver_docs', 'selfie', 'vehicle_docs')
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id in ('driver_docs', 'selfie', 'vehicle_docs')
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "savari_storage_delete_own_driver_docs"
on storage.objects
for delete
to authenticated
using (
  bucket_id in ('driver_docs', 'selfie', 'vehicle_docs')
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
