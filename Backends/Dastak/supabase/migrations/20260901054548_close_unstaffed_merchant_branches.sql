-- An organization without an active Merchant operator must not continue to
-- advertise an open branch. Persona deletion and account retirement suspend
-- Merchant memberships; closing the branch here makes that identity change
-- fail closed for matching and system-health monitoring. Recovery deliberately
-- does not reopen a branch: an active Merchant must opt in again.

create function dastak_v1.close_unstaffed_merchant_branches_after_membership_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid;
begin
  if tg_op = 'UPDATE' then
    if old.status <> 'ACTIVE' or new.status = 'ACTIVE' then
      return new;
    end if;
    v_organization_id := new.organization_id;
  else
    if old.status <> 'ACTIVE' then
      return old;
    end if;
    v_organization_id := old.organization_id;
  end if;

  if not exists (
    select 1
    from dastak_v1.merchant_users merchant_user
    where merchant_user.organization_id = v_organization_id
      and merchant_user.status = 'ACTIVE'
  ) then
    update dastak_v1.branch_operational_states operating
    set is_open = false,
        accepting_orders = false,
        version = operating.version + 1
    from dastak_v1.merchant_branches branch
    where branch.id = operating.branch_id
      and branch.organization_id = v_organization_id
      and (operating.is_open or operating.accepting_orders);
  end if;

  if tg_op = 'UPDATE' then
    return new;
  end if;
  return old;
end;
$$;

revoke all on function
  dastak_v1.close_unstaffed_merchant_branches_after_membership_change()
from public, anon, authenticated, service_role;

create trigger merchant_users_close_unstaffed_branches_on_status
after update of status on dastak_v1.merchant_users
for each row
execute function dastak_v1.close_unstaffed_merchant_branches_after_membership_change();

create trigger merchant_users_close_unstaffed_branches_on_delete
after delete on dastak_v1.merchant_users
for each row
execute function dastak_v1.close_unstaffed_merchant_branches_after_membership_change();

-- Repair historical branches left open after the one-time identity retirement.
-- The update is intentionally limited to organizations with no active Merchant.
update dastak_v1.branch_operational_states operating
set is_open = false,
    accepting_orders = false,
    version = operating.version + 1
from dastak_v1.merchant_branches branch
where branch.id = operating.branch_id
  and (operating.is_open or operating.accepting_orders)
  and not exists (
    select 1
    from dastak_v1.merchant_users merchant_user
    where merchant_user.organization_id = branch.organization_id
      and merchant_user.status = 'ACTIVE'
  );

comment on function
  dastak_v1.close_unstaffed_merchant_branches_after_membership_change() is
  'Fail-closes every branch when its organization loses its final active Merchant operator.';
