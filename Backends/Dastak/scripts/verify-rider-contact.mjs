import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
const root=new URL('../supabase/',import.meta.url);
if(readFileSync(new URL('.temp/project-ref',root),'utf8').trim()!=='zmtsolkfxlrxepshnjdf')throw Error('Wrong linked project');
const migration=process.argv[2]==='preflight'?readFileSync(new URL('migrations/20261009134004_repair_customer_rider_phone.sql',root),'utf8'):'';
const checks=readFileSync(new URL('tests/database/rider_contact_projection.contract.sql',root),'utf8');
const result=spawnSync('supabase',['db','query','--linked','--workdir',new URL('..',root).pathname,
  `begin; set local lock_timeout='3s'; set local statement_timeout='25s'; ${migration} ${checks} rollback; select 'RIDER_CONTACT_PROJECTION_OK' result;`],{encoding:'utf8',maxBuffer:1024*1024});
process.stdout.write(result.stdout??'');process.stderr.write(result.stderr??'');if(result.error)throw result.error;process.exitCode=result.status??1;
