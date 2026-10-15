# Catalogue activation history reconciliation — 16 October 2026

Status: **completed in production with explicit owner approval**. Customer + Delivery's product wrap is unchanged. No phone/web build or Edge deployment was required. The preparation notes below are retained as historical release evidence; the final activation receipt is recorded at the end.

Follow-up verification: the complete 287-file chronological migration chain has now passed against a fresh isolated Supabase database, including this preserved old activation and the new correction. The broader database contract suite is not all green. See [the full rebuild report](dastak-full-backend-rebuild-2026-10-16.md) for the exact scope, results and separately open findings; the bounded-fixture limitation below describes the earlier reconciliation tests, not this later full-chain replay.

## Why the old migration remains pending

`20260929191745_activate_reference_catalogue_browse_map.sql` was absent from linked production history, although browse map version 1 was already ACTIVE. The old file expects 112 nodes and 125 sources, including a Dairy Alternatives source. The current reviewed map has 121 nodes and 133 sources, including the later approved Janamaz and Tasbih changes. Replaying the old fixed-count activation would fail and must not undo those changes.

The missing Dairy Alternatives source is still a genuine gap: its active canonical category and five subcategories exist, and the correct rail exists, but no source links that category to the rail. There are no active SKUs in that category today. The read-only audit found **572 active SKUs, zero invalid placements**; all current active products have exactly one destination and one rail under that destination. This explains why current browsing works without implying that the missing source should be ignored.

## Prepared correction

- Preserve the old migration **byte for byte** for chronological fresh-environment replay. SHA-256: `1a4c428bcfa1ff85b35c392497c873f91f7d5c3ac5a569dea10a66ad6ac5ae84`.
- New CLI-generated forward migration: `20261015203400_reconcile_catalogue_browse_activation.sql`. It requires the expected active map, correct Dairy Alternatives rail/parent/taxonomy, and no conflicting source/exclusions. It adds only `(version=1, node_key=dairy-alternatives, source_order=10, type_slug=dairy-bread-eggs, category_slug=dairy-alternatives)` and validates unique destination/rail coverage for every active SKU. It does not recreate taxonomy or change products, prices, stock, orders, payments or permissions.
- `Backends/Dastak/scripts/reconcile-catalogue-browse-activation.mjs` provides a read-only `inspect` mode and an explicitly gated production `apply --approved-production` mode. **Apply has not been run.**
- The scoped release transaction locks map configuration/history briefly, checks the exact reviewed map fingerprints and required later migration, runs the forward correction, verifies every previous node/source is unchanged, and records exactly two history entries: the new correction and a transparent supersession receipt for the old activation. The old entry explicitly states its historical fixed-count SQL was NOT replayed, and records the original file's hash. An already-recorded reconciliation or any drift aborts. Correction and both history entries commit together, or all roll back. No broad `db push`, unrelated migration, function deployment or token/secret operation is included.

This follows Supabase's separation between live database state and migration tracking: [official migration-history guidance](https://supabase.com/docs/guides/deployment/database-migrations#diagnosing-and-fixing-sync-errors). Because one effect was missing, a history-only repair was rejected; the forward correction must succeed before supersession is recorded.

## Live read-only preflight

Linked project: `zmtsolkfxlrxepshnjdf`. Node fingerprint `e655fb9301b2ef89c609acbd07c63a08`; source fingerprint `95aea904789558567b1aa4d60d03958f`. These are deterministic MD5 checksums of non-secret ordered configuration rows used to detect accidental drift, not cryptographic authenticity claims. The runner pins them and compares again under lock at activation. After success, expected counts are **121 unchanged nodes and 134 sources**; the one new source is the only catalogue change.

CLI linked migration list succeeded. The only local-only entries at this checkpoint are the old activation and the newly prepared reconciliation. Error-level linked security advisors reported **No issues found**; no claim of a full security/performance audit is made. The final read-only runner inspection confirmed the original map fingerprints/counts, 572 valid active SKUs, zero active Dairy Alternatives SKUs and the unrecorded old activation. No production write or rollback-based production mutation test was used.

## Local verification and limitations

**20 tests passed, zero failures, zero skips** using a new isolated local PostgreSQL 14 cluster on a private Unix socket. Tests cover the untouched old file; required explicit release mode; active soy/milk/prayer mapping; empty categories; forward idempotence; rejection of draft/other active maps, altered rail/taxonomy, source conflicts and exclusions; missing/duplicate rails; inactive/unresolved taxonomy; original-size draft activation followed by the forward correction; exactly two atomic history entries; repeat-release refusal; configuration-drift refusal; and rollback of the inserted source/history after an injected post-patch failure.

The historical replay test is a bounded original-size schema/data fixture, **not a full empty Supabase migration-chain reset or a production clone**. SQL tests run only against the dedicated `catalogue_reconcile_test` database after asserting that its data directory matches the newly created private test socket directory. Without `DASTAK_CATALOGUE_TEST_SOCKET`, database cases are explicitly skipped; do not report a default unit-only run as the full database pass.

Commands:

```sh
node Backends/Dastak/scripts/reconcile-catalogue-browse-activation.mjs inspect
DASTAK_CATALOGUE_TEST_SOCKET=/private/tmp/dastak-catalogue-pg.dsiCgc node --test Backends/Dastak/tests/catalogue-browse-reconciliation.test.mjs
```

The task-created test cluster is stopped after verification; retained data/logs are disposable local evidence. Script syntax and `git diff --check` passed. Logs: `/private/tmp/dastak-catalogue-reconciliation-tests-final.log`, `/private/tmp/dastak-catalogue-reconciliation-inspect-final.json`, `/private/tmp/dastak-catalogue-reconciliation-advisors.log`, `/private/tmp/dastak-catalogue-reconciliation-migrations-before.log`.

## Production gate

Obtain explicit owner approval to apply the one mapping correction and record the two exact migration entries atomically. After approval, rerun read-only inspection; stop on any drift. Run the scoped apply mode, then verify live map identity, exact source shape, unchanged prior configuration, product coverage, both history receipts, remaining migration-list differences and error-level security advisors. No real order, payment, catalogue product edit, app installation or deployment is needed for this maintenance.

## Approved production activation — completed 16 October 2026

The owner explicitly approved the exact repair. Branch/HEAD remained unchanged; existing unrelated edits were preserved. Repeated live read-only preflight matched the reviewed node/source fingerprints and 572 valid active SKUs. All **20 isolated PostgreSQL/runner tests passed again**, zero failures/skips. Error-level security advisors reported no issues before application.

Executed only the scoped `apply --approved-production` runner. The transaction succeeded: one Dairy Alternatives source was inserted, and old activation supersession/new forward-correction history entries were committed atomically. The old fixed-count migration SQL was not replayed. No broad migration push, app build/install, Edge/web deployment, product/stock/price/category edit, order action or payment operation was performed.

Independent post-release read-only verification confirms:

- Browse version 1 remains ACTIVE. All **121 nodes are byte-equivalent under the ordered-row checksum** to the preflight configuration; all **133 prior source rows are likewise unchanged**.
- There are now **134 sources**, with exactly the reviewed Dairy Alternatives source and no exclusions. The full source checksum is `c662c330891c50f4a66dd78e017209cb`.
- All **572 active SKUs still have valid unique destination/rail placement**; zero invalid placements and zero active Dairy Alternatives SKUs. No products were invented to fill the empty shelf.
- Both history entries exist. The old entry explicitly records supersession and that its fixed-count block was NOT replayed. The new entry's stored SQL MD5 `b51e2dba06e4f1887395e7ae9e8aa45c` matches the exact local forward migration.
- The linked CLI migration list has **287 matching local/remote entries, zero mismatches**: the pending migration gap is closed.
- Error-level security advisors again reported **No issues found**. This is the same bounded advisor check, not a full security certification.

The task-created local test server was stopped after verification; retained temporary test data/logs remain recoverable. Evidence: `/private/tmp/dastak-catalogue-reconciliation-apply.log`, `/private/tmp/dastak-catalogue-reconciliation-approved-before.json`, `/private/tmp/dastak-catalogue-reconciliation-approved-after.json`, `/private/tmp/dastak-catalogue-reconciliation-production-verification.json`, `/private/tmp/dastak-catalogue-reconciliation-migrations-after.log`, `/private/tmp/dastak-catalogue-reconciliation-advisors-before-apply.log`, `/private/tmp/dastak-catalogue-reconciliation-advisors-after.log`, `/private/tmp/dastak-catalogue-reconciliation-activation-tests.log`. Supabase migration-history separation and short, timeout-bounded Postgres transactions informed the scoped repair.
