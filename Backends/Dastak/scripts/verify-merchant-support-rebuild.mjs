// New support-chain verification. Historical 295-file tools/pins stay unchanged.
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateMerchantRebuildManifest } from './merchant-rebuild-manifest.mjs';
import { expandIncludes } from './test-local-database-contracts.mjs';

const root = realpathSync(process.argv[2] ?? '');
const mode = process.argv[3];
if (!/^\/private\/tmp\/dastak-full-rebuild\.[A-Za-z0-9]+$/.test(root)
  || !['prepare','replay','contracts','support','contention'].includes(mode) || process.argv.length !== 4
  || existsSync(join(root,'.env')) || existsSync(join(root,'supabase/.temp/project-ref'))
  || !/^project_id = "DastakRebuild20261016R9"$/m.test(readFileSync(join(root,'supabase/config.toml'),'utf8'))) throw Error('Disposable unlinked R9 project required');
const source = fileURLToPath(new URL('../supabase/migrations/', import.meta.url));
const sha = text => createHash('sha256').update(text).digest('hex');
const rows = readdirSync(source).filter(name => /^\d{14}_.+\.sql$/.test(name)).sort().map(name => ({ name, sha256:sha(readFileSync(join(source,name))) }));
const chain = list => sha(list.map(row => `${row.name}:${row.sha256}`).join('\n'));
validateMerchantRebuildManifest({count:295, migrations:rows.slice(0,295),chainSha256:chain(rows.slice(0,295))});
if (rows.length!==297 || rows[295].name!=='20261020193411_merchant_support_inbox.sql'
  || rows[295].sha256!=='bf284bb716f402202d65366a41b5d7afd6d19590f3df89904d6c066a090d6778'
  || chain(rows.slice(0,296))!=='2520d22baa28f1fc8dd137751360c51e691961ec22da72a84736c29cde8230e7'
  || rows[296].name!=='20261020203749_merchant_support_request_hardening.sql'
  || rows[296].sha256!=='5b1243b6c2f3ca152055ee9b5bb688ce456d62b8dfe5f3dc5fa07d26907d0eff'
  || chain(rows)!=='03003a1c7835d7602e7fb80214c8521a3c3a46e4ba2770f65a3d90c2b311a26f') throw Error('Unreviewed support-chain source');
const manifest = {count:rows.length,chainSha256:chain(rows),migrations:rows};
const docker = ['--host','unix:///Users/Furqan/.colima/default/docker.sock'];
const original = 'supabase_db_DastakRebuild20261016R9';
const container = 'dastak_support_hardened_final_20261021';
const image = 'sha256:3866d94d8426927e8db3f1c5d790752292bfbe27b5f1f46e199ae1b7d3c1710b';
function run(args,input) {
  const result=spawnSync('docker',[...docker,...args],{input,encoding:'utf8',maxBuffer:24*1024*1024});
  if (result.status) throw Error((result.stderr||'Docker command failed').slice(0,3000));
  return result.stdout;
}
const query=(target,sql) => run(['exec','-i',target,'psql','-X','-Atq','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],sql);
function isolated() {
  const info=JSON.parse(run(['inspect',container]))[0];
  if (info.Image!==image || Object.keys(info.NetworkSettings.Networks).join()!=='none'
    || Object.keys(info.HostConfig.PortBindings??{}).length
    || info.Config.Labels?.['com.dastak.qa']!=='merchant-support-hardening-20261021') throw Error('Unexpected runtime/network/port/ownership');
  if (query(container,"select current_setting('cron.launch_active_jobs')='off';").trim()!=='t') throw Error('Scheduler is enabled');
}
if (mode==='prepare') {
  const info=JSON.parse(run(['inspect',original]))[0];
  if (info.Image!==image || !info.State.Running || !info.Name.endsWith(original)) throw Error('Unexpected bootstrap runtime');
  const fresh=JSON.parse(query(original,"select json_build_object('empty',to_regclass('public.accounts') is null and to_regnamespace('dastak_v1') is null,'users',(select count(*) from auth.users),'cron',current_setting('cron.launch_active_jobs'));").trim());
  if (!fresh.empty || fresh.users!==0 || fresh.cron!=='off') throw Error('Bootstrap is not empty/scheduler-disabled');
  const probe=spawnSync('docker',[...docker,'inspect',container],{encoding:'utf8'});
  if (!probe.status) throw Error('Verification container already exists; never replace it');
  const task=['storage','rest','realtime','auth','kong','db'].map(name=>`supabase_${name}_DastakRebuild20261016R9`);
  run(['stop',...task]);
  // Reuse only this fresh project's platform volume, never a user workspace.
  // Clone the image/bootstrap command without publishing ports or networking.
  const args=['create','--pull=never','--name',container,'--network','none','--label','com.dastak.qa=merchant-support-hardening-20261021','--volumes-from',original];
  for (const value of info.Config.Env) args.push('--env',value);
  args.push('--entrypoint',info.Config.Entrypoint[0],image,...info.Config.Entrypoint.slice(1),...(info.Config.Cmd??[]));
  run(args); run(['start',container]);
  for (let attempt=0;attempt<30;attempt++) {
    const ready=spawnSync('docker',[...docker,'exec',container,'pg_isready','-U','postgres'],{encoding:'utf8'});
    if (!ready.status) break;
    if (attempt===29) throw Error('Isolated database did not start');
    await new Promise(resolve=>setTimeout(resolve,1000));
  }
  isolated();
  mkdirSync(join(root,'supabase/migrations'),{recursive:true});
  for (const row of rows) { const target=join(root,'supabase/migrations',row.name); copyFileSync(join(source,row.name),target); if(sha(readFileSync(target))!==row.sha256) throw Error('Staging mismatch'); }
  writeFileSync(join(root,'support-rebuild-manifest.json'),JSON.stringify(manifest,null,2));
  console.log(JSON.stringify({prepared:true,count:297,chainSha256:manifest.chainSha256,network:'none',publishedPorts:0,cron:'off'}));
} else {
  isolated();
  const saved=JSON.parse(readFileSync(join(root,'support-rebuild-manifest.json'),'utf8'));
  if (saved.chainSha256!==manifest.chainSha256 || JSON.stringify(saved.migrations)!==JSON.stringify(rows)) throw Error('Manifest drift');
  for (const row of rows) if(sha(readFileSync(join(root,'supabase/migrations',row.name)))!==row.sha256)throw Error('Staged file drift');
  const sql=input=>query(container,input);
  if(mode==='replay') {
    if(sql("select to_regclass('public.accounts') is null and to_regnamespace('dastak_v1') is null and (select count(*) from auth.users)=0;").trim()!=='t')throw Error('Replay requires EMPTY database');
    sql('create schema if not exists supabase_migrations; create table if not exists supabase_migrations.schema_migrations(version text primary key,statements text[],name text);');
    if(sql('select count(*) from supabase_migrations.schema_migrations;').trim()!=='0')throw Error('History not empty');
    let applied=0; const literal=value=>"'"+value.replaceAll("'","''")+"'";
    for(const row of rows) {
      const sourceSQL=readFileSync(join(root,'supabase/migrations',row.name),'utf8');
      try {
        const result=sql(`begin; set local statement_timeout='60s';\n${sourceSQL}\n;\ninsert into supabase_migrations.schema_migrations(version,name,statements) values(${literal(row.name.slice(0,14))},${literal(row.name.slice(15,-4))},array[${literal(sourceSQL)}]);\ncommit;`);
        writeFileSync(join(root,`${row.name}.log`),result); applied++;
        console.log(`APPLIED ${applied}/297 ${row.name}`);
      }catch(error){writeFileSync(join(root,'support-rebuild-result.json'),JSON.stringify({ok:false,applied,failed:row.name,error:String(error)},null,2));throw error;}
    }
    const recorded=JSON.parse(sql("select json_agg(json_build_object('name',version||'_'||name||'.sql','sha256',encode(sha256(convert_to(statements[1],'UTF8')),'hex')) order by version) from supabase_migrations.schema_migrations;").trim());
    if(JSON.stringify(recorded)!==JSON.stringify(rows))throw Error('Recorded SQL/history hash mismatch');
    const result={ok:true,applied,chainSha256:manifest.chainSha256,historyMatches:true,runtime:sql('select version();').trim()};
    writeFileSync(join(root,'support-rebuild-result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
  }else if(mode==='contention') {
    if(!JSON.parse(readFileSync(join(root,'support-rebuild-result.json'),'utf8')).ok)throw Error('Successful complete replay required');
    const tid='b5100000-0000-4000-8000-000000000001';
    if(sql(`select count(*) from private.merchant_support_tickets where id='${tid}';`).trim()!=='0')throw Error('Probe ID already exists');
    const payload={operation:'create',ticketId:tid,requestId:'c5100000-0000-4000-8000-000000000001',tokenHash:'a'.repeat(64),subject:'Isolated lock probe',category:'OTHER',message:'Synthetic lock probe only; delete after verification.'};
    let holder;
    try {
      sql(`set role service_role; select public.merchant_support_command(null,'${JSON.stringify(payload)}');`);
      holder=spawn('docker',[...docker,'exec','-i',container,'psql','-X','-Atq','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{stdio:['pipe','pipe','pipe']});
      const finished=new Promise(resolve=>holder.on('close',resolve));
      const locked=new Promise((resolve,reject)=>{
        let output='';const timer=setTimeout(()=>reject(Error('Lock probe startup deadline')),3000);
        holder.stdout.on('data',chunk=>{output+=chunk; if(output.includes('QA_LOCK_HELD')){clearTimeout(timer);resolve();}});
        holder.on('error',error=>{clearTimeout(timer);reject(error);});
      });
      holder.stdin.end(`begin; select id from private.merchant_support_tickets where id='${tid}' for update; select 'QA_LOCK_HELD'; select pg_sleep(2); rollback;`);
      await locked;
      const read = {...payload,operation:'read'};
      let rejected='';
      try {sql(`set statement_timeout='150ms'; set role service_role; select public.merchant_support_command(null,'${JSON.stringify({...read,tokenHash:'b'.repeat(64)})}');`);}catch(error){rejected=String(error);}
      if(!rejected.includes('support_not_found')||rejected.includes('statement timeout'))throw Error('Wrong-token read blocked or leaked');
      const snapshot=JSON.parse(sql(`set statement_timeout='150ms'; set role service_role; select public.merchant_support_command(null,'${JSON.stringify(read)}');`).trim());
      if(snapshot.id!==tid)throw Error('Valid read failed behind lock');
      let busy='';
      try {sql(`set statement_timeout='150ms'; set role service_role; select public.merchant_support_command(null,'${JSON.stringify({...payload,operation:'reply',requestId:'c5100000-0000-4000-8000-000000000002',version:1})}');`);}catch(error){busy=String(error);}
      if(!busy.includes('support_busy')||busy.includes('statement timeout'))throw Error('Mutation lock did not fail fast');
      if(await finished!==0)throw Error('Lock holder failed');
      holder=spawn('docker',[...docker,'exec','-i',container,'psql','-X','-Atq','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{stdio:['pipe','pipe','pipe']});
      const globalFinished=new Promise(resolve=>holder.on('close',resolve));
      const globalLocked=new Promise((resolve,reject)=>{
        let output='';const timer=setTimeout(()=>reject(Error('Admission probe startup deadline')),3000);
        holder.stdout.on('data',chunk=>{output+=chunk;if(output.includes('QA_ADMISSION_HELD')){clearTimeout(timer);resolve();}});
        holder.on('error',error=>{clearTimeout(timer);reject(error);});
      });
      holder.stdin.end("begin; select pg_advisory_xact_lock(7610021); select 'QA_ADMISSION_HELD'; select pg_sleep(2); rollback;");
      await globalLocked;
      let admission='';
      try {sql(`set statement_timeout='150ms'; set role service_role; select public.merchant_support_command(null,'${JSON.stringify({...payload,ticketId:'b5100000-0000-4000-8000-000000000002'})}');`);}catch(error){admission=String(error);}
      if(!admission.includes('support_busy')||admission.includes('statement timeout'))throw Error('Admission lock did not fail fast');
      if(await globalFinished!==0)throw Error('Admission lock holder failed');
      const result={ok:true,requests:4,statementDeadlineMs:150,wrongToken:'support_not_found',authorizedRead:'succeeded behind held write lock',contendedWrite:'support_busy',contendedAdmission:'support_busy',evidence:busy,admissionEvidence:admission};
      writeFileSync(join(root,'support-contention-results.json'),JSON.stringify(result,null,2)); console.log(JSON.stringify(result));
    } finally {
      if(holder&&holder.exitCode===null)holder.kill();
      sql(`delete from private.merchant_support_messages where ticket_id='${tid}'; delete from private.merchant_support_tickets where id='${tid}';`);
      if(sql('select count(*) from private.merchant_support_tickets;').trim()!=='0')throw Error('Probe cleanup failed');
    }
  }else {
    if(!JSON.parse(readFileSync(join(root,'support-rebuild-result.json'),'utf8')).ok || sql('select count(*) from supabase_migrations.schema_migrations;').trim()!=='297')throw Error('Successful complete replay required');
    const directory=fileURLToPath(new URL('../supabase/tests/database/',import.meta.url));
    const files=mode==='contracts' ? readdirSync(directory,{withFileTypes:true}).filter(e=>e.isFile()&&e.name.endsWith('.pgtap.sql')).map(e=>join(directory,e.name)).sort() : [fileURLToPath(new URL('../supabase/tests/merchant_support_full.sql',import.meta.url))];
    const results=[];
    for(const file of files){
      const name=file.split('/').at(-1);let output;
      try{output=sql("set statement_timeout='45s';\n"+expandIncludes(file));}
      catch(error){writeFileSync(join(root,`${mode}-${name}.log`),String(error));throw error;}
      writeFileSync(join(root,`${mode}-${name}.log`),output);
      const assertions=[...output.matchAll(/^(?:not )?ok\s+\d+\b/gm)].length;
      const plan=[...output.matchAll(/^1\.\.(\d+)\s*$/gm)].at(-1)?.[1];
      const ok=Number(plan)===assertions&&!/^not ok\b|# Looks like|# TODO|# SKIP/m.test(output);
      results.push({name,ok,assertions,sha256:sha(readFileSync(file))});
      console.log(`${ok?'PASS':'FAIL'} ${name} (${assertions} assertions)`);
      if(!ok){writeFileSync(join(root,`support-${mode}-results.json`),JSON.stringify({ok:false,results},null,2));throw Error('Database assertion failed; stop rather than skip');}
    }
    const hygiene=JSON.parse(sql("select json_build_object('users',(select count(*) from auth.users),'tickets',(select count(*) from private.merchant_support_tickets),'cronRuns',(select count(*) from cron.job_run_details),'httpQueued',(select count(*) from net.http_request_queue),'httpResponses',(select count(*) from net._http_response));").trim());
    if(Object.values(hygiene).some(count=>count!==0))throw Error('Fixture rollback/scheduler/network hygiene failed');
    const result={ok:true,files:results.length,assertions:results.reduce((sum,r)=>sum+r.assertions,0),hygiene,results};
    writeFileSync(join(root,`support-${mode}-results.json`),JSON.stringify(result,null,2));console.log(JSON.stringify({...result,results:undefined}));
  }
}
