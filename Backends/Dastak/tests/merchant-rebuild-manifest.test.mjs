import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync,readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { validateMerchantRebuildManifest,merchantChainHash } from '../scripts/merchant-rebuild-manifest.mjs';
const directory = new URL('../supabase/migrations/',import.meta.url);
function source() {
  const migrations=readdirSync(directory).filter(name=>/^\d{14}_.+\.sql$/.test(name)).sort().map(name=>({name,
    sha256:createHash('sha256').update(readFileSync(new URL(name,directory))).digest('hex')}));
  return {count:migrations.length,chainSha256:merchantChainHash,migrations};
}
test('accepts only the reviewed current 295-file source chain',()=>assert.equal(validateMerchantRebuildManifest(source()).count,295));
test('rejects a changed file even if caller recomputes the manifest hash',()=>{
  const value=source();value.migrations[0].sha256='0'.repeat(64);
  value.chainSha256=createHash('sha256').update(value.migrations.map(row=>`${row.name}:${row.sha256}`).join('\n')).digest('hex');
  assert.throws(()=>validateMerchantRebuildManifest(value),/fingerprint/);
});
test('rejects omitted, duplicate, unordered and extra migration entries',()=>{
  for(const mutate of [m=>m.migrations.pop(),m=>m.migrations.push(m.migrations[0]),m=>m.migrations.reverse(),m=>m.migrations[1]=m.migrations[0]]){
    const value=source();mutate(value);assert.throws(()=>validateMerchantRebuildManifest(value),/manifest/);
  }
});
test('rejects unsupported path names and malformed hashes',()=>{
  for(const mutate of [m=>m.migrations[0].name='../escape.sql',m=>m.migrations[0].sha256='bad']){
    const value=source();mutate(value);assert.throws(()=>validateMerchantRebuildManifest(value),/manifest/);
  }
});
