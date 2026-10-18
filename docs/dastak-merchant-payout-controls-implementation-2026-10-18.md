# Merchant payout controls — local implementation checkpoint

18 October 2026. M-06 financial follow-up to the [native Earnings read workspace](dastak-merchant-earnings-implementation-2026-10-18.md) and [Merchant completion audit](dastak-merchant-completion-audit-2026-10-18.md). **Implemented and automatically checked locally; not activated or financially acceptance-tested.**

## Scope and guard

Solo work in `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, unchanged HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`. Earlier Merchant changes and unrelated Customer fixtures, artwork, release documents and dependency-lockfile changes were preserved. No production query/write, migration application, provider configuration, deployment, push/commit, Apple change, phone installation, real destination registration or money movement occurred.

Supabase authentication and Postgres guidance informed actor-derived RPC calls, least-privilege function grants and transaction-level advisory locking. Financial authority remains with existing Merchant-organization permission checks, not the selected store or a relabelled Rider client. See [Supabase Edge authentication](https://supabase.com/docs/guides/functions/auth).

## Native controls

- Bank-account or UPI destination setup/change, with holder/IFSC/account-confirmation/UPI validation and masked review. The exact organization is shown before submission. Setup does not request money.
- Strict rupee entry with at most two decimal places, positive safe-integer paise bounds and no rounding of extra digits, exponent notation, commas or currency symbols. Withdrawal requires a fresh authorized organization read, current balance, active reviewed destination and existing service availability.
- Retry/check for an existing eligible payout using its exact withdrawal ID and expected version. Retry does not create a replacement withdrawal or change its amount/destination.
- Explicit recovery of a retained financial action. Opening, refreshing, polling or foregrounding Earnings **never** submits or replays a financial mutation. Concurrent actions are locked while a saved financial outcome is unresolved.
- Requested/processing is not described as money received. The ledger remains readable independently when financial permissions, secure storage or provider availability prevent changes.

The native root explicitly supplies the Merchant Keychain store. Tests use isolated memory/fault stores. `DastakMerchantRoyaltyClient.swift`, `DastakMerchantEarningsModel.swift`, `DastakMerchantPayoutStorage.swift` and `DastakMerchantPayoutControls.swift` hold the typed contracts, state/recovery, storage and forms respectively. No Customer/Delivery payout flow was edited.

## Protected immutable recovery

Before a financial network call, an account- and organization-bound command is secured with its original key, operation, amount, destination/version or withdrawal/version. Commands are not silently rebased to newer details. Revision checks prevent an obsolete workspace overwriting a newer local record. An account change clears the visible financial context without deleting the original account's recovery record.

Production storage uses the Merchant app's own generic-password Keychain service, no shared access group, synchronizable false and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. It is not a menu draft, UserDefaults value, app-group file or custom encryption scheme. Records are bounded to 16 KiB and validated before use. No raw bank/UPI request is logged or used as a displayed summary.

Destination recovery necessarily contains the original holder/account/IFSC or UPI details, including account confirmation. The form explains this before submission. Unsent form fields are cleared on close, background/disappearance and confirmation. Only masked summaries appear in recovery. Stored details remain until acknowledged cleanup succeeds; no automatic expiry discards an uncertain action. Keychain may survive app removal: uninstall is **not** claimed to erase a pending record. Locked-device behavior, account/persona deletion, retention/disclosure and real signed-device Keychain acceptance remain Merchant distribution/privacy gates.

Each asynchronous phase has a 12-second caller deadline, with single-attempt financial transport. This is **not** a claim that all sequential identity/storage/network/refresh phases together finish in 12 seconds. A noncooperative late network result cannot clear the retained command. Acknowledgement is persisted before cleanup; a failed deletion leaves acknowledged recovery that finishes local cleanup without submitting again.

A fresh exact-org payout read can resolve an existing retry whose version already advanced after a lost response. Otherwise explicit recovery preserves the original ID/version/key. Uncertain responses retain the action; a later generic rejection does not erase earlier uncertainty. A first definitive rejection can release the local command. A checked destination-change rejection is separately safe to release because the server checks for an existing original receipt before rejecting a new reservation.

**Destination registration caveat:** the existing provider registration path does not provide an end-to-end idempotent registration receipt. Manual resubmission of protected original details may create another provider contact/fund-account record. It is not called exactly-once, and no automatic destination-registration retry was added. Withdrawal execution retains its existing withdrawal-based provider identity.

## Additive backend guard and compatibility

New migration: `Backends/Dastak/supabase/migrations/20261018151210_merchant_payout_review_guards.sql`.

1. `merchantRoyaltyControlsSnapshot` delegates the existing Merchant ledger snapshot and adds per-organization `canManagePayouts` using the existing `merchant.royalty.withdraw` authority helper. Setup permission is therefore independent of a zero available balance. The Edge response advertises `merchantControlsAvailable` only on this new contract.
2. `requestMerchantRoyaltyWithdrawal` requires a reviewed destination ID/version and Merchant subject kind. The verified bearer actor is supplied by Edge, not a body actor override.
3. The checked SQL wrapper takes the same destination-registration advisory lock and then the existing royalty lock, validates the active destination under the transaction, and delegates the original withdrawal/reservation/posting function. A concurrent bank/UPI change cannot redirect a newly reviewed reservation.
4. An existing organization/key receipt delegates original replay before checking the now-active destination. A lost acknowledgement can therefore recover its original reserved withdrawal even after the destination changes. Original actor/amount/idempotency validation and append-only financial posting remain in the unchanged delegate.
5. Private functions and public wrappers have explicit service-role-only execute grants, empty search paths and existing permission checks. Anonymous/authenticated callers cannot supply arbitrary actor IDs directly. No tables, new RLS policies or financial accounting rewrites were added.

Old migrations, old web/Rider operations and old request contracts remain unchanged. An old server's exact `400 invalid_operation` response permits a **read-only** fallback to the old snapshot. There is no financial-write downgrade. Missing new capability leaves controls disabled. Applying the migration without deploying Edge, or deploying Edge without its RPCs, does not complete activation.

Existing provider gates are unchanged: direct destination registration remains limited to configured TEST-mode availability; the current live-registration fixed-egress boundary was not enabled. Withdrawal execution still needs its existing configured gateway. New UI does not make any provider available, purchase anything or imply current live readiness.

## Local verification

| Check | Result | Boundary |
| --- | --- | --- |
| Full DastakUI package | **748 passed**, zero failures | Includes 17 new payout tests and the existing 17 Earnings tests; macOS-hosted fixtures, not native tap-through |
| Full MarketplaceInfrastructure package | **189 passed**, zero failures | Existing shared transport/model regression suite |
| Full Edge test directory | **384 passed**, zero failures | Four new earnings handler tests; simulated RPC/provider dependencies only |
| Earnings Edge entrypoint | `deno check` passed | Type checking, not deployment |
| Isolated Postgres payout guard fixture | Passed | Existing permission helpers, new grants/guard/replay routing and concurrent destination change |
| Merchant generic iOS Simulator Debug build | **BUILD SUCCEEDED**, signing disabled | arm64/x86_64 compilation; not device/visual/signing acceptance |

The SQL fixture creates a temporary local Unix-socket-only database, with no hosted URL, credentials or provider. It uses the original actor permission helpers but **delegate spies** for the old snapshot and original withdrawal accounting function. This proves guard authorization, exact reviewed destination/version, original receipt routing, service-role grants and lock serialization; it does not prove real ledger postings, provider transactions or a complete migration-chain rebuild. The server is stopped afterward and local diagnostic fixtures are retained.

New native coverage includes strict amounts, normalized/masked destination requests, Merchant body/organization authority, old-server read-only compatibility, permission/provider/balance gates, stale destination review, failed secure read/write, lost withdrawal acknowledgement across relaunch, original request replay, advanced retry-version resolution, acknowledged cleanup failure, manual destination recovery, invalid responses, noncooperative timeout/late response and account changes. Actual OS Keychain access is not exercised by the memory-store tests.

Logs: `/tmp/dastak-merchant-payout-ui-final.log`, `/tmp/dastak-merchant-payout-infra.log`, `/tmp/dastak-merchant-payout-edge.log`, `/tmp/dastak-merchant-payout-edge-check.log`, `/tmp/dastak-merchant-payout-sql.log`, `/tmp/dastak-merchant-payout-ios.log`.

## Still separate

- Production activation of this migration and the earnings endpoint requires separate authority. The earlier detail/history/discovery migrations and their orders/catalogue deployments also remain pending:
  - `20261018003730_merchant_scoped_order_detail.sql`
  - `20261018014110_merchant_active_and_paged_history.sql`
  - `20261018131824_merchant_catalogue_and_location_pages.sql`
  - `20261018151210_merchant_payout_review_guards.sql`
- No live provider setup, payout transaction, real financial reconciliation or production financial account acceptance was performed. Availability may legitimately keep these controls unavailable.
- Signed-in organization/role-denial checks, iPhone/iPad form/keyboard/VoiceOver/large-text checks, real Keychain lock/relaunch/account-lifecycle acceptance, APNs delivery acceptance and Merchant distribution remain separate.
- This completes the local native financial-control slice, not a claim that Merchant is wrapped, installed, deployed or released.
