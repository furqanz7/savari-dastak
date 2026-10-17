// Conditional one-time maintenance of the approved history table only.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { secureEnvironment, checkedDirectory, digest } from './cron-history-recovery.mjs';
import { LiveSession,diskHeadroom } from './cron-history-cleanup.mjs';
const MiB=1024*1024;
let stage='initialization';
async function run(inputDirectory,execute) {
  const directory=checkedDirectory(inputDirectory);
  const manifest=JSON.parse(fs.readFileSync(path.join(directory,'manifest.json'),'utf8'));
  const logs=fs.readFileSync(path.join(directory,'cleanup-receipts.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
  const complete=logs.findLast(x=>x.type==='complete');
  const baseline=logs.find(x=>x.type==='baseline');
  if(!complete || complete.deleted!==manifest.candidate_rows || complete.skipped!==0 || complete.expired_remaining!==0
    || !manifest.restore_verified || await digest(path.join(directory,'successful-history.csv.gz.gcm'))!==manifest.archive_sha256) {
    throw new Error('COMPLETED_VERIFIED_CLEANUP_REQUIRED');
  }
  const environment=secureEnvironment(true);
  environment.PGOPTIONS='-c statement_timeout=15000 -c lock_timeout=1000';
  environment.PGAPPNAME='dastak-approved-history-compaction';
  const session=new LiveSession(environment,180000);
  try {
    if(await session.query('SHOW default_transaction_read_only;')!=='off') throw new Error('SERVER_READ_ONLY_STOP');
    stage='measured_compaction_assessment';
    const observed=JSON.parse(await session.query(`BEGIN READ ONLY; SET LOCAL ROLE postgres;
      SELECT jsonb_build_object('observed_at',now(),'database_bytes',pg_database_size(current_database()),
        'history_bytes',pg_total_relation_size('cron.job_run_details'),
        'index_bytes',pg_indexes_size('cron.job_run_details'),
        'indexes',(SELECT jsonb_agg(indexdef ORDER BY indexname) FROM pg_indexes WHERE schemaname='cron' AND tablename='job_run_details'),
        'toast_bytes',(SELECT CASE WHEN reltoastrelid=0 THEN 0 ELSE pg_total_relation_size(reltoastrelid) END FROM pg_class WHERE oid='cron.job_run_details'::regclass),
        'rows',(SELECT count(*) FROM cron.job_run_details),
        'aligned_tuple_bytes',(SELECT sum(((pg_column_size(h)+7)/8)*8+4) FROM cron.job_run_details h),
        'max_aligned_tuple_bytes',(SELECT max(((pg_column_size(h)+7)/8)*8+4) FROM cron.job_run_details h),
        'failed_rows',(SELECT count(*) FROM cron.job_run_details WHERE status='failed'),
        'active_orders',(SELECT count(*) FROM dastak_v1.orders WHERE status::text IN ('CREATED','MATCHING','FULLY_SECURED','AWAITING_PAYMENT','PAID','PREPARING','PICKUP_IN_PROGRESS','OUT_FOR_DELIVERY')),
        'active_deliveries',(SELECT count(*) FROM dastak_v1.delivery_missions WHERE status::text NOT IN ('DELIVERED','CANCELLED','RECOVERED_RETURNED')),
        'active_returns',(SELECT count(*) FROM dastak_v1.return_missions WHERE status::text NOT IN ('COMPLETED','CANCELLED')),
        'old_snapshots',(SELECT count(*) FROM pg_stat_activity WHERE pid<>pg_backend_pid() AND backend_xmin IS NOT NULL AND xact_start<'${baseline.at}'::timestamptz),
        'slot_xmin_count',(SELECT count(*) FROM pg_replication_slots WHERE xmin IS NOT NULL),
        'replication_lag_bytes',(SELECT coalesce(max(pg_wal_lsn_diff(pg_current_wal_lsn(),restart_lsn)),0) FROM pg_replication_slots),
        'history_waiters',(SELECT count(*) FROM pg_locks WHERE relation='cron.job_run_details'::regclass AND NOT granted),
        'long_cron_runs',(SELECT count(*) FROM cron.job_run_details WHERE end_time IS NULL AND start_time<now()-interval '60 seconds'),
        'wal_bytes',(SELECT sum(size) FROM pg_ls_waldir()),
        'can_maintain',has_table_privilege(current_user,'cron.job_run_details','MAINTAIN'),
        'schedules_hash',(SELECT md5(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text) FROM cron.job j WHERE jobname<>'dastak-successful-cron-history-retention')); ROLLBACK;`));
    const space=await diskHeadroom();
    // New heap holds retained tuples, not the deleted 90% of the old allocation.
    // Account for alignment/line pointers, worst page-tail loss from the largest
    // retained tuple, a freshly measured rebuilt index (or the entire old index
    // allocation if no valid measurement exists), TOAST and 16 MiB layout slack.
    if(observed.max_aligned_tuple_bytes>=4096 || observed.toast_bytes>MiB
      || observed.indexes.length!==1 || !/USING btree \(runid\)$/.test(observed.indexes[0])) throw new Error('UNEXPECTED_ROW_LAYOUT_STOP');
    const heapBound=Math.ceil(observed.aligned_tuple_bytes/(8168-observed.max_aligned_tuple_bytes))*8192;
    let indexBound=observed.index_bytes;
    let measuredCopy;
    const probePath=path.join(directory,'retained-copy-measurement.json');
    if(fs.existsSync(probePath)) {
      const probe=JSON.parse(fs.readFileSync(probePath,'utf8'));
      const growth=observed.rows-probe.rows;
      if(!probe.temporary_copy_removed || growth<0 || growth>5000 || probe.total_bytes<=0
        || Date.now()-Date.parse(probe.observed_at)>15*60000) throw new Error('FRESH_RETAINED_COPY_MEASUREMENT_REQUIRED');
      // Actual PG17 rebuild of this exact one-column unique B-tree, not an
      // estimate from the old mostly-empty 40 MiB index. Add 1 MiB and 64 B per
      // intervening row, plus the separate 16 MiB new-copy/layout slack below.
      indexBound=probe.index_bytes+MiB+Math.ceil(growth*64/8192)*8192;
      measuredCopy=probe;
    }
    const layoutBound=heapBound+indexBound+observed.toast_bytes+16*MiB;
    const copyBound=measuredCopy
      ? Math.ceil(Math.max(layoutBound,measuredCopy.total_bytes*1.25)/(16*MiB))*16*MiB
      : Math.max(128*MiB,Math.ceil(layoutBound/(16*MiB))*16*MiB);
    // Allow twice the new-copy bound for WAL, plus 128 MiB separate workspace/growth reserve.
    const required=copyBound*3+128*MiB;
    const safe=space.avail_bytes>=required && observed.active_orders===0 && observed.active_deliveries===0
      && observed.active_returns===0 && observed.old_snapshots===0 && observed.slot_xmin_count===0
      && observed.replication_lag_bytes<64*MiB && observed.history_waiters===0 && observed.long_cron_runs===0
      && observed.can_maintain && observed.schedules_hash===baseline.schedules_hash;
    const assessment={...observed,space,heap_bound_bytes:heapBound,index_bound_bytes:indexBound,
      retained_copy_measurement:measuredCopy,new_copy_bound_bytes:copyBound,
      required_available_bytes:required,space_margin_bytes:space.avail_bytes-required,safe};
    fs.writeFileSync(path.join(directory,'compaction-assessment.json'),JSON.stringify(assessment,null,2),{mode:0o600});
    console.log(JSON.stringify({stage:'compaction_assessment',...assessment}));
    if(!execute) {await session.close();return;}
    if(!safe) throw new Error('COMPACTION_SAFETY_GATE_STOP');
    if(observed.database_bytes<=450*MiB) {console.log(JSON.stringify({stage:'compaction_unnecessary'}));await session.close();return;}
    stage='single_bounded_table_rewrite';
    // Dedicated session, no BEGIN: VACUUM must not run inside a transaction block.
    await session.query(`SET ROLE postgres;
SET lock_timeout='1s';
SET statement_timeout='60s';
SET maintenance_work_mem='32MB';
VACUUM (FULL, ANALYZE) cron.job_run_details;`,75000);
    stage='physical_reclamation_verification';
    const result=JSON.parse(await session.query(`SELECT jsonb_build_object('observed_at',now(),
      'database_bytes',pg_database_size(current_database()),'history_bytes',pg_total_relation_size('cron.job_run_details'),
      'rows',(SELECT count(*) FROM cron.job_run_details),'failed_rows',(SELECT count(*) FROM cron.job_run_details WHERE status='failed'),
      'schedules_hash',(SELECT md5(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text) FROM cron.job j WHERE jobname<>'dastak-successful-cron-history-retention'));`));
    if(result.history_bytes>=observed.history_bytes || result.rows<observed.rows || result.failed_rows<observed.failed_rows
      || result.schedules_hash!==observed.schedules_hash) throw new Error('COMPACTION_VERIFICATION_STOP');
    fs.writeFileSync(path.join(directory,'compaction-result.json'),JSON.stringify(result,null,2),{mode:0o600});
    console.log(JSON.stringify({stage:'physical_reclamation_complete',...result}));
    await session.close();
  } catch(error) {await session.stop();throw error;}
}
if(process.argv[1]===fileURLToPath(import.meta.url)) try {
  if(!['--assess','--compact-approved'].includes(process.argv[2]) || process.argv.length!==4) throw new Error('EXACT_COMPACTION_MODE_REQUIRED');
  await run(process.argv[3],process.argv[2]==='--compact-approved');
} catch(error) {
  console.error(JSON.stringify({stage,success:false,code:/^[A-Z_0-9]+$/.test(error.message)?error.message:'COMPACTION_STOPPED'}));
  process.exitCode=1;
}
