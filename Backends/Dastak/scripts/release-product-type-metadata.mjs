import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const mode = process.argv[2];
if (!['verify', 'apply'].includes(mode)) throw new Error('Use verify (rollback) or apply (commit).');
if (readFileSync('supabase/.temp/project-ref', 'utf8').trim() !== 'zmtsolkfxlrxepshnjdf') throw new Error('Wrong linked project.');
const version = '20261008182018';
const name = 'catalogue_product_type_metadata';
const sql = readFileSync(`supabase/migrations/${version}_${name}.sql`, 'utf8');
const quote = value => "'" + value.replaceAll("'", "''") + "'";
const signature = "'dastak_v1_api.merchant_canonical_catalogue_snapshot(uuid,uuid,integer)'::regprocedure";
const marker = "'variant', sku.variant_name,";
const addition = "'variant', sku.variant_name,\n        'attributes', pg_catalog.jsonb_build_object('productType', sku.attribute_data->'productType'),";
const digest = "(select md5(coalesce(string_agg(to_jsonb(s)::text, '' order by s.id),'') ) from dastak_v1.skus s)";
const history = mode === 'apply' ? `insert into supabase_migrations.schema_migrations(version,name,statements) values(${quote(version)},${quote(name)},array[${quote(sql)}]);` : '';
const query = `begin; set local lock_timeout='5s'; set local statement_timeout='90s';
 select pg_advisory_xact_lock(20261008,182018);
 do $guard$ begin
   if exists(select 1 from supabase_migrations.schema_migrations where version=${quote(version)}) then raise exception 'Migration already recorded'; end if;
   if exists(select 1 from pg_constraint where conname='skus_product_type_valid' and conrelid='dastak_v1.skus'::regclass) then raise exception 'Unrecorded constraint exists'; end if;
 end; $guard$;
 create temporary table product_type_before on commit drop as
 select pg_get_functiondef(oid) definition, proacl, prosecdef, proconfig, proowner,
   ${digest} sku_digest,
   (select exists(select 1 from supabase_migrations.schema_migrations where version='20260929191745')) unrelated_applied
 from pg_proc where oid=${signature};
 ${sql}
 do $verify$ declare previous record; current_function record; begin
   select * into strict previous from product_type_before;
   select pg_get_functiondef(oid) definition, proacl, prosecdef, proconfig, proowner into strict current_function from pg_proc where oid=${signature};
   assert current_function.definition=replace(previous.definition,${quote(marker)},${quote(addition)}),'Unexpected Merchant function change';
   assert current_function.proacl is not distinct from previous.proacl,'Grants changed';
   assert current_function.prosecdef=previous.prosecdef and current_function.proconfig=previous.proconfig and current_function.proowner=previous.proowner,'Function security changed';
   assert ${digest}=previous.sku_digest,'SKU records changed';
   assert (select exists(select 1 from supabase_migrations.schema_migrations where version='20260929191745'))=previous.unrelated_applied,'Unrelated migration state changed';
   assert (select convalidated from pg_constraint where conname='skus_product_type_valid' and conrelid='dastak_v1.skus'::regclass),'Constraint not validated';
   assert not has_function_privilege('anon',${signature},'execute'),'Anonymous execute allowed';
   assert has_function_privilege('authenticated',${signature},'execute'),'Authenticated execute lost';
 end; $verify$;
 set local role authenticated;
 do $actor$ begin
   begin perform dastak_v1_api.merchant_canonical_catalogue_snapshot('00000000-0000-4000-8000-000000000000'); raise exception 'Missing/foreign actor accepted'; exception when insufficient_privilege then null; end;
 end; $actor$;
 reset role;
 ${history}
 ${mode === 'apply' ? 'commit' : 'rollback'};
 select ${quote(mode === 'apply' ? 'Product Type migration committed and recorded; SKU data unchanged' : 'Product Type live-schema preflight passed and rolled back')} release_result;`;
const result = spawnSync('supabase', ['db', 'query', '--linked', query], { encoding: 'utf8', maxBuffer: 2 * 1024 * 1024 });
process.stdout.write(result.stdout ?? '');
process.stderr.write(result.stderr ?? '');
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
