# Free-only database retention and reclamation plan

Prepared 17 October 2026. **Historical planning snapshot, before execution.** Current authorized execution and verification results are in [EXECUTION_STATUS.md](EXECUTION_STATUS.md). The owner explicitly requires no paid services. The earlier paid-plan recommendation is superseded by that requirement.

**Later execution checkpoint:** the owner approved execution of this scope and renewed that permission. The CA and real encrypted backup/restore gates were resolved, bounded deletion completed, and the retention migration was applied. Physical maintenance and acceptance evidence are recorded separately in [execution status](EXECUTION_STATUS.md). Do not interpret this original plan's future-tense steps as a current pending-work list.

## 1. Exact scope

Only `cron.job_run_details` rows satisfying **all** these conditions are initial cleanup candidates:

```sql
status = 'succeeded'
AND end_time IS NOT NULL
AND end_time < :fixed_cutoff_utc
AND runid <= :snapshot_high_water_runid
```

Set the cutoff once to the approved execution start minus three days. Record it and the high-water run ID in a private execution manifest. Do not let the cutoff move during the initial cleanup. Only rows present in the verified recovery archive may be removed. Recheck the predicate and an archived row fingerprint immediately before each deletion; skip any row that changed after the archive snapshot. MD5 of the canonical JSONB row is a change-detection aid, not a security proof; file integrity uses SHA-256. Use consistent UTC/ISO session settings for fingerprint generation and comparison.

Preserve all failed/cancelled/non-success runs, unfinished rows and rows with missing completion times. Preserve rows at the cutoff boundary. No orders, payments, financial journals, accounts, addresses, catalogue records, Storage objects, invariant history or monitor-run history are cleanup targets. Do not change the existing 11 business-job schedules, suppress logging, disable triggers/RLS, or relax roles to make cleanup pass.

At the refreshed aggregate snapshot, **17 October 2026 19:40:56 IST**, there were **1,679,866** run-history rows, including **6,580 failed** and zero unfinished. **1,497,906** successful completed rows were older than three days. These are planning counts, not permanent execution targets; the approved execution must take a new snapshot.

The database then measured **1,100,549,267 bytes**, and job history **720,977,920 bytes**. A row-proportional estimate gives **436.46 MiB** after effective reclamation, with failures/audit data retained. This remains an estimate; table packing, indexes, WAL, subsequent activity and quota accounting affect the actual outcome.

## 2. Preflight and stop conditions

Recheck project `zmtsolkfxlrxepshnjdf`, branch/worktree, schema, sizes, current role, candidate count and quota status before execution. The plan was prepared in `codex/dastak-v1-launch` at `9ad1125ed2d9361de3145f126ff00500004884e7`, with existing local changes preserved.

Read-only capability inspection found PostgreSQL **17.6**, pg_cron **1.6.4**, `cron.log_run=on`, and UTC cron scheduling. `postgres` is not a superuser, but has BYPASSRLS, SELECT/DELETE/INSERT and the table's MAINTAIN privilege. `supabase_admin` owns the table; `postgres` is not a member of that role. The table's RLS policy restricts ordinary callers to their own username. No referencing foreign keys or triggers were found on this table. No role, privilege or policy was changed. Maintenance privilege is necessary; it is not proof a real compaction will complete.

Stop without cleanup if any gate fails:

- Owner approval for the exact deletion/retention scope and a quiet maintenance window is absent.
- The selected project/role/schema differs, read-only/Fair Use restrictions block the required operation, or dependencies have changed.
- A protected recovery archive cannot be made and restored/tested successfully.
- **Server disk headroom is unverified or insufficient.** Database size is not free filesystem space. Confirm project disk/WAL headroom through supported Supabase diagnostics/dashboard before any rewrite. Conservative planning should allow another current table/index copy plus WAL/workspace; the exact available server headroom has **not** been verified. The Mac's available space is a separate resource.
- Active customer/delivery work would be affected by the approved compaction window, or lock/error/backlog/latency checks show it is unsafe to proceed.

Do not force a read-write override, buy capacity, stop business workers, grant privileges or truncate/recreate an extension-owned table as a fallback. If the Free project's disk/restriction gates cannot be satisfied, report the blocker and seek supported no-cost guidance from Supabase before another owner decision. No free workaround is guaranteed.

## 3. Recovery checkpoint — before any removal

The export is **not yet made**. A production export would contain cron command/response text and may contain credentials. It needs an owner-approved protected, encrypted local destination, outside the repository, shared folders and public artifacts. Never print/upload its payload to chat, ordinary logs or CI. Use existing secure database authentication; do not place passwords/tokens in shell command arguments or documentation.

After execution approval:

1. Use one consistent READ ONLY snapshot to select the cutoff/high-water mark, count candidates, and stream the candidate rows plus canonical row fingerprints into the archive. Export explicit columns in the audited schema order. Keep the high-water manifest, counts, schema/version metadata and SHA-256 checksum alongside it, equally protected.
2. Enforce client/server timeouts and inspect the query plan without executing the deletion. Stream/chunk the export if necessary; do not hold an unbounded snapshot that harms live work. A failed/incomplete export is not a recovery checkpoint.
3. Restore the archive into a fresh **local isolated** table/database. Verify checksum, parsed row count, unique run IDs, all eligibility predicates, and row fingerprints, including CSV quoting, multiline text, Unicode and nulls. Do not restore it over production just to test it.
4. Keep the recovery checkpoint until the owner accepts the cleanup and decides its secure retention/removal. There is no automatic archive deletion in this plan. The one-time archive does not constitute a complete production database backup.

Local `psql`/`pg_dump` are **14.19**, older than the live server's 17.6. Do not claim a `pg_dump 14` production backup; PostgreSQL rejects dumping a newer-major server. A streamed SQL/COPY export is the proposed candidate-row archive route, subject to a real round-trip check. Any full database dump requires a compatible toolchain and separate handling; none was created here.

## 4. Bounded initial cleanup

Drive the initial removal from the verified archive's run-ID/fingerprint manifest, in batches of **at most 2,000**. Send only IDs and fingerprints as bound inputs, not archived secret-bearing command text. Look up by the existing primary key, then recheck status, completion time, cutoff, high-water and fingerprint inside the delete transaction.

- Commit each batch independently; do not perform the million-row removal in one transaction.
- Use a **1-second lock timeout** and **5-second statement timeout** per batch. A timeout rolls that batch back. Pause and investigate; never keep retrying indefinitely.
- Record attempted/deleted/skipped counts and the last acknowledged batch outside the database in the protected execution manifest. If the connection outcome is uncertain, reconcile its exact IDs before retrying. Deleted IDs make an exact replay harmless; a missing acknowledgment is not evidence of failure.
- Treat changed/skipped rows as a separate review list, never silently broaden the predicate.
- Briefly yield between batches; stop on elevated service errors, heartbeat delays, work backlog or lock contention. No throughput/duration promise is made from the small fixture.

Recovery means restoring **only missing archived rows**, preserving original run IDs, without replacing newer/conflicting rows. Conflicts require inspection. Do not lower/reset the live run-ID sequence. Re-importing old history will consume quota again; recovery is not a quota fix.

## 5. Physical reclamation — separate maintenance gate

After initial deletion, measure the table and database again. Plain VACUUM normally makes internal space reusable but need not lower the reported allocated size enough. If physical size is already below the target, do not rewrite unnecessarily.

If required and all disk/window/privilege gates pass, the planned one-time table-specific compaction is `VACUUM (FULL, ANALYZE) cron.job_run_details` in a dedicated session, **outside a transaction block**. It must not be appended to a multi-statement CLI transaction. Set session lock timeout to 1 second and an initial statement-time budget of 60 seconds, inspect progress separately, and stop/report on timeout rather than repeating automatically. This budget is a safety stop, not a completion estimate.

FULL compaction takes an exclusive table lock and extra disk; pg_cron's history writes may wait, potentially affecting job execution. Owner-approved quiet timing is required even though application order tables are not the lock target. No zero-downtime claim is made. Do not run this on a recurring schedule. If compaction cannot safely reclaim enough space on Free, stop; do not switch to TRUNCATE, paid resizing or another destructive technique without a new plan/approval.

## 6. Prevent recurrence

After the initial cleanup/reclamation is accepted, add **one** narrowly named cron job, proposed name `dastak-successful-cron-history-retention`, running hourly at minute 15 UTC (`15 * * * *`). Do not replace an existing name; check first. The job itself runs as the verified maintenance role, with no public RPC, security-definer endpoint or new client privilege.

Each run deletes at most **3,000** oldest completed successes with `end_time < now() - interval '3 days'`, retaining failures/unfinished/non-success runs. Apply the same lock/statement budgets and return only an affected-row count. The initial estimate is about 2,450 new run-history rows/hour; 3,000 is an initial cap, not a guarantee against spikes. pg_cron serializes instances of the same job. Verify its actual query plan/duration and monitor backlog. Never automatically increase the deletion scope or remove failures to catch up.

This recurring expiry is intentional retention: future expired history is not automatically copied into the one-time recovery archive. Application/audit records remain unchanged. If the owner requires ongoing historical archives, that is a separate local-archive/storage design, not an unmentioned promise of reversibility.

Record this additive retention change in a new migration only after approval, using the CLI's migration creation workflow; leave existing migrations untouched. Disable/unschedule **only this new retention job** to roll the policy back. Disabling it does not restore already expired records.

## 7. Acceptance checks and free-capacity boundaries

- Recount successful/failed/unfinished history; explain every removed ID from the initial archive manifest. Verify no rows outside the target were removed.
- Verify immutable audit protections, RLS, and the original 11 business schedules remain unchanged.
- Check business-job heartbeat/backlog and perform a read-only application refresh; real-order tests need their own owner-approved workflow. A succeeded cron SQL row alone is not an end-to-end delivery test.
- Measure actual database/table bytes, aim for **at most 450 MiB** initially, and verify the dashboard's precise quota interpretation. Remaining below 500 MB is not guaranteed by a row estimate. Use an operating warning below the limit (proposed 450 MiB) and reassess on growth; no automatic expansion of cleanup scope.
- Check actual quota/Fair Use status. Supabase documents billing-period averaging, so a size reduction does not promise immediate restriction removal. Do not call the launch gate resolved while a restriction remains.
- Recheck after at least one retention run and again after a day. Future business/audit growth can exhaust Free capacity even if this policy works. Do not discard business records to keep the plan free.

### File storage is separate

The aggregate metadata-only inventory found:

| Bucket | Objects | Known object bytes |
| --- | ---: | ---: |
| `dastak-catalogue` | 3,830 | 788,682,313 |
| `dastak-evidence` | 86 | 188,241,557 |

All returned size fields were valid. No filenames, owners, content or private URLs were fetched. This inventory does **not** prove that any object is unused, and it is not the provider's billing metric.

No Storage deletion/replacement is part of the cron-history cleanup. The free-only follow-up is a separate dry-run reference/duplicate audit, covering catalogue assets, order snapshots, onboarding/evidence references and legacy URLs before proposing any specific object. Only a reviewed list with verified recovery/reference safety may be offered for approval. Future upload compression/deduplication can be evaluated locally without paid transformation services; it is not implemented in this plan. Never SQL-delete `storage.objects` metadata: supported Storage API deletion is required to remove actual files. Evidence retention needs its own policy; age alone is not deletion authority.

## 8. Verification performed for this plan

- Read-only live capability/retention/storage aggregates succeeded. Preflight SQL is checked in as `maintenance-preflight.sql`; storage inventory as `storage-capacity-audit.sql`.
- `retention-selection-fixture.sql` ran against a newly initialized, Unix-socket-only PostgreSQL **14.19** cluster containing synthetic data. It checked cutoff boundary, failed/recent/unfinished/non-success protection, a two-row batch bound, high-water exclusion of a late insert, fingerprint exclusion of a changed row, harmless retry and recovery without overwriting conflicts.
- A synthetic CSV archive exported/restored exactly, including multiline/quoted/Unicode content. This demonstrates the local selection/archive mechanics, **not** a production recovery rehearsal or pg_cron integration/performance test.
- Temporary synthetic databases were stopped and removed; no existing local database or user files were removed.
- Actual production archive/restore, disk-headroom check, real compaction, initial cleanup, scheduled retention and capacity acceptance are **not performed**. No migration, push or deployment was made for this plan.

## References

- [pg_cron monitoring and retention](https://github.com/citusdata/pg_cron#monitoring-jobs): run-history records are not automatically cleaned; scheduling is role-scoped.
- [PostgreSQL 17 VACUUM](https://www.postgresql.org/docs/17/sql-vacuum.html): MAINTAIN permission, exclusive FULL rewrite, extra disk and transaction restrictions.
- [PostgreSQL 17 pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html): client/server major-version compatibility.
- [Supabase database-size limits](https://supabase.com/docs/guides/platform/database-size): Free quota, reclaiming space and Fair Use averaging.
- [Supabase Storage deletion](https://supabase.com/docs/guides/storage/management/delete-objects): permanent removal through the supported API, not SQL metadata deletion.

**Historical authority requirement at plan preparation:** execution permission for the specified candidate export/recovery rehearsal and bounded old-success-history cleanup, with conditional compaction, plus recurring retention. That permission was subsequently received; see the execution record rather than asking for identical approval again.
