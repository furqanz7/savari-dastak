import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
const directory = mkdtempSync(join(tmpdir(), 'dastak-product-type-'));
const data = join(directory, 'data');
function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8', maxBuffer: 2 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`${command} failed: ${result.stderr || result.stdout}`);
  return result.stdout;
}
let started = false;
try {
  run('initdb', ['-D', data, '-A', 'trust', '--no-locale']);
  run('pg_ctl', ['-D', data, '-l', join(directory, 'postgres.log'), '-o', `-k ${directory} -c listen_addresses=''`, '-w', 'start']);
  started = true;
  const args = ['-h', directory, '-d', 'postgres', '-X', '-v', 'ON_ERROR_STOP=1'];
  for (const file of ['supabase/tests/product_type_metadata_fixture.sql', 'supabase/migrations/20261008182018_catalogue_product_type_metadata.sql', 'supabase/tests/product_type_metadata_assertions.sql']) {
    process.stdout.write(run('psql', [...args, '-f', file]));
  }
} finally {
  if (started) run('pg_ctl', ['-D', data, '-m', 'fast', '-w', 'stop']);
  process.stdout.write(`Stopped local-only fixture; diagnostic files retained at ${directory}\n`);
}
