create or replace function public.list_merchant_applications(
  p_owner_id uuid
)
returns table (
  application_id uuid,
  account_id uuid,
  business_name text,
  business_address text,
  evidence_object_path text,
  status text
)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_owner_id
    and membership.role = 'owner'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  for share;

  if not found then
    return;
  end if;

  return query
  select
    application.id,
    application.account_id,
    application.business_name,
    application.business_address,
    application.evidence_object_path,
    application.status
  from private.merchant_applications as application
  where application.status = 'pending'
  order by application.submitted_at, application.id;
end;
$$;
