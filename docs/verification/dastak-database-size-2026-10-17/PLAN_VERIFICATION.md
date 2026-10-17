# Plan verification receipt — 17 October 2026

This receipt covers the free-only **plan**, not production cleanup completion.

## Production reads

- `maintenance-preflight.sql` succeeded inside a bounded READ ONLY transaction. Live PostgreSQL 17.6 / pg_cron 1.6.4; `postgres` has the table's MAINTAIN and SELECT/DELETE/INSERT permissions and BYPASSRLS, but is not a superuser or member of the table owner `supabase_admin`. No role changes were made.
- `retention-estimate.sql` refreshed at 19:40:56 IST: 1,679,866 history rows; 1,497,906 completed successes older than three days; 6,580 failed and zero unfinished; direct database size 1,100,549,267 bytes. Three-day row-proportional estimate 436.46 MiB, not guaranteed reclamation.
- `storage-capacity-audit.sql` succeeded using aggregate metadata only. Catalogue: 3,830 objects / 788,682,313 known bytes. Evidence: 86 objects / 188,241,557 known bytes. No object paths, content or owner identifiers were fetched.

Only catalog/aggregate reads were sent to the linked database. Temporary query outputs are `/private/tmp/dastak-maintenance-preflight-20261017.json`, `/private/tmp/dastak-retention-refresh-20261017.json`, and `/private/tmp/dastak-storage-capacity-audit-20261017.json`.

## Local synthetic fixture

The final checked-in `retention-selection-fixture.sql` ran successfully in a fresh PostgreSQL 14.19 cluster with TCP listening disabled, a private Unix socket, host authentication rejected, and database `retention_fingerprint_check`. It was not connected to Supabase and did not contain real cron commands, credentials or customer data.

Verified:

- Guard fails before DDL against a different local database; no fixture schema was created there.
- Eligible old completed successes are selected.
- Failed, non-success, unfinished, missing-completion, recent and exact-cutoff rows survive.
- Two-row fixture batch limit holds; seven eligible unchanged rows removed over multiple batches.
- A post-snapshot late insert is excluded by the high-water bound.
- A changed-after-archive row is excluded by its canonical JSONB fingerprint.
- Retry after completion removes zero additional rows.
- Restoring missing archive rows reproduces original rows without overwriting changed/conflicting rows.
- CSV export/import reproduces all eight archived synthetic rows exactly, including comma/newline/quoted/Unicode content. SHA-256: `f5a72aba21d7228362021b4ea06b752cf74eb4c8b1906598a67162febf4f77be`.

The local cluster was stopped and its temporary synthetic files removed. The test uses smaller batches and a local transaction loop to validate selection/retry/recovery, not production per-batch commits, concurrency, pg_cron integration, full schema restoration, performance or actual compaction.

Markdown local links and `git diff --check` pass. New live-read SQL files retain explicit READ ONLY / ROLLBACK guards. An initial ad hoc keyword check incorrectly flagged quoted privilege names (`DELETE`/`INSERT`); stripping SQL literals before checking statements resolved that false positive. No query mutation was found or performed.

## Not performed

No real history export/restore, production deletion, VACUUM/ANALYZE, retention schedule, migration creation/application, push, deployment, plan upgrade or purchase. Production disk headroom, maintenance timing, actual reclaimed size and post-cleanup quota status remain execution gates.
