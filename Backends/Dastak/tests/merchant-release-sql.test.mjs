import {test} from 'node:test';
import assert from 'node:assert/strict';
import {buildMerchantReleaseSQL,merchantReleaseSource} from '../scripts/merchant-release-sql.mjs';
test('pins the full source chain and prepares exactly four history records',()=>{
 assert.equal(merchantReleaseSource().length,295);
 const sql=buildMerchantReleaseSQL();
 assert.equal((sql.match(/^insert into supabase_migrations.schema_migrations/gm)??[]).length,4);
 assert.equal((sql.match(/^begin;/gm)??[]).length,1);
 assert.ok(sql.trim().endsWith('rollback;'));
});
test('requires explicit commit and retains finite budgets and verification',()=>{
 const sql=buildMerchantReleaseSQL({commit:true});assert.ok(sql.trim().endsWith('commit;'));
 assert.match(sql,/lock_timeout='2000ms'/);assert.match(sql,/statement_timeout='15000ms'/);
 assert.match(sql,/Old history changed/);assert.match(sql,/Existing dependency or grants changed/);
 assert.doesNotMatch(sql,/\b(?:truncate|delete from|update) (?:dastak_v1\.|private\.)/i);
});
test('rejects unbounded, injected and invalid budget options',()=>{
 for(const options of [{lockMilliseconds:0},{lockMilliseconds:2001},{statementMilliseconds:15001},{statementMilliseconds:0},
  {lockMilliseconds:'2000;commit'},{commit:'yes'},{lockMilliseconds:100,statementMilliseconds:100}])assert.throws(()=>buildMerchantReleaseSQL(options),/Invalid bounded/);
});
