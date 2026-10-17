# Approved cleanup execution checkpoint — 17 October 2026

**Current summary:** the real encrypted recovery checkpoint, 1,506,093-row bounded deletion and physical reclamation are complete; the additive retention correction passed both manual and actual hourly scheduled execution. See [RESULTS.md](RESULTS.md) for current measurements and remaining verification boundaries. The chronological sections below preserve earlier failure/gate evidence; they are not all current blockers.

## Authorization

The owner answered **yes please** to executing the protected recovery archive, bounded old-success-history cleanup, and three-day retention policy, with compaction conditional on disk-headroom and quiet-window checks. No paid service is authorized. This approval is recorded; another identical cleanup approval is not needed. The operational safety gates below still apply.

## Directly checked before any deletion

- Authoritative worktree: `codex/dastak-v1-launch`, HEAD `9ad1125ed2d9361de3145f126ff00500004884e7`. Existing local changes were preserved.
- Read-only capability query at **17 October 2026 21:32:38 IST**: database 1,102,711,955 bytes; history table 723,116,032 bytes. Existing SELECT/INSERT/DELETE/MAINTAIN privileges and BYPASSRLS are present; superuser/table-owner membership are not. RLS remains enabled, with no referencing foreign keys or triggers found for history.
- Separate read-only aggregates found **zero active V1 orders, zero active delivery missions and zero active return missions** at that observation. This is not a perpetual quiet-window guarantee; activity must be checked again immediately before any disruptive step.
- Supabase Infrastructure showed **1.37 GB used of 2 GB**, approximately **0.63 GB free**; database approximately 1 GB, WAL 128 MB, system 209.8 MB. Values are rounded dashboard measurements, not an exact filesystem-free probe. Disk configuration was not changed.
- The approved plan's conservative allowance for another current history-table/index copy **plus WAL/workspace is not established** by this available space. No deletion or compaction may proceed while this gate remains unresolved. Do not silently substitute a riskier space model, truncate/recreate the extension table, remove other data, buy disk, pause workers or override read-only mode.
- The Mac separately has approximately 9.8 GiB free and FileVault is On. Local free space does not resolve the server-disk gate.

## Recovery archive preparation

The installed Supabase CLI's documented `db dump --dry-run` generated existing temporary-login connection metadata. Credential values were kept in process memory and not printed or written to source/artifacts; only success/variable-name/error-category metadata was returned. No database data dump was executed by this command.

A direct `psql` connection with **verify-full** and the system CA bundle failed certificate validation. The second bounded probe confirmed a certificate-category error rather than password, role, capacity or network errors. Certificate validation was not disabled or weakened, and no password/credential was reset.

Current official Supabase documentation directs users to download the project CA from Database Settings. The authenticated project page's Download certificate button was selected. Safari displayed its **Allow downloads from supabase.com** prompt, but native UI interaction then returned `noWindowsAvailable`; the download is not confirmed. No matching project CA file was found in Downloads. The owner was asked to unlock the Mac and allow this requested download; no password was requested in chat.

**No production recovery archive exists yet. No production recovery rehearsal passed.** Do not treat the prior synthetic fixture as the real checkpoint or proceed with deletion without the real archive.

## Actual mutations so far

No production job-history deletion, VACUUM/ANALYZE, retention-job installation, migration creation/application, Storage removal, privilege/configuration change, paid upgrade, purchase, push or deployment was performed. The CLI's normal temporary-login initialization is not a cleanup or application-data change. Only this local execution-status document was added.

## Resume requirements

1. Finish the authenticated public CA download and validate a verify-full connection without printing secrets.
2. Create the approved private encrypted archive and verify an isolated local restore. This preparatory read/export may proceed without deleting anything while the compaction gate remains closed.
3. Resolve server-headroom safety through supported diagnostics and an evidence-backed approved reclamation route. If the existing conservative plan cannot be met, report the exact alternative and obtain approval for any material risk/scope change; no paid fallback.
4. Recheck current activity, backup validity and headroom. Only then run the already-authorized bounded cleanup, conditional compaction and narrow retention installation, with complete before/after verification.

## Follow-up after owner unlocked the Mac

Safari's authenticated download permission was accepted and the project CA was downloaded to `/Users/Furqan/Downloads/prod-ca-2021.crt`. Its SHA-256 certificate fingerprint is `807025AD50D4ED219D2C9C7D299C004F824EB00CF7F65AFEF607D07B72E6CAFA`. A direct connection using verify-full and this CA succeeded with SSL true and the session read-only. The previous certificate-download gate is resolved.

The CLI's temporary login must explicitly `SET LOCAL ROLE postgres` within the read-only transaction to use its already-authorized underlying role; the default temporary login lacks direct history-table permission. A bounded aggregate verified the role switch succeeds and sees approximately 1.685 million rows. No role membership, grant, RLS policy or credential was changed/reset to achieve that.

`cron-history-recovery.mjs` was prepared as a recovery-only helper. It has no production DELETE/maintenance/install operation. It enforces read-only live sessions, exact project checks, verify-full TLS, a fixed repeatable-read snapshot, explicit column export, canonical row fingerprints, streaming gzip/AES-256-GCM encryption, Keychain-held random keys and private local output permissions. Its separate restore mode targets only a new local Unix-socket cluster. A valid archive requires completed GCM finalization, a SHA-256 manifest and a successful restore receipt.

The first protected export stopped on the temporary-role issue and was not accepted. After the role correction, the direct export was incomplete under its bounded execution; an alternate existing free session pooler was then attempted, also with verify-full and existing login permissions. Neither transport produced a complete archive/manifest. Partial ciphertext files exist under the private recovery folder, but **none is a valid recovery checkpoint**. No raw history payload/key/connection password was printed, committed, sent to CI or placed in a shared repository. These failed private output copies are not evidence of any production deletion.

The streaming child initially reported only a generic failure code, so the exact server/client failure must not be asserted from that code alone. Timeout diagnostics were subsequently improved to distinguish a client deadline, database statement timeout, TLS failure and role permission failure, with a hard-stop fallback. This improvement has syntax/static checks only; it was not used to launch another full production export. Per the Supabase skill's repeated-failure guidance, no further identical full export was retried.

The helper's source syntax and diff whitespace checks pass. Its full production archive/restore path has **not** passed; the earlier synthetic selection/archive fixture is not substituted for it. A draft provider-support request is prepared locally in `NO_COST_SUPPORT_DRAFT.md`; no message has been sent.

The task is **incomplete, stopped before destructive changes at its safety gates**. Owner approval was received; safe execution prerequisites, not consent for the same cleanup, are the outstanding issue. The private archive is still unverified and conservative server-headroom clearance is still absent. No retention migration or job has been installed.

References: [Supabase verified TLS setup](https://supabase.com/docs/guides/platform/ssl-enforcement), [PostgreSQL compaction requirements](https://www.postgresql.org/docs/17/sql-vacuum.html), and the [approved free-only plan](FREE_ONLY_PLAN.md).

## Renewed owner instruction and verified recovery checkpoint

The owner subsequently declined provider contact and renewed permission: **you can do the cleanup**. No message was sent to Supabase and no paid resource is authorized.

The repeated export failure was diagnosed with a bounded EXPLAIN/timeout probe: stale table statistics selected a large sequential scan/sort even for a 2,000-row ordered batch. A table-specific `ANALYZE cron.job_run_details` completed under a 20-second statement budget and 1-second lock budget. It changes planner metadata, not history records. The new plan uses `job_run_details_pkey` without that sort.

A chunked repeatable-read export then completed: **1,506,093** eligible rows, encrypted archive **65,957,964 bytes**. A private local, Unix-socket-only PostgreSQL 14.19 restore verified all **1,506,093 unique IDs**, zero eligibility violations and zero canonical-row fingerprint mismatches. AES-GCM authentication and SHA-256 checks passed. The generated key is held in the Mac Keychain; archive and typed candidate manifest are outside the repository, private and FileVault-protected. This is a backup of the cleanup candidates, not a complete database backup. An initial local verification setup hit the macOS Unix-socket pathname limit; the disposable fixture was moved to a short private path and the real restore passed. No data was lost in that local setup failure.

Actual `/data` available space was verified through the supported Supabase Metrics API using the existing service-role credential in memory: **603,144,192 bytes** at 17:25:03 UTC. No credential was printed/saved or regenerated. The larger `/` filesystem is not used as the database headroom measure.

Initial deletion and physical compaction have separate space budgets. Bounded 2,000-row DML does **not** create another full table copy. The initial-cleanup runner requires at least 450 MiB available before starting, stops below 300 MiB available or on WAL growth over 192 MiB above baseline, and checks work/locks/WAL every 25 batches (filesystem metrics at most once/minute). It never overrides a server read-only default, disables business jobs, changes RLS, or rewrites the table. The conservative full-table-copy-plus-WAL compaction gate remains closed until a fresh post-deletion assessment; these bounded-DML safeguards are not a declaration that FULL compaction is safe.

The new retention migration and synthetic runtime fixture are prepared locally. The fixture passed the archived-fingerprint guard, 3,000-row hourly cap and failed/unfinished/recent/boundary protections. The migration has **not yet been applied** at this checkpoint. All preexisting local/remote migration versions matched before creating it. Original migrations and unrelated local changes remain untouched.

## Completed bounded deletion and refined physical-space evidence

All **754 batches** committed: **1,506,093 attempted/deleted, zero skipped**. The original final aggregate hit its 15-second statement timeout after deletion had completed; this was not an uncertain deletion outcome. Every attempt has its matching commit acknowledgment in the protected receipt log. No deletion was replayed. A second bounded table-specific ANALYZE completed, and a single-pass read-only verification passed at **17:53:28 UTC**: **182,850 rows remaining, all 6,580 failures retained, zero fixed-snapshot expired successes remaining**, and original schedule fingerprint `677b87374d26ee95bcc21b1d89c4a556` unchanged. Database allocation was still 1,105,276,051 bytes; history allocation 725,647,360 bytes. Logical removal is not physical reclamation.

Only migration `20261017173813_successful_cron_history_retention` was pending in `db push --dry-run`; it was then applied through the normal linked CLI workflow and recorded in migration history. The new hourly job is ID **35**, active, owned by `postgres`, minute 15 UTC. Its installed command exactly matches the reviewed migration (SHA-256 `4e79677e51692bb8c96a91d36e61a0842a2082925ad87d24d6076a517456946c`). An actual EXPLAIN confirms one 3,000-row LIMIT and primary-key index lookups. The first manual policy exercise timed out at its 5-second budget and rolled back; **successful execution is not yet verified**. No timeout was relaxed and no scheduled-run success is claimed. Physical bloat still affects this query; it must be retested after reclamation, or the new job must not be treated as healthy.

The initial conservative rewrite allowance (128 MiB new copy + twice that for WAL + 128 MiB independent workspace/growth reserve) did not fit the post-delete filesystem headroom (~400 MB available), so no FULL operation was attempted at that gate. Live checks confirmed automatic vacuum completed at 17:52:10 UTC, autovacuum/track_counts enabled, no replication lag/pinned xmin, no old snapshot or long cron run, and no active order/delivery/return. WAL recycling can retain files based on prior checkpoint-cycle usage; it is not assumed to instantly free space.

To replace the uncertain old-index size estimate with direct evidence, a dedicated bounded transaction created a **temporary, unlogged server-side copy of only the retained live history rows**, rebuilt its single unique run-ID B-tree, returned only counts/sizes, then **ROLLBACK removed the temporary objects**. The real extension table was never truncated, replaced or recreated. At **18:01:54 UTC**, 183,196 retained rows occupied **57,147,392 heap bytes + 4,136,960 index bytes**, **61,292,544 total bytes**. A following `to_regclass` check confirmed the temporary table was absent. No raw command/response contents left the server in this probe.

The refined space model uses the independently aligned live-tuple/page bound, the **measured rebuilt index** with an extra 1 MiB plus 64 bytes per intervening new row, another 16 MiB layout allowance, and at least 25% over the measured total, rounded upward to 16 MiB. A measurement must be under 15 minutes old with at most 5,000 intervening rows. It retains the same **twice-new-copy WAL allowance and separate 128 MiB workspace/growth reserve**. For these measurements the new-copy bound is about 80 MiB, hence required available space **368 MiB**. This is evidence-based refinement of the retained working set, not a removal of WAL/reserve/quiet-window gates. A fresh assessment must pass immediately before the already-authorized single-table, 1-second-lock/60-second-statement-budget FULL operation. No global checkpoint/configuration/privilege change is used to force the gate.

## Physical reclamation and actual retention correction

The fresh space/quiet-window assessment passed at 18:04 UTC: 400,515,072 available bytes against 385,875,968 required including all reserves. No active work, old snapshots, slot xmin, replication lag, history waiters or long cron runs were found. The single bounded FULL operation completed at **18:04:36 UTC**. Database allocation became **440,560,787 bytes**, history allocation **60,915,712 bytes**; all 6,580 failures and the original schedule hash were preserved. `/data` available space subsequently measured over **1.065 GB**. No timeout was relaxed and no repeated FULL operation was performed.

The initial recurring query still timed out at five seconds after compaction. That disproved the provisional assumption that physical bloat alone explained its runtime. A read-only EXPLAIN ANALYZE compared selection variants; a scalar-subquery cutoff created one-time initplan evaluation and completed in **328 ms**. Additive migration **20261017180844_optimize_successful_cron_history_retention** changes only the new job's command to use this evaluation, leaving schedule/cap/eligibility/ownership/time budgets unchanged and the first applied migration untouched. Its activation → correction sequence passed the synthetic fixture, the exact pending version passed CLI dry run, and the version was applied through normal CLI migration bookkeeping.

The installed corrected policy committed **1,593** newly expired successful rows in **2,946 ms** at 18:10 UTC. Both migration records, installed command hash and 12-job total were verified; all 11 business schedules still match the baseline. The subsequent five-minute business-job aggregate showed successes for every original job and zero SQL failures. This is not an end-to-end application/delivery test. Final migration dry run reports no unapplied local versions.

The owner separately authorized committing/pushing **only the two cleanup migrations and cleanup verification files**, preserving existing app/screenshot changes. Encrypted archive/key material remains outside source control. No support draft was sent; the declined support draft is not included in the cleanup commit.

The actual first hourly job completed successfully at **18:15:03.692858 UTC**, run **3,741,616**, duration **3,604.058 ms**. The 18:15:16 UTC aggregate found **zero successes expired before the run's cutoff remaining**, all **6,580 failed rows retained**, database **440,798,355 bytes** and history **61,153,280 bytes**. This closes the scheduled-execution gate without changing the hourly schedule for testing. Next-day stability and Supabase's delayed/Fair Use quota-warning clearance are not yet established.

The subsequent authenticated Safari Usage-page refresh also showed database accounting below quota: **0.456 / 0.5 GB (91%)**, Dastak per-project panel **434.8 MB**. The general grace-period notice remains, but its conditional warning is not evidence of an active restriction by itself. No full authenticated app-health or next-day check is claimed. The first cleanup-only commit **93a5957** was pushed to the existing `codex/dastak-v1-launch` branch; unrelated app/screenshot changes and the declined support draft remained uncommitted.
