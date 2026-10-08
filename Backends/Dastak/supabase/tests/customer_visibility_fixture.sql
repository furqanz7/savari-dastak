-- Small isolated governance fixture; no live account or merchant changes.
alter table dastak_v1.merchant_branches add column version bigint not null default 1;
alter table dastak_v1.merchant_branches add column updated_at timestamptz not null default now();
alter table dastak_v1.orders add column restaurant_branch_id uuid;
create table dastak_v1.idempotency_records(actor_id uuid,command_name text,idempotency_key text,request_hash bytea,response_body jsonb,response_status integer,resource_id uuid);
create table dastak_v1.audit_events(actor_id uuid,action text,resource_type text,resource_id uuid,metadata jsonb);
create function dastak_v1_api.request_hash(value jsonb) returns bytea language sql immutable as $$select decode(md5(value::text),'hex')$$;
create function dastak_v1_api.assert_merchant_governance_admin(actor uuid) returns void language plpgsql as $$begin
 if actor is distinct from 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid then raise exception using errcode='42501',message='test admin required'; end if;
end;$$;
create function dastak_v1_api.admin_merchant_governance_page(actor uuid,query text,org uuid,branch uuid,lim integer,after_time timestamptz,after_id uuid)
 returns jsonb language plpgsql as $$declare row record; begin
 select md5('branch205')::uuid branch_id,12 capacity_limit into row;
 return jsonb_build_object('merchants',jsonb_build_array(jsonb_build_object('branch',jsonb_build_object('id',row.branch_id,'capacityLimit', row.capacity_limit))));
end;$$;
