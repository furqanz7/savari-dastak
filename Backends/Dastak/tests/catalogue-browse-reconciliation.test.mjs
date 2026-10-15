import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync, realpathSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { releaseSQL, oldVersion, newVersion, main } from '../scripts/reconcile-catalogue-browse-activation.mjs';

const migration = readFileSync(new URL(`../supabase/migrations/${newVersion}_reconcile_catalogue_browse_activation.sql`, import.meta.url), 'utf8');
const original = readFileSync(new URL(`../supabase/migrations/${oldVersion}_activate_reference_catalogue_browse_map.sql`, import.meta.url), 'utf8');
const fixture = readFileSync(new URL('./catalogue-browse-reconciliation-fixture.sql', import.meta.url), 'utf8');
const socket = process.env.DASTAK_CATALOGUE_TEST_SOCKET;
const psql = '/opt/homebrew/opt/postgresql@14/bin/psql';
function db(sql, success = true) {
  const result = spawnSync(psql, ['-X', '-Atq', '-v', 'ON_ERROR_STOP=1', '-h', socket,
    '-p', '55461', '-d', 'catalogue_reconcile_test'], { input: sql, encoding: 'utf8' });
  if (result.error) throw result.error;
  if (success) assert.equal(result.status, 0, result.stderr);
  else assert.notEqual(result.status, 0, 'Expected SQL to fail closed');
  return result.stdout.trim() + (success ? '' : result.stderr);
}
if (socket) {
  assert.match(realpathSync(socket), /^\/private\/tmp\/dastak-catalogue-pg\.[A-Za-z0-9]+$/);
  assert.equal(db("select current_setting('data_directory');"), `${realpathSync(socket)}/data`);
}
function scenario(name, setup = '', error = null, verify = '') {
  test(name, { skip: !socket }, () => {
    db(`begin; ${fixture} ${setup} commit;`);
    const output = db(`begin; ${migration} ${verify} commit;`, error === null);
    if (error) assert.match(output, error);
  });
}
const added = "(select count(*) from dastak_v1.catalogue_browse_sources where node_key='dairy-alternatives')=1";
const check = expression => `do $test$ begin if not (${expression}) then raise exception 'Assertion failed'; end if; end; $test$;`;
const fingerprints = `select jsonb_build_object(
  'nodes',(select md5(jsonb_agg(to_jsonb(n) order by node_key)::text) from dastak_v1.catalogue_browse_nodes n where version=1),
  'sources',(select md5(jsonb_agg(to_jsonb(s) order by node_key,source_order)::text) from dastak_v1.catalogue_browse_sources s where version=1));`;

test('historical activation remains byte-for-byte unchanged', () => {
  assert.equal(createHash('sha256').update(original).digest('hex'), '1a4c428bcfa1ff85b35c392497c873f91f7d5c3ac5a569dea10a66ad6ac5ae84');
});
test('release requires explicit mode and production flag', () => {
  for (const args of [[], ['apply'], ['inspect', '--approved-production'], ['apply', '--other']]) {
    assert.throws(() => main(args), /Use inspect/);
  }
});
test('release validates fingerprint format and writes explanatory supersession receipt', () => {
  assert.throws(() => releaseSQL(migration, original, { nodes: 'bad', sources: 'bad' }), /fingerprints/);
  const sql = releaseSQL(migration, original);
  assert.match(sql, /Historical fixed-count activation was NOT replayed/);
  assert.match(sql, /set local lock_timeout='5s'/);
  assert.ok(sql.indexOf(migration) < sql.indexOf('insert into supabase_migrations.schema_migrations'));
  assert.ok(sql.indexOf('insert into supabase_migrations.schema_migrations') < sql.indexOf('\ncommit;'));
});
scenario('forward correction maps active soy and preserves milk and prayer configuration', '', null,
  check(`${added} and (select count(*) from dastak_v1.skus)=3 and (select label from dastak_v1.catalogue_browse_nodes where node_key='pooja-store')='Janamaz and Tasbih' and (select count(*) from dastak_v1.catalogue_browse_sources)=5`));
scenario('forward correction is idempotent', migration, null, check(added));
scenario('empty dairy category is safely mapped', "delete from dastak_v1.skus where id='00000000-0000-0000-0000-000000000032';", null, check(added));
scenario('draft activation is not silently bypassed', "update dastak_v1.catalogue_browse_versions set state='DRAFT';", /Expected active catalogue/);
scenario('another active map requires review', "insert into dastak_v1.catalogue_browse_versions values(2,'ACTIVE');", /Expected active catalogue/);
scenario('changed rail parent is rejected', "update dastak_v1.catalogue_browse_nodes set parent_key='pooja-store' where node_key='dairy-alternatives';", /identity differs/);
scenario('inactive dairy taxonomy is rejected', "update dastak_v1.categories set status='INACTIVE' where slug='dairy-alternatives';", /identity differs/);
scenario('conflicting source is not overwritten', "insert into dastak_v1.catalogue_browse_sources(version,node_key,source_order,type_slug,category_slug) values(1,'dairy-alternatives',10,'other','other');", /source conflicts/);
scenario('exclusions on existing source fail closed', "insert into dastak_v1.catalogue_browse_sources(version,node_key,source_order,type_slug,category_slug,excluded_subcategory_slugs) values(1,'dairy-alternatives',10,'dairy-bread-eggs','dairy-alternatives',array['soy-milk']);", /source conflicts/);
scenario('missing active product rail prevents release', "delete from dastak_v1.catalogue_browse_sources where node_key='milk';", /invalid active SKU/);
scenario('duplicate active product rails prevent release', "insert into dastak_v1.catalogue_browse_sources(version,node_key,source_order,type_slug,category_slug) values(1,'janamaz',20,'dairy-bread-eggs','milk');", /invalid active SKU/);
scenario('inactive taxonomy under another active SKU prevents release', "update dastak_v1.subcategories set status='INACTIVE' where slug='fresh-milk';", /invalid active SKU/);
scenario('unresolved active taxonomy prevents release', "update dastak_v1.skus set subcategory_id=gen_random_uuid() where id='00000000-0000-0000-0000-000000000031';", /invalid active SKU/);

test('original-size draft activation followed by forward correction replays safely', { skip: !socket }, () => {
  db(`begin; ${fixture}
    update dastak_v1.catalogue_browse_versions set state='DRAFT';
    insert into dastak_v1.catalogue_browse_nodes select 1,'fixture-'||g,null,'SECTION','Fixture',g from generate_series(1,105) g;
    insert into dastak_v1.catalogue_browse_sources(version,node_key,source_order,type_slug)
      select 1,'fixture-1',g,'unused-fixture-'||g from generate_series(1,120) g;
    ${original} ${migration}
    ${check("(select state from dastak_v1.catalogue_browse_versions where version=1)='ACTIVE' and (select count(*) from dastak_v1.catalogue_browse_nodes)=112 and (select count(*) from dastak_v1.catalogue_browse_sources)=125")}
    commit;`);
});

test('release atomically adds source and exactly two history entries; repeated release refuses', { skip: !socket }, () => {
  db(`begin; ${fixture} commit;`);
  const expected = JSON.parse(db(fingerprints));
  const sql = releaseSQL(migration, original, expected);
  db(sql);
  db(check(`${added} and (select count(*) from supabase_migrations.schema_migrations where version in ('${oldVersion}','${newVersion}'))=2`));
  assert.match(db(sql, false), /already recorded/);
});
test('configuration drift records nothing and adds no source', { skip: !socket }, () => {
  db(`begin; ${fixture} commit;`);
  const expected = JSON.parse(db(fingerprints));
  db("update dastak_v1.catalogue_browse_nodes set label='Changed' where node_key='milk';");
  assert.match(db(releaseSQL(migration, original, expected), false), /changed since reviewed/);
  db(check("not exists(select 1 from dastak_v1.catalogue_browse_sources where node_key='dairy-alternatives') and (select count(*) from supabase_migrations.schema_migrations)=1"));
});
test('failure after source insertion rolls back source and all history entries', { skip: !socket }, () => {
  db(`begin; ${fixture} commit;`);
  const expected = JSON.parse(db(fingerprints));
  const failing = migration + "\ndo $fail$ begin raise exception 'Injected post-patch failure'; end; $fail$;";
  assert.match(db(releaseSQL(failing, original, expected), false), /Injected post-patch failure/);
  db(check("not exists(select 1 from dastak_v1.catalogue_browse_sources where node_key='dairy-alternatives') and (select count(*) from supabase_migrations.schema_migrations)=1"));
});
