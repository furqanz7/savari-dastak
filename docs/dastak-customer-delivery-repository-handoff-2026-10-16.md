# Customer + Delivery repository and release handoff — 16 October 2026

**Final status: COMPLETE within this handoff's scope.** All intended source changes are committed/pushed, all five Foundation CI jobs pass on final source `dc971c3`, both verified web artifacts are promoted and independently checked on their canonical production addresses, and all 289 database migrations match. No database/Edge deployment is pending for this source. The final receipt itself is a documentation-only follow-up commit; its diff does not change the tested source.

## Scope

Owner approved completing the pending repository/CI/deployment handoff after Customer + Delivery product acceptance. This is not authority for a TestFlight/App Store submission, a main-branch merge, payout settlement, real orders/payments, or finishing/releasing Merchant/Admin. Existing shared/native dependencies are preserved so the accepted combined app can be reproduced.

## Source checkpoint

- Authoritative branch: `codex/dastak-v1-launch` in the existing `wave1-runtime-ci` worktree.
- Starting HEAD: `94f531d679e6dcca1bd588ab63c5000b1eb2c620`, 16 commits ahead of GitHub.
- `bab61fda242fc9a0584c991134c83f911b574028`: checked in accepted native app/source/assets/tests, already-live backend changes, 12 already-applied migration source files, local rebuild scripts and sanitized release evidence. Pushed together with the preceding 16 commits.
- `3e949d7ee0e81daaf9d0abb2ac326273fcc60583`: container-safe pgTAP include expansion, local-only runner tests and source recovery of existing catalogue helper functions.
- `966e523aa9c9a9a9746ecd7faab014e164428135`: extracted Customer startup from the SwiftUI result-builder chain for hosted cross-architecture type checking; updated real-submission concurrency fixtures for current rider/stock admission; collected all concurrency failures without skipping gates.
- `902d630a717d336442845d9ae3ad14b80547cb89`: split Customer modifier chains into opaque computed views without inserting dynamic branches/type erasure; identified manually constructed historical race fixtures with the existing availability/pricing policy version 0. Fresh submissions still use default version 1.
- `f500da0788efcccff4d74c7bf72e00a0c6158f04`: restored all six transport profiles in race fixtures, corrected fixture column naming, and used authenticated, project-scoped CLI reads for protected deployment verification.
- `d71a1dccc0155f932d8336dc7e25a2b30bff877c`: flushed actual deferred trigger events before re-enabling a fixture trigger, published valid GPS samples through the actual arrival API, removed a runner-only command dependency, and added race-fixture contract tests.
- `dc971c3ba038487c576a85336a896924ef81f9fd`: updated final-handoff races to the current PIN/photo/collection sequence. Actual wrong-PIN/three-attempt blocking assertions run in a rollback-only subscenario; authorized Operations override is then exercised from its valid ACTIVE state. No handoff, proximity, payment or immutable ledger guard is disabled to complete these commands.
- Secrets/environment files, signing credentials, build directories and dependency caches remain ignored. Pattern-based credential inspection of 339 candidate text files and the pre-existing unpushed commit diff found no matching credentials; this is not a universal secret-detection guarantee.
- 36 unreviewed screenshots and the two explicitly non-production historical RPM 3D assets remain local, unchanged and untracked. They are not required source/build inputs. No personal files were removed.

The GitHub repository is public. The already-committed map screenshot in the preceding 16 commits was inspected: it shows a public landmark/sample pin, not a saved personal address.

## Checks completed locally

| Check | Result |
| --- | --- |
| Native Dastak UI/model regressions | 547 passed, including after startup extraction |
| MarketplaceInfrastructure | 183 passed |
| DastakLiveTracking model | 6 passed |
| Complete web suite | 149 files, 1,062 tests passed |
| Web ESLint and TypeScript/Vite build | Passed; pre-existing large-chunk warning retained |
| Backend function tests | 370 passed, including after formatting |
| Static database contracts | 166 passed |
| Payout gateway replay storage test | 1 passed; local fixture, not a payout |
| Runtime pin, include-transport and concurrency-fixture tests | 17 passed |
| Backend formatting | 269 files pass |

The first web suite run exposed a hard-coded full-order divider colour. Replaced it with the existing adaptive `--divider` token; the complete suite then passed. Deno formatting normalized 39 files without changing historical migration SQL.

## Hosted CI

Initial run [38816814958](https://github.com/furqanz7/savari-dastak/actions/runs/38816814958) exposed host-side `psql` include paths unavailable inside the Supabase pgTAP container, and a hosted simulator compiler type-checking limit. No production failure is inferred from those CI failures.

Follow-up [38817488723](https://github.com/furqanz7/savari-dastak/actions/runs/38817488723) confirmed **76 database files / 2,081 assertions passed** through the normal Supabase container, then reached outdated concurrency submission fixtures. The expanded SQL uses only the exact reviewed fixture and preserved historical correction; CLI pgTAP plan/failure checks remain intact. The duplicate second execution of the same suite was removed, not its coverage.

Follow-up [38818616041](https://github.com/furqanz7/savari-dastak/actions/runs/38818616041) confirmed successful hosted builds for all five iOS schemes and successful Swift package tests after splitting the view's type-inference boundaries. Subsequent runs passed nine of ten concurrency gates and identified the final handoff test's obsolete pre-PIN payment/photo sequence. These failures are retained as diagnostic evidence, not hidden by disabling workflow gates.

Final source verification run: [38820588305](https://github.com/furqanz7/savari-dastak/actions/runs/38820588305), source `dc971c3ba038487c576a85336a896924ef81f9fd`: **completed / success, all five jobs green** (`ios-build`, `swift-packages`, `dastak-backend`, `dastak-web`, `savari-backend`). Final completion: 15 October 2026 23:06:19 UTC / 16 October 2026 04:36:19 IST.

The final hosted Dastak job confirms the fresh chronological reset, **76 files / 2,081 database assertions**, all **ten** concurrency suites (including real ordered PIN/photo/CASH+UPI completion and replay races), all **17** runner/fixture safety tests, function/contract tests, frozen type checks and formatting. iOS builds cover all five configured schemes. This is isolated CI execution, not a real order, payment, provider call or payout.

## Database and Edge source reconciliation

Live migration check after the source push: **289 local/remote entries match, zero mismatches**. No migration was applied in this handoff. The existing [production database receipt](evidence/dastak-backend-production-release-2026-10-16.json) remains authoritative for the prior approved application.

Downloaded all deployed Edge Function sources using the authenticated Supabase source API. After identical Deno formatting normalization, **all 68 files with local counterparts matched**. No behavior difference requires a redeployment. In particular: `courier-dispatch` v28, `process-v1-outbox` v13 and `register-order-live-activity` v1 remain ACTIVE.

Three additional downloaded files had no repository counterpart: existing `catalogue-packshot-ingest` v2, `process-catalogue-assets` v3 and `process-catalogue-sources` v16. Recovered their source under [ops/deployed-functions](../Backends/Dastak/ops/deployed-functions/README.md), outside active CLI deployment discovery. They were not invoked, changed, enabled/disabled or redeployed. The archive preserves original dependency specifiers; it is not a new security/functional certification of those older ingestion utilities.

## Web production reconciliation

Customer and Delivery canonical production addresses initially remained READY at their previous releases. Production-configured builds of source `966e523` were staged; the two canonical addresses retained their prior deployment IDs during verification. The deployment script's initial plain HTTP verification followed the protected URL to a sign-in page, so that check failed rather than accepting a false provenance result. Rechecked both artifacts with authenticated CLI reads using their exact project identities; both return HTTP 200 and correct production environment, service variant, commit, deployment ID, CSP frame restriction and `nosniff` header. No deployment-protection setting was changed.

| Service | Verified staged artifact |
| --- | --- |
| Customer | `dpl_9iMzxvNYeeV68UXisVobH3TwuYYt` / `dastak-bl8ir9dwd-liquiflows-projects.vercel.app` |
| Delivery | `dpl_DVCGTxtRpZME3Y4cYPgRcg8tqNqm` / `dastak-delivery-32wzranr0-liquiflows-projects.vercel.app` |

The complete committed `Web/MarketplaceWeb` tree is identical between staged source `966e523` and final source `dc971c3`: tree SHA `1b9de6ec8fa72343c8d909ab233203917b7372ba`. Later source commits change only native compiler organization, test fixtures and release tooling, not web inputs. The deployment script excludes the two local-only historical RPM assets and environment/build/cache directories.

After the exact-source CI run passed, promoted **those same two artifacts**, without rebuilding. Independent public HTTP checks confirm:

- `https://dastak-customer.vercel.app` serves `dpl_9iMzxvNYeeV68UXisVobH3TwuYYt`, expected Customer variant, production environment and staged source SHA.
- `https://dastak-delivery.vercel.app` serves `dpl_DVCGTxtRpZME3Y4cYPgRcg8tqNqm`, expected Delivery variant, production environment and staged source SHA.
- Both canonical HTML responses are HTTP 200; all four entry-point JavaScript/CSS references per app return HTTP 200 with appropriate content types. Both CSP frame restrictions and `nosniff` headers are present.
- Bounded, deployment-specific Vercel error-log queries covering the preceding ten minutes each returned **zero records**. These static-host observations do not substitute for Supabase runtime telemetry, authenticated real-order tracing, or an ongoing monitoring/drains audit.
- Final linked migration check remains **289 matching versions / zero mismatches**; final error-level security advisors report **No issues found**. No migration was applied or Edge Function deployed in this handoff.

Machine-readable receipt: [repository handoff evidence](evidence/dastak-customer-delivery-repository-handoff-2026-10-16.json). Detailed temporary logs use the `/private/tmp/dastak-handoff-*` prefix. Build-time production environment files were kept in task-created temporary directories and removed by the deployment script's cleanup; no values were committed.

## Release transaction rule

The preceding database release completed and was independently verified, but the installed CLI emitted `SET LOCAL`-outside-transaction warnings. Applied historical files remain unchanged. For future scoped SQL releases that rely on transaction-local timeouts, use an explicit transaction-aware runner: `BEGIN`, both reviewed `SET LOCAL` bounds, exact SQL and history registration, independent invariants, then `COMMIT`; abort on drift/error. The existing catalogue reconciliation runner demonstrates this pattern. Do not rely on CLI process success or a dry run as evidence that those timeouts were effective. No new migration is necessary to change a completed session's timeout behavior.

## Separate release decisions

- Customer + Delivery product acceptance remains closed; Build 53 was previously installed and accepted as the final product checkpoint. No fresh phone installation is performed merely for formatting/CI handoff.
- TestFlight/App Store distribution, commercial weather-provider release configuration, privacy/store declarations, operating/monitoring readiness and actual payout settlement are separate gates, not certified by a Git push or a local compile.
- Merchant/Admin and Savari production are not released by this task. The shared Foundation workflow may compile/test them for regression protection.
- No main-branch merge, order action, payment, provider/payout activation, hosted database upgrade or personal-data cleanup is included.

Supabase and Vercel release guidance informed forward-only migration preservation, least-privilege/source comparisons, staging before promotion and separate source/runtime receipts. The React quality checklist informed the existing hook cleanup/dependency and accessibility review; no web redesign was undertaken.
