// Local Unix-socket fixture only. No environment URLs or live credentials.
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
const directory = mkdtempSync(join(tmpdir(), 'dastak-merchant-history-'));
const data = join(directory, 'data');
function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8', maxBuffer: 3 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`${command} failed: ${result.stderr || result.stdout}`);
  return result.stdout;
}
let started = false;
try {
  run('initdb', ['-D', data, '-A', 'trust', '--no-locale']);
  run('pg_ctl', ['-D', data, '-l', join(directory, 'postgres.log'), '-o', `-k ${directory} -c listen_addresses=''`, '-w', 'start']);
  started = true;
  const args = ['-h', directory, '-d', 'postgres', '-X', '-v', 'ON_ERROR_STOP=1'];
  for (const file of ['supabase/tests/merchant_order_detail_fixture.sql', 'supabase/tests/merchant_history_fixture.sql',
    'supabase/migrations/20260916060000_include_released_merchant_history.sql']) process.stdout.write(run('psql', [...args, '-f', file]));
  process.stdout.write(run('psql', [...args, '-c', `select set_config('request.jwt.claim.sub','99000000-0000-4000-8000-000000000001',false);
    create table fixture_previous_feed as select dastak_v1_api.list_merchant_fulfilments('99000000-0000-4000-8000-000000000001',1) payload;`]));
  for (const file of ['supabase/migrations/20261018014110_merchant_active_and_paged_history.sql', 'supabase/tests/merchant_history_assertions.sql'])
    process.stdout.write(run('psql', [...args, '-f', file]));
} finally {
  if (started) run('pg_ctl', ['-D', data, '-m', 'fast', '-w', 'stop']);
  process.stdout.write(`Stopped local-only fixture; diagnostics retained at ${directory}\n`);
}
