import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';

const backend = fileURLToPath(new URL('../', import.meta.url));
export const oldVersion = '20260929191745';
export const newVersion = '20261015203400';
const migrationPath = `supabase/migrations/${newVersion}_reconcile_catalogue_browse_activation.sql`;
const quote = text => "'" + text.replaceAll("'", "''") + "'";
export const reviewedMap = Object.freeze({
  nodes: 'e655fb9301b2ef89c609acbd07c63a08',
  sources: '95aea904789558567b1aa4d60d03958f',
});

export function releaseSQL(migration, original, expected = reviewedMap) {
  if (![expected.nodes, expected.sources].every(value => /^[0-9a-f]{32}$/.test(value))) {
    throw new Error('Invalid reviewed map fingerprints');
  }
  const originalHash = createHash('sha256').update(original).digest('hex');
  // History is a documented verified supersession, not a claim that the old
  // fixed-count DO block ran on today's catalogue. Fresh replay keeps that file.
  const receipt = `-- Reconciled by ${newVersion}: current active map validated, missing Dairy Alternatives source supplied.\n-- Original ${oldVersion} preserved for fresh replay; SHA-256 ${originalHash}.\n-- Historical fixed-count activation was NOT replayed on the evolved live map.`;
  return `begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
select pg_advisory_xact_lock(20261015,203400);
lock table dastak_v1.catalogue_browse_versions, dastak_v1.catalogue_browse_nodes,
  dastak_v1.catalogue_browse_sources in share row exclusive mode;
lock table supabase_migrations.schema_migrations in share row exclusive mode;
do $guard$ begin
  if exists(select 1 from supabase_migrations.schema_migrations where version in ('${oldVersion}','${newVersion}')) then
    raise exception 'Reconciliation history changed or already recorded; inspect instead of replaying';
  end if;
  if not exists(select 1 from supabase_migrations.schema_migrations where version='20261014224848') then
    raise exception 'Expected prayer-essentials migration is not recorded';
  end if;
  if (select md5(coalesce(jsonb_agg(to_jsonb(n) order by node_key)::text,'[]')) from dastak_v1.catalogue_browse_nodes n where version=1) <> '${expected.nodes}'
    or (select md5(coalesce(jsonb_agg(to_jsonb(s) order by node_key,source_order)::text,'[]')) from dastak_v1.catalogue_browse_sources s where version=1) <> '${expected.sources}' then
    raise exception 'Catalogue map changed since reviewed preflight; nothing will be recorded';
  end if;
end; $guard$;
${migration}
do $verify$ begin
  if (select md5(coalesce(jsonb_agg(to_jsonb(n) order by node_key)::text,'[]')) from dastak_v1.catalogue_browse_nodes n where version=1) <> '${expected.nodes}'
    or (select md5(coalesce(jsonb_agg(to_jsonb(s) order by node_key,source_order)::text,'[]')) from dastak_v1.catalogue_browse_sources s where version=1 and not (node_key='dairy-alternatives' and source_order=10)) <> '${expected.sources}' then
    raise exception 'Existing catalogue configuration was changed';
  end if;
end; $verify$;
insert into supabase_migrations.schema_migrations(version,name,statements)
values ('${oldVersion}','activate_reference_catalogue_browse_map',array[${quote(receipt)}]),
  ('${newVersion}','reconcile_catalogue_browse_activation',array[${quote(migration)}]);
commit;
select 'Catalogue source corrected and exact two history entries committed atomically' as result;`;
}

export function main(args) {
  const inspect = args.length === 1 && args[0] === 'inspect';
  const apply = args.length === 2 && args[0] === 'apply' && args[1] === '--approved-production';
  if (!inspect && !apply) throw new Error('Use inspect (read only), or apply --approved-production after explicit owner approval.');
  if (readFileSync(`${backend}supabase/.temp/project-ref`, 'utf8').trim() !== 'zmtsolkfxlrxepshnjdf') {
    throw new Error('Wrong linked project; refusing reconciliation');
  }
  const sql = inspect ? readFileSync(`${backend}scripts/catalogue-browse-reconciliation-audit.sql`, 'utf8')
    : releaseSQL(readFileSync(`${backend}${migrationPath}`, 'utf8'),
      readFileSync(`${backend}supabase/migrations/${oldVersion}_activate_reference_catalogue_browse_map.sql`, 'utf8'));
  // SQL files may start with "--" comments: terminate CLI option parsing first.
  const result = spawnSync('supabase', ['db', 'query', '--linked', '--workdir', backend, '--', sql],
    { encoding: 'utf8', maxBuffer: 2 * 1024 * 1024 });
  process.stdout.write(result.stdout ?? '');
  process.stderr.write(result.stderr ?? '');
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main(process.argv.slice(2));
