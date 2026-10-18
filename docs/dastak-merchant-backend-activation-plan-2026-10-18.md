# Merchant backend activation — scoped preparation, not a release receipt

18 October 2026. Follow-up to the [completion audit](dastak-merchant-completion-audit-2026-10-18.md) and [native payout-controls checkpoint](dastak-merchant-payout-controls-implementation-2026-10-18.md).

**Current outcome:** exact local activation candidates and dependencies identified; four isolated database fixtures and the complete Edge suite passed again. No production database, migration history, deployed function, website, app installation, provider configuration or money movement was changed. This document is not authorization to activate anything.

**Later rebuild gate closed:** the [expanded full-chain rebuild](dastak-merchant-full-rebuild-2026-10-18.md) now passes all 295 migrations, the 76-file/2,081-assertion real database suite and a 113-assertion integrated Merchant scenario (32 new assertions). Source/history hashes match. This supersedes the local-rebuild pending status below; hosted preflight, activation authority/execution, device acceptance and distribution remain pending.

**19 October hosted preflight:** the [read-only production check](dastak-merchant-production-preflight-2026-10-19.md) now confirms 291 applied migrations, exactly the four reviewed pending candidates, unchanged earlier receipts, matching inspected prerequisite/deployed source and no error-level security advisor findings. This closes the scoped hosted-baseline check at its timestamp, not the release-runner rehearsal, source checkpoint or activation approval. No production application/deployment occurred.

**19 October release rehearsal:** the [bounded local release procedure](dastak-merchant-release-rehearsal-2026-10-19.md) now passes explicit rollback, conflicting-lock timeout, statement-timeout rollback, atomic local commit and already-applied rejection against a fresh real 291-file baseline. Post-release database contracts remain green. A separate-index source tree is prepared without touching the real index; it is not a commit or push. Hosted activation authority and execution remain separate.

## Source guard and immutable preparation evidence

Worktree: `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`; branch `codex/dastak-v1-launch`; unchanged HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`. Solo work. Existing Merchant implementation changes and unrelated Customer fixtures/artwork/release documents/dependency-lockfile change were preserved. This preparation adds this document and its evidence manifest, plus a navigation/status note in the completion audit; no runtime source was edited.

[Machine-readable candidate manifest](evidence/dastak-merchant-activation-manifest-2026-10-18.json) records SHA-256 hashes for the four migration candidates, the three Edge entrypoints and their recursively discovered static relative TypeScript imports, current config and dependency lock. It also fingerprints the ordered **295-file local migration chain**. This is a source snapshot, not an Apple archive, deployed bundle attestation, current hosted-history assertion or full-chain test pass. Any change invalidates the relevant source snapshot and requires review/reverification before activation.

No tracked historical migration differs from HEAD. The four 18 October Merchant files are currently untracked. Existing source work has not been committed or pushed by this preparation. A scoped reproducible source checkpoint is a release prerequisite; do not deploy an arbitrary dirty workspace or stage unrelated files with `git add .`.

## Exact candidates and dependencies

| Order | Migration | Backend dependency | Effect and caution |
| --- | --- | --- | --- |
| 1 | `20261018003730_merchant_scoped_order_detail.sql` | `dastak-v1-orders`: `merchantOrderDetail` | Adds an authenticated, branch-authorized historical order projection with explicit field allowlists. No Customer get or Admin authority is reused. |
| 2 | `20261018014110_merchant_active_and_paged_history.sql` | `dastak-v1-orders`: `merchantFulfilmentHistory` and the existing Merchant list operation | Replaces the existing Merchant list implementation to retain active work, adds cursor history and a fulfilments index. This is not purely a new unused endpoint: old Merchant callers also receive the changed list behavior. |
| 3 | `20261018131824_merchant_catalogue_and_location_pages.sql` | `dastak-v1-catalogue`: `merchantInventoryPage`, `merchantLocationsPage` | Adds authorized paged retail catalogue and location discovery; existing catalogue read/write operations remain intact. |
| 4 | `20261018151210_merchant_payout_review_guards.sql` | `earnings`: `merchantRoyaltyControlsSnapshot`, `requestMerchantRoyaltyWithdrawal` | Adds per-organization management permission and exact destination-review locking before delegating original financial reservation/posting. No provider activation, new financial table or historical ledger rewrite. |

There are **three** existing function deployments, not four new functions. Apply and verify database changes before enabling their Edge routes; verify those routes before distributing a Merchant binary that depends on them. An additive database-only interval is preferable to new Edge routes calling absent RPCs, but the shared Merchant-list change still needs observation.

The orders entrypoint statically imports the catalogue handler as part of its dependency graph. Hash/check the complete listed local source closure for each bundle, not only each `index.ts` or the newly edited handler. Existing imports of provider helpers in the earnings bundle remain unchanged; including those files is not permission to configure or exercise a provider.

## Authentication and compatibility gates

- `dastak-v1-orders` and `dastak-v1-catalogue` currently have `verify_jwt = false` in source because they handle preflight and verify the bearer inside their authenticated handlers. This is not an anonymous-data permission. Their new read RPCs use the caller's token and database wrappers derive `auth.uid()`.
- `earnings` retains `verify_jwt = true` **and** its existing bearer verification. The service client supplies only that verified actor to service-role-only payout wrappers. Do not use a blanket `--no-verify-jwt` deploy across all three functions or copy a service key into native/web clients.
- Existing Customer, Delivery, web and legacy operation names remain. Native Earnings can fall back to an old read only on its exact unsupported-operation response; missing new capability leaves financial controls disabled. Financial writes never downgrade to the old unchecked request.
- Preserve permission helpers, immutable accounting, original request/withdrawal identities, role grants, empty search paths and existing provider availability gates. Deployment is not a reason to weaken stale-version, access or payout checks.
- Live direct destination registration remains restricted by the existing provider boundary. Native setup controls may legitimately remain unavailable after code activation. Do not promise live bank/UPI setup or money receipt without a separately authorized provider-readiness and financial acceptance step.

## Fresh local checks completed in this preparation

| Check | Result | Interpretation |
| --- | --- | --- |
| Detail migration fixture | Passed | All five target kinds, historical lookup, scope/actor/grant denials and field privacy |
| Active/history fixture | Passed | Active versus historical discovery and cursor behavior using the existing list contract |
| Catalogue/location fixture | Passed | 5,201 products, 151 quiet locations, scope, revocation and media checks |
| Payout-guard fixture | Passed | Existing permission helpers, exact destination/version, replay routing, grants and a concurrent destination change |
| Full Edge test directory | **384 passed; 0 failed** | Controlled handler/provider/RPC dependencies, no hosted request |
| Static database contracts | **166 passed; 0 failed** | Source-based SQL invariants, not real-database pgTAP or a chain replay |
| All three deployment entrypoints | `deno check` passed with frozen lock | Type checking, not a deployed-bundle or authentication smoke pass |

Reproduction from `Backends/Dastak`:

```sh
node scripts/test-merchant-order-detail.mjs
node scripts/test-merchant-history.mjs
node scripts/test-merchant-discovery.mjs
node scripts/test-merchant-payout-guards.mjs
```

From `Backends/Dastak/supabase/functions`:

```sh
deno test --config deno.json --lock deno.lock --frozen --allow-env tests/
deno check --config deno.json --lock deno.lock --frozen dastak-v1-orders/index.ts dastak-v1-catalogue/index.ts earnings/index.ts
```

The SQL runners create and stop task-specific Unix-socket-only Postgres instances. They do not consume hosted URLs/credentials. Predecessor helpers/projections and financial delegates are partly stubbed, as detailed in each implementation checkpoint. **These are not one integrated 295-migration database or real financial posting tests.** Local diagnostic directories are retained; no developer/personal data was cleaned up.

Static contracts were rerun from `Backends/Dastak` with `deno test --config supabase/functions/deno.json --lock supabase/functions/deno.lock --frozen --allow-read supabase/tests/database/`. Log: `/tmp/dastak-merchant-activation-static.log`. The candidate manifest's 27 source rows and full-chain fingerprint were independently reread and matched; 53 local documentation links resolved. Final whitespace and branch/HEAD guards passed. Existing Customer fixture diff counts are unchanged.

## Gates still required before production application

### 1. Integrated local rebuild and compatibility

The [earlier rebuild closure](dastak-backend-regression-closure-2026-10-16.md) recorded 289 migrations and 76 pgTAP files passing on an isolated Supabase platform database. Since then the source includes two retention migrations and these four Merchant migrations: **295 now, not 289**. That historical result cannot be relabelled a pass for this expanded chain.

At initial preparation, the staging/replay/contract tools deliberately pinned 289-file manifests and rejected the 295-file source. The later reviewed update now accepts the exact 295-file fingerprint while preserving disposable unlinked target checks, supported pinned runtime, fresh Supabase platform prerequisites, disabled scheduler, internal-only/no-outbound networking, exact SQL hashes, chronological transaction-aware replay, stop-on-first-error behavior and history/content verification. Do not bypass those guards or run them against the user's normal local database.

Run the full current chain and real database contract suite on that isolated target, then integration checks for the new detail/history/discovery RPCs and the payout guard with original permission/projection/financial delegates rather than fixture substitutes. No real provider call is needed or permitted by that local test. Preserve actual denial and balanced-ledger assertions. Source count alone is not success.

The expanded rebuild and original-dependency integration checks were subsequently completed in a fresh isolated platform; see the linked receipt. The stack is stopped and data/evidence retained. No cache, image, runtime or retained database was deleted to make room. A repeat requires a new empty target and a fresh disk/runtime headroom check.

### 2. Scoped source checkpoint and read-only hosted preflight

With separate authorization, checkpoint only the reviewed Merchant implementation/tests/migrations/docs, then compare those exact hashes with the candidate manifest. Confirm the intended hosted project independently; do not infer it from a directory name, use a Savari database, or print credentials.

Inspect current migration history, prior modified function definitions/grants, table/index structure, deployment settings, current error-level advisors and operational load. Compare all pre-existing migration receipts to source. The local candidate set is exactly four Merchant files; the actual hosted pending set has **not** been refreshed in this preparation. If anything else is pending, already installed without matching history, drifted or unknown, stop and report rather than repairing history or pushing unrelated files.

CLI 2.90.0 help was inspected during preparation. These are **future read-only preflight commands, not commands executed against production here**:

```sh
supabase migration list --linked --workdir Backends/Dastak
supabase db push --linked --dry-run --workdir Backends/Dastak
```

The dry run must list exactly the reviewed candidates after history comparison. Do not add `--include-all`, `--include-seed`, `--include-roles`, a history repair, `db reset` or a broad schema push to get past a mismatch. Secrets must remain in the established protected connection/authentication mechanism, not command text or this document.

### 3. Validate execution/locking and obtain precise activation authority

The history migration uses ordinary `CREATE INDEX`, not `CREATE INDEX CONCURRENTLY`, on the shared `dastak_v1.fulfilments` table. Index creation can block writes affecting Customer/Delivery as well as Merchant. Inspect table size/load and rehearse the actual release runner with effective finite lock/statement timeouts before choosing a low-traffic window. An unexpectedly expensive index requires a reviewed alternative, not an unbounded production attempt.

The earlier production receipt records that CLI 2.90.0 did not honor migration-file `SET LOCAL` outside a transaction. A dry run does not prove transaction boundaries or timeout effectiveness. The four new source migrations do not themselves establish release-session timeouts. Demonstrate the exact runner's behavior locally and retain evidence before application; do not assume all four files commit atomically together.

Request approval naming the exact four migrations and exact three Edge Functions, including this shared-index effect. Keep provider/secrets/billing changes, data cleanup, bank registration, withdrawals, app installation, website deployment, push/merge and App Store changes outside that approval unless separately requested.

### 4. Apply database first, verify independently, then deploy only the three functions

After approval and the gates above, apply precisely the reviewed migration set with recorded history and stop on any failure. Verify installed definitions, empty search paths, ownership/role grants, no anonymous execution, authenticated versus service-only wrapper boundaries and the index's ready/valid state. Verify all prior history receipts remain unchanged and no unexpected data policy or financial posting function changed. Do not call the new withdrawal or registration operation merely to test deployment.

Deploy only `dastak-v1-orders`, `dastak-v1-catalogue` and `earnings` from the reviewed source checkpoint, preserving each function's verified auth configuration. Installed CLI supports explicit function name/project ref and `--use-api`; select the deployment method during the rehearsal. Do not use all-function deployment, `--prune`, a global auth override or new secrets/provider settings.

Confirm deployment revisions and use authorized read-only smoke checks for location discovery, catalogue paging, active/history, full-order detail and Merchant royalty capability. Check unauthenticated, wrong-role and foreign-scope denial without creating work or exposing someone else's data. Compare existing Customer/Delivery read behavior and old Merchant operations. Do not claim live notification timing from an HTTP deployment check.

### 5. Release and acceptance remain distinct

Native iPhone/iPad installation and owner operational testing follow verified backend activation. Keychain lock/relaunch/account lifecycle, keyboard/VoiceOver/large text, role/location changes, offline recovery, old actions completed via web and APNs arrival/timing/duplication checks remain separate. Any real financial/provider acceptance needs its own explicit scope.

The local web full-order/history UI also needs its own reviewed web source checkpoint, build and separately authorized web deployment. Activating these backend contracts does not publish web screens. Merchant archive/signing/privacy/reviewer access/screenshots/TestFlight/review are independent of the already-submitted Customer/Delivery binary.

## Failure handling

- Before any application: stop if exact candidates, project identity, hashes, grants, integrated tests or effective timeout behavior do not match.
- After a partial migration success: record precisely which versions committed and re-inspect. Do not rerun successful `CREATE FUNCTION` files, mark a failed file applied or erase history.
- If an Edge revision fails: restore the verified preceding bundle and its auth settings under the approved incident procedure. An additive unused RPC can remain while investigated. Old Merchant-list behavior is a separate database change and cannot be rolled back by reverting Edge alone.
- Restoring that list, changing/removing an index or changing grants needs a reviewed forward correction, not a broad reset or modification of historical migrations.
- Never erase uncertain financial commands/receipts, rebalance historical money by hand or trigger a replacement withdrawal to clear a UI banner. Keep provider and financial accounting boundaries intact.

## Status

**Local activation preparation, expanded rebuild, timestamped hosted preflight, bounded local release rehearsal and separate-index source-tree preparation are complete. Actual source commit/push, migration/Edge activation, web publication, device acceptance and Merchant distribution remain separate and unperformed.** Time-sensitive hosted checks must be refreshed immediately before an approved release. The local transport test does not claim a hosted write-mode Management API rehearsal. Supabase migration-history guidance and the Postgres skills' least-privilege/transaction-locking checks shaped these gates: [migration guidance](https://supabase.com/docs/guides/deployment/database-migrations), [Edge deployment guidance](https://supabase.com/docs/guides/functions/deploy).
