// Extra real-schema assertions layered into the existing rollback-only Wave-1
// contract, never into production or a minimal substitute schema.
import { existsSync,readFileSync,realpathSync,writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { expandIncludes } from './test-local-database-contracts.mjs';
import { validateMerchantRebuildManifest } from './merchant-rebuild-manifest.mjs';
const root=realpathSync(process.argv[2]??'');
if(!/^\/private\/tmp\/dastak-full-rebuild\.[A-Za-z0-9]+$/.test(root)||existsSync(join(root,'.env'))||existsSync(join(root,'supabase/.temp/project-ref')))throw Error('Disposable unlinked target required');
const project=readFileSync(join(root,'supabase/config.toml'),'utf8').match(/^project_id = "(DastakRebuild20261016R[2-9])"$/m)?.[1];
const manifest=validateMerchantRebuildManifest(JSON.parse(readFileSync(join(root,'rebuild-manifest.json'),'utf8')));
const receipt=JSON.parse(readFileSync(join(root,'rebuild-result.json'),'utf8'));
if(!project||!receipt.ok||receipt.applied!==295||receipt.chainSha256!==manifest.chainSha256)throw Error('Verified rebuild required');
const docker=['--host','unix:///Users/Furqan/.colima/default/docker.sock'];
function run(args,input){const r=spawnSync('docker',[...docker,...args],{input,encoding:'utf8',maxBuffer:16*1024*1024});if(r.status)throw Error(r.stderr);return r.stdout;}
const container='supabase_db_'+project;
const info=JSON.parse(run(['inspect',container]))[0];
if(Object.keys(info.NetworkSettings.Networks).join()!=='dastak-rebuild-20261016'||!JSON.parse(run(['network','inspect','dastak-rebuild-20261016']))[0].Internal)throw Error('Internal-only network required');
const args=['exec','-i',container,'psql','-X','-Atq','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'];
const guard=run(args,"select (select count(*) from supabase_migrations.schema_migrations)=295 and current_setting('cron.launch_active_jobs')='off' and (select count(*) from auth.users)=0;");
if(guard.trim()!=='t')throw Error('Migration/scheduler/fixture guard failed');
const base=expandIncludes(new URL('../supabase/tests/database/026_dastak_v1_wave_1.pgtap.sql',import.meta.url));
const extra=readFileSync(new URL('../supabase/tests/merchant_rebuild_integration.sql',import.meta.url),'utf8');
if((base.match(/select \* from finish\(\);/g)??[]).length!==1||!base.trim().endsWith('rollback;'))throw Error('Unexpected parent contract');
const active=readFileSync(new URL('../supabase/tests/merchant_rebuild_active.sql',import.meta.url),'utf8');
const anchor='create temp table tap_wave1_capacity_order on commit drop as';
if(base.split(anchor).length!==2)throw Error('Unexpected active-work fixture anchor');
const sql="set statement_timeout='45s';\n"+base.replace(anchor,()=>active+'\n'+anchor)
  .replace('select * from finish();',()=>extra+'\nselect * from finish();');
const output=run(args,sql);writeFileSync(join(root,'merchant-integration.log'),output);
const assertions=[...output.matchAll(/^(?:not )?ok\s+\d+\b/gm)].length;
const plan=[...output.matchAll(/^1\.\.(\d+)\s*$/gm)].at(-1)?.[1];
const ok=!/^not ok\b/m.test(output)&&!/# Looks like|# TODO|# SKIP/.test(output)&&Number(plan)===assertions;
const result={ok,assertions,chainSha256:manifest.chainSha256,scope:'Original Wave-1 contract plus new Merchant assertions; real migrated helpers and financial posting; rollback only'};
writeFileSync(join(root,'merchant-integration-result.json'),JSON.stringify(result,null,2));
if(!ok)console.log(output.split('\n').filter(line=>/^not ok|^#/.test(line)).join('\n'));
console.log(JSON.stringify(result));process.exitCode=ok?0:1;
