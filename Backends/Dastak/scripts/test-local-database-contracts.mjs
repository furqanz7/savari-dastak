// Supabase's pgTAP container receives individual SQL files, not their host-side
// include dependencies. Expand only reviewed repository includes before transport.
import { mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';

const backend = fileURLToPath(new URL('../', import.meta.url));
const directory = join(backend, 'supabase/tests/database');
const allowedIncludes = new Set([
  realpathSync(join(directory, 'fixtures/customer-area.sql.inc')),
  realpathSync(join(backend, 'supabase/migrations/20260925185849_align_masalas_canonical_parents.sql')),
]);

export function expandIncludes(file, seen = new Set()) {
  const path = realpathSync(file);
  if (seen.has(path)) throw new Error('Cyclic database fixture include');
  const next = new Set([...seen, path]);
  return readFileSync(path, 'utf8').replace(/^\\ir\s+([^\r\n]+)\s*$/gm, (_, relative) => {
    const target = realpathSync(resolve(dirname(path), relative.trim()));
    if (!allowedIncludes.has(target)) throw new Error('Unreviewed database fixture include');
    return expandIncludes(target, next);
  });
}

export function runLocalContracts(run = spawnSync) {
  const stage = mkdtempSync(join(tmpdir(), 'dastak-pgtap-inputs-'));
  try {
    const files = readdirSync(directory, { withFileTypes: true })
      .filter(entry => entry.isFile() && entry.name.endsWith('.pgtap.sql'))
      .map(entry => entry.name).sort();
    if (!files.length) throw new Error('No database contracts found');
    for (const name of files) {
      const sql = expandIncludes(join(directory, name));
      if (/^\\i(?:r)?\b/m.test(sql)) throw new Error('Unexpanded SQL include');
      writeFileSync(join(stage, name), sql, { flag: 'wx' });
    }
    const result = run('supabase', ['test', 'db', ...files.map(name => join(stage, name)), '--local'], {
      cwd: backend, stdio: 'inherit',
    });
    if (result.error) throw result.error;
    return result.status ?? 1;
  } finally {
    // Only the exact task-created temporary input directory is removed.
    rmSync(stage, { recursive: true, force: true });
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.length !== 2) throw new Error('Local contracts take no database/remote options');
  process.exitCode = runLocalContracts();
}
