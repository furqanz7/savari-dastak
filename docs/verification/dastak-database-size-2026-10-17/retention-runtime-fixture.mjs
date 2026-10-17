// Synthetic local-only regression test for the migration and initial-delete guard.
import fs from 'node:fs';
import path from 'node:path';
import { command } from './cron-history-recovery.mjs';
const root=fs.mkdtempSync('/private/tmp/dastak-retention-runtime-');
const data=path.join(root,'data');
let started=false;
try {
  command('initdb',['-D',data,'-U','retention_fixture','--auth-local=trust','--auth-host=reject','--no-locale']);
  command('pg_ctl',['-D',data,'-l',path.join(root,'server.log'),'-o',`-c listen_addresses='' -c unix_socket_directories='${root}' -p 55488`,'-w','start']);
  started=true;
  const migration=fs.readFileSync(new URL('../../../Backends/Dastak/supabase/migrations/20261017173813_successful_cron_history_retention.sql',import.meta.url),'utf8');
  const correction=fs.readFileSync(new URL('../../../Backends/Dastak/supabase/migrations/20261017180844_optimize_successful_cron_history_retention.sql',import.meta.url),'utf8');
  const sql=String.raw`
\set ON_ERROR_STOP on
BEGIN;
SET timezone='UTC'; SET datestyle='ISO,YMD';
SELECT 1/CASE WHEN inet_server_addr() IS NULL AND current_user='retention_fixture' THEN 1 ELSE 0 END;
CREATE SCHEMA cron;
CREATE TABLE cron.job(jobid bigint GENERATED ALWAYS AS IDENTITY,jobname text UNIQUE,schedule text,command text);
CREATE FUNCTION cron.schedule(text,text,text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE result bigint;
BEGIN INSERT INTO cron.job(jobname,schedule,command) VALUES($1,$2,$3) RETURNING jobid INTO result; RETURN result; END; $$;
CREATE FUNCTION cron.alter_job(bigint,command text) RETURNS void LANGUAGE sql AS $$
 UPDATE cron.job SET command=$2 WHERE jobid=$1; $$;
CREATE TABLE cron.job_run_details(runid bigint PRIMARY KEY,status text,end_time timestamptz,details text);
INSERT INTO cron.job_run_details SELECT i,'succeeded',now()-interval '10 days','synthetic' FROM generate_series(1,8000)i;
INSERT INTO cron.job_run_details VALUES
 (8001,'failed',now()-interval '10 days','failure'),(8002,'running',NULL,'unfinished'),
 (8003,'succeeded',now()-interval '3 days','boundary'),(8004,'succeeded',now(),'recent'),
 (8005,'succeeded',NULL,'no completion'),(8006,'cancelled',now()-interval '10 days','cancelled');
CREATE TABLE recovered AS SELECT runid,md5(to_jsonb(h)::text) AS fingerprint FROM cron.job_run_details h WHERE runid<=2000;
UPDATE cron.job_run_details SET details='changed since backup' WHERE runid=1;
DO $$ DECLARE n integer;
BEGIN
 WITH candidates AS (SELECT * FROM recovered ORDER BY runid LIMIT 2000), removed AS (
 DELETE FROM cron.job_run_details h USING candidates c WHERE h.runid=c.runid AND h.status='succeeded'
 AND h.end_time IS NOT NULL AND h.end_time<now()-interval '3 days' AND h.runid<=8006
 AND md5(to_jsonb(h)::text)=c.fingerprint RETURNING h.runid)
 SELECT count(*) INTO n FROM removed;
 IF n<>1999 THEN RAISE EXCEPTION 'initial deletion/fingerprint regression'; END IF;
END; $$;
${migration}
${correction}
DO $$ DECLARE n integer; job_sql text;
BEGIN
 SELECT command INTO job_sql FROM cron.job WHERE jobname='dastak-successful-cron-history-retention';
 IF (SELECT schedule FROM cron.job)<>'15 * * * *' THEN RAISE EXCEPTION 'schedule regression'; END IF;
 -- PL/pgSQL cannot EXECUTE a multi-statement string with a SELECT destination.
 -- Apply the exact timeout statements separately, then execute the exact CTE body.
 PERFORM set_config('lock_timeout','1s',true); PERFORM set_config('statement_timeout','5s',true);
 job_sql:=substring(job_sql FROM position('WITH expired' IN job_sql));
 EXECUTE job_sql INTO n;
 IF n<>3000 THEN RAISE EXCEPTION 'retention cap regression: %',n; END IF;
 IF (SELECT count(*) FROM cron.job_run_details WHERE runid>=8001)<>6 THEN RAISE EXCEPTION 'protected row regression'; END IF;
 IF (SELECT count(*) FROM cron.job_run_details WHERE status='succeeded' AND end_time<now()-interval '3 days')<>3001
 THEN RAISE EXCEPTION 'unexpected expired remainder'; END IF;
END; $$;
ROLLBACK;
SELECT 'PASS: initial fingerprint guard, retention 3000 cap, failed/unfinished/recent/boundary protection, activation then immutable corrective migration';
`;
  const output=command('psql',['-X','-q','-A','-t','-h',root,'-p','55488','-U','retention_fixture','-d','postgres'],
    {input:sql,env:{...process.env,PGOPTIONS:'',PGSSLMODE:'disable'},timeout:60000});
  console.log(output.trim());
} finally {
  if(started) command('pg_ctl',['-D',data,'-m','fast','-w','stop']);
  if(!fs.existsSync(path.join(data,'postmaster.pid'))) fs.rmSync(root,{recursive:true});
}
