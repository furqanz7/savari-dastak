import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pinLocalTestPostgres, testPostgresVersion } from '../scripts/pin-local-test-postgres.mjs';
function fixture(config='project_id = "Dastak"\n[db]\nmajor_version = 17\n') {
  const root=mkdtempSync(join(tmpdir(),'dastak-runtime-pin-'));
  mkdirSync(join(root,'supabase/.temp'),{recursive:true});
  writeFileSync(join(root,'supabase/config.toml'),config);
  return root;
}
test('pins the reviewed fixed image and is repeat-safe',()=>{
  const root=fixture(); assert.equal(pinLocalTestPostgres(root),testPostgresVersion);
  assert.equal(readFileSync(join(root,'supabase/.temp/postgres-version'),'utf8'),testPostgresVersion);
  assert.equal(pinLocalTestPostgres(root),testPostgresVersion);
});
test('refuses a linked project',()=>{
  const root=fixture(); writeFileSync(join(root,'supabase/.temp/project-ref'),'synthetic-ref');
  assert.throws(()=>pinLocalTestPostgres(root),/Refusing linked/);
});
test('refuses environment-configured project',()=>{
  const root=fixture(); writeFileSync(join(root,'.env'),'TEST_ONLY=true');
  assert.throws(()=>pinLocalTestPostgres(root),/environment-configured/);
});
test('does not overwrite another image selection',()=>{
  const root=fixture(); writeFileSync(join(root,'supabase/.temp/postgres-version'),'17.6.1.106');
  assert.throws(()=>pinLocalTestPostgres(root),/Different existing/);
  assert.equal(readFileSync(join(root,'supabase/.temp/postgres-version'),'utf8'),'17.6.1.106');
});
test('rejects another project or database major',()=>{
  assert.throws(()=>pinLocalTestPostgres(fixture('project_id = "Another"\n[db]\nmajor_version = 17\n')),/Unexpected/);
  assert.throws(()=>pinLocalTestPostgres(fixture('project_id = "Dastak"\n[db]\nmajor_version = 15\n')),/Unexpected/);
});
