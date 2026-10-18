// Isolated fixture only: no provider, hosted URL, credentials or real money.
import {mkdtempSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
const directory=mkdtempSync(join(tmpdir(),'dastak-merchant-payout-'));
const data=join(directory,'data');
function run(command,args) {
  const r=spawnSync(command,args,{encoding:'utf8',maxBuffer:3*1024*1024});
  if(r.status!==0) throw new Error(command+' failed: '+(r.stderr||r.stdout));
  return r.stdout;
}
let started=false;
try {
  run('initdb',['-D',data,'-A','trust','--no-locale']);
  run('pg_ctl',['-D',data,'-l',join(directory,'postgres.log'),'-o',"-k "+directory+" -c listen_addresses=''",'-w','start']);started=true;
  const args=['-h',directory,'-d','postgres','-X','-v','ON_ERROR_STOP=1'];
  process.stdout.write(run('psql',[...args,'-f','supabase/tests/merchant_discovery_fixture.sql']));
  for(const [file,name] of [
    ['20260820195404_dastak_v1_wave_1.sql','dastak_v1_api.actor_has_wave1_merchant_permission'],
  ]) {
    const source=readFileSync('supabase/migrations/'+file,'utf8'),start=source.indexOf('create function '+name+'('),end=source.indexOf('$$;',start);
    if(start<0||end<0) throw new Error('Missing original helper');
    process.stdout.write(run('psql',[...args,'-c',source.slice(start,end+3)]));
  }
  process.stdout.write(run('psql',[...args,'-f','supabase/tests/merchant_payout_fixture.sql']));
  const source=readFileSync('supabase/migrations/20260824040000_dastak_v1_royalty_platform_fee.sql','utf8');
  const start=source.indexOf('create function dastak_v1_api.actor_can_manage_royalty_subject('),end=source.indexOf('$$;',start);
  if(start<0||end<0) throw new Error('Missing original royalty helper');
  process.stdout.write(run('psql',[...args,'-c',source.slice(start,end+3)]));
  for(const file of ['supabase/migrations/20261018151210_merchant_payout_review_guards.sql','supabase/tests/merchant_payout_assertions.sql'])
    process.stdout.write(run('psql',[...args,'-f',file]));
  const holder=spawn('psql',[...args,'-qAt','-c',`begin;
    select pg_advisory_xact_lock(hashtextextended('dastak-v1-payout-destination:MERCHANT_ORGANIZATION:95000000-0000-4000-8000-000000000001',0));
    update dastak_v1.royalty_payout_destinations set version=2;
    select pg_sleep(1); commit;`],{stdio:['ignore','pipe','pipe']});
  const completed=new Promise((resolve,reject)=>holder.once('exit',code=>code===0?resolve():reject(new Error('Lock holder failed'))));
  let locked=false;
  for(let i=0;i<50;i++) {
    const probe=run('psql',[...args,'-qAt','-c',"select pg_try_advisory_xact_lock(hashtextextended('dastak-v1-payout-destination:MERCHANT_ORGANIZATION:95000000-0000-4000-8000-000000000001',0));"]);
    if(probe.trim()==='f'){locked=true;break;}
    await new Promise(resolve=>setTimeout(resolve,20));
  }
  if(!locked) throw new Error('Concurrent lock was not observed');
  const rejected=spawnSync('psql',[...args,'-c',`select public.dastak_v1_request_merchant_royalty_withdrawal_checked(
    '95000000-0000-4000-8000-000000000031','95000000-0000-4000-8000-000000000001',100,'race',
    '95000000-0000-4000-8000-000000000091',1);`],{encoding:'utf8'});
  if(rejected.status===0||!rejected.stderr.includes('REVIEWED_PAYOUT_DESTINATION_CHANGED')) throw new Error('Concurrent destination change was not rejected');
  await completed;
  process.stdout.write(run('psql',[...args,'-c',`do $$begin
    if exists(select 1 from dastak_v1.royalty_withdrawals where idempotency_key='race') then raise exception 'Race reserved money'; end if;
    perform public.dastak_v1_request_merchant_royalty_withdrawal_checked('95000000-0000-4000-8000-000000000031',
      '95000000-0000-4000-8000-000000000001',100,'first','95000000-0000-4000-8000-000000000091',1);
    if (select count(*) from dastak_v1.royalty_withdrawals)<>1 then raise exception 'Replay duplicated delegate'; end if;
  end $$;`]));
  process.stdout.write('Merchant payout guards passed: authorization, reviewed destination, replay, grants and concurrent destination change.\n');
} finally {
  if(started) run('pg_ctl',['-D',data,'-m','fast','-w','stop']);
  process.stdout.write('Stopped local-only fixture; diagnostics retained at '+directory+'\n');
}
