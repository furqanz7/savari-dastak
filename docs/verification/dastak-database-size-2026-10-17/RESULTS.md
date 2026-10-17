# Free-only database cleanup — execution results

17 October 2026. Project `zmtsolkfxlrxepshnjdf` (Dastak). This supersedes the original read-only audit/plan as the current execution summary. Detailed recovery, timeout and space-gate evidence is retained in [EXECUTION_STATUS.md](EXECUTION_STATUS.md).

## Completed in production

- Archived and deleted **1,506,093** completed successful cron-history rows older than the fixed cutoff **14 October 2026 17:31:01.432791 UTC**, limited to snapshot high-water run ID **3,739,835**. All **754 batches** were acknowledged; **zero skipped/changed rows**. No deletion was blindly replayed after a timeout.
- The encrypted candidate-row archive was authenticated, checksum-verified and restored into an isolated local PostgreSQL 14.19 fixture. **1,506,093 unique rows**, zero eligibility errors and zero canonical-row fingerprint mismatches. Archive size **65,957,964 bytes**, SHA-256 `a56290948f743fe4121569abb4be36ac9dfa4757e144635f167264e2cc4b5258`. This is **not a full database backup**. The archive remains private outside Git, FileVault-protected, with its random encryption key in the Mac Keychain. No raw history, command/response payload or credential was committed/uploaded.
- Preserved **all 6,580 failed runs**, unfinished/non-success records, and all application/audit/accounting/catalogue/Storage data. History RLS remains enabled. Both invariant-history and monitor-run immutability triggers remain enabled.
- Completed the single authorized `VACUUM (FULL, ANALYZE) cron.job_run_details` after live quiet-window, lock, privilege, snapshot, replication and measured-space gates passed. It ran outside a transaction with a **1-second lock budget / 60-second statement budget**. No extension table was truncated/replaced/recreated. A disposable retained-copy capacity probe was rolled back and verified absent before this operation.
- Installed **one** hourly retention job, ID **35**, `dastak-successful-cron-history-retention`, `15 * * * *` UTC, owned by `postgres`. It removes **at most 3,000** completed successes older than three days per run, preserves failures/unfinished records, and keeps the **1-second lock / 5-second statement budgets**. Its cutoff calculation is evaluated once per phase rather than for every scanned row.

## Directly measured size reduction

| Metric | Before deletion | After compaction and policy exercise |
| --- | ---: | ---: |
| PostgreSQL database allocation | 1,105,144,979 bytes | 440,700,051 bytes |
| Cron-history allocation including index | 725,532,672 bytes | 61,054,976 bytes |

The final aggregate observation above is **18:11:03 UTC**; ordinary background writes continue, so these are timestamped measurements, not fixed future sizes. The database is approximately **441 decimal MB / 420 MiB**, below the Free-plan **500 MB** database allowance. The one-time compaction reclaimed about **665 MB** of allocated database space. Actual `/data` filesystem available space was **1,065,218,048 bytes** at 18:05:37 UTC, versus approximately 602 MB before the bounded deletion.

## Migration and runtime verification

Applied through the normal linked CLI workflow, after a dry run confirmed each exact pending migration:

1. `20261017173813_successful_cron_history_retention.sql` — activates the narrowly named job.
2. `20261017180844_optimize_successful_cron_history_retention.sql` — additive correction of that job only. The applied activation migration is unchanged.

`supabase db push --linked --dry-run` subsequently reported **Remote database is up to date**. Both versions are recorded in `supabase_migrations.schema_migrations`.

The first policy definition hit its five-second timeout both before and after compaction; neither transaction committed. A bounded read-only plan/runtime investigation measured a cutoff-once selection at **328 ms**. The corrective definition then committed **1,593 newly expired successful rows in 2,946 ms**, within the unchanged five-second budget. These rows expired after the initial fixed archive cutoff and were removed under the separately approved ongoing retention policy; future expiry is not automatically archived by the one-time recovery copy.

Installed corrected command SHA-256: `04c86e253d98c66292232113e29a187e6bcdd9424284b0f3bcb68448814404cb`.

The synthetic local fixture passed the initial fingerprint guard, 3,000-row retention cap, failed/unfinished/recent/boundary protection, and activation → additive correction sequence. This is not a claim that the entire backend migration chain was rebuilt locally during this cleanup. Hosted full-chain CI verification is tracked separately after push.

**Automatic scheduler verification passed:** run ID **3,741,616** started **18:15:00.0888 UTC / 23:45 IST** and completed **18:15:03.692858 UTC**, status **succeeded**, duration **3,604.058 ms**. A subsequent read-only check found **zero successful records expired before that run's cutoff still remaining**, all **6,580 failed records** preserved, database allocation **440,798,355 bytes** and history allocation **61,153,280 bytes**. This is an actual pg_cron execution receipt, not a manually invoked substitute. The timestamped latest allocation remains about 441 MB.

## Existing work and safety boundaries

- All **11 original business jobs** retain fingerprint `677b87374d26ee95bcc21b1d89c4a556`; only the new maintenance job increases the total to 12. The latest five-minute aggregate showed recent successes for all 11 and **zero recent SQL-level failures**. A successful SQL cron record is not proof of an end-to-end downstream HTTP notification or real delivery.
- No business schedule/logging suppression, role/privilege/RLS weakening, read-only override, global checkpoint/configuration change, paid resource, purchase, support contact, Storage deletion or real-order mutation was made.
- An anonymous REST metadata-root probe returned HTTP 401 and was **not** treated as a successful application-health or authenticated-order test. No access permissions were changed to make a diagnostic pass. Normal real-order/customer-flow testing is separate.
- The original app/screenshot/release-document working-tree changes were preserved and are not part of the cleanup commit.

## Quota and follow-up boundary

The final Safari refresh of Supabase's organization Usage page showed **Database Size 0.456 / 0.5 GB (91%)**, with the Dastak per-project database panel showing **434.8 MB**. These provider accounting figures are below the allowance and are recorded separately from the direct SQL byte measurement; their labels/aggregation/refresh timing are not assumed identical. The earlier over-limit database usage display has therefore refreshed below quota too.

The general **grace period is over** notice remains visible. It says requests *can* be restricted if the organization is over quota; that notice alone is not evidence of a current restriction. The page also says usage may take up to one hour to refresh, and official documentation explains the separate billing-period-average Fair Use rule. **This cleanup does not establish that every possible service restriction has cleared or that every authenticated app operation was tested.** No paid upgrade or provider-contact workaround was used.

File Storage remains a separate near-limit resource (last dashboard observation about **0.929 / 1 GB**); no product image or evidence object was deleted. Future application/audit growth can still consume Free capacity even with successful-cron history bounded. A next-day stability check has not yet elapsed and no automatic expansion of deletion scope is authorized.

Sources: [Supabase database size and Fair Use accounting](https://supabase.com/docs/guides/platform/database-size), [PostgreSQL 17 VACUUM](https://www.postgresql.org/docs/17/sql-vacuum.html), [PostgreSQL initplan evaluation](https://www.postgresql.org/docs/17/using-explain.html).
