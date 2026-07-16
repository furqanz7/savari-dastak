create or replace function public.resolve_app_access(
  p_account_id uuid,
  p_application text
)
returns table (route text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_required_role private.membership_role;
  v_membership private.account_memberships%rowtype;
begin
  v_required_role := case p_application
    when 'customer' then 'customer'::private.membership_role
    when 'merchant' then 'merchant'::private.membership_role
    when 'admin' then 'owner'::private.membership_role
    else null
  end;

  if v_required_role is null then
    route := 'access_denied';
    return next;
    return;
  end if;

  if not exists (
    select 1
    from public.accounts
    where id = p_account_id
  ) then
    route := 'needs_profile';
    return next;
    return;
  end if;

  select *
  into v_membership
  from private.account_memberships
  where account_id = p_account_id
    and role = v_required_role;

  if not found then
    route := 'access_denied';
    return next;
    return;
  end if;

  if v_membership.suspended_until is not null
    and v_membership.suspended_until > pg_catalog.now()
  then
    route := 'suspended';
    return next;
    return;
  end if;

  if v_required_role in (
    'merchant'::private.membership_role,
    'owner'::private.membership_role
  ) and v_membership.approved_at is null then
    route := 'pending_approval';
    return next;
    return;
  end if;

  route := 'active';
  return next;
end;
$$;

revoke execute on function public.resolve_app_access(uuid, text) from public, anon, authenticated;
grant execute on function public.resolve_app_access(uuid, text) to service_role;
