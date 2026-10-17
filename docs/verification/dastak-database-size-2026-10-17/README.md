# Dastak database-size audit — 17 October 2026

**Historical read-only audit snapshot.** The owner subsequently authorized the free-only cleanup. For the actual backup, deletion, migration and maintenance results, use [EXECUTION_STATUS.md](EXECUTION_STATUS.md). Statements below about unperformed work describe the original audit boundary, not the later execution state.

## Scope and authority

The owner selected **Audit database size first; delete nothing**. The linked project was verified as Dastak, `zmtsolkfxlrxepshnjdf`, in Mumbai. This audit made catalog/aggregate reads only. No application data, cron schedules, retention settings, migrations, billing, or logging configuration were changed. No DELETE, TRUNCATE, VACUUM, ANALYZE, or other maintenance was run.

Queries intentionally exclude cron command/response text, incident snapshots, account identifiers, addresses, and order contents. The larger aggregate queries use an explicit READ ONLY transaction, a 15-second statement timeout, and ROLLBACK. The earlier size/catalog queries are single SELECT statements.

## Live observations

- The Free-plan organization usage page displayed database usage **1,098 / 500 MB**, file storage **0.93 / 1 GB**, log ingestion **2.68 / 1 GB**, and an ended grace period. Project overview still displayed Healthy; the banner is not proof of an ongoing outage.
- The direct database-size query returned **1,083,288,723 bytes = 1,033.10 MiB**. A later retention query at **2026-10-16 23:48:17 UTC / 17 October 05:18:17 IST** returned **1,083,403,411 bytes**. These are instantaneous measurements of this database, not the dashboard's organization/billing-period metric; MB/MiB units also differ.
- `default_transaction_read_only` was `off` at inspection. This does not certify every API write or exclude organization-level Fair Use restrictions.
- No existing job-history retention schedule was visible among the 11 active cron jobs; the repository search likewise found no `job_run_details` retention implementation. Six jobs run every 10 seconds and five every minute. The prior 24-hour aggregate counted **58,842 job-history rows**. A cron SQL execution marked succeeded does not prove a downstream HTTP operation succeeded.

## Main space consumers

Table totals include indexes and associated TOAST; the TOAST schema is excluded from the schema sum to avoid counting it again.

| Relation | Allocated bytes | MiB |
| --- | ---: | ---: |
| `cron.job_run_details` | 703,987,712 | 671.38 |
| `dastak_v1.invariant_incident_history` | 204,292,096 | 194.83 |
| `dastak_v1.catalogue_import_items` | 22,798,336 | 21.74 |
| `dastak_v1.skus` | 14,565,376 | 13.89 |
| `dastak_v1.invariant_monitor_runs` | 12,984,320 | 12.38 |
| `storage.objects` (metadata, not image-file contents) | 12,083,200 | 11.52 |

The first two relations account for approximately **83.8%** of the measured database. Catalog estimates of row counts were stale: use the exact aggregate counts below, not `reltuples`, for retention planning. Estimated dead-tuple counts are not a measured bloat assessment.

## Exact history counts

At the retention-query snapshot, `cron.job_run_details` contained **1,644,608 rows**: **1,638,028 succeeded**, **6,580 failed**, and **zero unfinished**. Completed history spans 18 September through 16 October 2026 UTC. None of the failed completed entries was over 30 days old.

The invariant history contains **294,061 events**: 294,035 REPEATED, 13 DETECTED, and 13 RESOLVED. All 13 current incident records are RESOLVED. No incident-history events were recorded in the preceding day; the latest resolution was 28 September 2026. This is historical repeated-monitor evidence, not 294,061 distinct current incidents.

Live metadata confirms enabled immutable triggers on both invariant history and monitor runs. The source defines full incident snapshots on insert/update and rejects updates/deletions of these audit tables in `Backends/Dastak/supabase/migrations/20260823023000_dastak_v1_launch_hardening.sql`. Do not disable these protections or treat audit history as disposable logs.

## Retention sizing, not deletion approval

The proposed candidate is **completed successful cron execution history only**. Keep all failed entries for now and retain every application/audit/accounting table unchanged.

| Successful-run history retained | Older successful rows at snapshot | Rough remaining database after effective compaction |
| --- | ---: | ---: |
| 1 day | 1,579,192 | 388 MiB |
| 3 days | 1,462,684 | 436 MiB |
| 7 days | 1,227,429 | 532 MiB |
| 14 days | 815,607 | 700 MiB |

These are **row-proportional estimates**, not measured reclaimable bytes or guarantees. Formula: `database_bytes - cron_history_bytes × eligible_rows / total_rows`, using the later snapshot's 704,102,400-byte cron table. Record lengths, existing free space, index packing, future writes, other database growth, and quota accounting can change the result. Seven-day retention alone does not appear sufficient. Three days could provide a temporary Free-plan fit, but limited headroom remains.

Deleting old rows ordinarily creates reusable space inside PostgreSQL; it need not reduce the allocated file/database size immediately. Physical compaction can require extra space and an exclusive table lock, so any reclamation plan must separately assess permissions, backup/export and restore verification, available database disk, service impact, bounded batches, maintenance timing, and verification. No compaction strategy was executed or assumed safe here.

Supabase also documents that organization Fair Use database restrictions can use billing-period averages, so lowering live usage does not guarantee immediate removal of a restriction/banner. A cleanup-only launch cannot assume immediate quota recovery.

## Recommendation and remaining decision

**Later owner decision:** no paid services. The paid-plan recommendation below is historical and is superseded by the [free-only execution plan](FREE_ONLY_PLAN.md). That plan is prepared and locally fixture-checked, not activated. Production deletion/maintenance still needs separate approval.

For public launch, a paid production plan plus bounded successful-cron-history retention is the more durable route. Billing must be completed by the owner; no plan change was made. Retention remains valuable after an upgrade, because execution-history growth continues even without customer traffic.

If staying on Free is required, prepare and approve a specific three-day-success-history retention and reclamation plan first, with an export/recovery checkpoint and a maintenance window. Do not delete invariant history, reduce business-worker frequency, or disable scheduling merely to hide the growth. This audit is not authorization to perform that cleanup.

File storage is a separate near-limit metric and would not be reduced by deleting PostgreSQL job history. No Storage objects or product images were read or removed.

## Logging boundary checked during this audit

The project's Log Drains settings page displayed the upgrade-only feature screen on its current Free plan, with no configured destinations shown. Official Free-plan documentation lists one-day API/database log retention and no included Log Drains. This narrows the earlier Management API 403 uncertainty, but does not establish a custom retention override or independently inventory historical/manual exports. Provider log retention is separate from the durable `cron.job_run_details` and invariant-history tables measured here.

## Reproduction

Run each checked-in SQL file with the existing linked CLI configuration, passing its absolute path:

```sh
supabase --workdir Backends/Dastak db query --linked --file /absolute/path/to/audit.sql --output json
```

- `size-audit.sql`: database, relation and schema sizes; metadata estimates.
- `catalog-audit.sql`: relevant columns/indexes and job schedule metadata, excluding commands.
- `history-audit.sql`: exact grouped historical counts and immutability-trigger metadata.
- `retention-estimate.sql`: exact age-bucket counts for successful completed job runs.

Raw aggregate outputs were held under `/private/tmp/dastak-db-*-20261017.json`; durable decision-relevant results are recorded above. No customer rows or secrets are included in this report.

## Primary references checked

- [Supabase database and disk size](https://supabase.com/docs/guides/platform/database-size): size accounting, physical reclamation, Free-plan restrictions and billing-period-average caveat.
- [Supabase billing FAQ](https://supabase.com/docs/guides/platform/billing-faq): quota and Fair Use restrictions.
- [PostgreSQL routine vacuuming](https://www.postgresql.org/docs/current/routine-vacuuming.html): normal vacuum reuse versus compaction, exclusive locks and temporary disk needs.
- [Supabase pricing](https://supabase.com/pricing): current plan features and provider log-retention limits.

This is a completed read-only size audit. Quota remediation, any backup/export, retention implementation and physical reclamation remain unperformed and require separate approval.
