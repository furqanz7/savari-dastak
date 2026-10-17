// Disposable, transaction-rolled-back capacity probe. Never replace/recreate the
// extension table. Only aggregate sizes leave the temporary server-side copy.
import fs from 'node:fs';
import path from 'node:path';
import { checkedDirectory,secureEnvironment } from './cron-history-recovery.mjs';
import { LiveSession,diskHeadroom } from './cron-history-cleanup.mjs';
let session;
let stage='initialization';
try {
  if(process.argv.length!==3) throw new Error('RECOVERY_DIRECTORY_REQUIRED');
  const directory=checkedDirectory(process.argv[2]);
  const completion=fs.readFileSync(path.join(directory,'cleanup-receipts.jsonl'),'utf8').trim().split('\n').map(JSON.parse).findLast(x=>x.type==='complete');
  if(!completion || completion.skipped!==0 || completion.expired_remaining!==0) throw new Error('COMPLETED_CLEANUP_REQUIRED');
  const space=await diskHeadroom();
  // Retained tuple/old-index metadata already bounds the probe below 128 MiB.
  // Require another 128 MiB reserve; TEMP copy/index data are not WAL-logged.
  if(space.avail_bytes<256*1024*1024) throw new Error('TEMPORARY_PROBE_RESERVE_STOP');
  const environment=secureEnvironment(true);
  environment.PGOPTIONS='-c statement_timeout=25000 -c lock_timeout=1000';
  environment.PGAPPNAME='dastak-retained-history-capacity-probe';
  session=new LiveSession(environment,90000);
  if(await session.query('SHOW default_transaction_read_only;')!=='off') throw new Error('SERVER_READ_ONLY_STOP');
  stage='rolled_back_retained_copy_measurement';
  const result=JSON.parse(await session.query(`BEGIN; SET LOCAL ROLE postgres;
    SET LOCAL maintenance_work_mem='32MB';
    CREATE TEMP TABLE dastak_retained_history_probe ON COMMIT DROP AS TABLE cron.job_run_details;
    CREATE UNIQUE INDEX ON dastak_retained_history_probe(runid);
    SELECT jsonb_build_object('observed_at',now(),'rows',(SELECT count(*) FROM dastak_retained_history_probe),
      'heap_bytes',pg_relation_size('dastak_retained_history_probe'),
      'index_bytes',pg_indexes_size('dastak_retained_history_probe'),
      'total_bytes',pg_total_relation_size('dastak_retained_history_probe'));
    ROLLBACK;`));
  const removed=await session.query("SELECT to_regclass('pg_temp.dastak_retained_history_probe') IS NULL;");
  if(removed!=='t') throw new Error('TEMPORARY_PROBE_REMOVAL_NOT_VERIFIED');
  result.temporary_copy_removed=true;
  fs.writeFileSync(path.join(directory,'retained-copy-measurement.json'),JSON.stringify(result,null,2),{mode:0o600});
  console.log(JSON.stringify({stage:'retained_copy_measured_and_removed',...result}));
  await session.close();
} catch(error) {
  if(session) await session.stop();
  console.error(JSON.stringify({stage,success:false,code:/^[A-Z_0-9]+$/.test(error.message)?error.message:'TEMPORARY_CAPACITY_PROBE_STOPPED'}));
  process.exitCode=1;
}
