import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

// Native PostGIS, actual linked schema, one rolled-back transaction. No real
// customers, orders, payments, stock or providers are changed or persisted.
const root = new URL('../supabase/', import.meta.url);
if (readFileSync(new URL('.temp/project-ref', root), 'utf8').trim() !== 'zmtsolkfxlrxepshnjdf') throw new Error('Wrong linked project');
const preflight = process.argv[2] === 'preflight';
const migration = preflight ? readFileSync(new URL('migrations/20261009131135_customer_thirty_km_serviceability.sql', root), 'utf8') : '';
const assertions = readFileSync(new URL('tests/database/thirty_km_serviceability.contract.sql', root), 'utf8');
const query = `begin; set local lock_timeout='3s'; set local statement_timeout='30s';
create temporary table protected_functions as
select p.oid,md5(pg_get_functiondef(p.oid)) digest from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where (n.nspname='private' and p.proname='customer_area_delivery_available')
or (n.nspname='dastak_v1_api' and p.proname in ('calculate_delivery_fee_paise','create_rider_offer_pool'));
${migration}
${assertions}
do $$begin assert not exists(select 1 from protected_functions where digest<>md5(pg_get_functiondef(oid))), 'delivery rule and fee functions changed'; end;$$;
select jsonb_build_object('passed',count(*),'checks',jsonb_agg(label order by label)) as verification from radius_checks;
rollback;`;
const result = spawnSync('supabase', ['db', 'query', '--linked', '--workdir', new URL('..', root).pathname, query], { encoding: 'utf8', maxBuffer: 1024 * 1024 });
process.stdout.write(result.stdout ?? ''); process.stderr.write(result.stderr ?? '');
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
