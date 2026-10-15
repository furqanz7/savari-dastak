// Run existing real database contracts against the isolated rebuilt database.
import { existsSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { join, dirname, resolve } from 'node:path';
const root = realpathSync(process.argv[2] ?? '');
if (!/^\/private\/tmp\/dastak-full-rebuild\.[A-Za-z0-9]+$/.test(root)
    || existsSync(join(root, 'supabase/.temp/project-ref'))) throw new Error('Disposable unlinked project required');
const project = readFileSync(join(root, 'supabase/config.toml'), 'utf8').match(/^project_id = "(DastakRebuild20261016(?:R[2-9])?)"$/m)?.[1];
if (!project || !JSON.parse(readFileSync(join(root, 'rebuild-result.json'), 'utf8')).ok) throw new Error('Successful rebuild required');
const container = `supabase_db_${project}`;
const runName = process.argv[3] ?? 'baseline';
if (!/^[a-z0-9-]+$/.test(runName)) throw new Error('Invalid run label');
const fixtureSuperuser = process.argv[4] === '--fixture-superuser';
if (process.argv.length > (fixtureSuperuser ? 5 : 4)) throw new Error('Unexpected arguments');
const docker = ['--host', 'unix:///Users/Furqan/.colima/default/docker.sock'];
const inspected = spawnSync('docker', [...docker, 'inspect', container], { encoding: 'utf8' });
if (inspected.status || Object.keys(JSON.parse(inspected.stdout)[0].NetworkSettings.Networks).join() !== 'dastak-rebuild-20261016') throw new Error('Unexpected database networking');
const network = spawnSync('docker', [...docker, 'network', 'inspect', 'dastak-rebuild-20261016'], { encoding: 'utf8' });
if (network.status || !JSON.parse(network.stdout)[0].Internal) throw new Error('Internal network required');
// Explicit diagnostic mode only: some governance fixtures require a genuine
// superuser to SET session_replication_role. SQL and in-test actor roles stay exact.
const psql = sql => spawnSync('docker', [...docker, 'exec', ...(fixtureSuperuser ? ['-e', 'PGPASSWORD=postgres'] : []),
  '-i', container, 'psql', '-X', '-Atq', '-v', 'ON_ERROR_STOP=1', '-U', fixtureSuperuser ? 'supabase_admin' : 'postgres', '-d', 'postgres'],
  { input: sql, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
const expectedMigrations = JSON.parse(readFileSync(join(root,'rebuild-result.json'),'utf8')).applied;
if (![287,289].includes(expectedMigrations)) throw new Error('Unreviewed migration manifest');
const guard = psql(`select (select count(*) from supabase_migrations.schema_migrations)=${expectedMigrations} and current_setting('cron.launch_active_jobs')='off';`);
if (guard.status || guard.stdout.trim() !== 't') throw new Error('Migration/scheduler guard failed');
const runtime = psql("select json_build_object('version',version(),'user',current_user,'sessionPreload',current_setting('session_preload_libraries'),'cron',current_setting('cron.launch_active_jobs'));");
if (runtime.status) throw new Error('Cannot record runtime');
const directory = fileURLToPath(new URL('../supabase/tests/database/', import.meta.url));
const results = [];
function fixtureSQL(path) {
  const source = readFileSync(path,'utf8');
  return source.replace(/^\\ir (fixtures\/[a-z0-9-]+\.sql\.inc|\.\.\/\.\.\/migrations\/20260925185849_align_masalas_canonical_parents\.sql)\s*$/gm, (_, relative) => {
    const file = resolve(dirname(path),relative);
    if (!file.startsWith(directory) && !file.endsWith('/supabase/migrations/20260925185849_align_masalas_canonical_parents.sql')) throw new Error('Fixture escaped database tests');
    return readFileSync(file,'utf8');
  });
}
for (const name of readdirSync(directory, { withFileTypes: true })
  .filter(entry => entry.isFile() && entry.name.endsWith('.pgtap.sql')).map(entry => entry.name).sort()) {
  const sql = readFileSync(join(directory, name), 'utf8');
  const expanded = fixtureSQL(join(directory,name));
  const result = psql("set statement_timeout='45s';\n" + expanded);
  const output = (result.stdout ?? '') + (result.stderr ?? '');
  writeFileSync(join(root, `${runName}-test-${name}.log`), output);
  const assertions = [...(result.stdout ?? '').matchAll(/^(?:not )?ok\s+\d+\b/gm)].length;
  const plan = [...(result.stdout ?? '').matchAll(/^1\.\.(\d+)\s*$/gm)].at(-1)?.[1];
  const failed = result.status !== 0 || /^not ok\b/m.test(output) || /# Looks like/.test(output)
    || plan === undefined || Number(plan) !== assertions;
  results.push({ name, ok: !failed, assertions, exitStatus: result.status,
    sha256: createHash('sha256').update(sql).digest('hex'),
    expandedSha256: createHash('sha256').update(expanded).digest('hex') });
  console.log(`${failed ? 'FAIL' : 'PASS'} ${name} (${assertions} assertions)`);
  if (failed) console.log(output.split('\n').filter(line => /^not ok\b|ERROR:|# Looks like/.test(line)).join('\n'));
}
const summary = { files: results.length, passed: results.filter(row => row.ok).length,
  failed: results.filter(row => !row.ok).length, assertions: results.reduce((sum, row) => sum + row.assertions, 0),
  runName, runtime: JSON.parse(runtime.stdout), results };
writeFileSync(join(root, `database-contract-results-${runName}.json`), JSON.stringify(summary, null, 2));
console.log(JSON.stringify({ files: summary.files, passed: summary.passed, failed: summary.failed, assertions: summary.assertions }));
process.exitCode = summary.failed ? 1 : 0;
