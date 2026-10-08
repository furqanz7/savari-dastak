import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
const mode=process.argv[2];
if(!['verify','apply'].includes(mode)) throw new Error('Use verify (rollback) or apply (commit).');
if(readFileSync('supabase/.temp/project-ref','utf8').trim()!=='zmtsolkfxlrxepshnjdf') throw new Error('Wrong linked project.');
const version='20261008114655';
const sql=readFileSync(`supabase/migrations/${version}_admin_customer_restaurant_visibility.sql`,'utf8');
const quote=value=>"'"+value.replaceAll("'","''")+"'";
const assertions=`do $check$ begin
 assert not exists(select 1 from dastak_v1.merchant_branches where not customer_listing_visible),'migration must not remove any real merchant';
 assert not has_function_privilege('anon','public.dastak_v1_admin_set_restaurant_customer_visibility(uuid,boolean,bigint,text,text)','execute');
 assert has_function_privilege('authenticated','public.dastak_v1_admin_set_restaurant_customer_visibility(uuid,boolean,bigint,text,text)','execute');
 assert (select count(*)=2 from pg_trigger where tgname in ('customer_restaurant_listing_context','customer_restaurant_listing_commit') and not tgisinternal);
 begin
  perform public.dastak_v1_admin_set_restaurant_customer_visibility('00000000-0000-4000-8000-000000000000',false,1,'Release permission check','release-no-auth');
  raise exception 'unauthenticated removal accepted';
 exception when insufficient_privilege then null; end;
end;$check$;`;
const history=mode==='apply'?`insert into supabase_migrations.schema_migrations(version,name,statements) values(${quote(version)},'admin_customer_restaurant_visibility',array[${quote(sql)}]);`:'';
const query=`begin; set local lock_timeout='5s'; set local statement_timeout='90s';
 select pg_advisory_xact_lock(20261008,114655);
 do $guard$ begin
 if exists(select 1 from supabase_migrations.schema_migrations where version=${quote(version)}) then raise exception 'Migration already recorded'; end if;
 if exists(select 1 from information_schema.columns where table_schema='dastak_v1' and table_name='merchant_branches' and column_name='customer_listing_visible') then raise exception 'Unrecorded visibility column exists'; end if;
 end;$guard$;
 ${sql} ${assertions} ${history} ${mode==='apply'?'commit':'rollback'};
 select ${quote(mode==='apply'?'Admin visibility migration committed and recorded':'Admin visibility native preflight passed and rolled back')} as release_result;`;
const result=spawnSync('supabase',['db','query','--linked',query],{encoding:'utf8',maxBuffer:2*1024*1024});
process.stdout.write(result.stdout??''); process.stderr.write(result.stderr??'');
if(result.error) throw result.error; process.exitCode=result.status??1;
