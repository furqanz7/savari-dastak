# Merchant support: local request and locking hardening

21 October 2026. **Local hardening record.** Subsequently deployed and enabled
with separate owner approval; see [production activation](activation/README.md).
The original scope and verification boundaries below describe the local slice.

## Approved boundaries and decision

The owner approved local hardening after the endpoint review, then explicitly
chose **local safeguards only**, no external bot provider, and **keep the current
storage cap; delete nothing**. No Turnstile integration, external account, paid
service, IP collection, secret change, production mutation, push/commit, Apple
change, retention job or real-ticket deletion was performed.

Worktree `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch
`codex/dastak-v1-launch`, HEAD
`61f51b7bcf691370c121e977b95b050311988267` unchanged. No native binary changed.

## Corrections

1. **Bounded request ingestion.** Actual streamed bytes still stop at 12KB;
   incomplete bodies now have a 3-second application deadline. Cancellation does
   not wait indefinitely for an underlying stream's cancel promise. Invalid
   bodies fail before any database command.
2. **Bounded backend dependencies.** Admin identity/session verification has a
   3.5-second deadline, and the database command has a 6-second deadline. The
   signal is propagated into the actual auth, revocation and RPC HTTP requests;
   the RPC transport combines rather than replaces the caller's abort signal.
   The existing browser deadline remains 15 seconds. A timeout remains an
   uncertain outcome, not invented success or permission to replay a new action.
   Auth timeouts return unavailable, not a false sign-in-expired diagnosis.
3. **Unsupported text rejected consistently.** Browser and Edge reject NUL and
   unpaired UTF-16 surrogates as invalid input before RPC invocation. Normal Urdu,
   multiline text and valid emoji remain supported. The existing UI's definitive
   invalid-input path clears a pending write for editing while preserving text;
   busy/uncertain writes retain their original request IDs/content.
4. **Nonblocking reads and contention.** A new forward migration replaces only
   the private support command. Reads validate the capability without taking a
   tuple write lock. Mutations re-lock with NOWAIT and retain version/digest/
   idempotency checks. Creation uses a nonblocking advisory transaction lock.
   Other lock waits are bounded at 500ms. Contention maps to safe `support_busy`
   responses and explicit same-request retry guidance, not raw SQL output.
5. **Per-worker admission/concurrency guard.** Before body parsing/auth/database
   work, each function worker allows at most 8 active requests, an initial burst
   of 30 and replenishment of 1 request/second. State is fixed-size counters, not
   an unbounded caller map; it stores no IP, identity or recovery code. Leases are
   released on completion/failure/deadline. OPTIONS/method/disabled gates remain
   ahead of this limiter. The actual deployed entrypoint always supplies it.

The shared auth helper's new cancellation option is optional: existing callers
without it retain their prior behavior. OAuth provider restrictions and session
revocation are unchanged and exercised by the tests. No authorization is based
on user metadata, caller-provided actor IDs or the in-memory limiter.

Migration: `20261020203749_merchant_support_request_hardening.sql`, created using
`supabase migration new`. The original support migration and all historical
files are unchanged. The private implementation still has an empty search path;
its existing service-only privileges and security-invoker public wrapper remain.
No ticket/message schema, financial ledger or account lifecycle rule changed.

## Explicit limit of the chosen abuse approach

**This is not distributed per-caller throttling or bot protection.** The in-memory
limiter resets on worker restart and is independent across workers. A determined
caller can still consume the shared 30/hour or 100/day ticket allowance; the
1000-stored-ticket cap can still close new intake until deliberate operator
action. Resolving tickets does not free the storage allowance. Existing private
ticket reads/recovery remain available when new-ticket admission is full, except
for ordinary service outages or the per-worker limiter itself.

Those residual risks are documented rather than described as fixed. They follow
the owner's decision to use local safeguards and retain the cap without a
deletion policy. No provider/privacy/billing setup is pending in this implementation.
Public activation still needs separate authorization with this limitation clear.

Technical references used: PostgreSQL's [row/advisory lock documentation](https://www.postgresql.org/docs/current/explicit-locking.html),
Supabase's [explicit rate-limiting example](https://supabase.com/docs/guides/functions/examples/rate-limiting),
and stream [cancellation semantics](https://developer.mozilla.org/en-US/docs/Web/API/ReadableStreamDefaultReader/cancel).
No external example service was provisioned or invoked.

## Verification

| Check | Verified result |
|---|---|
| Fresh Supabase application-schema replay | 297/297 migrations, stored SQL hashes match source |
| Existing regression suite | 76 files / 2,081 assertions pass |
| Full-schema support suite | 40 assertions pass |
| Fast socket-only PostgreSQL 14 fixture | 48 assertions pass, both support migrations + real Admin helper |
| Entire Edge test suite | 423 tests pass |
| Entire web test suite | 153 files / 1,112 tests pass |
| TypeScript/Vite production build | pass; pre-existing 3D chunk warning remains |
| Type checks, scoped lint/format, Node syntax, git diff check | pass |

The runtime probes held locks in a separate connection and imposed a 150ms SQL
deadline on the competing commands. Wrong capability returned not-found;
authorized read succeeded behind the lock; competing reply and admission returned
busy without reaching that deadline. No unauthorized ticket data was returned.

A separate retained **296-migration** synthetic fixture was upgraded with a ticket
already present. Its entire receipt was identical afterward, original-create
retry still produced one message, and recorded history matched the final 297
source files. The synthetic witness ticket/message were then removed; no real
support data was present or deleted. The fixture refuses repeat application.

Edge regression cases include never-ending body/cancel, never-settling command,
never-settling auth, caller abort, invalid Unicode, valid Urdu/emoji, bulkhead
burst/refill/concurrency, safe busy error, auth/revocation signal propagation,
successful OAuth validation and revoked-session rejection. Test auth HTTP is
mocked; no real OAuth or hosted Supabase request was made. No claim is made about
actual deployed gateways, PostgREST behavior, distributed traffic or production
load. Browser/API/real-Admin deployed smoke verification remains an activation gate.

### Rebuild pin and containment

Final chain SHA-256:
`03003a1c7835d7602e7fb80214c8521a3c3a46e4ba2770f65a3d90c2b311a26f`.
New correction SHA-256:
`5b1243b6c2f3ca152055ee9b5bb688ce456d62b8dfe5f3dc5fa07d26907d0eff`.
The first 296 retain the prior chain hash
`2520d22baa28f1fc8dd137751360c51e691961ec22da72a84736c29cde8230e7`.

Final fresh project R9 `/private/tmp/dastak-full-rebuild.6zd8Nv` had no existing
R9 volume before bootstrap. Application replay ran in
`dastak_support_hardened_final_20261021`, pinned Supabase PostgreSQL 17.6.1.155,
network **none**, zero published ports, scheduler off. No .env or hosted link was
read. Auth users/tickets/cron runs/HTTP queues/responses ended at zero.

The earlier R8 draft replay stopped at the new migration because of a SQL
dollar-quote typo. It did not change any historical migration. The typo was fixed,
tested in the disposable fixture, then the entire final source was replayed from
empty in fresh R9, not resumed or force-marked applied. R8 is retained and stopped.

Evidence is in [hardening/](hardening/), including
[rebuild receipt](hardening/support-rebuild-result.json),
[manifest](hardening/support-rebuild-manifest.json),
[database regressions](hardening/support-contracts-results.json),
[support results](hardening/support-support-results.json),
[contention proof](hardening/support-contention-results.json),
[upgrade witness](hardening/support-upgrade-result.json),
[Edge tests](hardening/all-edge-tests.log),
[web tests](hardening/web-tests.log), and [web build](hardening/web-build.log).
The historical verification evidence in `full-chain/` is retained, not overwritten.

## Remaining activation work

The local code and verification in this document are complete. To make this live,
separate authorization is still required to apply the two pending support
migrations, deploy the function/web integrations, enable the feature and perform
a disposable public-intake/Admin/recovery smoke check. Policy/privacy and the
App Store Support URL must match the activated service. No claim that those
production/listing steps have happened is made here.

The original protected eight-file diff remains byte-identical at
`89cb303d44be0291e8103a744cb49acf66052e15d35e60f9bd2fac5dadbeb473`.
Temporary runtime teardown is recorded in `hardening/teardown.log`. Source remains
uncommitted/unpushed; no existing native/app-store changes were overwritten.
