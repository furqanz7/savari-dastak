# Merchant release preparation — scoped checkpoint and bounded local rehearsal

19 October 2026, Asia/Calcutta. Follow-up to the [production preflight](dastak-merchant-production-preflight-2026-10-19.md). **The local release-procedure rehearsal passed. No production application, Edge deployment, Git commit or push was performed.**

## Rehearsed procedure

`Backends/Dastak/scripts/merchant-release-sql.mjs` is a transport-free SQL builder. It validates the entire tested 295-file source fingerprint and selects exactly the four pending Merchant migrations. It does not log in, connect, apply or deploy anything. Rollback is the default; an explicit boolean is required to build commit-mode SQL.

The built SQL:

1. Opens one explicit transaction, sets **2-second lock / 15-second statement timeouts**, and takes a transaction-scoped release advisory lock.
2. Requires the exact 291-version baseline, matching inspected prerequisite bodies/owners/security modes, no already-installed new RPC/private-function names and no unrecorded new index.
3. Retains temporary snapshots of old migration receipts and prerequisite definitions/metadata/grants.
4. Executes the four unchanged source migrations in timestamp order and records each original source SQL in `supabase_migrations.schema_migrations` **inside the same transaction**. It does not mark anything applied before execution succeeds.
5. Verifies 295 history entries, unchanged old receipts, unchanged prerequisite bodies/metadata/grants except the intended Merchant-list body, valid/ready history index and the intended authenticated-versus-service-only public RPC grants.
6. Reports the effective settings and transaction context, then explicitly rolls back or commits.

There is no provider operation, account/destination setup, withdrawal, stock/menu edit, business-table deletion or accounting rewrite in this procedure. Old migration files are unchanged. This prepares a single atomic release transaction rather than relying on ineffective file-local timeouts in the old CLI push path. `statement_timeout` is **per statement**, not a 15-second total release guarantee; the rehearsal client also has a 45-second caller budget. A lost transport/acknowledgement remains uncertain until history and installed state are read independently—never blindly rerun a suspected commit.

## Local containment

Only `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, unchanged HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`. Solo work. All unrelated dirty work was preserved.

New disposable project `/private/tmp/dastak-full-rebuild.HTHzAw`, `DastakRebuild20261016R6`, reused the previously downloaded reviewed PostgreSQL image `17.6.1.155`. Bootstrap ran with no application migrations staged. Before replay, all six task containers were attached only to the internal/no-outbound test network, and cron execution was disabled and read back as off.

The guarded replay script now supports the explicit `--merchant-baseline-291` fixture mode **only** with the exact reviewed 295-file source manifest. It replays the real first 291 files into an empty platform; it does not fabricate history, uninstall newer objects from an old database or change the user's existing database. The baseline fixture receipt is distinguished from a full rebuild pass. The preceding full 295-file empty replay remains independently documented.

`rehearse-merchant-release.mjs` has only a local Docker/psql transport. It refuses non-disposable paths, linked/env-configured targets, an unexpected project, wrong baseline receipt, outbound-capable networking, active scheduler or existing Auth test users. There is no hosted transport or deploy mode in that executable. The synthetic fault injections exist only in the local rehearsal path, not inside the four source migrations.

## Outcomes

| Rehearsal case | Result |
| --- | --- |
| Explicit rollback after installation/verification | Passed; settings read back as **2s / 15s**; baseline schema/list/history restored |
| Conflicting `ROW EXCLUSIVE` lock on fulfilments during new index creation | Failed as intended with SQLSTATE **55P03** in **478 ms** using a 400-ms test lock budget; no partial schema/history survived |
| Forced slow statement after all install verification | Failed as intended with SQLSTATE **57014** in **696 ms** using a 500-ms statement budget; full transaction rolled back |
| Explicit local commit | Passed; all four migrations and their exact history records installed together; effective settings **2s / 15s** |
| Repeat against already-applied state | Refused at baseline guard; no duplicate schema/history |
| Independent final source/history comparison | **295 / 295 match** |

The failure checks compared pre/post history content fingerprints, existing list body, detail presence and index presence. The successful subsequent baseline guard also checks all new private/public names. New-function creation, grants, index DDL and history recording did not survive either aborted transaction.

The post-commit database then passed:

- **76 real pgTAP files / 2,081 assertions**, zero failures.
- **113 integrated Merchant assertions**, including the reused 81-assertion original scenario and 32 additional checks; not 113 unique additions.
- **12 release/manifest/runtime safety tests**, zero failures.
- **384 Edge tests**, zero failures.
- **748 UI/model tests**, zero failures.
- **19 focused web tests** across Merchant history/order detail, zero failures.

Package/web tests ran in the current worktree, not a separately extracted candidate-tree build. No new physical-device or visual pass, iOS archive, complete web-suite/build, live JWT call, APNs delivery or external provider acceptance is inferred. Test values are synthetic and rolled back. Final local checks found 0 Auth users, 0 disabled application triggers, cron off, 0 job executions/HTTP queue/responses and 295 recorded migrations.

Permanent evidence: [rehearsal receipt](evidence/dastak-merchant-release-rehearsal-2026-10-19.json). Task-specific logs use `/tmp/dastak-merchant-release-*.log`; detailed SQL/results remain in the disposable project directory.

## Proposed source checkpoint

The companion [source-checkpoint manifest](evidence/dastak-merchant-source-checkpoint-2026-10-19.json) describes a separate-index Git tree based on the existing HEAD. It records each included path/group, working-file SHA-256 and resulting Git blob, plus exclusions. **It is a prepared tree, not a commit, branch update, staged change in the user's index or a push.** The manifest itself is a later self-describing receipt, excluded from its own content hash/tree to avoid a circular fingerprint.

Scope groups are native Merchant implementation/tests, Merchant backend/migrations/verification, Merchant web detail/history and Merchant documents/evidence. Two shared Swift files are explicitly included because their reviewed diffs are Merchant changes: `DastakProductDetailCard.swift` changes only the Merchant detail portion; `DastakNotificationPreferences.swift` adds `Sendable` for the permission-state value used by bounded notification work. The shared APNs change is a Merchant-route test, not a worker deployment.

Customer screenshot-capture fixtures, Customer/Delivery screenshots, App Store/privacy/copy artifacts, unrelated artwork/GLB files, dependency-lockfile drift and the declined support draft stay outside the proposed tree. Exclusion does not delete or revert them. No `git add .` is used. The real index is checked empty/unchanged before and after preparation; future scoped commit/push still requires approval and a fresh content/branch guard. All evidence/source in the tree is local fixture/metadata material, not credentials or raw customer/bank data.

## Remaining activation boundary

The SQL transaction mechanism, rollback behavior and bookkeeping have now been exercised on the same database major/runtime with real predecessor functions. This is **not** a write-mode execution test of Supabase's hosted Management API, proof of future production latency, or authorization to use that transport. A future approved release must send the prepared transaction as one unit, preserve the tested settings, stop on errors and independently inspect outcome/history after any connection failure. Do not substitute a bare normal push and claim its timeout behavior was rehearsed here.

Before activation: obtain approval for the exact scoped commit/push; then approval for exactly four migrations and three Edge updates. Refresh project/history/source/deployment/advisor/load preflight at execution time. Apply database before Edge and preserve per-function auth configuration. Provider/secrets/billing changes, actual financial acceptance, web publication, app installation, device testing and Merchant distribution remain separate.

The task Supabase stack was stopped by exact project ID with data/diagnostics retained; no volumes, runtimes or personal files were deleted. Docker had no running containers before returning Colima to its original stopped state. Production was not queried or changed during this local rehearsal. Supabase/Postgres skill guidance informed exact source/history guards, least-privilege verification and transaction/timeout handling: [migration guidance](https://supabase.com/docs/guides/deployment/database-migrations), [Postgres timeout semantics](https://www.postgresql.org/docs/current/runtime-config-client.html).
