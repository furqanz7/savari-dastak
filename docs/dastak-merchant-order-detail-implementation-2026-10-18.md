# Merchant order details — local implementation

18 October 2026. M-05 follow-up to the [Merchant completion audit](dastak-merchant-completion-audit-2026-10-18.md), following [location context](dastak-merchant-location-implementation-2026-10-18.md). This is not a production activation, signed-in acceptance or Merchant release sign-off.

## Scope and boundaries

- Solo work only in `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, baseline HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`.
- Continued the preceding uncommitted Merchant reliability/location work. Existing Customer screenshot fixtures, release documents and artwork remain untouched by this slice.
- Added read-only detail screens for current-generation Grocery/Food records on iOS and web, with a dedicated additive backend operation. Existing mutation, Customer/Delivery and list RPC contracts are unchanged.
- No commit, push, deployment, production migration, signed-in operational call, device installation, Apple listing change, order, payment or payout was performed.

## Implemented

### Entry points and readable detail

“View full order” is available from native current/history fulfilments, incoming Grocery/Food requests, held Grocery requests, recovery offers and return cards. Corresponding current-generation web cards open the new dialog. Target identity includes record kind, record ID and the exact store/location ID.

The read-only view includes:

- Customer-facing store name, order number, order status and order-created timestamp.
- Exact location-authorized requested/fulfilled product lines, quantities, pack/variant snapshots and selected food options, with product-only values where the existing projection provides them.
- Preparation promise/start/expected-ready/actual-ready, package count and evidence count/recorded timestamps. This is evidence **status**, not a photo viewer or download of private storage objects.
- Existing authorized rider name/assignment, pickup stop status and collection timestamp when the predecessor projection supplies them. The predecessor currently omits completed delivery missions; historical rider information is therefore not invented or promised.
- Reported problems, recovery cases and exact-SKU recovery offers, return-stop metadata and fulfilment-linked settlement status.
- Clear explanation that requested and fulfilled product values can overlap and must not be summed. Settlement entries are not described as a Royalty balance, bank transfer or payout confirmation.

No mutation was moved into the detail screen. Pickup and return verification codes stay on their existing guarded operational cards.

### Independent refresh and identity isolation

- Native reads use the existing Merchant bounded transport, with bounded account verification before and after the request. Concurrent refreshes coalesce; a cancelled or late response cannot publish after its ownership check fails.
- Native details close on explicit location change. Web dialogs are keyed by account/location/target and abort their reader on cleanup; an old target's response cannot populate its replacement.
- Both support manual refresh and foreground/visible periodic refresh. A transient failure may retain the last successful read-only snapshot with an explicit warning; authentication/authorization/not-found errors clear it.
- The web dialog uses native modal focus handling, Escape/close controls, restores prior focus and page scrolling, and has responsive styling with visible keyboard focus and at least 44-pixel dialog buttons. Visual/device/VoiceOver acceptance remains separate.

### Additive authorized read

Migration: [`20261018003730_merchant_scoped_order_detail.sql`](../Backends/Dastak/supabase/migrations/20261018003730_merchant_scoped_order_detail.sql).

The `merchantOrderDetail` operation verifies the bearer through the existing handler boundary and accepts only `branchId`, `targetKind` and `targetId`; it never accepts a caller-supplied actor override. It invokes `public.dastak_v1_merchant_order_detail`, whose invoker wrapper supplies `auth.uid()` to the private-schema implementation.

The implementation:

1. Checks the authenticated actor and exact location's existing fulfilment-management or opportunity-response permission.
2. Resolves the requested fulfilment, Grocery opportunity, Food request, recovery offer or return stop **within that location**. Foreign/missing target reads use the same not-found result.
3. Reads related records for that order **and location**, respecting each section's permission, independently of recent-list limits.
4. Allowlist-projects fields from existing Merchant projections. Raw customer/private/contact/address/tracking/code fields and photo-storage paths do not reach the response.
5. Limits settlement context to entries explicitly linked to this location's fulfilment, exact order and merchant organization, with active organization membership. Ambiguous organization-wide entries are omitted.

The new functions use an empty search path; helper execution is private, and the public read is granted only to `authenticated`, not `anon` or `service_role`. No new table, RLS policy, financial write or Customer/Delivery function replacement was introduced. Native and web display models also verify exact returned scope rather than trusting arbitrary response fields.

## Local verification

| Check | Result | What it proves |
| --- | --- | --- |
| Full DastakUI package | 593 tests passed, zero failures | Includes six new detail request/scope/privacy/identity/concurrency/error tests; macOS-hosted model/package tests, not a tap-through |
| Full MarketplaceInfrastructure package | 189 tests passed, zero failures | Existing infrastructure regression coverage |
| Full web Vitest suite | 150 files / 1,073 tests passed | Includes eight new detail parser/client/dialog tests and existing web regressions |
| Isolated Postgres fixture | Passed | Actual new migration, all five target kinds, old order beyond 150 newer fixture fulfilments, same-order foreign-location denial, forged actor/least privilege, private-field exclusion and function grants |
| Edge entry-point type check | Passed | New handler/dependency/RPC wiring type-checks |
| Full Dastak Edge-function suite | 373 tests passed, zero failures | Includes all 43 order-handler tests; fixture-based function regressions, not live Supabase requests |
| Targeted React/TypeScript ESLint | Passed | Changed web components, parser, transport and tests |
| Final web production build | Passed | TypeScript and production bundling; existing large-chunk warning remains, not a deployment |
| Merchant Debug generic iOS Simulator build | BUILD SUCCEEDED, signing disabled | Compiles the real SwiftUI screen for arm64/x86_64 Simulator; not a simulator interaction or physical-device pass |
| `git diff --check` | Passed | No whitespace errors; baseline branch/HEAD unchanged |

The SQL fixture deliberately uses a minimal isolated schema and stubbed predecessor projection functions containing private sentinel fields. It executes the **actual new migration** but is **not** a complete rebuild of the backend migration chain, an integration test of all predecessor projections, or a production JWT/RLS acceptance run. Its server listens only on a temporary Unix socket; it does not read a live connection URL or credentials, and is stopped afterwards. Diagnostic directories are retained locally.

Reproduce from the checkout:

```sh
swift test --package-path Packages/DastakUI --jobs 2
swift test --package-path Packages/MarketplaceInfrastructure --jobs 2
```

From `Web/MarketplaceWeb`: `npm test`, `npm run build`.

From `Backends/Dastak`: `node scripts/test-merchant-order-detail.mjs`, and the existing Deno function-test command from the Foundation workflow.

Local logs:

- `/tmp/dastak-merchant-detail-native-full.log`
- `/tmp/dastak-merchant-detail-infra-full.log`
- `/tmp/dastak-merchant-detail-web-full.log`
- `/tmp/dastak-merchant-detail-web-build-final.log`
- `/tmp/dastak-merchant-detail-eslint.log`
- `/tmp/dastak-merchant-detail-sql-final.log`
- `/tmp/dastak-merchant-detail-edge-check.log`
- `/tmp/dastak-merchant-detail-edge-full.log`
- `/tmp/dastak-merchant-detail-ios-build.log`

## Still separate / not claimed complete

- Apply the new migration and deploy the updated `dastak-v1-orders` Edge Function only with separate production authorization. **The deployed backend does not gain this feature from local code changes.** Coordinate backend activation before releasing a client that depends on it.
- Signed-in Grocery/Food, permission removal, multi-store/account switching, expired session, old/terminal orders, recovery, returns, network interruption, scrolling, larger text, light/dark, VoiceOver and real iPhone/iPad acceptance.
- Existing recent feed/window limits and full active/history discovery remain M-10. Targeted details can resolve an older known ID, but do not make an undiscovered old card appear.
- Older legacy account-wide orders use separate contracts and have not been routed through the new current-generation endpoint. No Customer order-detail API was repurposed to fill that gap.
- Complete authorized-location enumeration remains the M-04 follow-up gap. Royalty/Earnings, menu/catalogue editing and remaining Merchant audit items are not completed by this detail implementation.
