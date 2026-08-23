# Dastak Phase 0-B Environment Inventory

Recorded on 2026-08-13. This inventory contains identifiers and variable names only. Secret values are intentionally excluded.

## Source control

- Repository: `furqanz7/savari-dastak`
- Baseline branch: `codex/savari-dastak-execution`
- Product worktree: `.worktrees/savari-dastak-execution`
- CI workflow: `.github/workflows/foundation.yml`

## Pinned build tools

| Tool | Baseline version |
| --- | --- |
| Xcode | 26.6 (17F113) |
| Swift | 6.3.3 |
| Node.js | 24.5.0 locally; 24.x on Vercel and CI |
| npm | 11.5.1 |
| Deno | 2.8.2 |
| Supabase CLI | 2.90.0 |
| Vercel CLI | 55.0.0 |

Supabase CLI 2.90.0 remains pinned because CI uses that version. Upgrading it is a separate compatibility task.

## Supabase

- Project: `Dastak`
- Project ref: `zmtsolkfxlrxepshnjdf`
- Region: `ap-south-1`
- Status at inventory time: `ACTIVE_HEALTHY`
- Local directory: `Backends/Dastak`
- Phase 0-A migration snapshot: 46 local and 46 remote versions matched
- Phase 0-B baseline: 47 local migrations and 46 remote versions; the forward-only earnings-role repair `20260813003805_fix_dastak_delivery_earnings_role.sql` is intentionally not pushed in this phase
- Edge Functions: 17 local and 17 active remote functions; Phase 0-A source parity matched, while the Phase 0-B CORS repair for `earnings` remains local until its migration and function are released together

Post-baseline release status: Phase 1 Task 1 released the pending migration and `earnings` Function together on 2026-08-13. Hosted migration history now matches all 47 local versions, and deployed `earnings` version 12 matches the committed bundle with JWT verification enabled.

Configured secret names:

- `APNS_BUNDLE_ID`
- `APNS_ENVIRONMENT`
- `APNS_KEY_ID`
- `APNS_PRIVATE_KEY`
- `APNS_TEAM_ID`
- `DASTAK_NOTIFICATION_SECRET`
- `RAZORPAY_KEY_ID`
- `RAZORPAY_KEY_SECRET`
- `RAZORPAY_WEBHOOK_SECRET`
- `RAZORPAYX_MODE`
- `RAZORPAYX_KEY_ID`
- `RAZORPAYX_KEY_SECRET`
- `RAZORPAYX_ACCOUNT_NUMBER`
- `RAZORPAYX_WEBHOOK_SECRET`
- `RAZORPAYX_DESTINATION_FINGERPRINT_SECRET`
- `RAZORPAYX_LIVE_EGRESS_ALLOWLIST_CONFIRMED`
- Supabase-managed URL, key, database, and JWKS variables

Razorpay test/live mode is determined by the configured key pair. This inventory verifies presence, not the mode or values. No payment credential is changed in Phase 0-B.

RazorpayX Royalty payouts use a separate test/live mode flag and credentials. Live mode is structurally blocked unless fixed outbound egress has been allowlisted with RazorpayX and `RAZORPAYX_LIVE_EGRESS_ALLOWLIST_CONFIRMED=true`; setting that flag without the external allowlist is not an activation procedure. RazorpayX webhook signing uses its dedicated secret.

## Vercel

Owner: `liquiflow's projects`. Every project uses Node.js 24.x, Vite, `npm ci`, `npm run build`, output directory `dist`, and root directory `Web/MarketplaceWeb`.

| Role | Vercel project | Project ID | Production alias | Required app variant |
| --- | --- | --- | --- | --- |
| Customer | `dastak` | `prj_Wy48d7Vv3OXLAgulBukYHoXiXy0f` | `dastak-customer.vercel.app` | `dastak-customer` |
| Delivery | `dastak-delivery` | `prj_NvUua79V8pUlGGA4QIOixsVFJDsX` | `dastak-delivery.vercel.app` | `dastak-delivery` |
| Merchant | `dastak-merchant` | `prj_O1XldqBxHKKVChvBqOASbBvi7Tyl` | `dastak-merchant.vercel.app` | `dastak-merchant` |
| Admin | `dastak-admin` | `prj_8bTPMpvbQqSOqcgXWwR8cHp0shVS` | `dastak-admin.vercel.app` | `dastak-admin` |

Required production variable names for each project:

- `VITE_APP_VARIANT`
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

The guarded deployment entry point is `scripts/deploy-dastak-web.sh`. It verifies the target project and role before building or deploying.

## iOS

Apple developer team: `RBLBKM3W74`.

| Scheme | Product | Bundle identifier |
| --- | --- | --- |
| `Dastak` | Customer and delivery-partner modes | `com.dastak.app` |
| `DastakMerchant` | Merchant | `com.dastak.merchant` |
| `DastakAdmin` | Admin | `com.dastak.admin` |

All three targets use:

- `Apps/Dastak/Supporting/Info.plist`
- `Apps/Dastak/Supporting/SignInWithApple.entitlements`
- App icon asset name `AppIcon`
- `MARKETPLACE_SUPABASE_URL`
- `MARKETPLACE_SUPABASE_PUBLISHABLE_KEY`

Configured capabilities and URL access:

- Sign in with Apple
- APNs entitlement (development in the checked-in entitlement; distribution is supplied by the release signing profile)
- Location while in use
- Razorpay return URL schemes
- Allowlisted UPI application query schemes

The 1024 x 1024 App Store icon and required generated icon sizes are present in the shared asset catalogue. Google branding is supplied as a packaged bitmap resource. Three bundled MP4 launch assets exist for iOS and web.

## Auth and notification ownership

- Apple and Google OAuth provider configuration is owned in the Dastak Supabase Auth project and the corresponding Apple/Google developer consoles.
- The iOS app consumes the Supabase URL and publishable key through ignored `Secrets.xcconfig` files.
- Web apps consume the same public project values through role-specific Vercel environments.
- APNs signing material and the notification worker secret are owned as Supabase Edge Function secrets.
- Local secret files, Vercel-linked files, DerivedData, package build directories, and generated web output are ignored and must never be committed.

## Verification commands

- Web: `scripts/test-dastak-web.sh`
- iOS: `scripts/test-dastak-ios.sh`
- Backend and package foundation: `scripts/test-foundation.sh`
- Deployment mapping only: `scripts/deploy-dastak-web.sh all --check`
