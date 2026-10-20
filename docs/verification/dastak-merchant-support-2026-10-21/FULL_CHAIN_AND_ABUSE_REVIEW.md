# Merchant support: full-chain rebuild and public endpoint review

21 October 2026. **Rebuild verified locally; public activation held.**

Historical review snapshot. The findings below were subsequently addressed or
explicitly bounded by the owner's local-only/no-deletion decision; see
[the final 297-migration hardening verification](HARDENING.md). This earlier
296-file evidence is retained unchanged as a separate checkpoint.

## Outcome and authority

The owner approved a complete current migration-chain rebuild in a disposable
Supabase runtime and a review of anonymous endpoint abuse protection. No hosted
migration, deployment, push, commit, paid service, external account grant, Apple
change, real ticket, order or financial action was performed. The endpoint still
defaults disabled. This verification does not approve its public exposure.

Worktree: `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`.
Branch `codex/dastak-v1-launch`; HEAD
`61f51b7bcf691370c121e977b95b050311988267` unchanged.

## Complete migration replay — PASS

- **296/296 unmodified source migrations** replayed chronologically, including
  `20261020193411_merchant_support_inbox.sql`.
- The historical first 295 files retain their exact reviewed chain hash:
  `631b55eee8ea11249c5831599b81d3b10176b313ab73c5802004bdf2a678657f`.
- Support migration SHA-256:
  `bf284bb716f402202d65366a41b5d7afd6d19590f3df89904d6c066a090d6778`.
- Full 296-file chain hash:
  `2520d22baa28f1fc8dd137751360c51e691961ec22da72a84736c29cde8230e7`.
- Recorded migration names and stored SQL hashes match all 296 source files.
  No historical file was edited, skipped, replaced or marked applied without
  executing it. The historical 295-file validator remains unchanged; a separate
  support-chain verifier pins the extension.
- **76 existing pgTAP files / 2,081 assertions pass** after the replay.
- **37 additional full-schema support assertions pass**, exercising actual roles,
  Admin bootstrap/assignment, RLS/ACLs, capability checks, reply/reopen, retry
  idempotency, stale-version protection, cooldown, admission exhaustion and
  recovery. One assertion characterizes the NUL-input finding below.
- Edge checks: **24 existing tests pass plus 3 characterization probes** that
  reproduce review findings. Their passing is not an abuse-safety endorsement.
- Final hygiene: zero Auth users, support tickets, cron run records, queued HTTP
  requests and HTTP responses. Cron scheduling remained off throughout source
  replay and tests. Fixture transactions rolled back; the one committed synthetic
  contention-probe ticket and its message were explicitly removed afterward.

Evidence: [replay receipt](full-chain/support-rebuild-result.json),
[manifest](full-chain/support-rebuild-manifest.json),
[replay log](full-chain/replay-console.log),
[regression summary](full-chain/support-contracts-results.json),
[regression log](full-chain/contracts-console.log),
[support summary](full-chain/support-support-results.json),
[support assertions](full-chain/support-merchant_support_full.sql.log),
[Edge characterization log](full-chain/edge-review.log).

### Meaning of “from empty” and runtime containment

This was an **empty application database on a real, initialized Supabase local
platform**, with its standard Auth/Storage roles and schemas. It is not a bare
PostgreSQL installation and does not test hosted project provisioning.

Supabase CLI 2.90.0 bootstrapped a new, unlinked project
`DastakRebuild20261016R7` in `/private/tmp/dastak-full-rebuild.qY49PW`. No R7 volume
existed before bootstrap; `public.accounts` was absent and Auth had zero users.
Image `public.ecr.aws/supabase/postgres:17.6.1.155`, pinned image ID
`sha256:3866d94d8426927e8db3f1c5d790752292bfbe27b5f1f46e199ae1b7d3c1710b`.

Before application SQL ran, the platform containers were stopped and only this
new project's database volume was attached to a labelled verification container,
`dastak_support_rebuild_20261021`. It had Docker network **none**, **no published
ports**, and `cron.launch_active_jobs=off`. These conditions were rechecked by
the verifier. Source cron/HTTP definitions were installed but could not execute
scheduled external work. No .env, hosted project link or production credentials
were loaded for replay. The tests did not replace security helpers or disable
account/audit safeguards.

The first proposed project name, R6, restored a retained 295-migration test
volume. The empty-database guard refused it before application replay. That stack
was stopped and retained, not reset or deleted. R7 is the successful fresh run.

The new test fixture initially attempted to suspend immutable Superadmin
membership, then omitted required lifecycle timestamps. The real schema rejected
both setup errors. The fixture was corrected to use a separately assigned
Executive Admin and valid deletion-state timestamps; no product constraint was
loosened. Each failed attempt disconnected and rolled back.

## Public endpoint review — NOT ready for exposure

### 1. Shared admission is a storage cap, not request/bot protection

**High priority before activation.** Anonymous, well-shaped requests reach the
database without per-caller throttling or a verified bot challenge. The handler
probe forwarded all 35 synthetic reads to its mock command dependency; this was
not a hosted load test. The full-schema test filled the actual 30/hour allowance
and confirmed the next creation is rejected while prior ticket recovery works.

The 30/hour and 100/day limits are shared by everyone. A single abusive caller
could consume them and prevent legitimate requests. Creation also takes a
blocking global advisory transaction lock. The 1000-stored-ticket cap has no
retention/archival policy, so reaching it closes intake until deliberate operator
action. Resolving tickets does not free that allowance.

Recommendation: define a no-paid-service bot/throttling strategy before database
admission, bound database lock waits, and approve a retention/archival policy.
Do not treat CORS or a public Supabase key as caller authentication. Do not add
an external challenge provider, IP collection or legal retention claim without
the corresponding setup and privacy decision.

Supabase documents implementing function rate limiting explicitly; its example
uses Redis/Upstash. That example is not an automatic protection attached to this
custom endpoint: [official rate-limiting example](https://supabase.com/docs/guides/functions/examples/rate-limiting).

### 2. Public reads unnecessarily wait on a ticket write lock

**Medium priority.** `private.merchant_support_command` selects the ticket
`FOR UPDATE` before checking a supplied token, including read operations. With
one fixture connection holding that row lock, a second read using a wrong token
hit a deliberately short 150ms statement deadline while locking the tuple. After
the lock was released, the same read correctly returned `support_not_found`.
No unauthorized data was returned. Only two reads were used, not a saturation
test. [Contention evidence](full-chain/support-contention-results.json).

Recommendation: perform authorized read-only snapshots without a write lock;
reserve row locks for mutations, recheck authorization/version inside the write
transaction and give contention a bounded, explicit retry outcome. Do not drop
idempotency/version guards to obtain speed.

### 3. Body size is bounded, but body-read duration is not

**Medium priority.** The handler correctly counts actual streamed bytes up to
12KB, but `reader.read()` has no application deadline or request-abort handling.
A synthetic incomplete small body remained pending after 250ms, before any DB
call. We then closed it and verified rejection/cleanup. Source review confirms
there is no handler body-read deadline; the probe does not measure the hosted
platform's eventual termination limit. The DB HTTP client's 10s deadline and
browser's 15s deadline do not bound a custom caller's incomplete body upload.

Recommendation: add a server body-read deadline with stream cancellation and a
safe terminal response; preserve the byte cap and fail-closed activation gate.

### 4. Permanently invalid text is reported as a temporary outage

**Medium priority.** A JSON string containing NUL passes current Edge validation.
The full rebuilt PostgreSQL rejects the JSONB value with `22P05` before the RPC
can process it. The handler's generic error mapping presents this as retryable
503, so the UI may keep retrying an action that cannot succeed unchanged.

Recommendation: reject unsupported text before database invocation as invalid
input, consistently across browser and Edge. Keep raw database errors private;
do not report success or mutate the saved pending action silently.

## Positive boundaries verified

Private tables have RLS and no direct anon/authenticated/service table grants.
Only service_role can execute the exposed security-invoker wrapper; the definer
implementation is private with an empty search path. Edge strips submitted actor
claims and hashes the 256-bit recovery capability. Database checks actual Admin
assignment, membership suspension, account lifecycle and matching Auth email.
Wrong capabilities fail without revealing tickets; replies preserve expected
versions and request idempotency. No order/payment/account mutation authority is
provided by this feature. These controls passed; they do not cancel the abuse
and availability findings above.

## Remaining work / verification limits

1. Locally harden the four findings and choose the no-cost abuse/retention plan.
   This review did not modify the endpoint or migration to implement those fixes.
   Preserve the already-replayed original migration; use a new forward migration
   for installed SQL behavior changes, then rerun the complete chain and tests.
2. Obtain separate production authorization, apply the final pending migrations,
   deploy the function and web integration, enable the feature and perform a
   deliberately disposable deployed intake/Admin/recovery check. No live OAuth,
   PostgREST HTTP integration, hosted gateway behavior, APNs or production load
   was verified by this database run.
3. Complete the separate public policy/privacy/contact/retention and App Store
   Support URL decisions. The new page must not be advertised as live yet.

## Reproduction and cleanup

`Backends/Dastak/scripts/verify-merchant-support-rebuild.mjs ROOT MODE` supports
`prepare`, `replay`, `contracts`, `support`, `contention`. It intentionally pins
this reviewed image, chain, disposable R7 configuration and no-egress container;
it refuses populated replay targets and source drift. A later fresh run needs a
separately reviewed unused project/volume identity, not deletion/reset of the
retained fixture. Do not run `replay` again on the populated R7 database.

The original small PG14 fixture remains a useful fast isolated test, but the
296-file Supabase replay above now closes its earlier full-chain compatibility
gap. Detailed local runtime/log artifacts are retained under the named temporary
root. Sanitized receipts are checked into this working document folder (not
committed). Teardown status is recorded separately in `full-chain/teardown.log`.

The original eight-file unrelated diff guard still hashes to
`89cb303d44be0291e8103a744cb49acf66052e15d35e60f9bd2fac5dadbeb473`.
The script, fixture tests, characterization tests and verification documents are
the only additions/edits in this follow-up; no production business code changed.
