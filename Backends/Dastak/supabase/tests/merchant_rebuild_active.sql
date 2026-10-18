-- Runs in the original Wave-1 fixture after acceptance and before cancellation.
reset role;
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000003',true);
select is(jsonb_array_length(dastak_v1_api.list_merchant_fulfilments(
 '97000000-0000-4000-8000-000000000003',1)->'fulfilments'),1,
 'real command-created active fulfilment is retained by the new list');
select is(jsonb_array_length(public.dastak_v1_merchant_fulfilment_history(
 '97000000-0000-4000-8000-000000000021',null,null,1)->'fulfilments'),0,
 'active fulfilment does not appear in historical-only page');
set local role authenticated;
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000001',true);
