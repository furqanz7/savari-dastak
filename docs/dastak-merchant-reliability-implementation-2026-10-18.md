# Merchant reliability — first local implementation slice

18 October 2026. Follow-up to the [Merchant completion audit](dastak-merchant-completion-audit-2026-10-18.md), covering the first native implementation of M-01, M-02 and M-03. This is **not Merchant release sign-off**. Live/device acceptance remains separate.

## Scope preserved

Work was performed solo in `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, baseline `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`. Existing unrelated Customer screenshot-fixture/release-document changes and untracked artwork were preserved. No shared server contract, migration, backend, Customer or Delivery implementation was changed by this slice. No commit, push, deployment, App Store edit, installation or real operational/payment request was made.

## Implemented locally

### M-01: protect ordinary actions across interruptions

- Added immutable journal commands for Grocery/Food acceptance and decline; package declaration, Ready photo and Ready; retail stock/selection batches and operating state; retained earlier-order/store/category/product mutation routes.
- Persist the original account, target, version, details and idempotency key before sending a write. A replacement command cannot overwrite an unresolved one.
- Ready/product uploads retain original bytes, bucket and account-owned random path. Confirmed upload completion is journaled separately; retry skips an already-confirmed upload. A duplicate response is accepted only for the same frozen owned path. Failed local persistence prevents the first network write/upload.
- Validate command receipts against the original target, requested values and advancing version where the contract provides a version. A timed-out write is not inferred successful merely because a refreshed entity has changed.
- Preserve the existing two-stage acknowledged/cleanup protocol. Local cleanup failure cannot resend an acknowledged write.
- Existing Restaurant/recovery journal files remain readable; the upload-stage field is optional. Protected-file atomic writes, account scoping, permissions, backup exclusion and compare-and-swap revision checks remain in place. The serialized file cap accommodates base64 encoding of the existing 10 MB Ready-photo allowance.
- Account changes do not replay another actor's command. The original account's recovery record remains intact. Normal preparation targets do not persist pickup PINs, rider location or customer destination.
- Existing earlier-order refund follow-up is journaled atomically before proceeding; no live refund was exercised or authorized by this implementation.

### M-02: bounded requests and visible recovery

- Merchant's production function clients use a dedicated single-attempt adapter with a 12-second **per-request** UI deadline. This also covers reads, notification requests and Restaurant multipart requests. Identity lookup, explicit session refresh and ordinary object upload have the same per-call deadline.
- This is not a 12-second end-to-end workflow promise: identity, upload, command and follow-up refresh are separate stages. Server execution may finish after a timeout; the original saved key is retained for reconciliation.
- A late SDK response cannot resume the released caller or overwrite newer model state. Existing injected test-client protocols remain injectable; the production convenience initializer supplies the bounded clients.
- Foreground recovery checks every three seconds, with five automatic attempts per recovery budget and backoff of 3, 10, then 30 seconds. Restarting restores the saved action; manual retry remains available after the automatic budget. No background-execution guarantee is implied.
- Existing realtime subscription and 30-second fallback reads remain. Orders still load independent current, incoming, Food and earlier-order feeds; one failed feed does not erase another successful feed. Refresh coalescing has a two-pass drain bound.
- Version/generation checks reject reads started before a newer mutation. An invalidated Restaurant read no longer retains its loading ownership. Releasing a successful write before its follow-up refresh cannot release a later action's lock.
- Failed catalogue/earnings reads have explicit stale-data messages. Failed incoming/Food/earlier-order feeds keep last-good data but disable their writes. An expired session gets a reconnect action; unresolved commands are not discarded to dismiss the banner.
- This slice does not bound every possible operating-system storage stall, redesign the authentication shell, or guarantee network/server latency. Those are not implied by the request deadline.

### M-03: stable order identity and input

- Removed the whole order ScrollView identity reset keyed to queue/server state.
- Incoming cards and problem-report forms keep stable entity identities rather than remounting on every version.
- New versions reset physical confirmation and dismiss stale approval dialogs, while keeping unrelated typed decline/problem text and still-valid preparation choices.
- A changed fulfilment dismisses an old Ready confirmation. Existing explicit package-count updates remain reflected in their own controls.
- Scroll, keyboard and large-text behaviour still require simulator/device acceptance; source changes and package tests are not a visual pass. Restaurant menu dirty-draft handling is the separate M-08 slice.

## Automated verification

- Added 18 ordinary-operation tests: exact package replay after relaunch; persistence failure; malformed receipt; acknowledged cleanup; first definitive rejection versus later rejection after uncertainty; retained Ready-photo upload; account-owned upload paths; no PIN/rider persistence in targets; bounded automatic retry/manual continuation; identity switch; expired session; older journal decoding; cancellation-ignoring transport and late receipt; no upload before persistence; stock/operating exact replay; matching stock receipt versus failed follow-up read; earlier catalogue draft codec/identity.
- Existing Merchant incoming retry regression now explicitly retries the protected original command instead of submitting a second new action.
- Full `DastakUI` package: **573 tests, 0 failures**, including the 88 existing Merchant tests plus 18 new ordinary-operation tests (106 Merchant tests in total). These are macOS-hosted package tests, not device UI acceptance.
- Full `MarketplaceInfrastructure` package: **189 tests, 0 failures**.
- Native `DastakMerchant` Debug build for generic iOS Simulator, signing disabled: **BUILD SUCCEEDED**, exit 0. A second incremental build explicitly confirmed success after the first quiet build emitted misleading exit-0 compiler warning wrappers. Existing shared-source deprecation/unused-capture warnings were not modified.
- `git diff --check`: passed. No Release archive/signing verification or visual simulator/device run was performed.

Local log paths (ephemeral, not committed evidence):

- `/tmp/dastak-merchant-reliability-final-ui.log`
- `/tmp/dastak-merchant-reliability-infrastructure.log`
- `/tmp/dastak-merchant-operation-final.log`
- `/tmp/dastak-merchant-reliability-ios-build.log`
- `/tmp/dastak-merchant-reliability-ios-confirm.log`

## Remaining work

M-04 through M-14 remain as described in the audit: store/location context, full order details on both platforms, Merchant Earnings/Royalty, menu editing/search, stale menu-draft review, complete catalogue/history discovery, validation/package-range alignment, notification acceptance, full visual polish and Merchant distribution. This slice does not fix the web's in-memory ordinary-command retry limitations identified by the audit.

Physical-device, signed-in cross-role, interrupted-network/relaunch and real notification delivery checks are deliberately not marked passed. No new Merchant build was installed on the owner's iPhone.
