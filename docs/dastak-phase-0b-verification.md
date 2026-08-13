# Dastak Phase 0-B Verification

Recorded on 2026-08-13. Phase 0-B establishes a reproducible, committed source baseline. It does not mutate the production database, deploy Edge Functions, change Razorpay credentials, or deploy web applications.

## Source and configuration gate

- The complete pending tree was classified by ownership and reviewed for generated output, debug instrumentation, credentials, and accidental legacy changes.
- `git diff --check`, shell syntax checks, plist validation, entitlement validation, asset-catalog JSON validation, and a changed-source secret scan passed.
- All four Vercel role mappings pass `scripts/deploy-dastak-web.sh all --check`.
- Dastak iOS app identifiers, signing team, capabilities, URL schemes, app icons, Google mark, and three launch videos were verified.
- The three iOS launch videos and their web counterparts have matching SHA-256 hashes.

## Automated verification

| Surface | Result |
| --- | --- |
| MarketplaceFoundation | 4 tests passed |
| MarketplaceDesignSystem | 5 tests passed |
| MarketplaceInfrastructure | 82 tests passed |
| DastakDomain | 18 tests passed |
| Dastak Edge Functions | 122 tests passed; all 85 TypeScript files pass frozen dependency checking and formatting |
| Dastak database contracts | 26 tests passed |
| Dastak web | 14 files and 75 tests passed; lint passed; Customer, Delivery, Merchant, and Admin production builds passed |
| Dastak iOS | `Dastak`, `DastakMerchant`, and `DastakAdmin` simulator test gates passed using the real package graph |

The standalone `DastakUI` macOS package command is not a supported gate because Razorpay's binary module is iOS-only. The three iOS scheme gates compile and test that package in its supported runtime.

The web production dependency audit reports zero vulnerabilities. npm reports four development-only findings during installation; remediation belongs to dependency maintenance rather than this baseline. Vite also reports one 568.7 kB application chunk, which is recorded for later performance work.

## Backend repairs awaiting release

Hosted lint exposed an invalid `delivery_partner` role comparison in the earnings RPC. The repository fixes it to the canonical `dastak_partner` role through the new forward-only migration `20260813003805_fix_dastak_delivery_earnings_role.sql` and protects the contract with a static database test.

The local `earnings` Edge Function now handles browser CORS and has tests for preflight, authentication, RPC mapping, invalid operations, and malformed responses. Production remains intentionally unchanged in Phase 0-B: it has 46 applied migrations while the baseline has 47, and its deployed `earnings` source precedes this CORS repair. Release both changes together in an explicitly approved backend deployment.

Hosted database lint also emits PostGIS extension-owned warnings. These are not application-owned definitions and were not rewritten.

## Clean baseline gate

The complete staged baseline was committed and checked out into a detached, empty worktree. From that clean checkout:

- the backend gate passed 122 Edge Function tests, 26 database-contract tests, frozen checking of all 85 TypeScript files, and formatting;
- the web gate passed 75 tests, lint, its production dependency audit, and all four role-specific production builds;
- the four supported Swift package gates passed 109 tests in total;
- the `Dastak`, `DastakMerchant`, and `DastakAdmin` iOS scheme gates passed; and
- the non-deploying Vercel guard reverified Customer, Delivery, Merchant, and Admin project-to-role mappings.

The clean worktree remained source-clean after verification. Only this verification record was updated afterward; no application, backend, build, or deployment source changed after the clean gate.
