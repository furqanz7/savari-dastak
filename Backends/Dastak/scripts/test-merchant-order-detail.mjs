// Isolated Unix-socket fixture; never reads connection URLs or live credentials.
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
const directory = mkdtempSync(join(tmpdir(), 'dastak-merchant-detail-'));
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
  for (const file of ['supabase/tests/merchant_order_detail_fixture.sql', 'supabase/migrations/20261018003730_merchant_scoped_order_detail.sql', 'supabase/tests/merchant_order_detail_assertions.sql']) {
    process.stdout.write(run('psql', [...args, '-f', file]));
  }
} finally {
  if (started) run('pg_ctl', ['-D', data, '-m', 'fast', '-w', 'stop']);
  process.stdout.write(`Stopped local-only fixture; diagnostics retained at ${directory}\n`);
}
