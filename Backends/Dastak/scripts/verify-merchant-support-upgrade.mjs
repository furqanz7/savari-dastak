// One-time upgrade witness in the retained, synthetic R7 fixture only.
import { existsSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { deepStrictEqual } from 'node:assert';
import { join } from 'node:path';
const root=realpathSync(process.argv[2]??'');
if(process.argv.length!==3||!/^\/private\/tmp\/dastak-full-rebuild\.[A-Za-z0-9]+$/.test(root)||existsSync(join(root,'.env'))||existsSync(join(root,'supabase/.temp/project-ref')))throw Error('Unlinked fixture only');
if(!/^project_id = "DastakRebuild20261016R7"$/m.test(readFileSync(join(root,'supabase/config.toml'),'utf8')))throw Error('Wrong project');
const prior=JSON.parse(readFileSync(join(root,'support-rebuild-result.json'),'utf8'));
if(!prior.ok||prior.applied!==296||prior.chainSha256!=='2520d22baa28f1fc8dd137751360c51e691961ec22da72a84736c29cde8230e7')throw Error('Prior full replay receipt required');
const sha=s=>createHash('sha256').update(s).digest('hex');
const directory=new URL('../supabase/migrations/',import.meta.url);
const rows=readdirSync(directory).filter(name=>/^\d{14}_.+\.sql$/.test(name)).sort().map(name=>({name,sha256:sha(readFileSync(new URL(name,directory)))}));
if(rows.length!==297||sha(rows.map(row=>`${row.name}:${row.sha256}`).join('\n'))!=='03003a1c7835d7602e7fb80214c8521a3c3a46e4ba2770f65a3d90c2b311a26f')throw Error('Source drift');
const target='dastak_support_rebuild_20261021';
function docker(args,input){const r=spawnSync('docker',['--host','unix:///Users/Furqan/.colima/default/docker.sock',...args],{input,encoding:'utf8',maxBuffer:1024*1024});if(r.status)throw Error(r.stderr);return r.stdout;}
const info=JSON.parse(docker(['inspect',target]))[0];
if(info.Image!=='sha256:3866d94d8426927e8db3f1c5d790752292bfbe27b5f1f46e199ae1b7d3c1710b'||Object.keys(info.NetworkSettings.Networks).join()!=='none'||Object.keys(info.HostConfig.PortBindings??{}).length||info.Config.Labels?.['com.dastak.qa']!=='merchant-support-20261021'||info.State.Running)throw Error('Unexpected runtime/state/isolation');
const sql=text=>docker(['exec','-i',target,'psql','-X','-Atq','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],text).trim();
const quote=text=>"'"+text.replaceAll("'","''")+"'";
const tid='b5200000-0000-4000-8000-000000000001';let seeded=false;
docker(['start',target]);
try{
  for(let n=0;n<30;n++){if(!spawnSync('docker',['--host','unix:///Users/Furqan/.colima/default/docker.sock','exec',target,'pg_isready','-U','postgres']).status)break;await new Promise(resolve=>setTimeout(resolve,500));}
  if(sql("select current_setting('cron.launch_active_jobs')='off' and (select count(*) from auth.users)=0 and (select count(*) from private.merchant_support_tickets)=0;")!=='t')throw Error('Dirty or scheduled fixture');
  const history=()=>JSON.parse(sql("select json_agg(json_build_object('name',version||'_'||name||'.sql','sha256',encode(sha256(convert_to(statements[1],'UTF8')),'hex')) order by version) from supabase_migrations.schema_migrations;"));
  deepStrictEqual(history(),rows.slice(0,296));
  const input={operation:'create',ticketId:tid,requestId:'c5200000-0000-4000-8000-000000000001',tokenHash:'a'.repeat(64),category:'OTHER',subject:'Upgrade witness only',message:'Synthetic pre-upgrade ticket; no real customer data.'};
  const call=()=>JSON.parse(sql(`set role service_role;select public.merchant_support_command(null,${quote(JSON.stringify(input))});`));
  const before=call();seeded=true;
  const migration=readFileSync(new URL(rows[296].name,directory),'utf8');
  sql(`begin;set local statement_timeout='10s';\n${migration}\ninsert into supabase_migrations.schema_migrations(version,name,statements) values('20261020203749','merchant_support_request_hardening',array[${quote(migration)}]);commit;`);
  deepStrictEqual(call(),before);deepStrictEqual(history(),rows);
  const result={ok:true,from:296,to:297,existingTicketUnchanged:true,idempotentCreatePreserved:true,historyMatches:true};
  writeFileSync(join(root,'support-upgrade-result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
}finally{
  if(seeded)sql(`delete from private.merchant_support_messages where ticket_id='${tid}';delete from private.merchant_support_tickets where id='${tid}';`);
  const clean=sql("select (select count(*) from auth.users)=0 and (select count(*) from private.merchant_support_tickets)=0 and (select count(*) from cron.job_run_details)=0 and (select count(*) from net.http_request_queue)=0 and (select count(*) from net._http_response)=0;");
  docker(['stop',target]);if(clean!=='t')throw Error('Upgrade fixture hygiene failed');
}
