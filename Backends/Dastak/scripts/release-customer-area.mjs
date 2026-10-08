import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

// Release only this migration, never other pending database migrations.
const mode = process.argv[2];
if (!['verify', 'apply'].includes(mode)) throw new Error('Use verify (rollback) or apply (commit).');
if (readFileSync('supabase/.temp/project-ref', 'utf8').trim() !== 'zmtsolkfxlrxepshnjdf') throw new Error('Wrong linked project.');
const version = '20261008095639';
const sql = readFileSync(`supabase/migrations/${version}_customer_area_availability.sql`, 'utf8');
const quote = value => "'" + value.replaceAll("'", "''") + "'";
const assertions = `
do $check$
declare origin extensions.geometry; result boolean;
begin
 assert (select column_default='1' from information_schema.columns where table_schema='dastak_v1' and table_name='orders' and column_name='availability_policy_version'), 'new order policy default';
 assert (select count(*)=3 from pg_trigger where tgname in ('customer_area_order_context','customer_area_order_line','customer_area_order_commit') and not tgisinternal), 'admission triggers';
 assert not has_function_privilege('anon','public.dastak_v1_customer_area_availability(uuid,timestamptz)','execute');
 assert not has_function_privilege('authenticated','private.customer_area_stock(extensions.geometry,uuid)','execute');
 assert has_function_privilege('authenticated','public.dastak_v1_customer_area_availability(uuid,timestamptz)','execute');
 origin:=extensions.st_setsrid(extensions.st_makepoint(77.5946,12.9716),4326);
 result:=private.customer_area_delivery_available(origin);
 assert result is not null, 'native geographic delivery read';
 assert not exists(select 1 from private.customer_area_stock(origin) where available_quantity<=0), 'native geographic stock read';
 -- Fail closed without an authenticated customer. No customer impersonation.
 begin
   perform public.dastak_v1_customer_area_availability('00000000-0000-4000-8000-000000000000',now());
   raise exception 'unauthenticated area read accepted';
 exception when insufficient_privilege then null;
 end;
end;$check$;
`;
const history = mode === 'apply' ? `insert into supabase_migrations.schema_migrations(version,name,statements)
 values(${quote(version)},'customer_area_availability',array[${quote(sql)}]);` : '';
const query = `begin;
 set local lock_timeout='5s'; set local statement_timeout='90s';
 select pg_advisory_xact_lock(20261008,95639);
 do $guard$ begin
 if exists(select 1 from supabase_migrations.schema_migrations where version=${quote(version)}) then raise exception 'Migration already recorded; inspect before rerunning'; end if;
 if exists(select 1 from information_schema.columns where table_schema='dastak_v1' and table_name='orders' and column_name='availability_policy_version') then raise exception 'Unrecorded policy column exists; inspect before rerunning'; end if;
 end;$guard$;
 ${sql}
 ${assertions}
 ${history}
 ${mode === 'apply' ? 'commit' : 'rollback'};
 select ${quote(mode === 'apply' ? 'specific availability migration committed and recorded' : 'native migration preflight passed and rolled back')} as release_result;`;
const result = spawnSync('supabase', ['db', 'query', '--linked', query], { encoding: 'utf8', maxBuffer: 2 * 1024 * 1024 });
process.stdout.write(result.stdout ?? '');
process.stderr.write(result.stderr ?? '');
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
