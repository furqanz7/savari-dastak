import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
const mode=process.argv[2];
if(!['verify','apply'].includes(mode)) throw new Error('Use verify (rollback) or apply (commit).');
if(readFileSync('supabase/.temp/project-ref','utf8').trim()!=='zmtsolkfxlrxepshnjdf') throw new Error('Wrong linked project.');
const version='20261008130951';
const sql=readFileSync(`supabase/migrations/${version}_customer_active_order_discovery.sql`,'utf8');
const quote=value=>"'"+value.replaceAll("'","''")+"'";
const assertions=`do $check$ begin
 assert not has_function_privilege('anon','public.dastak_v1_customer_active_orders()','execute');
 assert has_function_privilege('authenticated','public.dastak_v1_customer_active_orders()','execute');
 assert to_regclass('dastak_v1.orders_customer_active_discovery_idx') is not null;
 assert to_regclass('private.merchant_orders_customer_active_discovery_idx') is not null;
 begin perform public.dastak_v1_customer_active_orders(); raise exception 'unauthenticated discovery accepted'; exception when insufficient_privilege then null; end;
end;$check$;`;
const history=mode==='apply'?`insert into supabase_migrations.schema_migrations(version,name,statements) values(${quote(version)},'customer_active_order_discovery',array[${quote(sql)}]);`:'';
const query=`begin; set local lock_timeout='5s'; set local statement_timeout='90s';
 select pg_advisory_xact_lock(20261008,130951);
 do $guard$ begin
 if exists(select 1 from supabase_migrations.schema_migrations where version=${quote(version)}) then raise exception 'Migration already recorded'; end if;
 if to_regprocedure('public.dastak_v1_customer_active_orders()') is not null then raise exception 'Unrecorded discovery RPC exists'; end if;
 end;$guard$;
 ${sql} ${assertions} ${history} ${mode==='apply'?'commit':'rollback'};
 select ${quote(mode==='apply'?'Active discovery migration committed and recorded':'Native active discovery preflight passed and rolled back')} as release_result;`;
const result=spawnSync('supabase',['db','query','--linked',query],{encoding:'utf8',maxBuffer:2*1024*1024});
process.stdout.write(result.stdout??'');process.stderr.write(result.stderr??'');
if(result.error)throw result.error;process.exitCode=result.status??1;
