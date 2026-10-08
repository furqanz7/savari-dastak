import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
const mode=process.argv[2];
if(!['verify','apply'].includes(mode)) throw new Error('Use verify (rollback) or apply (commit).');
if(readFileSync('supabase/.temp/project-ref','utf8').trim()!=='zmtsolkfxlrxepshnjdf') throw new Error('Wrong linked project.');
const version='20261008174027';
const name='repair_customer_active_order_discovery_permissions';
const sql=readFileSync(`supabase/migrations/${version}_${name}.sql`,'utf8');
const quote=value=>"'"+value.replaceAll("'","''")+"'";
// Exercise the RPC using the real customer role without disclosing any account
// IDs or orders. JWT context is transaction-local and no customer data is written.
const customerContext=`do $context$ declare actor uuid; begin
 select a.id into actor from public.accounts a join private.account_memberships m on m.account_id=a.id
 where m.role='customer' and (m.suspended_until is null or m.suspended_until<=now()) limit 1;
 if actor is null then raise exception 'No active customer available for role preflight'; end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
end;$context$;`;
const assertions=`set local role authenticated;
do $check$ declare result jsonb; begin
 assert not has_schema_privilege(current_user,'private','usage'),'Private schema must remain inaccessible';
 result:=public.dastak_v1_customer_active_orders();
 assert jsonb_typeof(result->'orders')='array';
 assert (result->>'totalCount')::integer>=jsonb_array_length(result->'orders');
 assert jsonb_array_length(result->'orders')<=20;
 begin perform dastak_v1_api.customer_active_order_discovery('00000000-0000-4000-8000-000000000000'); raise exception 'Actor override accepted'; exception when insufficient_privilege then null; end;
 assert not has_function_privilege('anon','public.dastak_v1_customer_active_orders()','execute');
 assert not has_function_privilege('service_role','public.dastak_v1_customer_active_orders()','execute');
end;$check$;
reset role;
set local role anon;
do $anon$ begin
 begin perform public.dastak_v1_customer_active_orders(); raise exception 'Anonymous discovery accepted'; exception when insufficient_privilege then null; end;
end;$anon$;
reset role;`;
const history=mode==='apply'?`insert into supabase_migrations.schema_migrations(version,name,statements) values(${quote(version)},${quote(name)},array[${quote(sql)}]);`:'';
const query=`begin; set local lock_timeout='5s'; set local statement_timeout='90s';
 select pg_advisory_xact_lock(20261008,174027);
 do $guard$ begin
 if exists(select 1 from supabase_migrations.schema_migrations where version=${quote(version)}) then raise exception 'Migration already recorded'; end if;
 if to_regprocedure('private.customer_active_order_discovery(uuid)') is null then raise exception 'Original discovery helper missing'; end if;
 end;$guard$;
 ${customerContext}
 set local role authenticated;
 do $before$ begin
 begin perform public.dastak_v1_customer_active_orders(); raise exception 'Expected private schema permission failure'; exception when insufficient_privilege then assert sqlerrm='permission denied for schema private',sqlerrm; end;
 end;$before$;
 reset role;
 ${sql} ${assertions} ${history} ${mode==='apply'?'commit':'rollback'};
 select ${quote(mode==='apply'?'Customer discovery permission repair committed and recorded':'Customer-role failure reproduced; repair passed and rolled back')} as release_result;`;
const result=spawnSync('supabase',['db','query','--linked',query],{encoding:'utf8',maxBuffer:2*1024*1024});
process.stdout.write(result.stdout??'');process.stderr.write(result.stderr??'');
if(result.error)throw result.error;process.exitCode=result.status??1;
