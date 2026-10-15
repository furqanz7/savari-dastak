// Apply the exact staged migration files to the task's EMPTY Supabase database.
// Docker exec avoids reopening host/outbound networking for the test database.
import { existsSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

const root = realpathSync(process.argv[2] ?? '');
if (!/^\/private\/tmp\/dastak-full-rebuild\.[A-Za-z0-9]+$/.test(root)) throw new Error('Refusing non-disposable target');
if (existsSync(join(root, 'supabase/.temp/project-ref'))) throw new Error('Linked target forbidden');
const project = readFileSync(join(root, 'supabase/config.toml'), 'utf8').match(/^project_id = "(DastakRebuild20261016(?:R[2-9])?)"$/m)?.[1];
if (!project) throw new Error('Unexpected project identity');
const container = `supabase_db_${project}`;
const docker = ['--host', 'unix:///Users/Furqan/.colima/default/docker.sock'];
function command(args, input) {
  const result = spawnSync('docker', [...docker, ...args], { input, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  if (result.error) throw result.error;
  return result;
}
const inspected = command(['inspect', container]);
if (inspected.status) throw new Error('Cannot inspect disposable database');
const info = JSON.parse(inspected.stdout)[0];
if (Object.keys(info.NetworkSettings.Networks).join() !== 'dastak-rebuild-20261016') throw new Error('Database has an unexpected network');
const network = command(['network', 'inspect', 'dastak-rebuild-20261016']);
if (network.status || !JSON.parse(network.stdout)[0].Internal) throw new Error('Database network is not internal');
const psql = sql => command(['exec', '-i', container, 'psql', '-X', '-Atq', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], sql);
const empty = psql(`select json_build_object('app',to_regclass('public.accounts') is not null,
  'schema',to_regnamespace('dastak_v1') is not null,'users',(select count(*) from auth.users),
  'cron',current_setting('cron.launch_active_jobs'));
`);
if (empty.status) throw new Error(empty.stderr);
const state = JSON.parse(empty.stdout);
if (state.app || state.schema || state.users !== 0 || state.cron !== 'off') throw new Error('Database is not a fresh, scheduler-disabled platform');
const history = psql(`create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations(version text primary key, statements text[], name text);
select count(*) from supabase_migrations.schema_migrations;`);
if (history.status || history.stdout.trim() !== '0') throw new Error('Migration history is not empty');
const manifest = JSON.parse(readFileSync(join(root, 'rebuild-manifest.json'), 'utf8'));
if (manifest.count !== 289 || manifest.migrations.length !== 289) throw new Error('Unexpected migration count');
const quote = text => "'" + text.replaceAll("'", "''") + "'";
let applied = 0;
for (const { name, sha256 } of manifest.migrations) {
  if (!/^\d{14}_.+\.sql$/.test(name)) throw new Error('Invalid migration filename');
  const sql = readFileSync(join(root, 'supabase/migrations', name), 'utf8');
  if (createHash('sha256').update(sql).digest('hex') !== sha256) throw new Error(`Migration changed after staging: ${name}`);
  const version = name.slice(0, 14);
  const label = name.slice(15, -4);
  // Match migration-runner transaction scope, including ON COMMIT DROP tables.
  // Preserve file SQL verbatim (some files also carry explicit BEGIN/COMMIT).
  // History is recorded only after success; any failure stops the whole replay.
  const result = psql(`begin; set local statement_timeout='60s';\n${sql}\n;
insert into supabase_migrations.schema_migrations(version,name,statements)
values (${quote(version)},${quote(label)},array[${quote(sql)}]);\ncommit;`);
  writeFileSync(join(root, `${version}.log`), result.stdout + result.stderr);
  if (result.status) {
    writeFileSync(join(root, 'rebuild-result.json'), JSON.stringify({ ok: false, applied, failed: name, chainSha256: manifest.chainSha256 }, null, 2));
    console.error(`FAILED after ${applied} migrations: ${name}`);
    console.error(result.stderr.split('\n').filter(line => /ERROR:|FATAL:/.test(line)).join('\n'));
    process.exit(1);
  }
  applied++;
  console.log(`APPLIED ${applied}/${manifest.count} ${name}`);
}
writeFileSync(join(root, 'rebuild-result.json'), JSON.stringify({ ok: true, applied, chainSha256: manifest.chainSha256 }, null, 2));
console.log(`All ${applied} migration files applied without skips.`);
