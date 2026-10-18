// LOCAL ONLY: no linked database, hosted URL, credentials or deploy transport.
import {existsSync,readFileSync,realpathSync,writeFileSync} from 'node:fs';
import {spawn,spawnSync} from 'node:child_process';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {buildMerchantReleaseSQL,merchantReleaseSource} from './merchant-release-sql.mjs';
const root=realpathSync(process.argv[2]??'');
if(process.argv.length!==3||!/^\/private\/tmp\/dastak-full-rebuild\.[A-Za-z0-9]+$/.test(root)
 ||existsSync(join(root,'.env'))||existsSync(join(root,'supabase/.temp/project-ref')))throw Error('Disposable unlinked target required');
const project=readFileSync(join(root,'supabase/config.toml'),'utf8').match(/^project_id = "(DastakRebuild20261016R[2-9])"$/m)?.[1];
const receipt=JSON.parse(readFileSync(join(root,'rebuild-result.json'),'utf8'));
if(!project||!receipt.ok||receipt.applied!==291||receipt.fixtureMode!=='merchant-pre-release-291')throw Error('Fresh reviewed 291 baseline required');
const docker=['--host','unix:///Users/Furqan/.colima/default/docker.sock'],container='supabase_db_'+project;
function command(args,input){return spawnSync('docker',[...docker,...args],{input,encoding:'utf8',maxBuffer:8*1024*1024,timeout:45000});}
function successful(args,input){const r=command(args,input);if(r.status!==0)throw Error(r.stderr||r.error?.message||'Local command failed');return r.stdout;}
const networks=JSON.parse(successful(['inspect',container]))[0].NetworkSettings.Networks;
if(Object.keys(networks).join()!=='dastak-rebuild-20261016'
 ||!JSON.parse(successful(['network','inspect','dastak-rebuild-20261016']))[0].Internal)throw Error('Internal-only network required');
const args=['exec','-i',container,'psql','-X','-Atq','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-U','postgres','-d','postgres'];
const sql=input=>successful(args,input).trim();
if(sql("select current_setting('cron.launch_active_jobs')='off' and (select count(*) from auth.users)=0;")!=='t')throw Error('Scheduler/user guard failed');
function state(){return JSON.parse(sql(`select json_build_object('history',(select count(*) from supabase_migrations.schema_migrations),
 'detail',to_regprocedure('public.dastak_v1_merchant_order_detail(uuid,text,uuid)') is not null,
 'index',to_regclass('dastak_v1.fulfilments_merchant_history_cursor_idx') is not null,
 'historyHash',(select md5(string_agg(version||name||array_to_string(statements,''),'' order by version)) from supabase_migrations.schema_migrations),
 'listHash',(select md5(prosrc) from pg_proc where oid='dastak_v1_api.list_merchant_fulfilments(uuid,integer)'::regprocedure));`));}
const before=state(),sameBaseline=()=>{if(JSON.stringify(state())!==JSON.stringify(before))throw Error('Failed attempt left partial schema/history');};
const results=[];
const rolled=command(args,buildMerchantReleaseSQL());
writeFileSync(join(root,'release-rollback.log'),rolled.stdout+rolled.stderr);
if(rolled.status!==0)throw Error(rolled.stderr);sameBaseline();
results.push({case:'explicit-rollback',ok:true,observedBudgets:JSON.parse(rolled.stdout.trim().split('\n').at(-1))});

const holder=spawn('docker',[...docker,...args],{stdio:['pipe','pipe','pipe']});
holder.stdin.end("begin;lock table dastak_v1.fulfilments in row exclusive mode;select pg_sleep(6);rollback;");
const ended=new Promise((resolve,reject)=>holder.once('exit',code=>code===0?resolve():reject(Error('Local lock holder failed'))));
let observed=false;
for(let i=0;i<60;i++){
 if(sql("select exists(select 1 from pg_locks where relation='dastak_v1.fulfilments'::regclass and mode='RowExclusiveLock' and granted);")==='t'){observed=true;break;}
 await new Promise(resolve=>setTimeout(resolve,20));
}
if(!observed)throw Error('Conflicting lock not observed');
let started=Date.now();
const blocked=command(args,buildMerchantReleaseSQL({lockMilliseconds:400,statementMilliseconds:4000}));
const blockedMs=Date.now()-started;
writeFileSync(join(root,'release-lock-timeout.log'),blocked.stdout+blocked.stderr);
if(blocked.status===0||!blocked.stderr.includes('55P03')||blockedMs>3500)throw Error('Lock timeout was not effective');
sameBaseline();await ended;
results.push({case:'conflicting-index-lock',ok:true,sqlState:'55P03',durationMs:blockedMs,noPartialSchemaOrHistory:true});

const slow=buildMerchantReleaseSQL({lockMilliseconds:100,statementMilliseconds:500})
 .replace(/rollback;\s*$/,()=>"select pg_sleep(1);\nrollback;\n");
started=Date.now();const timed=command(args,slow),timedMs=Date.now()-started;
writeFileSync(join(root,'release-statement-timeout.log'),timed.stdout+timed.stderr);
if(timed.status===0||!timed.stderr.includes('57014')||timedMs>3500)throw Error('Statement timeout was not effective');
sameBaseline();results.push({case:'statement-timeout-after-install-verification',ok:true,sqlState:'57014',durationMs:timedMs,noPartialSchemaOrHistory:true});

const committed=command(args,buildMerchantReleaseSQL({commit:true}));
writeFileSync(join(root,'release-commit.log'),committed.stdout+committed.stderr);
if(committed.status!==0)throw Error(committed.stderr);
const after=state();if(after.history!==295||!after.detail||!after.index)throw Error('Final schema/history mismatch');
const history=JSON.parse(sql("select json_agg(json_build_object('version',version,'name',name,'sha256',encode(sha256(convert_to(statements[1],'UTF8')),'hex')) order by version) from supabase_migrations.schema_migrations;"));
const source=merchantReleaseSource();
for(let i=0;i<source.length;i++)if(history[i].version!==source[i].name.slice(0,14)||history[i].name!==source[i].name.slice(15,-4)
 ||history[i].sha256!==createHash('sha256').update(source[i].sql).digest('hex'))throw Error('Final full history/source mismatch');
results.push({case:'explicit-local-commit',ok:true,historyMatches:295,observedBudgets:JSON.parse(committed.stdout.trim().split('\n').at(-1))});
const replay=command(args,buildMerchantReleaseSQL({commit:true}));
if(replay.status===0||!replay.stderr.includes('Unexpected migration baseline')||JSON.stringify(state())!==JSON.stringify(after))throw Error('Already-applied replay guard failed');
results.push({case:'already-applied-rejected',ok:true,noDuplicateHistory:true});
const output={ok:true,localOnly:true,project,chainSha256:receipt.chainSha256,results,before,after,sourceHistoryMatches:295};
writeFileSync(join(root,'merchant-release-rehearsal.json'),JSON.stringify(output,null,2));
writeFileSync(join(root,'rebuild-result.json'),JSON.stringify({ok:true,applied:295,chainSha256:receipt.chainSha256,
 method:'291 real migration baseline plus atomic four-migration release rehearsal'},null,2));
console.log(JSON.stringify(output));
