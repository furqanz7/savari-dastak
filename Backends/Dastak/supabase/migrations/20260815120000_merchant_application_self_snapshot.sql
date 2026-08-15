create or replace function public.get_merchant_application_snapshot(
  p_account_id uuid
)
returns table (
  response_body jsonb,
  response_status integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_application private.merchant_applications%rowtype;
begin
  if not exists (
    select 1
    from public.accounts as account
    where account.id = p_account_id
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'profile_required',
        'message', 'Complete the account profile first.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  select application.*
  into v_application
  from private.merchant_applications as application
  where application.account_id = p_account_id;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'onboardingState', 'not_applied',
      'applicationId', null,
      'businessName', null,
      'businessAddress', null,
      'evidenceObjectPath', null,
      'reviewReason', null
    );
    response_status := 200;
    return next;
    return;
  end if;

  response_body := pg_catalog.jsonb_build_object(
    'onboardingState', v_application.status,
    'applicationId', v_application.id,
    'businessName', v_application.business_name,
    'businessAddress', v_application.business_address,
    'evidenceObjectPath', v_application.evidence_object_path,
    'reviewReason', v_application.review_reason
  );
  response_status := 200;
  return next;
end;
$$;

revoke execute on function public.get_merchant_application_snapshot(uuid)
  from public, anon, authenticated;
grant execute on function public.get_merchant_application_snapshot(uuid)
  to service_role;
