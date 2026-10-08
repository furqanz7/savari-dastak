-- Explicit reversible Admin removal is independent of open/closed and suspension.
-- Preserve merchant identity, menus, financial history and existing fulfilments.
alter table dastak_v1.merchant_branches add column customer_listing_visible boolean not null default true;

create function private.admin_set_restaurant_customer_visibility(
 p_actor_id uuid,p_branch_id uuid,p_visible boolean,p_expected_version bigint,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_branch dastak_v1.merchant_branches%rowtype; v_existing dastak_v1.idempotency_records%rowtype;
 v_hash bytea; v_response jsonb; v_command constant text:='setRestaurantCustomerVisibility';
begin
 perform dastak_v1_api.assert_merchant_governance_admin(p_actor_id);
 if p_actor_id is distinct from auth.uid() then raise exception using errcode='42501',message='authenticated Admin required'; end if;
 if p_branch_id is null or p_visible is null or p_expected_version is null or p_expected_version<1
  or length(btrim(coalesce(p_reason,''))) not between 3 and 500
  or length(btrim(coalesce(p_idempotency_key,''))) not between 1 and 200 then
  raise exception using errcode='22023',message='reviewed restaurant visibility command required';
 end if;
 v_hash:=dastak_v1_api.request_hash(jsonb_build_object('branchId',p_branch_id,'visible',p_visible,
  'expectedVersion',p_expected_version,'reason',btrim(p_reason)));
 perform pg_advisory_xact_lock(hashtextextended(p_actor_id::text||':'||v_command||':'||btrim(p_idempotency_key),0));
 select * into v_existing from dastak_v1.idempotency_records where actor_id=p_actor_id and command_name=v_command and idempotency_key=btrim(p_idempotency_key);
 if found then
  if v_existing.request_hash=v_hash then return v_existing.response_body; end if;
  raise exception using errcode='22023',message='idempotency key was already used with a different request';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('merchant-governance-branch:'||p_branch_id::text,0));
 select * into v_branch from dastak_v1.merchant_branches where id=p_branch_id for update;
 if not found then raise exception using errcode='P0002',message='restaurant branch not found'; end if;
 if not exists(select 1 from dastak_v1.merchant_organizations where id=v_branch.organization_id and merchant_type='RESTAURANT_CAFE' and status<>'PENDING_REVIEW')
  or v_branch.status='PENDING_REVIEW' then
  raise exception using errcode='55000',message='only onboarded Restaurant/Cafe branches support Customer removal';
 end if;
 if v_branch.version<>p_expected_version then raise exception using errcode='40001',message='stale merchant branch version'; end if;
 if v_branch.customer_listing_visible=p_visible then raise exception using errcode='55000',message='restaurant visibility is already in the requested state'; end if;
 update dastak_v1.merchant_branches set customer_listing_visible=p_visible,version=version+1,updated_at=now() where id=p_branch_id returning * into v_branch;
 insert into dastak_v1.audit_events(actor_id,action,resource_type,resource_id,metadata)
 values(p_actor_id,case when p_visible then 'RESTAURANT_CUSTOMER_LISTING_RESTORED' else 'RESTAURANT_CUSTOMER_LISTING_REMOVED' end,
  'merchant_branch',p_branch_id,jsonb_build_object('organizationId',v_branch.organization_id,'reason',btrim(p_reason),
   'fromVisible',not p_visible,'toVisible',p_visible,'fromVersion',p_expected_version,'version',v_branch.version));
 v_response:=jsonb_build_object('branchId',p_branch_id,'customerListingVisible',p_visible,'version',v_branch.version,'updatedAt',v_branch.updated_at);
 insert into dastak_v1.idempotency_records(actor_id,command_name,idempotency_key,request_hash,response_body,response_status,resource_id)
 values(p_actor_id,v_command,btrim(p_idempotency_key),v_hash,v_response,200,p_branch_id);
 return v_response;
end;$$;
create function public.dastak_v1_admin_set_restaurant_customer_visibility(
 p_branch_id uuid,p_visible boolean,p_expected_version bigint,p_reason text,p_idempotency_key text
) returns jsonb language sql volatile security invoker set search_path='' as $$
 select private.admin_set_restaurant_customer_visibility(auth.uid(),p_branch_id,p_visible,p_expected_version,p_reason,p_idempotency_key);
$$;

-- Keep the canonical current paging/availability implementations, with guarded
-- source edits so a future schema change cannot silently skip Customer removal.
do $$declare signature text; definition text; needle text; expected integer; begin
 foreach signature in array array[
  'dastak_v1_api.customer_area_availability(uuid,uuid,timestamptz)',
  'dastak_v1_api.customer_restaurants_area_page(uuid,uuid,timestamptz,text,integer,text,uuid,integer,uuid)',
  'dastak_v1_api.list_customer_restaurants_page(uuid,text,integer,text,uuid,uuid)',
  'private.customer_restaurant_accepting(uuid)'
 ] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  needle:=case when signature like 'private.%' then 'b.status=''ACTIVE''' else 'b.status<>''PENDING_REVIEW''' end;
  expected:=case when signature like '%customer_area_availability%' then 2 else 1 end;
  if (length(definition)-length(replace(definition,needle,'')))/length(needle)<>expected then raise exception 'visibility predicate drift in %',signature; end if;
  execute replace(definition,needle,needle||' and b.customer_listing_visible');
 end loop;
 signature:='dastak_v1_api.admin_merchant_governance_page(uuid,text,uuid,uuid,integer,timestamptz,uuid)';
 definition:=pg_get_functiondef(signature::regprocedure);
 needle:='''capacityLimit'', row.capacity_limit';
 if (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 then raise exception 'Admin visibility projection drift'; end if;
 execute replace(definition,needle,'''customerListingVisible'', (select b.customer_listing_visible from dastak_v1.merchant_branches b where b.id=row.branch_id), '||needle);
end;$$;

-- Direct/replayed API callers cannot submit or confirm NEW orders for a removed
-- store. Existing submitted orders remain recoverable; no custody is abandoned.
create function private.enforce_restaurant_customer_listing() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_branch_id uuid; v_policy smallint;
begin
 if tg_table_name='orders' then
  if new.status<>'PAID' or old.status='PAID' then return new; end if;
  v_branch_id:=new.restaurant_branch_id; v_policy:=new.availability_policy_version;
 else
  select restaurant_branch_id,availability_policy_version into v_branch_id,v_policy from dastak_v1.orders where id=new.order_id;
 end if;
 if v_policy=1 and v_branch_id is not null and not exists(select 1 from dastak_v1.merchant_branches where id=v_branch_id and customer_listing_visible) then
  raise exception using errcode='55000',message='This restaurant is no longer available. Your cart is saved.';
 end if;
 return new;
end;$$;
create trigger customer_restaurant_listing_context before insert on dastak_v1.order_context_snapshots
 for each row execute function private.enforce_restaurant_customer_listing();
create trigger customer_restaurant_listing_commit before update of status on dastak_v1.orders
 for each row execute function private.enforce_restaurant_customer_listing();
revoke all on function private.admin_set_restaurant_customer_visibility(uuid,uuid,boolean,bigint,text,text),
 private.enforce_restaurant_customer_listing(),public.dastak_v1_admin_set_restaurant_customer_visibility(uuid,boolean,bigint,text,text) from public,anon,service_role;
revoke all on function private.enforce_restaurant_customer_listing() from authenticated;
grant execute on function private.admin_set_restaurant_customer_visibility(uuid,uuid,boolean,bigint,text,text),
 public.dastak_v1_admin_set_restaurant_customer_visibility(uuid,boolean,bigint,text,text) to authenticated;
