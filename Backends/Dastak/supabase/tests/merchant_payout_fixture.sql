create schema private;
create table private.delivery_partner_profiles(account_id uuid);
create table private.account_memberships(account_id uuid,role text,approved_at timestamptz,suspended_until timestamptz);
create type dastak_v1.settlement_subject_type as enum('MERCHANT_ORGANIZATION','RIDER');
create table dastak_v1.royalty_payout_destinations(id uuid primary key,subject_type dastak_v1.settlement_subject_type,subject_id uuid,status text,version bigint);
create table dastak_v1.royalty_withdrawals(id uuid primary key default gen_random_uuid(),subject_type dastak_v1.settlement_subject_type,
  subject_id uuid,idempotency_key text,amount_paise bigint,requested_by uuid,unique(subject_type,subject_id,idempotency_key));
insert into dastak_v1.royalty_payout_destinations values('95000000-0000-4000-8000-000000000091','MERCHANT_ORGANIZATION','95000000-0000-4000-8000-000000000001','ACTIVE',1);
insert into dastak_v1.permission_bundle_permissions values
 ('95000000-0000-4000-8000-000000000041','merchant.earnings.read'),('95000000-0000-4000-8000-000000000041','merchant.royalty.withdraw');
insert into dastak_v1.merchant_users values('95000000-0000-4000-8000-000000000023','95000000-0000-4000-8000-000000000033','95000000-0000-4000-8000-000000000001','ACTIVE');
insert into dastak_v1.permission_bundles values('95000000-0000-4000-8000-000000000042','MERCHANT',true);
insert into dastak_v1.permission_bundle_permissions values('95000000-0000-4000-8000-000000000042','merchant.earnings.read');
insert into dastak_v1.merchant_permission_grants values('95000000-0000-4000-8000-000000000023','95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000042',null,null);
grant usage on schema dastak_v1_api to service_role;
-- Delegates are deliberate spies, not the financial posting implementation.
-- This fixture verifies the NEW guard/locks/permission/receipt routing only.
create function dastak_v1_api.get_royalty_snapshot(actor uuid,kind text) returns table(response_body jsonb,response_status integer)
language sql stable as $$select jsonb_build_object('subjects',jsonb_build_array(jsonb_build_object('subjectId','95000000-0000-4000-8000-000000000001'))),200$$;
create function dastak_v1_api.request_royalty_withdrawal(actor uuid,kind text,subject uuid,amount bigint,key text) returns jsonb
language plpgsql as $$declare existing dastak_v1.royalty_withdrawals; begin
  select * into existing from dastak_v1.royalty_withdrawals where subject_type=kind::dastak_v1.settlement_subject_type and subject_id=subject and idempotency_key=key;
  if found then
    if existing.amount_paise<>amount or existing.requested_by<>actor then raise invalid_parameter_value; end if;
    return jsonb_build_object('withdrawalId',existing.id,'replayed',true);
  end if;
  insert into dastak_v1.royalty_withdrawals(subject_type,subject_id,idempotency_key,amount_paise,requested_by)
    values(kind::dastak_v1.settlement_subject_type,subject,key,amount,actor) returning * into existing;
  return jsonb_build_object('withdrawalId',existing.id,'replayed',false);
end$$;
