// Protected recovery preparation ONLY. This helper cannot delete production rows.
// Archive payload/key material must never be printed or checked into this repository.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import cp from 'node:child_process';
import { Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import zlib from 'node:zlib';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';

const workspace = '/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci';
const recoveryBase = '/Users/Furqan/Library/Application Support/Dastak/Recovery';
const certificate = '/Users/Furqan/Downloads/prod-ca-2021.crt';
const projectRef = 'zmtsolkfxlrxepshnjdf';
const columns = ['jobid', 'runid', 'job_pid', 'database', 'username', 'command',
  'status', 'return_message', 'start_time', 'end_time'];
let stage = 'initialization';

function command(name, args, options = {}) {
  const result = cp.spawnSync(name, args, {
    encoding: 'utf8', timeout: 20000, maxBuffer: 4 * 1024 * 1024,
    input: '', cwd: workspace, ...options,
  });
  // Never include child stdout/stderr or the full error in a thrown message.
  if (result.status !== 0) throw new Error('CHILD_COMMAND_FAILED');
  return result.stdout;
}

function secureEnvironment(useSessionPooler = false) {
  const script = command('supabase', ['--workdir', 'Backends/Dastak', 'db', 'dump',
    '--linked', '--dry-run', '--schema', 'cron']);
  const connection = {};
  for (const match of script.matchAll(/^export\s+(PGHOST|PGPORT|PGUSER|PGPASSWORD|PGDATABASE)=("(?:[^"\\]|\\.)*")\s*$/gm)) {
    connection[match[1]] = JSON.parse(match[2]);
  }
  const cachedPooler = new URL(fs.readFileSync(path.join(workspace,
    'Backends/Dastak/supabase/.temp/pooler-url'), 'utf8').trim());
  const directTarget = connection.PGHOST === `db.${projectRef}.supabase.co`;
  const sessionTarget = connection.PGHOST === cachedPooler.hostname
    && connection.PGPORT === '5432' && connection.PGUSER.endsWith(`.${projectRef}`);
  if (Object.keys(connection).length !== 5 || (!directTarget && !sessionTarget)) {
    throw new Error('UNEXPECTED_CONNECTION_TARGET');
  }
  let rootCertificate = certificate;
  if (useSessionPooler) {
    const pooler = new URL(fs.readFileSync(path.join(workspace,
      'Backends/Dastak/supabase/.temp/pooler-url'), 'utf8').trim());
    if (!pooler.hostname.endsWith('.pooler.supabase.com') || pooler.port !== '5432'
      || !pooler.username.endsWith(`.${projectRef}`) || pooler.password) {
      throw new Error('UNEXPECTED_SESSION_POOLER_TARGET');
    }
    connection.PGHOST = pooler.hostname;
    connection.PGPORT = pooler.port;
    if (!connection.PGUSER.endsWith(`.${projectRef}`)) connection.PGUSER += `.${projectRef}`;
    // Trust only the downloaded provider CA and existing system roots; never disable verification.
    rootCertificate = path.join(recoveryBase, 'supabase-ca-bundle.pem');
    fs.writeFileSync(rootCertificate, Buffer.concat([fs.readFileSync(certificate),
      Buffer.from('\n'), fs.readFileSync('/opt/homebrew/etc/openssl@3/cert.pem')]), { mode: 0o600 });
  }
  return { ...process.env, ...connection, PGSSLMODE: 'verify-full',
    PGSSLROOTCERT: rootCertificate, PGCONNECT_TIMEOUT: '10',
    PGAPPNAME: 'dastak-approved-history-recovery',
    PGOPTIONS: '-c default_transaction_read_only=on -c statement_timeout=120000' };
}

async function digest(file) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}

function keyFromKeychain(service) {
  if (!/^Dastak\.CronHistoryRecovery\.[a-f0-9-]+$/.test(service)) throw new Error('INVALID_KEY_REFERENCE');
  const key = command('security', ['find-generic-password', '-a', 'dastak-recovery', '-s', service, '-w']).trim();
  if (!/^[a-f0-9]{64}$/.test(key)) throw new Error('INVALID_ARCHIVE_KEY');
  return Buffer.from(key, 'hex');
}

function saveKey(service, key) {
  // security interactive mode takes the generated key through stdin, not process arguments.
  command('security', ['-i'], {
    input: `add-generic-password -a dastak-recovery -s ${service} -w ${key.toString('hex')}\n`,
  });
  if (!crypto.timingSafeEqual(key, keyFromKeychain(service))) throw new Error('KEYCHAIN_ROUNDTRIP_FAILED');
}

function childExit(child, timeoutMs) {
  let timer;
  let errors = '';
  let deadlineExceeded = false;
  let hardStop;
  const done = new Promise((resolve, reject) => {
    child.on('error', () => reject(new Error('CHILD_START_FAILED')));
    child.on('close', code => {
      clearTimeout(timer);
      clearTimeout(hardStop);
      const sqlstate = errors.match(/(?:ERROR|FATAL):\s+([0-9A-Z]{5})(?:\s|$)/)?.[1];
      if (code === 0) resolve(); else reject(new Error(deadlineExceeded
        ? 'CLIENT_TIME_BUDGET_EXCEEDED' : /statement timeout/i.test(errors)
        ? 'QUERY_TIME_BUDGET_EXCEEDED' : /certificate/i.test(errors)
          ? 'TLS_CERTIFICATE_REJECTED' : /permission denied/i.test(errors)
            ? 'QUERY_ROLE_PERMISSION_DENIED' : sqlstate ? `SQLSTATE_${sqlstate}` : 'CHILD_STREAM_FAILED'));
    });
    timer = setTimeout(() => {
      deadlineExceeded = true;
      child.kill('SIGTERM');
      hardStop = setTimeout(() => child.kill('SIGKILL'), 5000);
    }, timeoutMs);
  });
  // Ensure an early child exit cannot become an unhandled rejection during streaming.
  done.catch(() => {});
  child.stderr.on('data', chunk => { if (errors.length < 4096) errors += chunk.toString(); });
  return done;
}

function checkedDirectory(directory) {
  const resolved = fs.realpathSync(directory);
  if (!resolved.startsWith(`${recoveryBase}/cron-history-`)) throw new Error('UNSAFE_RECOVERY_DIRECTORY');
  if ((fs.statSync(resolved).mode & 0o077) !== 0) throw new Error('RECOVERY_DIRECTORY_NOT_PRIVATE');
  return resolved;
}

async function exportArchive(useSessionPooler = false) {
  stage = 'local_safety_checks';
  if (!command('fdesetup', ['status']).includes('FileVault is On')) throw new Error('FILEVAULT_REQUIRED');
  if (fs.readFileSync(path.join(workspace, 'Backends/Dastak/supabase/.temp/project-ref'), 'utf8').trim() !== projectRef) {
    throw new Error('LINKED_PROJECT_MISMATCH');
  }
  fs.mkdirSync(recoveryBase, { recursive: true, mode: 0o700 });
  const directory = fs.mkdtempSync(path.join(recoveryBase, 'cron-history-'));
  fs.chmodSync(directory, 0o700);
  const keyService = `Dastak.CronHistoryRecovery.${crypto.randomUUID()}`;
  const key = crypto.randomBytes(32);
  stage = 'keychain_recovery_key';
  saveKey(keyService, key);
  const nonce = crypto.randomBytes(12);
  fs.writeFileSync(path.join(directory, 'preparation.json'), JSON.stringify({
    project_ref: projectRef, complete: false, keychain_service: keyService,
    iv_hex: nonce.toString('hex'), created_at: new Date().toISOString(),
  }, null, 2), { flag: 'wx', mode: 0o600 });
  const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);
  stage = 'verified_tls_readonly_export';
  const environment = secureEnvironment(useSessionPooler);
  const child = cp.spawn('psql', ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1'],
    { env: environment, stdio: ['pipe', 'pipe', 'pipe'] });
  const exit = childExit(child, 150000);
  let firstLine = Buffer.alloc(0);
  let snapshot;
  const splitMetadata = new Transform({
    transform(chunk, _encoding, callback) {
      if (snapshot) return callback(null, chunk);
      firstLine = Buffer.concat([firstLine, chunk]);
      const end = firstLine.indexOf(10);
      if (end < 0) {
        if (firstLine.length > 16384) return callback(new Error('SNAPSHOT_METADATA_MISSING'));
        return callback();
      }
      try {
        snapshot = JSON.parse(firstLine.subarray(0, end).toString('utf8'));
        if (snapshot.project_ref !== projectRef || !Number.isSafeInteger(snapshot.candidate_rows)
          || snapshot.candidate_rows <= 0 || !Number.isSafeInteger(snapshot.high_water_runid)) {
          throw new Error('INVALID_SNAPSHOT');
        }
        callback(null, firstLine.subarray(end + 1));
        firstLine = Buffer.alloc(0);
      } catch { callback(new Error('INVALID_SNAPSHOT')); }
    },
  });
  const partial = path.join(directory, 'successful-history.csv.gz.gcm.partial');
  const quotedColumns = columns.map(column => `h."${column}"`).join(', ');
  child.stdin.end(`BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL ROLE postgres;
SET LOCAL timezone = 'UTC';
SET LOCAL datestyle = 'ISO, YMD';
SELECT to_char(transaction_timestamp() - interval '3 days', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS cutoff,
  coalesce(max(runid),0) AS highwater FROM cron.job_run_details \\gset snapshot_
SELECT json_build_object('project_ref','${projectRef}', 'snapshot_at', transaction_timestamp(),
  'cutoff_utc', :'snapshot_cutoff', 'high_water_runid', :snapshot_highwater,
  'candidate_rows', count(*))
FROM cron.job_run_details WHERE status='succeeded' AND end_time < :'snapshot_cutoff'::timestamptz
  AND runid <= :snapshot_highwater;
COPY (SELECT ${quotedColumns}, md5(to_jsonb(h)::text) AS recovery_fingerprint
  FROM cron.job_run_details AS h WHERE status='succeeded'
    AND end_time < :'snapshot_cutoff'::timestamptz AND runid <= :snapshot_highwater
  ORDER BY runid) TO STDOUT WITH (FORMAT csv, HEADER true);
ROLLBACK;
`);
  try {
    await pipeline(child.stdout, splitMetadata, zlib.createGzip({ level: 6 }), cipher,
      fs.createWriteStream(partial, { flags: 'wx', mode: 0o600 }));
    await exit;
  } catch {
    child.kill('SIGTERM');
    try { await exit; } catch (error) { throw error; }
    throw new Error('ARCHIVE_EXPORT_INCOMPLETE');
  }
  if (!snapshot) throw new Error('SNAPSHOT_METADATA_MISSING');
  const archive = path.join(directory, 'successful-history.csv.gz.gcm');
  fs.renameSync(partial, archive);
  const receipt = { ...snapshot, format: 'csv+gzip+aes-256-gcm', columns,
    iv_hex: nonce.toString('hex'), tag_hex: cipher.getAuthTag().toString('hex'),
    keychain_service: keyService, archive_sha256: await digest(archive),
    encrypted_bytes: fs.statSync(archive).size, restore_verified: false,
    connection_mode: useSessionPooler ? 'verified_tls_session_pooler' : 'verified_tls_direct' };
  fs.writeFileSync(path.join(directory, 'manifest.json'), JSON.stringify(receipt, null, 2), { flag: 'wx', mode: 0o600 });
  key.fill(0);
  console.log(JSON.stringify({ stage: 'archive_export_complete', directory,
    candidate_rows: snapshot.candidate_rows, encrypted_bytes: receipt.encrypted_bytes,
    restore_verified: false }));
}

async function exportChunked() {
  stage = 'chunked_export_safety';
  if (!command('fdesetup', ['status']).includes('FileVault is On')) throw new Error('FILEVAULT_REQUIRED');
  if (fs.readFileSync(path.join(workspace, 'Backends/Dastak/supabase/.temp/project-ref'), 'utf8').trim() !== projectRef) {
    throw new Error('LINKED_PROJECT_MISMATCH');
  }
  fs.mkdirSync(recoveryBase, { recursive: true, mode: 0o700 });
  const directory = fs.mkdtempSync(path.join(recoveryBase, 'cron-history-'));
  fs.chmodSync(directory, 0o700);
  const keyService = `Dastak.CronHistoryRecovery.${crypto.randomUUID()}`;
  const key = crypto.randomBytes(32);
  saveKey(keyService, key);
  const nonce = crypto.randomBytes(12);
  fs.writeFileSync(path.join(directory, 'preparation.json'), JSON.stringify({
    project_ref: projectRef, complete: false, keychain_service: keyService,
    iv_hex: nonce.toString('hex'), created_at: new Date().toISOString(),
  }, null, 2), { flag: 'wx', mode: 0o600 });
  const environment = secureEnvironment(true);
  const child = cp.spawn('psql', ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate'],
    { env: environment, stdio: ['pipe', 'pipe', 'pipe'] });
  const exit = childExit(child, 1200000);
  let buffered = Buffer.alloc(0);
  let pending;
  child.stdout.on('data', chunk => {
    buffered = Buffer.concat([buffered, chunk]);
    if (buffered.length > 32 * 1024 * 1024) {
      pending?.reject(new Error('EXPORT_FRAME_TOO_LARGE'));
      child.kill('SIGTERM'); return;
    }
    if (!pending) return;
    const end = buffered.indexOf(pending.marker);
    if (end < 0) return;
    clearTimeout(pending.timer);
    const body = buffered.subarray(0, end);
    buffered = buffered.subarray(end + pending.marker.length);
    const resolve = pending.resolve;
    pending = undefined;
    resolve(body);
  });
  child.on('close', () => {
    if (pending) {
      clearTimeout(pending.timer);
      pending.reject(new Error('EXPORT_SESSION_CLOSED'));
      pending = undefined;
    }
  });
  const frame = sql => new Promise((resolve, reject) => {
    if (pending) return reject(new Error('EXPORT_FRAME_OVERLAP'));
    const markerText = `RECOVERY_FRAME_${crypto.randomBytes(24).toString('hex')}`;
    const timer = setTimeout(() => {
      reject(new Error('EXPORT_FRAME_TIMEOUT')); child.kill('SIGTERM');
    }, 30000);
    pending = { marker: Buffer.from(markerText + '\n'), timer, resolve, reject };
    child.stdin.write(sql + '\n\\echo ' + markerText + '\n');
  });
  const gzip = zlib.createGzip({ level: 6 });
  const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);
  const partial = path.join(directory, 'successful-history.csv.gz.gcm.partial');
  const writer = pipeline(gzip, cipher, fs.createWriteStream(partial, { flags: 'wx', mode: 0o600 }));
  writer.catch(() => {});
  const write = async bytes => { if (!gzip.write(bytes)) await once(gzip, 'drain'); };
  try {
    stage = 'chunked_snapshot';
    const snapshot = JSON.parse((await frame(String.raw`BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL ROLE postgres;
SET LOCAL timezone='UTC'; SET LOCAL datestyle='ISO,YMD';
SET LOCAL statement_timeout='15s'; SET LOCAL idle_in_transaction_session_timeout='45s';
SELECT to_char(transaction_timestamp()-interval '3 days','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS cutoff,
  coalesce(max(runid),0) AS highwater FROM cron.job_run_details \gset snapshot_
SELECT json_build_object('project_ref','${projectRef}','snapshot_at',transaction_timestamp(),
  'cutoff_utc',:'snapshot_cutoff','high_water_runid',:snapshot_highwater,'candidate_rows',count(*))
FROM cron.job_run_details WHERE status='succeeded' AND end_time < :'snapshot_cutoff'::timestamptz
  AND runid <= :snapshot_highwater;`)).toString().trim());
    if (snapshot.project_ref !== projectRef || !Number.isSafeInteger(snapshot.candidate_rows)
      || snapshot.candidate_rows <= 0 || !Number.isSafeInteger(snapshot.high_water_runid)) throw new Error('INVALID_SNAPSHOT');
    console.log(JSON.stringify({ stage: 'chunked_snapshot_started', directory, candidate_rows: snapshot.candidate_rows }));
    await write(Buffer.from([...columns, 'recovery_fingerprint'].join(',') + '\n'));
    let after = 0;
    let exported = 0;
    let chunks = 0;
    while (true) {
      stage = 'chunked_bounds_query';
      const bounds = JSON.parse((await frame(String.raw`SELECT count(*) AS rows, coalesce(max(runid),0) AS last
FROM (SELECT runid FROM cron.job_run_details WHERE status='succeeded'
  AND end_time < :'snapshot_cutoff'::timestamptz AND runid <= :snapshot_highwater
  AND runid > ${after} ORDER BY runid LIMIT 2000) AS selected \gset chunk_
SELECT json_build_object('rows',:chunk_rows,'last',:chunk_last);`)).toString().trim());
      if (!Number.isSafeInteger(bounds.rows) || bounds.rows < 0 || bounds.rows > 2000) throw new Error('INVALID_CHUNK_BOUND');
      if (bounds.rows === 0) break;
      if (!Number.isSafeInteger(bounds.last) || bounds.last <= after || bounds.last > snapshot.high_water_runid) throw new Error('INVALID_CHUNK_BOUND');
      stage = 'chunked_copy_query';
      const csv = await frame(`COPY (SELECT ${columns.map(c => `h."${c}"`).join(',')},
        md5(to_jsonb(h)::text) AS recovery_fingerprint FROM cron.job_run_details AS h
        WHERE runid > ${after} AND runid <= ${bounds.last} AND status='succeeded'
        AND end_time < :'snapshot_cutoff'::timestamptz ORDER BY runid)
        TO STDOUT WITH (FORMAT csv, HEADER false);`);
      await write(csv);
      after = bounds.last;
      exported += bounds.rows;
      chunks++;
      if (chunks % 25 === 0) console.log(JSON.stringify({ stage: 'chunked_export_progress', exported_rows: exported,
        candidate_rows: snapshot.candidate_rows, encrypted_bytes: fs.statSync(partial).size }));
    }
    if (exported !== snapshot.candidate_rows) throw new Error('EXPORT_COUNT_MISMATCH');
    await frame('ROLLBACK;');
    child.stdin.end();
    await exit;
    gzip.end();
    await writer;
    const archive = path.join(directory, 'successful-history.csv.gz.gcm');
    fs.renameSync(partial, archive);
    const receipt = { ...snapshot, format: 'csv+gzip+aes-256-gcm', columns,
      iv_hex: nonce.toString('hex'), tag_hex: cipher.getAuthTag().toString('hex'), keychain_service: keyService,
      archive_sha256: await digest(archive), encrypted_bytes: fs.statSync(archive).size,
      restore_verified: false, connection_mode: 'verified_tls_session_pooler_chunked', chunks };
    fs.writeFileSync(path.join(directory, 'manifest.json'), JSON.stringify(receipt,null,2), { flag: 'wx', mode: 0o600 });
    console.log(JSON.stringify({ stage: 'archive_export_complete', directory,
      candidate_rows: exported, encrypted_bytes: receipt.encrypted_bytes, restore_verified: false }));
  } catch (error) {
    child.kill('SIGTERM');
    gzip.destroy();
    await writer.catch(() => {});
    try { await exit; } catch (childError) { throw childError; }
    throw error;
  } finally { key.fill(0); }
}

async function verifyArchive(inputDirectory) {
  stage = 'archive_integrity_check';
  const directory = checkedDirectory(inputDirectory);
  const manifestPath = path.join(directory, 'manifest.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const archive = path.join(directory, 'successful-history.csv.gz.gcm');
  if (manifest.project_ref !== projectRef
    || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/.test(manifest.cutoff_utc)
    || !Number.isSafeInteger(manifest.high_water_runid) || manifest.high_water_runid < 0
    || !Number.isSafeInteger(manifest.candidate_rows) || manifest.candidate_rows <= 0
    || await digest(archive) !== manifest.archive_sha256) {
    throw new Error('ARCHIVE_INTEGRITY_MISMATCH');
  }
  // PostgreSQL Unix sockets have a short platform pathname limit. Keep this private,
  // FileVault-protected disposable fixture under a short path, not the archive path.
  const restore = fs.mkdtempSync('/private/tmp/dastak-history-restore-');
  fs.chmodSync(restore, 0o700);
  const data = path.join(restore, 'data');
  const port = '55489';
  let started = false;
  const localEnvironment = { ...process.env, PGOPTIONS: '', PGSSLMODE: 'disable' };
  const psqlArgs = ['-X', '-q', '-A', '-t', '-h', restore, '-p', port, '-U', 'dastak_recovery',
    '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'];
  try {
    stage = 'isolated_restore_setup';
    command('initdb', ['-D', data, '-U', 'dastak_recovery', '--auth-local=trust', '--auth-host=reject', '--no-locale']);
    command('pg_ctl', ['-D', data, '-l', path.join(restore, 'server.log'), '-o',
      `-c listen_addresses='' -c unix_socket_directories='${restore}' -p ${port}`, '-w', 'start']);
    started = true;
    command('psql', [...psqlArgs, '-c', `CREATE TABLE recovery_rows (
      jobid bigint, runid bigint PRIMARY KEY, job_pid integer, "database" text,
      username text, command text, status text, return_message text,
      start_time timestamptz, end_time timestamptz, recovery_fingerprint text NOT NULL);`],
    { env: localEnvironment });
    stage = 'authenticated_decryption_and_local_restore';
    const key = keyFromKeychain(manifest.keychain_service);
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(manifest.iv_hex, 'hex'));
    decipher.setAuthTag(Buffer.from(manifest.tag_hex, 'hex'));
    const child = cp.spawn('psql', [...psqlArgs, '-c',
      'COPY recovery_rows FROM STDIN WITH (FORMAT csv, HEADER true)'],
    { env: localEnvironment, stdio: ['pipe', 'ignore', 'pipe'] });
    const exit = childExit(child, 150000);
    try {
      await pipeline(fs.createReadStream(archive), decipher, zlib.createGunzip(), child.stdin);
      await exit;
    } catch { child.kill('SIGTERM'); throw new Error('ISOLATED_RESTORE_FAILED'); }
    key.fill(0);
    stage = 'restored_row_validation';
    const result = JSON.parse(command('psql', [...psqlArgs, '-c', `SET timezone='UTC'; SET datestyle='ISO,YMD';
      SELECT json_build_object('rows',count(*),'unique_ids',count(DISTINCT runid),
      'invalid_rows',count(*) FILTER (WHERE status IS DISTINCT FROM 'succeeded'
        OR end_time IS NULL OR end_time >= '${manifest.cutoff_utc}'::timestamptz
        OR runid > ${manifest.high_water_runid}),
      'fingerprint_mismatches',count(*) FILTER (WHERE recovery_fingerprint
        IS DISTINCT FROM md5((to_jsonb(r) - 'recovery_fingerprint')::text))) FROM recovery_rows AS r;`],
    { env: localEnvironment, timeout: 60000 }).trim());
    if (result.rows !== manifest.candidate_rows || result.unique_ids !== result.rows
      || result.invalid_rows !== 0 || result.fingerprint_mismatches !== 0) throw new Error('RESTORE_VALIDATION_FAILED');
    stage = 'verified_candidate_manifest';
    // Only typed IDs/change fingerprints leave the isolated restore, never commands/responses.
    const candidates = path.join(directory, 'candidate-ids.csv');
    const candidatePartial = `${candidates}.partial`;
    const candidateChild = cp.spawn('psql', [...psqlArgs, '-c',
      'COPY (SELECT runid,recovery_fingerprint FROM recovery_rows ORDER BY runid) TO STDOUT WITH (FORMAT csv, HEADER false)'],
    { env: localEnvironment, stdio: ['ignore', 'pipe', 'pipe'] });
    const candidateExit = childExit(candidateChild, 60000);
    await pipeline(candidateChild.stdout, fs.createWriteStream(candidatePartial, { flags: 'wx', mode: 0o600 }));
    await candidateExit;
    fs.renameSync(candidatePartial, candidates);
    const receipt = { ...manifest, restore_verified: true, restore_verified_at: new Date().toISOString(),
      restore_result: result, candidate_manifest_sha256: await digest(candidates),
      local_server: command('psql', [...psqlArgs, '-c', 'SHOW server_version;'],
        { env: localEnvironment }).trim() };
    fs.writeFileSync(manifestPath, JSON.stringify(receipt, null, 2), { mode: 0o600 });
    console.log(JSON.stringify({ stage: 'archive_restore_verified', directory, ...result }));
  } finally {
    if (started) command('pg_ctl', ['-D', data, '-m', 'fast', '-w', 'stop']);
    // Exact newly-created fixture directory only; preserve the encrypted recovery archive.
    if (!fs.existsSync(path.join(data, 'postmaster.pid')) && restore.startsWith('/private/tmp/dastak-history-restore-')) {
      fs.rmSync(restore, { recursive: true });
    }
  }
}

export { command, secureEnvironment, digest, checkedDirectory, childExit };

if (process.argv[1] === fileURLToPath(import.meta.url)) try {
  if (process.argv[2] === '--export' && process.argv.length === 3) await exportArchive();
  else if (process.argv[2] === '--export-pooler' && process.argv.length === 3) await exportArchive(true);
  else if (process.argv[2] === '--export-chunked' && process.argv.length === 3) await exportChunked();
  else if (process.argv[2] === '--verify' && process.argv.length === 4) await verifyArchive(process.argv[3]);
  else throw new Error('USE_EXPORT_OR_VERIFY_ONLY');
} catch (error) {
  // Deliberately omit child output, input, credentials and raw record contents.
  console.error(JSON.stringify({ stage, success: false, code: /^[A-Z_0-9]+$/.test(error.message)
    ? error.message : 'RECOVERY_PREPARATION_FAILED', error_type: error.name }));
  process.exitCode = 1;
}
