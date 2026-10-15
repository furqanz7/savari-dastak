import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expandIncludes, runLocalContracts } from '../scripts/test-local-database-contracts.mjs';

test('expands exact rider/stock fixture without weakening assertions', () => {
  const file = fileURLToPath(new URL('../supabase/tests/database/025_dastak_v1_batch_1.pgtap.sql', import.meta.url));
  const result = expandIncludes(file);
  assert.ok(result.includes('create function pg_temp.available_rider'));
  assert.ok(result.includes('create function pg_temp.stocked_store'));
  assert.ok(result.includes('select * from finish();'));
  assert.doesNotMatch(result, /^\\ir\b/m);
});

test('expands preserved historical correction verbatim', () => {
  const file = fileURLToPath(new URL('../supabase/tests/database/082_reference_catalogue_parent_paths.pgtap.sql', import.meta.url));
  const historical = readFileSync(new URL('../supabase/migrations/20260925185849_align_masalas_canonical_parents.sql', import.meta.url), 'utf8');
  assert.ok(expandIncludes(file).includes(historical));
});

test('passes every pgTAP input to local CLI only and removes temporary inputs', () => {
  let temporary;
  const result = runLocalContracts((command, args, options) => {
    assert.equal(command, 'supabase');
    assert.deepEqual(args.slice(0, 2), ['test', 'db']);
    assert.equal(args.at(-1), '--local');
    assert.equal(args.length - 3, 76);
    for (const file of args.slice(2, -1)) {
      assert.doesNotMatch(readFileSync(file, 'utf8'), /^\\i(?:r)?\b/m);
    }
    temporary = args[2];
    assert.ok(options.cwd.endsWith('/Backends/Dastak/'));
    return { status: 0 };
  });
  assert.equal(result, 0);
  assert.equal(existsSync(temporary), false);
});

test('propagates CLI failures', () => {
  assert.equal(runLocalContracts(() => ({ status: 7 })), 7);
});
