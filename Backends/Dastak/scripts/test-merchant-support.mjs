// Disposable socket-only database. Never reads project secrets or connects to
// a hosted database. Tests both support migrations, not the entire chain.
import { mkdtempSync, readFileSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { handleMerchantSupport } from '../supabase/functions/merchant-support/handler.ts';

const bin = '/opt/homebrew/opt/postgresql@14/bin';
const root = realpathSync(mkdtempSync('/private/tmp/dastak-support-fixture.'));
if (!root.startsWith('/private/tmp/dastak-support-fixture.')) throw Error('Disposable target required');
const data = join(root, 'data'); const port = '56429';
function run(command, args, input) {
  const result = spawnSync(command, args, { input, encoding: 'utf8', maxBuffer: 5 * 1024 * 1024 });
  if (result.status !== 0) throw Error(result.stderr || result.stdout);
  return result.stdout.trim();
}
const args = ['-X', '-Atq', '-v', 'ON_ERROR_STOP=1', '-h', root, '-p', port, '-U', 'postgres', '-d', 'postgres'];
const sql = input => run(join(bin, 'psql'), args, input);
let assertions = 0;
const check = (value, expected) => { assert.deepEqual(value, expected); assertions++; };
const quote = value => `'${JSON.stringify(value).replaceAll("'", "''")}'::jsonb`;
const admin = '22222222-2222-4222-8222-222222222222';
const other = '33333333-3333-4333-8333-333333333333';
const commandSQL = (input, actor = null) => `set role service_role; select public.merchant_support_command(${actor ? `'${actor}'::uuid` : 'null'},${quote(input)});`;
const call = (input, actor) => JSON.parse(sql(commandSQL(input, actor)));
function rejects(input, error, actor) {
  assert.throws(() => call(input, actor), new RegExp(error)); assertions++;
}
const create = () => ({ operation: 'create', ticketId: randomUUID(), requestId: randomUUID(), tokenHash: 'a'.repeat(64), category: 'ACCESS', subject: 'Store access help', message: 'Cannot access the approved workspace.' });
async function concurrent(input, actor) {
  return await new Promise((resolve, reject) => {
    const child = spawn(join(bin, 'psql'), args, { stdio: ['pipe', 'pipe', 'pipe'] }); let out = ''; let err = '';
    child.stdout.on('data', b => out += b); child.stderr.on('data', b => err += b);
    child.on('error', reject); child.on('close', code => code ? reject(Error(err)) : resolve(JSON.parse(out.trim())));
    child.stdin.end(commandSQL(input, actor));
  });
}
run(join(bin, 'initdb'), ['-D', data, '-U', 'postgres', '-A', 'trust', '--no-locale', '-E', 'UTF8']);
let started = false;
try {
  run(join(bin, 'pg_ctl'), ['-D', data, '-l', join(root, 'postgres.log'), '-o', `-k ${root} -h '' -p ${port} -F`, 'start']); started = true;
  sql(`create role anon; create role authenticated; create role service_role;
    create schema private; create schema auth; create schema dastak_v1; create schema dastak_v1_api;
    create type dastak_v1.admin_role as enum ('SUPERADMIN','EXECUTIVE');
    create table public.accounts(id uuid primary key, account_state text);
    create table auth.users(id uuid primary key,email text);
    create table private.account_memberships(account_id uuid,role text,approved_at timestamptz,suspended_until timestamptz);
    create table dastak_v1.admin_role_assignments(account_id uuid,email_normalized text,role dastak_v1.admin_role);
    insert into public.accounts values('${admin}','ACTIVE'),('${other}','ACTIVE');
    insert into auth.users values('${admin}','admin@sample.invalid'),('${other}','other@sample.invalid');
    insert into private.account_memberships values('${admin}','owner',now(),null);
    insert into dastak_v1.admin_role_assignments values('${admin}','admin@sample.invalid','SUPERADMIN');
    grant usage on schema public,private to service_role;`);
  // Actual authorization helper, with minimal dependency tables rather than a
  // permissive fake is_admin function. No full-chain integration claim.
  const helper = readFileSync(new URL('../supabase/migrations/20260831131307_admin_role_access_control.sql', import.meta.url), 'utf8')
    .match(/create function dastak_v1_api\.admin_role_for_actor\(p_account_id uuid\)[\s\S]*?\$\$;/)?.[0];
  if (!helper) throw Error('Real admin helper not found'); sql(helper);
  sql(readFileSync(new URL('../supabase/migrations/20261020193411_merchant_support_inbox.sql', import.meta.url), 'utf8'));
  sql(readFileSync(new URL('../supabase/migrations/20261020203749_merchant_support_request_hardening.sql', import.meta.url), 'utf8'));
  const input = create(); let ticket = call(input);
  check(ticket.status, 'OPEN'); check(ticket.version, 1); check(ticket.messages.length, 1);
  check(Object.hasOwn(ticket, 'token_hash'), false);
  check(call(input).messages.length, 1);
  rejects({ ...input, message: 'Changed original request' }, 'support_conflict');
  rejects({ ...input, tokenHash: 'b'.repeat(64) }, 'support_not_found');
  rejects({ operation: 'read', ticketId: input.ticketId, tokenHash: 'b'.repeat(64) }, 'support_not_found');
  rejects({ operation: 'read', ticketId: randomUUID(), tokenHash: 'b'.repeat(64) }, 'support_not_found');
  rejects({ operation: 'adminRead', ticketId: input.ticketId }, 'support_forbidden', other);
  rejects({ operation: 'adminList' }, 'support_forbidden');
  check(call({ operation: 'adminList', status: 'OPEN' }, admin).tickets.length, 1);
  const reply = { operation: 'adminReply', ticketId: input.ticketId, requestId: randomUUID(), message: 'Please confirm which sign-in option you used.', status: 'WAITING_ON_MERCHANT', version: 1 };
  ticket = call(reply, admin); check(ticket.status, 'WAITING_ON_MERCHANT'); check(ticket.version, 2);
  check(call(reply, admin).messages.length, 2);
  rejects({ ...reply, message: 'Changed replay contents' }, 'support_conflict', admin);
  rejects({ ...reply, requestId: randomUUID() }, 'support_stale', admin);
  rejects({ ...reply, requestId: randomUUID(), version: 2 }, 'support_forbidden', other);
  sql(`update public.accounts set account_state='SUSPENDED' where id='${admin}';`);
  rejects({ operation: 'adminList' }, 'support_forbidden', admin);
  sql(`update public.accounts set account_state='ACTIVE' where id='${admin}'; update auth.users set email='changed@sample.invalid' where id='${admin}';`);
  rejects({ operation: 'adminList' }, 'support_forbidden', admin);
  sql(`update auth.users set email='admin@sample.invalid' where id='${admin}'; update private.account_memberships set suspended_until=now()+interval '1 hour';`);
  rejects({ operation: 'adminList' }, 'support_forbidden', admin);
  sql(`update private.account_memberships set suspended_until=null;`);
  const publicReply = { operation: 'reply', ticketId: input.ticketId, tokenHash: input.tokenHash, requestId: randomUUID(), version: 2, message: 'I used the Apple sign-in option.' };
  rejects(publicReply, 'support_rate_limited');
  sql(`update private.merchant_support_messages set created_at=now()-interval '1 minute' where side='MERCHANT';`);
  ticket = call(publicReply); check(ticket.status, 'OPEN'); check(ticket.messages.length, 3);
  check(call(publicReply).messages.length, 3);
  const resolve = { ...reply, requestId: randomUUID(), version: 3, status: 'RESOLVED', message: 'Please use the same identity as your application.' };
  ticket = call(resolve, admin); check(ticket.status, 'RESOLVED');
  check(call({ operation: 'adminList', status: 'OPEN' }, admin).tickets.length, 0);
  check(call({ operation: 'adminList', status: 'RESOLVED' }, admin).tickets.length, 1);
  sql(`update private.merchant_support_messages set created_at=now()-interval '1 minute' where side='MERCHANT';`);
  check(call({ ...publicReply, requestId: randomUUID(), version: 4 }).status, 'OPEN');
  // Two concurrent identical requests produce one message and one version step.
  const duplicate = { ...resolve, requestId: randomUUID(), version: 5 };
  // NOWAIT deliberately returns busy rather than queueing. Retry the exact
  // request only after the competing call finishes; there must still be one write.
  const concurrentResults = await Promise.allSettled([concurrent(duplicate, admin), concurrent(duplicate, admin)]);
  const both = concurrentResults.map(result => {
    if (result.status === 'fulfilled') return result.value;
    assert.match(String(result.reason), /support_busy/);
    return call(duplicate, admin);
  });
  check(both.map(t => t.version), [6, 6]);
  check(both.map(t => t.messages.length), [6, 6]);
  for (const role of ['anon', 'authenticated']) {
    assert.throws(() => sql(`set role ${role}; select * from private.merchant_support_tickets;`), /permission denied/); assertions++;
    assert.throws(() => sql(`set role ${role}; select public.merchant_support_command(null,'{}');`), /permission denied/); assertions++;
  }
  assert.throws(() => sql('set role service_role; select * from private.merchant_support_tickets;'), /permission denied/); assertions++;
  check(sql("select bool_and(relrowsecurity) from pg_class where relname in ('merchant_support_tickets','merchant_support_messages');"), 't');
  // Global admission cap and indexed stable page cursor, without real traffic.
  for (let n = 0; n < 29; n++) call(create());
  rejects(create(), 'support_rate_limited');
  sql("update private.merchant_support_tickets set created_at=now()-interval '2 hours';");
  for (let n = 0; n < 12; n++) call(create());
  const page = call({ operation: 'adminList' }, admin); check(page.tickets.length, 41);
  const last = page.tickets[39]; const next = call({ operation: 'adminList', cursorAt: last.updatedAt, cursorId: last.id }, admin);
  check(next.tickets.length, 2); check(page.tickets.slice(0, 40).some(a => next.tickets.some(b => a.id === b.id)), false);
  call({ ...resolve, status: 'OPEN', requestId: randomUUID(), version: 6 }, admin);
  check(call({ operation: 'adminList', status: 'OPEN' }, admin).tickets[0].id, input.ticketId);
  // Message cap independently of admission and cooldown; fixtures only.
  sql(`insert into private.merchant_support_messages(id,ticket_id,side,body,status_after,request_digest)
    select gen_random_uuid(),'${input.ticketId}','SUPPORT','Additional fixture reply','OPEN',sha256('fixture'::bytea)
    from generate_series(1,13);`);
  rejects({ ...resolve, requestId: randomUUID(), version: 7 }, 'support_thread_full', admin);
  sql(`update private.merchant_support_tickets set created_at=now()-interval '2 hours';
    insert into private.merchant_support_tickets(id,token_hash,category,subject,initial_digest,created_at)
    select gen_random_uuid(),repeat('b',64),'OTHER','Daily limit fixture',sha256('fixture'::bytea),now()-interval '2 hours'
    from generate_series(1,58);`);
  check(sql('select count(*) from private.merchant_support_tickets;'), '100'); rejects(create(), 'support_rate_limited');
  sql(`update private.merchant_support_tickets set created_at=now()-interval '2 days';
    insert into private.merchant_support_tickets(id,token_hash,category,subject,initial_digest,created_at)
    select gen_random_uuid(),repeat('b',64),'OTHER','Storage limit fixture',sha256('fixture'::bytea),now()-interval '2 days'
    from generate_series(1,900);`);
  check(sql('select count(*) from private.merchant_support_tickets;'), '1000'); rejects(create(), 'support_rate_limited');
  // The admission cap must not prevent recovery/read of an existing request.
  check(call({ operation: 'read', ticketId: input.ticketId, tokenHash: input.tokenHash }).id, input.ticketId);
  console.log(JSON.stringify({ ok: true, assertions, fixture: root, scope: 'Both support migrations + actual Admin role helper on minimal dependency schema; socket-only Postgres 14; not full Supabase replay' }));
  if (process.argv.includes('--serve')) {
    // UI fixture starts with a fresh inbox after the bounded-storage tests.
    // This deletes only explicitly disposable sample rows inside this process.
    sql('truncate private.merchant_support_messages,private.merchant_support_tickets;');
    // Test-only credential. It is valid only in this disposable loopback process,
    // not in any Dastak account or production authentication implementation.
    const server = createServer(async (incoming, outgoing) => {
      if (incoming.url !== '/functions/v1/merchant-support') { outgoing.writeHead(404); outgoing.end(); return; }
      try {
        const chunks = []; let size = 0;
        for await (const part of incoming) { size += part.length; if (size > 12_000) { outgoing.writeHead(413); outgoing.end(); return; } chunks.push(part); }
        const request = new Request('http://127.0.0.1:56430/functions/v1/merchant-support', {
          method: incoming.method, headers: incoming.headers,
          ...(incoming.method === 'POST' ? { body: Buffer.concat(chunks) } : {}),
        });
        const result = await handleMerchantSupport(request, { enabled: true,
          authenticate: async bearer => { if (bearer !== 'Bearer local-fixture-admin') throw Error('No fixture access'); return { accountId: admin }; },
          command: async (actor, input) => call(input, actor),
        });
        outgoing.writeHead(result.status, Object.fromEntries(result.headers)); outgoing.end(await result.text());
      } catch { outgoing.writeHead(503); outgoing.end('{}'); }
    });
    await new Promise(resolve => server.listen(56430, '127.0.0.1', resolve));
    console.log('Disposable Merchant help fixture on http://127.0.0.1:56430; local-only sample data');
    await new Promise(resolve => { const stop = () => server.close(resolve); process.once('SIGTERM', stop); process.once('SIGINT', stop); });
  }
} finally {
  if (started) run(join(bin, 'pg_ctl'), ['-D', data, '-m', 'fast', 'stop']);
  // Retain small fixture/logs for inspection; do not perform recursive cleanup.
}
