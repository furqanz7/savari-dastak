# Dastak Reimagined — local phone workspace pass

Date: 9 October 2026. Worktree: `.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, guarded HEAD `9c754a787fad0ec7a4612865657d168d0d02362f`.

## Scope and boundaries

Continued the approved English-only UI/UX work through Orders, Profile, Settings, Payments, Food and Grocery billing. Urdu remains only in the approved brand wordmark. Existing edits were preserved. No SKU, database, production, account, order, payment, push or deployment writes were performed. Background/staff redesign remains deferred. No subagents or paid asset generation were used.

## Reproduced defects and changes

1. Fixed dialogs embedded in a backdrop-filter panel were constrained to that panel. At 390×844 the profile backdrop occupied only x=13, y=279, width=364, height=496, instead of covering the screen. Added `ReimaginedModalLayer`, a body portal used only for embedded Reimagined account overlays. The resulting backdrop covers x=0, y=0, width=390, height=844. Existing forms, callbacks and authorization safeguards are unchanged.
2. Applied the shared layer to saved-address book/editor, profile editor, devices/sessions, sign-out confirmation, account deletion confirmation, merchant-order cancellation and support. The existing interface retains inline rendering. Checkout's saved-address picker uses the same helper. Browser interaction directly verified the profile editor; regression tests cover the shared wiring and legacy fallback, not each live account action.
3. Reproduced inherited system-dark colours on the light glass panel: Payments text computed as `rgb(244, 239, 229)`. Scoped a light palette to embedded customer workspaces and portalled dialogs; text now computes as `rgb(40, 35, 29)` while the browser's dark preference remains enabled. The legacy interface's dark theme is unchanged. A higher-specificity modal selector prevents late-loading account styles from overriding this palette.
4. Added a localhost/DEV-only workspace preview and upgraded the synthetic Grocery fixture to use the real item-review and billing components. Account sections in this preview use render-only snapshots; profile editing, Orders, receipts and Payments use the real components with synthetic/no-op callbacks. This avoids authenticated account reads/writes. Food's fixture clearly labels checkout as a local simulation instead of displaying an integration-pending claim about production.

## Browser verification

Used the Codex browser with explicit 320×740 and 390×844 responsive viewports, including its existing dark preference. Responsive overrides were temporary. Scene rendering was replaced by an inert test backdrop in these fixtures, not in the application.

| Surface | Verified locally | Limits |
| --- | --- | --- |
| Profile editor | Full viewport backdrop at 390px, readable light theme, focused name field, Escape/close, app isolation | No profile save request; no physical keyboard test |
| Settings | 320px layout, panel scroll width equals client width, English controls and Merchant/Delivery sections present | Render-only snapshot; access cards remain in their initial checking state |
| Orders/receipt | Synthetic delivered order, Details/Back, navigation remains usable, ₹122 confirmed total, no overflow at 320px | No real order reads, cancellation, receipt download or support submission |
| Payments | Readable dark-preference rendering at 390px, history reachable at 320px, ₹122 retained | No payment collection or backend refresh |
| Grocery | Take Bucket → Add synthetic item → Cart → Delivery & billing; focused step heading; long address wraps; 320px panel has no horizontal overflow | Local estimate only; final reservation/submission counter not exercised |
| Food | Restaurant → dish → required Large option → Add → Review cart; option estimate changes ₹150 to ₹180; 320px panel has no horizontal overflow | No restaurant reservation, delivery eligibility or real order placement |

Screenshots are in `docs/verification/dastak-workspace-phone-2026-10-09/`: profile-editor-390.jpg, receipt-390.jpg, payments-390.jpg, payment-history-320.jpg, settings-320.jpg, grocery-billing-320.jpg and food-cart-320.jpg.

## Automated verification

- Full suite: 137 files, 924 tests passed.
- Added three modal regression tests and one scoped palette safeguard. Final focused suite rechecked after the palette-specificity adjustment.
- Targeted ESLint and TypeScript build passed.
- Production bundle build passed; the existing oversized 3D/cashier chunk warning remains, not addressed in this UI pass.
- `git diff --check` passed; guarded branch/HEAD unchanged.

## Remaining verification

This is not a complete certification of Dastak. Authenticated live forms, devices/session revocation, account deletion/re-authentication, notification permissions, real stock/delivery checks and end-to-end order/payment workflows remain outside this local visual pass. A physical phone/Safari software keyboard also remains unverified. SKU classification work remains postponed. These changes have not been pushed or deployed.
