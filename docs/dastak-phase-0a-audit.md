# Dastak Phase 0-A Audit

Snapshot: 13 August 2026, branch `codex/savari-dastak-execution`, base commit `8aceba5`.

## Pending Source Classification

The initial worktree contained 77 changed status entries: 51 tracked modifications and 26 untracked entries. Every pending entry was reviewed by ownership area.

| Area | Entries | Classification |
| --- | ---: | --- |
| Dastak iOS app and Xcode project | 10 | Intended app configuration, signing, notification, and icon work |
| Dastak SwiftUI package | 21 | Intended customer, merchant, delivery, address, payment, earnings, and launch work |
| Shared infrastructure | 12 | Intended authentication, checkout, parcel, earnings, token, and tests |
| Shared design system | 3 | Intended visual-token and surface work |
| Dastak Supabase | 13 | Intended payment, notification, earnings, migration, and configuration work |
| Marketplace web | 15 | Intended role UI, payment, earnings, resilience, style, asset, and test work |
| Repository configuration | 3 | Ignore/deployment configuration and dependency resolution |

No untracked application source or media was classified as disposable. Tracked `Package.resolved` files remain release lockfiles. App icons, the Google mark, and launch videos are product assets, not generated output.

Ignored build output and local tool state are disposable and must never be committed: Swift `.build` and `.swiftpm`, `node_modules`, `dist`, `.vercel`, Xcode `xcuserdata`, and `.DS_Store`. Environment files and `Secrets.xcconfig` are ignored but are credentials, not disposable build output.

## Supabase Parity

- Linked hosted project: `Dastak` (`zmtsolkfxlrxepshnjdf`).
- All 46 local migration versions are present in hosted migration history; no local-only or remote-only version was found.
- All 17 local Edge Function names are active remotely.
- Initial remote source comparison found exact matches for 15 functions.
- `controlled-categories` differed only by Deno formatting and was redeployed after its tests passed.
- Local `dastak-payments` contained the newer `entityType` checkout response required by current clients and was redeployed after its tests passed.
- Notification functions are now explicitly declared in `config.toml`: bearer JWT for token registration and the internal notification secret for sender/worker calls.
- A final download comparison confirms all 17 deployed Function sources match the repository.

The targeted controlled-category and payment suite passed 10 tests with no failures.

## Vercel Isolation

| Role | Vercel project | Production domain | Required variant | Root |
| --- | --- | --- | --- | --- |
| Customer | `dastak` | `dastak-customer.vercel.app` | `dastak-customer` | `Web/MarketplaceWeb` |
| Delivery | `dastak-delivery` | `dastak-delivery.vercel.app` | `dastak-delivery` | `Web/MarketplaceWeb` |
| Merchant | `dastak-merchant` | `dastak-merchant.vercel.app` | `dastak-merchant` | `Web/MarketplaceWeb` |
| Admin | `dastak-admin` | `dastak-admin.vercel.app` | `dastak-admin` | `Web/MarketplaceWeb` |

Admin was corrected from repository root to `Web/MarketplaceWeb`. All four production projects contain their expected `VITE_APP_VARIANT`, `VITE_SUPABASE_URL`, and browser-safe Supabase key.

Local `.vercel` links were removed because the repository root previously selected Customer while the web subdirectory selected Admin. Use `scripts/deploy-dastak-web.sh`; it verifies remote root and role configuration before every deployment and permits only one role per deployment. Its four-role production check passes.

## Phase 0-A Gate

Phase 0-A passed: ignored generated caches were removed, all 46 migration versions align, all 17 active Function names and sources align, all four Vercel roles pass the deployment guard, and the remaining worktree consists of classified source changes. Committing and clean-clone verification belong to Phase 0-B.
