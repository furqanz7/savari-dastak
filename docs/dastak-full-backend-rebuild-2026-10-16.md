# Full empty-database migration replay — 16 October 2026

Follow-up: all local findings listed below have since been corrected and the expanded 289-migration rebuild plus all 76 database test files now pass. See [the regression closure report](dastak-backend-regression-closure-2026-10-16.md) for final evidence and the separately gated production release. The results below are retained as the original audit record.

## Verdict

**The complete 287-file Dastak migration chain successfully rebuilds from a fresh Supabase platform database.** No application migration was skipped or modified. The historical catalogue activation ran chronologically, followed by all later changes and the new reconciliation. Its preservation for fresh setup is now tested, not merely inferred from a small fixture.

**The broader database regression suite is NOT green.** This verification found test-maintenance gaps, a schema-hardening omission, unresolved legacy-payment failures, and a reproducible local runtime fault. They are recorded below rather than hidden behind the successful migration replay. This does not establish a new production Customer/Delivery incident; nor does prior owner acceptance of those apps certify these additional backend checks.

No production database, migration history, order, payment, phone build, deployment, or notification was changed during this task. No new corrective migration has been created or applied.

## Scope and isolation

- Source: `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, HEAD `94f531d679e6dcca1bd588ab63c5000b1eb2c620`. Existing unrelated dirty work was preserved.
- Installed Supabase CLI: `2.90.0`. Database image: `public.ecr.aws/supabase/postgres:17.6.1.106`, image ID `sha256:21ab971149317ea9cd12a8126fe4ebb34def08c8972956b0958cba0924409dab`. PostgreSQL reports 17.6 on aarch64 Linux.
- Successful disposable project: `/private/tmp/dastak-full-rebuild.DsOH96`, ID `DastakRebuild20261016R2`. It had no linked project reference or copied environment/production credentials. Only synthetic local platform credentials were used.
- Empty means a newly bootstrapped **Supabase** database with its Auth/Storage schemas and platform roles, but no Dastak application schemas, accounts table, auth users, or migration history. It does not mean bare PostgreSQL without Supabase's platform prerequisites.
- Before staging application migrations, cron execution was disabled and all five test containers were disconnected from bootstrap networking and attached exclusively to Docker network `dastak-rebuild-20261016`, with `Internal=true` and no outbound gateway. An external DNS/HTTP probe failed. No application SQL was installed while bootstrap networking was available.
- The complete source SQL was replayed over `docker exec`/psql, one migration at a time with transaction scope, stopping on the first error. This is **not** a claim that a stock CLI `db reset` or a complete deployed-service recovery drill was executed. Custom replay avoided reopening the network for historical migrations containing scheduler/HTTP definitions.
- Both source and isolated project disable post-migration seed files. Migration-embedded seed SQL was executed unchanged.

Supabase documents migrations as chronological changes and supports separate local project identities: [local CLI workflow](https://supabase.com/docs/guides/local-development/cli-workflows), [multiple local projects](https://supabase.com/docs/guides/local-development/running-multiple-local-projects). Explicit isolation was particularly important here because historical SQL defines scheduled work.

## Migration result and independent checks

| Check | Result |
| --- | --- |
| Chronological files applied | **287 / 287**, no skips |
| First / last | `20260715090000_bootstrap_identity.sql` / `20261015203400_reconcile_catalogue_browse_activation.sql` |
| Exact source hashes still match staged files | **287 / 287** |
| Recorded history version, name and stored SQL hash match exact source | **287 / 287**, no extra history |
| Old activation unchanged | SHA-256 `1a4c428bcfa1ff85b35c392497c873f91f7d5c3ac5a569dea10a66ad6ac5ae84` |
| Final browse map | Version 1 ACTIVE; **121 nodes / 134 sources** |
| Catalogue coverage | **95 active seeded SKUs; 0 invalid placements** |
| Final map fingerprints | Nodes `e655fb9301b2ef89c609acbd07c63a08`; sources `c662c330891c50f4a66dd78e017209cb` |
| Dairy Alternatives | Exactly one correct source; one active seeded SKU maps correctly |
| Test-fixture cleanup | Auth users **0** after rollback-based tests; diagnostic function absent |
| Scheduler/outbound work | Cron execution `off`; **0 cron executions, 0 pg_net queued requests, 0 pg_net responses** |

Chain manifest SHA-256: `4d83f6e177a370d782ff4dc99dfaa27289adebc16299a5112a9d2251fc7d480b` (hash of ordered `filename:sha256` lines).

The map fingerprints match the earlier production reconciliation receipt. Production product contents are different from migration seed contents: the prior production inspection reported 572 active SKUs. Migrations are not a backup of subsequent operational product/account/order data or Storage object bytes. This test neither restores nor certifies those contents, external secrets, Edge deployments, APNs delivery, or full disaster recovery.

An earlier disposable attempt stopped after 207 migrations because the first replay harness used psql autocommit and lost an `ON COMMIT DROP` temporary table. The harness was corrected, and the successful run began again from a **second genuinely empty project**. No migration was patched or resumed past that failure.

## Additional database contracts: exact results, not an all-clear

There are **75 regular pgTAP SQL files**. Four directory entries ending in `.pgtap.sql` are empty directories, not runnable tests. Existing test SQL was not edited.

| Run | Passed files | Failed files | Assertion lines observed | Qualification |
| --- | ---: | ---: | ---: | --- |
| Stock local runtime | 52 | 23 | 1,484 | A permission-denial crash interrupted the server; several later failures were connection/recovery fallout, not separate bugs. |
| Diagnostic: omit `supautils` session preload | 57 | 18 | 1,658 | No crash. Two fixture files cannot set `session_replication_role` as the restricted `postgres` role. |
| Diagnostic: same hook isolation, superuser fixture setup | 59 | 16 | 1,729 | Exact same SQL and explicit in-test actor roles. Two governance fixture files pass. **This altered-runtime run is not a stock-runtime all-pass.** |

The `plpgsql_check` extension was installed only in the disposable database for investigation after the migration replay; no static full-function audit result is claimed. Original `session_preload_libraries=supautils` was restored after diagnostics. Cron remained disabled throughout.

### Findings and follow-up work

1. **Local runtime permission-denial crash.** Test `076_admin_network_permission_hardening` crashes the PostgreSQL backend at an anonymous EXECUTE-denial check. A separate rollback-only function returning the constant `1`, with EXECUTE revoked from PUBLIC/anon, reproduces the same signal-11 crash. Turning JIT off does not resolve it. Replacing the session preload `supautils` with `pg_stat_statements` makes the same probe return the correct normal permission error, and test 076 passes. This isolates a local-runtime interaction, not its underlying C-level root cause or production susceptibility. Keep a stock-runtime regression gate open until a supported runtime/configuration is validated. **Do not remove authorization checks to work around this.**
2. **One schema-hardening omission.** `dastak_v1.governed_entity_media` has RLS disabled and lacks an index supporting its `created_by` foreign key. This causes two assertions in test 025. Direct SELECT is denied to both anon/authenticated and authenticated has no domain-schema USAGE, so this check does **not** demonstrate public data exposure. Follow up with a least-privilege forward migration and wrapper regression tests; do not rewrite its historical creation migration. No such production change is authorized by this verification request.
3. **Current rider-availability policy versus older fixtures.** Tests 025, 026, 027, 028, 037, 044, 065, 073 and `079_delivery_partner_order_details` encounter the current “No delivery partners are available” admission guard. Several fixtures predate the guard; the full-order fixture creates rider approval/profile/availability but omits `approved_at` on its membership. Tests 026/037 also have configuration-error/discovery assertions to revisit. Update fixtures to establish current eligible-rider prerequisites and retain explicit no-rider negative cases. Do not disable availability rules or assume every later assertion will pass once setup is repaired.
4. **Four unresolved legacy merchant/payment test files.** Tests 006, 008, 009 and 011 fail exact-capture/ledger or subsequent transition assertions, including `merchant_order_ledger_unbalanced`. These target legacy merchant-order functions, not proof of a new V1 delivery-app failure. Root cause and production reachability are **not established**. Financial invariants, provider checks and immutable accounting must stay intact during diagnosis.
5. **Stale expectations/data dependencies.** Test 068 expects 25 Customer notification routes; the migrated schema has 26 following “Assigning your rider.” Test 084 expects 71 rails; the final map has 80 following the approved prayer-essentials expansion. Test 082 expects two named MTR SKUs that are absent from migration-only seed data. Maintain explicit current expectations and self-contained fixtures rather than importing production data or silently deleting assertions. These are not migration-execution failures.

The 16 diagnostic failing files are exactly the four legacy files, the nine availability-affected files (including test 025's hardening assertions), and tests 068/082/084. Full per-file results and source hashes are in the attached evidence JSON.

## Evidence and reproduction entry points

Durable sanitized evidence: `docs/evidence/dastak-full-backend-rebuild-2026-10-16.json`. It includes every migration filename/hash, all three contract-run outcomes, source/history verification, final catalogue state and isolation counters. It contains no production credentials or customer data.

Task-scoped scripts:

```sh
node Backends/Dastak/scripts/stage-clean-rebuild.mjs /private/tmp/dastak-full-rebuild.DsOH96
node Backends/Dastak/scripts/replay-clean-rebuild.mjs /private/tmp/dastak-full-rebuild.DsOH96
node Backends/Dastak/scripts/test-clean-rebuild.mjs /private/tmp/dastak-full-rebuild.DsOH96 baseline
```

The first two commands require a **new** empty disposable Supabase project with the reviewed project identity, internal network and cron-disabled guards. The retained successful database is already populated: replaying against it will deliberately fail the empty-database guard. These are pinned audit tools, not general reset commands or a CI pipeline. The contract runner accepts a distinct run label; `--fixture-superuser` is an explicitly marked diagnostic option, not an authorization workaround for application callers.

Temporary detailed evidence remains under `/private/tmp/dastak-full-rebuild.DsOH96` and `/private/tmp/dastak-full-rebuild-*.log/json`. Key logs are `dastak-full-rebuild-replay-r2.log`, `dastak-full-rebuild-contracts.log`, `dastak-full-rebuild-contracts-without-supautils.log`, `dastak-full-rebuild-contracts-fixture-superuser.log`, `dastak-full-rebuild-network-permission-rerun.log`, and `dastak-full-rebuild-denial-without-supautils.log`. Temporary files alone are not treated as permanent release evidence.

Script syntax checks passed. No app, business SQL, historical migration or existing test assertion was changed for this task. The Supabase skill's isolation guidance and Postgres privilege/RLS guidance shaped the test containment and classification of the media-table finding.

## Runtime restored

Both task-scoped Supabase stacks were stopped without `--all` or `--no-backup`; their disposable data/evidence remains recoverable. The user's pre-existing Dastak volumes were not reset, migrated or deleted. Docker had no running containers before shutdown. Colima was returned to its original **stopped** state and `colima status` confirmed it was not running. No personal, Codex or ChatGPT files/data were deleted. Downloaded runtime images and task test volumes remain on disk; no global Docker/cache prune was performed.
