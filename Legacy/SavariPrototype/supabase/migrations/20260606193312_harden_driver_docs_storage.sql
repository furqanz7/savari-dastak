-- Keep the Storage contract aligned with the iOS onboarding uploader.
-- The app writes all driver documents to:
--   driver_docs/<auth.uid()>/<filename>

insert into storage.buckets (id, name, public)
values ('driver_docs', 'driver_docs', false)
on conflict (id) do update
set
  name = excluded.name,
  public = false;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'storage'
      and table_name = 'buckets'
      and column_name = 'file_size_limit'
  ) then
    update storage.buckets
    set file_size_limit = 10485760
    where id = 'driver_docs';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'storage'
      and table_name = 'buckets'
      and column_name = 'allowed_mime_types'
  ) then
    update storage.buckets
    set allowed_mime_types = array['image/jpeg']
    where id = 'driver_docs';
  end if;
end $$;

drop policy if exists "savari_storage_select_own_driver_docs" on storage.objects;
drop policy if exists "savari_storage_insert_own_driver_docs" on storage.objects;
drop policy if exists "savari_storage_update_own_driver_docs" on storage.objects;
drop policy if exists "savari_storage_delete_own_driver_docs" on storage.objects;

create policy "savari_storage_select_own_driver_docs"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'driver_docs'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "savari_storage_insert_own_driver_docs"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'driver_docs'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "savari_storage_update_own_driver_docs"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'driver_docs'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'driver_docs'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
