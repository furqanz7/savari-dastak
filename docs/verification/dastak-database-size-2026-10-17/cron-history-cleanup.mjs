// Owner-approved initial cleanup ONLY: archived, unchanged successful cron history.
// No business table writes, schedule changes, compaction or privilege changes.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import cp from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';
import { command, secureEnvironment, digest, checkedDirectory, childExit } from './cron-history-recovery.mjs';

const projectRef = 'zmtsolkfxlrxepshnjdf';
let stage = 'initialization';
let lastMetrics;
let serviceKey;
export async function diskHeadroom() {
  if (lastMetrics && Date.now() - lastMetrics.fetched_ms < 60000) return lastMetrics;
  if (!serviceKey) {
    const keys = JSON.parse(command('supabase', ['projects', 'api-keys', '--project-ref', projectRef, '--output', 'json']));
    serviceKey = keys.find(key => key.name === 'service_role')?.api_key;
    if (!serviceKey) throw new Error('EXISTING_METRICS_CREDENTIAL_UNAVAILABLE');
  }
  const response = await fetch(`https://${projectRef}.supabase.co/customer/v1/privileged/metrics`, {
    headers: { Authorization: `Basic ${Buffer.from(`service_role:${serviceKey}`).toString('base64')}` },
    signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) throw new Error('FILESYSTEM_METRICS_UNAVAILABLE');
  const metrics = await response.text();
  const result = {};
  for (const line of metrics.split('\n')) {
    if (!line.startsWith('node_filesystem_') || !/mountpoint="\/data"/.test(line)) continue;
    const match = line.match(/^node_filesystem_(avail_bytes|free_bytes|size_bytes|readonly)\{[^}]+\}\s+([0-9.e+]+)$/);
    if (match) result[match[1]] = Number(match[2]);
  }
  if (!Number.isSafeInteger(result.avail_bytes) || result.avail_bytes <= 0
    || result.readonly !== 0) throw new Error('INVALID_FILESYSTEM_HEADROOM');
  lastMetrics = { ...result, observed_at: new Date().toISOString(), fetched_ms: Date.now() };
  return lastMetrics;
}

export class LiveSession {
  constructor(environment, maxMilliseconds = 1800000) {
    this.child = cp.spawn('psql', ['-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate'],
      { env: environment, stdio: ['pipe','pipe','pipe'] });
    this.exit = childExit(this.child, maxMilliseconds);
    this.buffered = Buffer.alloc(0);
    this.child.stdout.on('data', chunk => {
      this.buffered = Buffer.concat([this.buffered, chunk]);
      if (this.buffered.length > 1024 * 1024) { this.child.kill('SIGTERM'); return; }
      if (!this.pending) return;
      const end = this.buffered.indexOf(this.pending.marker);
      if (end < 0) return;
      clearTimeout(this.pending.timer);
      const body = this.buffered.subarray(0, end).toString().trim();
      this.buffered = this.buffered.subarray(end + this.pending.marker.length);
      const resolve = this.pending.resolve;
      this.pending = undefined;
      resolve(body);
    });
    this.child.on('close', () => {
      if (this.pending) {
        clearTimeout(this.pending.timer);
        const reject = this.pending.reject;
        this.pending = undefined;
        this.exit.then(() => reject(new Error('SESSION_CLOSED_BEFORE_ACKNOWLEDGEMENT')), reject);
      }
    });
  }
  query(sql, budget = 30000) {
    return new Promise((resolve,reject) => {
      if (this.pending || this.child.exitCode !== null) return reject(new Error('SESSION_NOT_READY'));
      const marker = `CLEANUP_${crypto.randomBytes(24).toString('hex')}`;
      const timer = setTimeout(() => { reject(new Error('BOUNDED_QUERY_TIMEOUT')); this.child.kill('SIGTERM'); }, budget);
      this.pending = { marker: Buffer.from(marker+'\n'), resolve, reject, timer };
      this.child.stdin.write(sql+'\n\\echo '+marker+'\n');
    });
  }
  async close() { this.child.stdin.end(); await this.exit; }
  async stop() { this.child.kill('SIGTERM'); await this.exit.catch(() => {}); }
}

const quietQuery = `SELECT jsonb_build_object(
  'active_orders',(SELECT count(*) FROM dastak_v1.orders WHERE status::text IN
    ('CREATED','MATCHING','FULLY_SECURED','AWAITING_PAYMENT','PAID','PREPARING','PICKUP_IN_PROGRESS','OUT_FOR_DELIVERY')),
  'active_deliveries',(SELECT count(*) FROM dastak_v1.delivery_missions WHERE status::text NOT IN ('DELIVERED','CANCELLED','RECOVERED_RETURNED')),
  'active_returns',(SELECT count(*) FROM dastak_v1.return_missions WHERE status::text NOT IN ('COMPLETED','CANCELLED')),
  'wal_bytes',(SELECT coalesce(sum(size),0) FROM pg_ls_waldir()),
  'long_history_locks',(SELECT count(*) FROM pg_locks WHERE relation='cron.job_run_details'::regclass AND NOT granted)
);`;

async function cleanup(inputDirectory) {
  const directory = checkedDirectory(inputDirectory);
  const manifest = JSON.parse(fs.readFileSync(path.join(directory,'manifest.json'),'utf8'));
  const candidates = path.join(directory,'candidate-ids.csv');
  if (manifest.project_ref !== projectRef || manifest.restore_verified !== true
    || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/.test(manifest.cutoff_utc)
    || !Number.isSafeInteger(manifest.high_water_runid)
    || await digest(candidates) !== manifest.candidate_manifest_sha256
    || await digest(path.join(directory,'successful-history.csv.gz.gcm')) !== manifest.archive_sha256) {
    throw new Error('VERIFIED_RECOVERY_REQUIRED');
  }
  const lines = fs.readFileSync(candidates,'utf8').trim().split('\n');
  let previous = 0;
  for (const line of lines) {
    const match = line.match(/^([1-9][0-9]*),([a-f0-9]{32})$/);
    const id = Number(match?.[1]);
    if (!match || !Number.isSafeInteger(id) || id <= previous || id > manifest.high_water_runid) throw new Error('INVALID_CANDIDATE_MANIFEST');
    previous = id;
  }
  if (lines.length !== manifest.candidate_rows) throw new Error('CANDIDATE_COUNT_MISMATCH');
  const log = path.join(directory,'cleanup-receipts.jsonl');
  if (fs.existsSync(log)) throw new Error('PRIOR_EXECUTION_REQUIRES_RECONCILIATION');
  const receipt = value => fs.appendFileSync(log, JSON.stringify({at:new Date().toISOString(),...value})+'\n',{mode:0o600});
  stage = 'fresh_production_preflight';
  const environment = secureEnvironment(true);
  // Remove only this helper's client-side read-only guard. Never override server/account read-only restrictions.
  environment.PGOPTIONS = '-c statement_timeout=5000 -c lock_timeout=1000';
  environment.PGAPPNAME = 'dastak-approved-bounded-history-cleanup';
  const session = new LiveSession(environment);
  try {
    const mode = await session.query('SHOW default_transaction_read_only;');
    if (mode !== 'off') throw new Error('SERVER_READ_ONLY_STOP');
    const baseline = JSON.parse(await session.query(`BEGIN READ ONLY; SET LOCAL ROLE postgres;
      SET LOCAL statement_timeout='15s';
      SELECT jsonb_build_object('database_bytes',pg_database_size(current_database()),
        'history_bytes',pg_total_relation_size('cron.job_run_details'),
        'failed_rows',(SELECT count(*) FROM cron.job_run_details WHERE status='failed'),
        'schedules_hash',(SELECT md5(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text) FROM cron.job j),
        'schedule_count',(SELECT count(*) FROM cron.job),
        'can_delete',has_table_privilege(current_user,'cron.job_run_details','DELETE'),
        'bypass_rls',(SELECT rolbypassrls FROM pg_roles WHERE rolname=current_user),
        'dependencies',(SELECT count(*) FROM pg_constraint WHERE contype='f' AND confrelid='cron.job_run_details'::regclass)
          +(SELECT count(*) FROM pg_trigger WHERE tgrelid='cron.job_run_details'::regclass)); ROLLBACK;`));
    if (baseline.schedule_count !== 11 || !baseline.can_delete || !baseline.bypass_rls || baseline.dependencies !== 0) throw new Error('PREFLIGHT_DRIFT_STOP');
    const space = await diskHeadroom();
    if (space.avail_bytes < 450 * 1024 * 1024) throw new Error('INITIAL_DISK_RESERVE_STOP');
    let safety = JSON.parse(await session.query(`BEGIN READ ONLY; SET LOCAL ROLE postgres; ${quietQuery} ROLLBACK;`));
    const safetyBaselineWal = safety.wal_bytes;
    const safe = check => check.active_orders===0 && check.active_deliveries===0 && check.active_returns===0 && check.long_history_locks===0;
    if (!safe(safety)) throw new Error('QUIET_WINDOW_REQUIRED');
    receipt({type:'baseline',...baseline,space,safety,cutoff_utc:manifest.cutoff_utc,high_water_runid:manifest.high_water_runid,archive_sha256:manifest.archive_sha256});
    const valuesFor = batch => batch.map(line=>{const [id,fingerprint]=line.split(','); return `(${id}::bigint,'${fingerprint}'::text)`;}).join(',');
    const deletion = batch => `WITH candidates(runid,fingerprint) AS (VALUES ${valuesFor(batch)}),
      removed AS (DELETE FROM cron.job_run_details h USING candidates c WHERE h.runid=c.runid
        AND h.status='succeeded' AND h.end_time IS NOT NULL
        AND h.end_time < '${manifest.cutoff_utc}'::timestamptz AND h.runid <= ${manifest.high_water_runid}
        AND md5(to_jsonb(h)::text)=c.fingerprint RETURNING h.runid)
      SELECT jsonb_build_object('deleted',count(*)) FROM removed`;
    const explain = JSON.parse(await session.query(`BEGIN READ ONLY; SET LOCAL ROLE postgres;
      SET LOCAL timezone='UTC'; SET LOCAL datestyle='ISO,YMD';
      EXPLAIN (FORMAT JSON) ${deletion(lines.slice(0,2000))}; ROLLBACK;`));
    const planText = JSON.stringify(explain);
    if (planText.includes('Seq Scan') || !planText.includes('job_run_details_pkey')) throw new Error('BOUNDED_INDEX_PLAN_REQUIRED');
    receipt({type:'query_plan',plan:explain});
    let deleted = 0;
    let batches = 0;
    for (let offset=0;offset<lines.length;offset+=2000) {
      if (batches % 25 === 0) {
        safety = JSON.parse(await session.query(`BEGIN READ ONLY; SET LOCAL ROLE postgres; ${quietQuery} ROLLBACK;`));
        const currentSpace = await diskHeadroom();
        receipt({type:'safety',batches,...safety,space:currentSpace});
        if (!safe(safety) || currentSpace.avail_bytes < 300*1024*1024
          || safety.wal_bytes > safetyBaselineWal + 192*1024*1024) throw new Error('LIVE_SAFETY_RESERVE_STOP');
      }
      const batch = lines.slice(offset,offset+2000);
      receipt({type:'attempt',batch:batches,offset,rows:batch.length,first_runid:Number(batch[0].split(',')[0]),last_runid:Number(batch.at(-1).split(',')[0])});
      stage = 'bounded_delete_transaction';
      const result = JSON.parse(await session.query(`BEGIN; SET LOCAL ROLE postgres;
        SET LOCAL timezone='UTC'; SET LOCAL datestyle='ISO,YMD'; SET LOCAL lock_timeout='1s'; SET LOCAL statement_timeout='5s';
        ${deletion(batch)}; COMMIT;`));
      if (!Number.isSafeInteger(result.deleted) || result.deleted<0 || result.deleted>batch.length) throw new Error('INVALID_DELETE_RECEIPT');
      deleted += result.deleted;
      receipt({type:'committed',batch:batches,attempted:batch.length,deleted:result.deleted,skipped:batch.length-result.deleted});
      batches++;
      if (batches%25===0) console.log(JSON.stringify({stage:'cleanup_progress',processed:offset+batch.length,deleted,batches}));
      await delay(30);
    }
    stage = 'post_cleanup_verification';
    const final = JSON.parse(await session.query(`BEGIN READ ONLY; SET LOCAL ROLE postgres; SET LOCAL statement_timeout='15s';
      SELECT jsonb_build_object('database_bytes',pg_database_size(current_database()),'history_bytes',pg_total_relation_size('cron.job_run_details'),
        'failed_rows',(SELECT count(*) FROM cron.job_run_details WHERE status='failed'),
        'expired_remaining',(SELECT count(*) FROM cron.job_run_details WHERE status='succeeded' AND end_time<'${manifest.cutoff_utc}'::timestamptz AND runid<=${manifest.high_water_runid}),
        'schedules_hash',(SELECT md5(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text) FROM cron.job j)); ROLLBACK;`));
    if (final.failed_rows < baseline.failed_rows || final.schedules_hash !== baseline.schedules_hash) throw new Error('POST_CLEANUP_DRIFT_STOP');
    receipt({type:'complete',candidate_rows:lines.length,deleted,skipped:lines.length-deleted,batches,...final});
    console.log(JSON.stringify({stage:'initial_cleanup_complete',candidate_rows:lines.length,deleted,skipped:lines.length-deleted,...final}));
    await session.close();
  } catch(error) { await session.stop(); throw error; }
}

async function verifyCompleted(inputDirectory) {
  stage='verify_acknowledged_cleanup_only';
  const directory=checkedDirectory(inputDirectory);
  const manifest=JSON.parse(fs.readFileSync(path.join(directory,'manifest.json'),'utf8'));
  const log=path.join(directory,'cleanup-receipts.jsonl');
  const records=fs.readFileSync(log,'utf8').trim().split('\n').map(JSON.parse);
  const baseline=records.find(x=>x.type==='baseline');
  const attempts=records.filter(x=>x.type==='attempt');
  const commits=records.filter(x=>x.type==='committed');
  if(!baseline || attempts.length!==commits.length || !manifest.restore_verified
    || await digest(path.join(directory,'successful-history.csv.gz.gcm'))!==manifest.archive_sha256
    || await digest(path.join(directory,'candidate-ids.csv'))!==manifest.candidate_manifest_sha256
    || commits.some((c,i)=>c.batch!==i || attempts[i].batch!==i || c.attempted!==attempts[i].rows || c.skipped!==0 || c.deleted!==c.attempted)
    || commits.reduce((n,c)=>n+c.deleted,0)!==manifest.candidate_rows) throw new Error('ACKNOWLEDGED_COMPLETE_BATCHES_REQUIRED');
  const session=new LiveSession(secureEnvironment(true),90000);
  try {
    // One pass instead of multiple scans of the still-large physical allocation.
    const counts=JSON.parse(await session.query(`BEGIN READ ONLY; SET LOCAL ROLE postgres;
      SET LOCAL statement_timeout='25s';
      SELECT jsonb_build_object('rows',count(*),'failed_rows',count(*) FILTER(WHERE status='failed'),
        'expired_remaining',count(*) FILTER(WHERE status='succeeded' AND end_time<'${manifest.cutoff_utc}'::timestamptz AND runid<=${manifest.high_water_runid}))
        FROM cron.job_run_details; ROLLBACK;`));
    const metadata=JSON.parse(await session.query(`BEGIN READ ONLY; SET LOCAL ROLE postgres;
      SELECT jsonb_build_object('database_bytes',pg_database_size(current_database()),'history_bytes',pg_total_relation_size('cron.job_run_details'),
        'schedules_hash',(SELECT md5(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text) FROM cron.job j)); ROLLBACK;`));
    if(counts.expired_remaining!==0 || counts.failed_rows<baseline.failed_rows || metadata.schedules_hash!==baseline.schedules_hash) throw new Error('POST_CLEANUP_DRIFT_STOP');
    const receipt={at:new Date().toISOString(),type:'complete',candidate_rows:manifest.candidate_rows,
      deleted:manifest.candidate_rows,skipped:0,batches:commits.length,...counts,...metadata};
    fs.appendFileSync(log,JSON.stringify(receipt)+'\n',{mode:0o600});
    console.log(JSON.stringify({stage:'initial_cleanup_verified',...receipt}));
    await session.close();
  } catch(error) {await session.stop();throw error;}
}

if (process.argv[1]?.endsWith('/cron-history-cleanup.mjs')) {
  try {
    if (process.argv[2] === '--disk-only') console.log(JSON.stringify(await diskHeadroom()));
    else if (process.argv[2] === '--execute-approved' && process.argv.length === 4) await cleanup(process.argv[3]);
    else if (process.argv[2] === '--verify-completed' && process.argv.length === 4) await verifyCompleted(process.argv[3]);
    else throw new Error('EXACT_APPROVED_MODE_REQUIRED');
  } catch(error) {
    console.error(JSON.stringify({stage,success:false,code:/^[A-Z_0-9]+$/.test(error.message)?error.message:'SCOPED_CLEANUP_STOPPED'}));
    process.exitCode=1;
  }
}
