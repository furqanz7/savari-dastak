// Verify the installed job matches the reviewed migration, and optionally exercise
// exactly one approved bounded retention transaction (not an added cron schedule).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { secureEnvironment,checkedDirectory } from './cron-history-recovery.mjs';
import { LiveSession } from './cron-history-cleanup.mjs';
let stage='initialization';
let session;
try {
  if(!['--inspect','--exercise-approved'].includes(process.argv[2]) || process.argv.length!==4) throw new Error('EXACT_VERIFICATION_MODE_REQUIRED');
  const directory=checkedDirectory(process.argv[3]);
  const migration=fs.readFileSync(new URL('../../../Backends/Dastak/supabase/migrations/20261017180844_optimize_successful_cron_history_retention.sql',import.meta.url),'utf8');
  const expected=migration.split('$retention$')[1];
  const environment=secureEnvironment(true);
  if(process.argv[2]==='--exercise-approved') environment.PGOPTIONS='-c statement_timeout=15000 -c lock_timeout=1000';
  session=new LiveSession(environment,120000);
  const job=JSON.parse(await session.query(`BEGIN READ ONLY; SET LOCAL ROLE postgres;
    SELECT jsonb_build_object('job_id',jobid,'name',jobname,'schedule',schedule,'active',active,'role',username,'command',command)
    FROM cron.job WHERE jobname='dastak-successful-cron-history-retention'; ROLLBACK;`));
  if(job.command!==expected || job.schedule!=='15 * * * *' || !job.active || job.role!=='postgres') throw new Error('INSTALLED_RETENTION_MISMATCH');
  const sql=job.command.slice(job.command.indexOf('WITH expired'));
  stage='installed_retention_plan';
  const plan=JSON.parse(await session.query(`BEGIN READ ONLY; SET LOCAL ROLE postgres; EXPLAIN (FORMAT JSON) ${sql} ROLLBACK;`));
  const limits=[];
  function visit(node) {if(node['Node Type']==='Limit') limits.push(node['Plan Rows']);for(const child of node.Plans??[])visit(child);}
  visit(plan[0].Plan);
  if(limits.length!==1 || limits[0]>3000) throw new Error('RETENTION_PLAN_BOUND_MISMATCH');
  const result={verified_at:new Date().toISOString(),job_id:job.job_id,name:job.name,schedule:job.schedule,
    active:job.active,role:job.role,command_sha256:crypto.createHash('sha256').update(job.command).digest('hex'),plan};
  if(process.argv[2]==='--exercise-approved') {
    if(await session.query('SHOW default_transaction_read_only;')!=='off') throw new Error('SERVER_READ_ONLY_STOP');
    stage='one_approved_retention_transaction';
    const start=Date.now();
    const removed=Number(await session.query(`BEGIN; SET LOCAL ROLE postgres; ${job.command} COMMIT;`));
    if(!Number.isSafeInteger(removed) || removed<0 || removed>3000) throw new Error('RETENTION_COUNT_BOUND_MISMATCH');
    result.exercise={removed,duration_ms:Date.now()-start,scheduled_run:false};
  }
  fs.writeFileSync(path.join(directory,'retention-verification.json'),JSON.stringify(result,null,2),{mode:0o600});
  console.log(JSON.stringify({stage:'installed_retention_verified',...result,plan:undefined}));
  await session.close();
} catch(error) {
  if(session) await session.stop();
  console.error(JSON.stringify({stage,success:false,code:/^[A-Z_0-9]+$/.test(error.message)?error.message:'RETENTION_VERIFICATION_STOPPED'}));
  process.exitCode=1;
}
