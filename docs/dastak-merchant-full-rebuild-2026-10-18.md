# Expanded Merchant backend — complete local rebuild and integration evidence

18 October 2026, Asia/Calcutta. **The complete current 295-file migration chain rebuilt successfully from an empty Supabase platform database. All 76 real database contract files passed, and the new Merchant integration pass also passed.** This closes the expanded local rebuild gate from the [activation plan](dastak-merchant-backend-activation-plan-2026-10-18.md), not production activation or device acceptance.

## Verified results

| Check | Result |
| --- | --- |
| Exact chronological migration replay | **295 / 295**, zero skips |
| Recorded history versions/names/stored SQL hashes against current source | **295 / 295 match** |
| Existing real database contract suite | **76 files, 2,081 assertions, zero failures, skips or TODOs** |
| Additional Merchant integration pass | **113 assertions passed**: the existing 81-assertion Wave-1 scenario plus **32 new checks** |
| Static database contracts | **166 passed**, zero failures |
| Local runtime/manifest safety tests | **9 passed**, zero failures |
| Repository no-client-DML assertion | Passed |
| Direct anon/authenticated mutation/control grants in public/private/audit/dastak_v1 | **0 violations** in the checked privilege set |
| Final Auth fixture users / disabled application triggers | **0 / 0** |
| New history index | Ready and valid |
| Cron / HTTP activity | Cron disabled; **0 job runs, 0 queued HTTP requests, 0 responses** |
| Historical migration edits | None; all current migration file hashes still match the staged replay |

The integration result overlaps the Wave-1 contract in the main suite; do **not** add all 113 assertions to 2,081 as unique tests. There are 32 additional assertions beyond that reused scenario. No app, web or Edge runtime source was changed in this rebuild task; the preceding Edge/iOS pass remains separately dated evidence, not a new device or deployed-service result.

Permanent sanitized evidence: [rebuild receipt](evidence/dastak-merchant-full-rebuild-2026-10-18.json). Chain SHA-256: `631b55eee8ea11249c5831599b81d3b10176b313ab73c5802004bdf2a678657f`.

## Fresh platform and containment

Source worktree `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, unchanged HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`. The known dirty Merchant implementation and unrelated Customer fixtures/artwork/release files/dependency lock were preserved. Solo execution; no commit/push, hosted query, production migration, deploy, secret change, provider call, phone installation or Apple action.

Disposable project `/private/tmp/dastak-full-rebuild.X0Ur7r`, ID `DastakRebuild20261016R5`. Runtime image `public.ecr.aws/supabase/postgres:17.6.1.155`, image ID `sha256:3866d94d8426927e8db3f1c5d790752292bfbe27b5f1f46e199ae1b7d3c1710b`. It reports PostgreSQL 17.6/aarch64 Linux. The same reviewed permission-denial runtime fix as the [earlier closure](dastak-backend-regression-closure-2026-10-16.md) was retained; `supautils` was not removed, and the full contract run used ordinary `postgres`, not the fixture-superuser diagnostic mode.

Empty means a freshly bootstrapped Supabase platform with Auth/Storage/Realtime prerequisites, but no Dastak schemas/accounts table, zero Auth users and empty application migration history. It does not mean bare PostgreSQL without platform prerequisites.

Bootstrap used only synthetic local platform credentials and an unlinked task config. Before application SQL was replayed, the six task containers were moved exclusively to the existing internal-only `dastak-rebuild-20261016` Docker network. A DNS/HTTPS probe failed as expected. Cron execution was disabled and independently read back as off. The replay runner refuses a populated application database, non-disposable/linked/env-configured target, unexpected network or active scheduler. Application SQL was never installed while bootstrap outbound networking was available.

The first bootstrap health check failed because the gateway was excluded; it was corrected before staging/replay. The first cron-disable command was denied to the restricted `postgres` role; only the local platform administrator then disabled that setting, after which the ordinary replay role confirmed it. The runner initially refused to replay while cron was still on. No application migration was skipped, edited or resumed past a migration failure. All 295 application files passed on the first actual permitted replay.

## Test-harness changes

The three existing stage/replay/contract scripts now recognize the reviewed 295-file chain **only with the exact ordered SHA-256 fingerprint**, through `scripts/merchant-rebuild-manifest.mjs`. This is not an arbitrary count increase or a caller-supplied-hash bypass. Staging and replay retain disposable target, fresh state, transaction/history and stop-on-error checks. Existing historical 289-file replay behavior remains supported; linked/env-configured targets remain forbidden. Tests reject modified hashes, missing/duplicate/out-of-order/extra rows and malformed paths/hashes.

The replay sends each unmodified migration with transaction scope and records its exact source SQL after success, preserving historical files that include explicit transaction statements. This is a guarded replay, **not** a claim that stock CLI `db reset` or the eventual hosted release runner was rehearsed successfully. Embedded migration transaction boundaries and production lock/statement budgets still require their own release-runner check.

`scripts/test-merchant-rebuild-integration.mjs` validates the new chain receipt, internal network, disabled scheduler and zero pre-test users, then extends the original rollback-only `026_dastak_v1_wave_1.pgtap.sql` scenario without editing that file. It expands only the existing reviewed includes, inserts an active-state check before cancellation, and appends the new integration assertions before the original `finish()`/rollback. Actual helpers, permission functions, projections, application triggers and financial delegates are never replaced or disabled.

New SQL inputs are `supabase/tests/merchant_rebuild_active.sql` and `supabase/tests/merchant_rebuild_integration.sql`. An initial integration attempt exposed JavaScript replacement-string interpretation of SQL dollar quotes; switching to a replacement callback preserved the exact SQL. That harness error was fixed before the successful final integration run. Existing application assertions were not removed or loosened.

## What the integrated checks establish

- A real command-created active fulfilment appears in the new Merchant list and not in historical-only pages. After the original scenario cancels/releases it, history discovers it through the real projections.
- Full-order detail resolves the actual authorized historical order/product. Another merchant is denied the same order/history. The new projection does not add Customer private/full-bill fields.
- The directory discovers the authorized location rather than the foreign location. Selected inventory uses original search/selection helpers and projects stock restored by the real cancellation workflow. The actual migration-seeded catalogue plus fixture product traverses multiple pages without duplicate SKUs or losing the fixture product. This is integrated behavior, not the separate 5,201-product volume fixture.
- A genuine earnings-read-only bundle cannot gain payout management or request a withdrawal. An existing organization-wide owner grant exposes setup authority even at zero available balance.
- A synthetic local credit is posted through the original balanced-financial-transaction function. The checked Merchant wrapper rejects a wrong reviewed destination before reservation, then delegates a valid request to the original withdrawal function. Exactly 1,000 paise is reserved from 5,000, with one reservation transaction and two debit/credit lines.
- Original destination registration/replacement executes only as local database operations with clearly synthetic references; there is **no external contact/fund-account or payment/provider call**. After replacement, original-key replay returns the original withdrawal; a new stale request and a changed amount under the original key are rejected. Balance stays 4,000, original destination snapshot remains immutable and exactly one withdrawal notification intent exists. All financial transactions remain balanced.
- Those synthetic rows, including financial/audit/outbox state, are rolled back. Real provider reconciliation, APNs delivery, end-to-end HTTP/JWT routing and signed-device behavior are not inferred from these SQL tests.

The earlier small fixtures remain useful for all target kinds, larger page counts and concurrent destination locking. This integrated pass complements them with original dependencies; it does not replace their distinct coverage or claim a new concurrency test against the rebuilt database.

## Reproduction

The target is already populated; replay deliberately refuses it. A fresh unlinked disposable Supabase platform and the same runtime/isolation/scheduler preflight are required for a new replay. Do not run reset/replay against the normal Dastak workspace database.

```sh
node Backends/Dastak/scripts/pin-local-test-postgres.mjs /private/tmp/dastak-full-rebuild.X0Ur7r
node Backends/Dastak/scripts/stage-clean-rebuild.mjs /private/tmp/dastak-full-rebuild.X0Ur7r
node Backends/Dastak/scripts/replay-clean-rebuild.mjs /private/tmp/dastak-full-rebuild.X0Ur7r
node Backends/Dastak/scripts/test-clean-rebuild.mjs /private/tmp/dastak-full-rebuild.X0Ur7r merchant-295
node Backends/Dastak/scripts/test-merchant-rebuild-integration.mjs /private/tmp/dastak-full-rebuild.X0Ur7r
node --test Backends/Dastak/tests/merchant-rebuild-manifest.test.mjs Backends/Dastak/tests/pin-local-test-postgres.test.mjs
```

Key host logs: `/tmp/dastak-merchant-rebuild-replay.log`, `/tmp/dastak-merchant-rebuild-contracts.log`, `/tmp/dastak-merchant-rebuild-integration.log`, `/tmp/dastak-merchant-rebuild-safety-tests.log`, `/tmp/dastak-merchant-rebuild-static.log`. Per-migration/per-contract logs, the full source manifest and result files remain in the task directory. Permanent evidence contains sanitized results and hashes, not credentials or customer data.

## Shutdown and remaining gates

The task Supabase stack was stopped with its exact project ID, without `--all` or `--no-backup`; its data volumes and diagnostic files remain recoverable. Docker had zero running containers before Colima was stopped. Colima was restored to its original stopped state. The user's existing Dastak containers/volumes were not started, reset or removed. No personal files, caches, simulator runtimes, images, Codex or ChatGPT data were deleted.

**Local full-chain rebuild and integrated-database verification are complete.** The following are still separate: source checkpoint/push authority; read-only hosted history/schema/function/auth drift and advisors; hosted release-runner transaction/timeout/index-window checks; exact four-migration/three-Edge activation approval and execution; authenticated read-only deployed smoke checks; web publication; physical device/notification/Keychain acceptance; provider readiness/financial acceptance; Merchant distribution.

The database rebuild is not a production-data/Storage-object/secret restore or disaster-recovery drill. It does not activate anything merely by passing. Supabase and Postgres skill guidance shaped the unlinked local target, scheduler/network containment, immutable source checks and real permission/ledger tests: [official local workflow](https://supabase.com/docs/guides/local-development/cli-workflows), [migration guidance](https://supabase.com/docs/guides/deployment/database-migrations).
