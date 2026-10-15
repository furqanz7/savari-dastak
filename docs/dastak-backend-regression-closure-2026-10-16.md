# Backend regression findings — local closure, 16 October 2026

**Final release status: completed in production with explicit owner approval.** Both reviewed forward migrations are applied; all 289 local/remote history entries match, and post-release error-level security advisors report no issues. The receipt and operational warning are recorded at the end. Earlier preparation/test checkpoints below are retained as historical evidence.

## Outcome

**All findings from the preceding empty-database audit are resolved and verified locally.** The expanded **289-file migration chain** passes on a new, empty Supabase platform database. The final suite passes with the ordinary Supabase `postgres` role, `supautils` enabled, and its original `anon, authenticated, service_role` hint roles intact. No permission assertions were skipped or replaced with metadata-only checks.

At the local-preparation checkpoint, **production was unchanged** and the two CLI-generated forward migrations awaited separate approval. That approval and release are now complete. The original 287 migrations remain byte-for-byte unchanged. Customer + Delivery app builds/UI were not altered, installed or deployed in this task.

| Verification | Final result |
| --- | --- |
| Empty-database chronological replay | **289 / 289 migrations**, no skips |
| Existing historical migration hashes | **287 / 287 unchanged** |
| Recorded version/name/SQL hashes versus source | **289 / 289 match** |
| Real database pgTAP contracts | **76 files; 2,081 assertions; zero failures, skips or TODOs** |
| Static database contracts | **166 passed; zero failed** |
| Runtime-pin safety tests | **5 passed; zero failed** |
| Repository no-client-DML SQL assertion | Passed |
| Anonymous/authenticated direct DML across public/private/audit/dastak_v1 | **0 unauthorized grants** |
| Final state | Auth fixture users 0; disabled application triggers 0; order availability/pricing defaults both 1 |
| Isolation | Cron off; 0 scheduled executions, HTTP queue entries or HTTP responses |

Sanitized machine-readable evidence: [regression closure evidence](evidence/dastak-backend-regression-closure-2026-10-16.json). The prior report remains a historical record, not a description of the final test status.

## Corrections

### Media metadata: RLS and foreign-key index

`Backends/Dastak/supabase/migrations/20261015214234_harden_governed_entity_media.sql` enables RLS on `dastak_v1.governed_entity_media` and adds `governed_entity_media_created_by_idx` on `created_by`. It adds no permissive client policy or grant. Existing audited security-definer media commands retain their intended access.

New pgTAP coverage exercises actual preparation, idempotent preparation replay and finalization through the service wrapper, exact asset activation/version advancement, restricted client grants, and denial of a Customer actor. It does not upload Storage bytes or claim a live upload test. No existing metadata row is rewritten by the migration.

### Legacy settlement: account for the already-existing platform fee

`Backends/Dastak/supabase/migrations/20261015214450_legacy_order_platform_fee_ledger.sql` fixes a real accounting omission. A later historical migration added a platform fee to the legacy order total, but settlement still credited only merchant payable, courier payable, merchant commission and delivery margin. Those four credits no longer equalled the whole-bill debit.

The forward correction adds the `platform_fee` ledger account code and a separate credit for the **already snapshotted** fee in new settlement postings. It retains the positive, balanced-ledger assertion, transaction uniqueness, helper execution privileges, and immutable journals. An explicit settlement replay test confirms no duplicate allocation, and a negative test confirms the balance assertion still rejects an empty transaction. Existing rows/journals, fee rates, prices, refund rules, provider checks and payment routing are not changed. No real payment is made and this is not a payout/provider activation.

Both migrations have short lock/statement timeouts and are tested in transaction scope. No historical migration is edited to hide the gap.

### Fixtures and expectations: current versus historical behavior

- Current submission fixtures now provide an approved, online, covered rider and positive known stock. Restaurant discovery has an owned delivery address. Supporting fixture functions live only in `pg_temp`, included explicitly from `fixtures/customer-area.sql.inc`, and roll back with each test.
- Added explicit current-submission rejection tests for an unapproved rider, NULL stock and zero stock, including absence of a partial idempotency result. The production admission guards were not weakened.
- Hand-built older projection/cancellation/tracking fixtures describe pre-policy, fixed-price historical orders. Their rollback-only setup explicitly uses historical availability/pricing version 0; real submission tests remain on current defaults. The existing unknown-stock compatibility scenario is separately marked historical. Post-test audit confirms both database defaults are still **1**.
- Governance fixtures no longer require superuser-only `session_replication_role`. They use table-scoped user-trigger suspension only while seeding/resolving their rollback fixture, preserve foreign-key checks, and re-enable guards before exercising the governance assertions. The full suite passes as `postgres`; no new production grants are introduced.
- Provider test amounts include the already-existing legacy platform fee. V1 payment fixtures send the authoritative reserved payment amount rather than a hardcoded items-only subtotal. Canonical SKU assertions distinguish item subtotal from whole-bill fees and preserve an additional whole-bill immutability assertion.
- Customer notification-route expectations now include enabled `RIDER_ASSIGNMENT_PENDING` / `customer.assigning_rider`, not the disabled earlier mission-created route. Catalogue expectations include the approved 80 rails.
- The MTR parent-correction test now supplies two rollback-only DRAFT source products, activates the required fixture target taxonomy, executes the exact historical correction, and verifies both SKU UUIDs/slugs survive. It no longer depends on production-only operational imports.
- A pending constraint-event queue is flushed before the existing pickup test's table-trigger fixture setup, without changing its production inventory trigger.

## Database runtime fix

The old image `public.ecr.aws/supabase/postgres:17.6.1.106` crashes on function EXECUTE denial under the hint roles. The minimal constant-returning-function probe reproduced the issue independently of Dastak. Supabase maintainers identify `supautils` 3.2.3 and Postgres image **17.6.1.155 or later** as containing the fix: [upstream resolution](https://github.com/supabase/supautils/issues/214).

Verified here with image `public.ecr.aws/supabase/postgres:17.6.1.155`, digest `sha256:3866d94d8426927e8db3f1c5d790752292bfbe27b5f1f46e199ae1b7d3c1710b`. The previously crashing denial now returns the expected permission error, and the original permission-test file passes. No JIT, hint-role or `supautils` workaround is used in the final run.

`scripts/pin-local-test-postgres.mjs` pins this reviewed runtime through the installed CLI's supported version-cache path for an **unlinked local/CI project**. It refuses linked/environment-configured projects, other project/major identities, or an existing different pin. Five tests cover these safeguards and repeat safety. The Dastak backend CI job invokes it before starting Supabase. This workflow edit preserves the existing unrelated Swift-test changes. It has been verified locally; **a hosted GitHub Actions run was not dispatched**. No globally installed CLI or pre-existing user database/runtime selection was upgraded.

## Clean rebuild and evidence

Successful final project: `/private/tmp/dastak-full-rebuild.telJgQ`, `DastakRebuild20261016R4`. The fixed image was selected before bootstrap; Auth, Storage and Realtime platform schemas were present. Before staging application SQL, the database had no Dastak schema/accounts table, zero Auth users and empty history. Cron was disabled; all test services were moved to the internal-only Docker network with no outbound gateway.

The exact SQL files were staged with SHA-256 checks and replayed through the guarded transaction-aware runner. The final manifest hash is `414a48042a283eb806fd7455cf5ebc91700f52502390a0a780f2a067331cd147`. The old activation's hash remains `1a4c428bcfa1ff85b35c392497c873f91f7d5c3ac5a569dea10a66ad6ac5ae84`.

The final catalogue remains version 1 ACTIVE, **121 nodes / 134 sources / 95 seeded active SKUs / zero invalid placements**, with the same map fingerprints as the earlier production reconciliation. This is still migration seed data, not a production-data/Storage/secret restore drill.

An intermediate R3 attempt deliberately stopped at migration 53 because that test harness disabled the Realtime platform schema. R4 restarted from a genuinely fresh platform with the prerequisite restored, not from a partially advanced application schema. This was a harness correction, not an application SQL change or skipped migration.

Key commands:

```sh
node Backends/Dastak/scripts/pin-local-test-postgres.mjs /private/tmp/dastak-full-rebuild.telJgQ
node Backends/Dastak/scripts/stage-clean-rebuild.mjs /private/tmp/dastak-full-rebuild.telJgQ
node Backends/Dastak/scripts/replay-clean-rebuild.mjs /private/tmp/dastak-full-rebuild.telJgQ
node Backends/Dastak/scripts/test-clean-rebuild.mjs /private/tmp/dastak-full-rebuild.telJgQ release-final
node --test Backends/Dastak/tests/pin-local-test-postgres.test.mjs
# In Backends/Dastak:
deno test --config supabase/functions/deno.json --lock supabase/functions/deno.lock --frozen --allow-read supabase/tests/database/
```

Replay requires an empty, unlinked, scheduler-disabled and internal-network-only platform; it refuses the now-populated evidence database. The final contract runner uses normal `postgres`, not `--fixture-superuser`. Syntax checks and `git diff --check` passed. No complete web/iOS/Edge/concurrency suite or hosted CI run is implied by these database results.

The generic CLI security advisor was attempted but could not reach the deliberately unexposed host DB port. It is **not recorded as an advisor pass**. Targeted actual SQL privilege/RLS/index/default/trigger checks, repository security SQL, and all database authorization tests passed over `docker exec`. Supabase's RLS/least-privilege skill guidance informed default-deny media hardening without broad client grants; [official RLS guidance](https://supabase.com/docs/guides/database/postgres/row-level-security).

## Release boundary

The audit's local correction/verification work is complete. The production application described here was separately gated and has now completed; see the receipt below. Release required read-only schema/function/history drift checks and current error-level advisors, followed by the exact two migrations in order and independent verification. No unrelated migration push, order creation, provider/payout activation, data rewrite, fee-policy change, app build or deployment was included.

## Cleanup

All task test stacks were stopped without deleting their data volumes. Docker showed no running containers, and Colima was restored to its original stopped state (`colima status`: not running). The pre-existing user database was not reset, migrated or deleted. Task evidence, test volumes and downloaded images remain recoverable; no personal, Codex or ChatGPT data was deleted and no broad cache/image prune was run.

## Approved production release receipt — 16 October 2026

The owner explicitly approved applying exactly `20261015214234_harden_governed_entity_media.sql` and `20261015214450_legacy_order_platform_fee_ledger.sql` after drift/security preflight. The branch/HEAD remained unchanged. All 289 local migration hashes matched the clean-rebuild evidence before release. The linked project identity matched the reviewed production project.

Preflight found exactly 287 recorded migrations and only these two pending. The existing settlement body matched its historical source, its grants/owner/search path/security-invoker metadata were correct, both immutable ledger guards were enabled, and direct client DML grants were zero. The media table had nine rows, no client SELECT grants and no RLS policies; the legacy journal had zero entries/transactions. Error-level security advisors reported **No issues found**. A CLI dry run listed exactly the two approved files. Five runtime-pin tests and 166 static database contracts passed again; the earlier 76-file/2,081-assertion isolated database pass remains the runtime-behavior evidence, not a production mutation test.

Executed the normal `supabase db push --linked --workdir Backends/Dastak --yes`, without `--include-all`, roles or seed flags. It applied precisely those two migrations and completed successfully.

Independent read-only post-release verification confirms:

- **289 matching local/remote migrations; zero pending/mismatched versions.** All 287 prior history receipts are unchanged.
- Both new history entries contain SQL matching the reviewed migration files after normalizing CLI statement splitting/comments/whitespace. Recorded SQL MD5 receipts: media `bc98653b4b230f1e3dd9a1613318fd7f`; ledger `e54535bdc5e6ad8fed12c348aaeaadb2`.
- Media RLS is enabled, the creator index is **valid and ready**, all prior indexes and ACLs remain unchanged, and there are still nine media rows. No permissive policy was added.
- The account-code constraint is validated and includes the new platform-fee account. The compiled settlement body matches the tested correction; its security mode, owner, volatility, empty search path and execution grants are unchanged.
- Both immutable journal triggers remain enabled with identical definitions. Existing ledger row counts remain zero; no historical journal was rewritten or backfilled. Direct client DML grants remain zero, client media SELECT remains denied, and clients still have no domain-schema USAGE.
- Error-level production security advisors again report **No issues found**. This is the scoped advisor gate, not a universal security certification.

**Operational warning:** CLI 2.90.0 emitted `SET LOCAL can only be used in transaction blocks` for the migrations' timeout settings. Those settings therefore did not bound this release. Both migrations finished and their complete installed state/history were independently verified; this receipt makes no claim that the two migrations committed atomically together or that their `SET LOCAL` timeouts were effective. Do not rerun applied files or rewrite historical migrations to suppress that warning. Future release-tooling work should explicitly validate transaction boundaries/timeouts.

Sanitized permanent receipt: [production evidence](evidence/dastak-backend-production-release-2026-10-16.json). Detailed temporary evidence: `/private/tmp/dastak-backend-release-production-{before,after,structural-checks}.json`, `...-apply.log`, `...-dry-run.log`, `...-advisors-{before,after}.log`, and `...-migrations-{before,after}.log`. No orders, payments, fee-rate changes, provider/payout activation, app/Edge deployment, database runtime upgrade or personal-data deletion was performed. Colima remains stopped.

Supabase's migration-history guidance and the skills' least-privilege checks informed the exact pending-file dry run, forward-only application and independent privilege/history verification: [official migration guidance](https://supabase.com/docs/guides/deployment/database-migrations).
