# Native Customer haptics — 14 October 2026

Customer-only haptic scopes now cover signed-out/first-launch controls and the authenticated Grocery/Food experience. Existing button styles, actions, disabled states, accessibility labels, navigation and commerce guards are preserved. Delivery Partner, Merchant and Admin do not opt in.

## Interaction map

- Soft activation: navigation, opening/dismissing controls, search submission, product details, Wishlist and order actions.
- Selection: pack sizes, dish options, category jumps, product-carousel pages, order-history scope, basket service, support categories and map pin placement/nudges.
- Basket: medium pickup; light successful add/increment; soft decrement/removal/clear; warning for the pickup-first gate or rejected quantity/stock changes. Grocery and Food retain independent baskets.
- Outcomes: acknowledged Wishlist changes, address save/select/delete, profile save, sign-in, reservation creation, order confirmation, cancellation and support actions use semantic feedback. Warnings/errors never imply a payment succeeded.
- Settings > Preferences > Haptics persists the customer's opt-out on this device. No preference is changed automatically.

## Safety and implementation

`MarketplaceHapticScope` coalesces a 20 ms action burst so a semantic result replaces the fallback tap. Background/inactive, disabled-preference and unmounted scopes are silent; queued feedback is discarded rather than replayed. Explicit user commands emit feedback; catalogue/address availability polling, cart restoration, typing and normal scrolling do not. UIKit feedback generators are retained and used on physical iOS only, without audio/fallback vibration. Simulator builds deliberately do not pretend to prove physical haptics.

Native alerts/confirmation dialogs keep primitive SwiftUI Buttons. Native navigation links preserve their activation and back behaviour. A Customer scope is outside presentation modifiers so sheets and full-screen product views share feedback. No Supabase auth/API, order, inventory, fee, payment or weather-permission logic was changed.

## Verification

New tests cover priority/coalescing, opt-out, inactive/background cancellation, no replay, independent Grocery/Food pickup gates, add/remove/quantity-limit events, and silent refresh/restoration/no-op changes. Evidence logs: `/tmp/dastak-haptics-design-tests.log`, `/tmp/dastak-haptics-ui-tests.log`, `/tmp/dastak-haptics-device-build.log`.

Build 26 is the haptics build. Physical vibration strength/feel needs the user's hands-on confirmation; it cannot be observed through Device Hub or validated in a simulator. No real-order testing is performed for this feature.

Final verification: 477 DastakUI tests pass; all six new haptic policy/scope tests and eight existing design-system tests pass. Both signed iPhone and simulator Build 26 succeed, code signature verification and `git diff --check` pass. Build 26 is installed and launched in the dedicated simulator. UI interaction/screenshots were blocked by the Mac lock, and physical installation remains pending because the iPhone is reported unavailable. The user has been asked to reconnect/unlock it. No claim of measured physical vibration is made.

Physical-device follow-up: after the user reconnected/unlocked the iPhone, Build 26 installed successfully in place and launched without preview flags. `devicectl device info apps --bundle-id com.dastak.app` independently confirmed version 1.0.0 / bundle version 26. Physical haptic feel and Settings opt-out remain for the user's hands-on confirmation; no order or basket mutation was performed by the agent.
