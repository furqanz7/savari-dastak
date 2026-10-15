# Reimagined responsive polish — 9 October 2026

## Scope

Customer header, short-screen forms, Food transitions and existing sign-in
presentation. Solo implementation, no new dependencies or paid model calls.
No SKU, scene/background redesign, Supabase/schema/configuration changes,
live profile/address/cart changes or real order/payment attempts.
Existing unrelated working-tree drafts and assets preserved.

## Reproduced and fixed

- At 881px, restored 34px branding overrode the earlier 28px tablet rule.
  Actual wordmark text ended at x=160.48 while location began at x=150.
  Place the tablet size after the restored branding declaration. The text
  now ends at x=135.79, leaving a 14.21px gap without changing the fonts,
  Urdu wordmark or phone navigation arrangement.
- At 320px, a long unbroken Food option legend forced a 413.30px fieldset
  into a 266px content area, clipping controls/text. Release the fieldset's
  intrinsic minimum and wrap legends/option text. Fieldset now measures
  260px; content scroll width equals its 266px client width. Option IDs,
  required-selection validation and price calculations are unchanged.
- Add CSS regression checks and a dev-only synthetic long-name Food scenario.

## Browser evidence

- Header at widths 320, 390, 430, 720, 721, 881, 900, 901, 1100, 1101 and
  1440: positive wordmark/location gaps and no document horizontal overflow.
- Long-name Food restaurant → menu → required option → local cart:
  base ₹150 + Large ₹30 = ₹180; cart retains exact selection on Continue
  Shopping. Reopening and selecting that option recognises the existing
  line as In cart: 1. No-partner Reserve remains disabled.
- Search at 390 × 400: input and completed regional suggestions render;
  main menu and cart remain unchanged while typing; Close search returns
  focus to its opener. Short-screen page scrolling remains available.
- Synthetic Profile at 390 × 400: dialog y=8..392, Save y=325..375,
  Cancel/Save reachable; synthetic save closes and returns opener focus.
- Synthetic address editor at 390 × 400: textarea scrolled into view,
  computed font 16px, Save y=308..355, dialog within viewport. Cancel
  restores the address-management opener; no save/API request made.
- Existing production-built local sign-in fixture at 320 × 568: 320px
  document width, both provider controls visible, legal/help links reachable
  through normal page scrolling. Outside environment present. No OAuth
  action or sign-out performed.
- Proof: `verification/dastak-responsive-polish-2026-10-09/`.

## Limits and release

These are desktop browser viewport/short-height simulations, not physical
iPhone/Safari software-keyboard tests. Real OAuth renewal, profile saves,
address writes and checkout/fulfilment/payment remain unverified. Existing
signed-in production session is not cleared to test signed-out presentation.

TypeScript build, scoped ESLint and full suite passed: 1,003 tests in 145
files. Only reproduced issues are changed; this does not certify every Dastak
UI/UX path.

## Production release

- Commit `34ee886d9e01cbdf857e7493f1d8e418548d5a56` pushed to
  `codex/dastak-v1-launch`.
- One Customer production deployment completed READY:
  `dpl_rUkBW2x8ytUKGG4vvJhKuSMfydkj`.
- Normal `https://dastak-customer.vercel.app/` returns HTTP 200 and matches
  the exact SHA, Customer variant, production environment and deployment ID.
  CSP, nosniff and DENY frame headers remain present.
- Signed-in live browser reload stayed signed in. At 881px, the actual
  wordmark/location gap is 14.21px and document width is exactly 881px.
- At 390px, Craft menu → Cappuccino details → Back to menu works read-only;
  document width is exactly 390px. No live cart/account/address writes.
- Live proofs: `tablet-live-header.png` and `phone-live-food.png` in the
  verification folder. Temporary responsive viewport overrides restored.
- Exact-SHA queued Delivery preview canceled. Merchant preview had already
  finished READY by cancellation time; Customer/Admin previews were already
  READY. These preview builds did not replace their production deployments.
- Release notes updated locally after deployment to avoid another push
  triggering redundant preview builds.
