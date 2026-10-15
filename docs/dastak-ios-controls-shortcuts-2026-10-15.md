# Dastak native Controls and App Shortcuts — Build 33

## Build 37 — native control presentation polish

The controls gallery uses concise labels: Search, Grocery, Food, Basket and Track Order. The repeated Dastak prefix is removed because the gallery already groups controls under the app name. Search is first in the widget bundle's suggested order; the system ultimately manages gallery presentation. Grocery now uses a storefront symbol, distinct from Basket, and tracking uses a direction marker instead of the scooter. Native action hints and a warm gold tint are configured through WidgetKit's public APIs. iOS controls their backgrounds, dimensions, gallery ordering and whether tint appears in a given system presentation; monochrome gallery previews are not a failure.

All five existing control kind identifiers and navigation intents are preserved. Once per installed build, app launch requests a public ControlCenter reload to refresh existing control content without replacing user placements. No basket contents, orders, payments or production data are modified.

Verification: nine MarketplaceFoundation tests and four hosted iOS simulator tests passed, including concise control labels, distinct symbols, native symbol availability and the existing four-entry Search quick-action/Shortcut metadata regressions. Final simulator and signed device Debug builds passed; strict deep signature verification and diff whitespace checks passed. These are targeted tests, not a rerun of the full UI suite. Build 37 was installed on the physical iPhone and its installed bundle version verified as 37. Remote launch was denied because the phone was locked. Simulator gallery interaction remained blocked by noWindowsAvailable even after the user reported unlocking the Mac; visual presentation is not marked passed. The user has been asked to open Dastak once and check the physical gallery.

The user subsequently checked Control Centre → Add a Control → Dastak on the physical iPhone and reported “Labels and icons look good.” The Build 37 physical gallery appearance check is therefore user-confirmed passed. This confirms the updated labels and icons, not additional invocation, Siri, Lock Screen or real-order tests.

## Build 36 — app-icon menu Search

At the user's request, the separate four-entry UIApplicationShortcutItems menu now contains Search, Grocery, Food and Track Order, in that order. Basket was removed only from this menu; the Basket App Shortcut, Spotlight registration, native control and in-app basket remain intact. Both cold- and warm-launch quick-action handlers use the existing validated `com.dastak.app.quick.search` routing and preserve the selected Food/Grocery service.

Verification: all three hosted iOS simulator regression tests passed (four menu entries and exact order, plus the two Search App Shortcut metadata checks). The signed device build and strict deep signature verification passed. The built app's plist contains Search, Grocery, Food and Track Order. No app removal, system setting changes, orders or payments are involved. Runtime long-press checks are recorded separately rather than inferred from build success.

Build 36 was installed and launched on the iPhone, and its installed bundle version was verified as 36. Simulator UI verification was interrupted by the Mac locking before the long press; it is not marked passed. The user then reported “Menu and Search both pass” on the physical iPhone. The four-entry menu and Search opening its field with the keyboard are therefore user-confirmed passed on Build 36.

## Build 35 — Spotlight Search follow-up

The user confirmed Build 34 Search appears on the full Dastak page in Shortcuts and opens the search field with the keyboard. However, their Spotlight screenshots showed only the original four actions even in the expanded Dastak section, and searching “Search Dastak” also did not show Search. Therefore Spotlight discoverability remains an unresolved gate, not merely Top Hit positioning.

Build 35 retains SearchDastakIntent's identifier and adds specific discovery phrases (including “Open search in Dastak” and “Search products in Dastak”). Search keywords improve lookup in the Shortcuts editor; they are not claimed to force Spotlight indexing. The scene delegate now calls the public updateAppShortcutParameters API when a foreground scene becomes active, in addition to the existing process-launch registration. No system search preferences, app data, other installed apps, orders or payments were changed.

Two hosted iOS simulator metadata regression tests passed, verifying five shortcuts, Search's first position and title, discoverable/non-assistant-only flags, no required parameters, stable identifiers and the new phrases. The signed device build and strict deep code-signature verification passed. Physical Spotlight retesting is required before declaring the issue fixed; stale indexing is a hypothesis rather than an established root cause.

Final Build 35 was installed, launched and its installed version verified on the physical iPhone. After returning Home and reopening Spotlight, the user reported “Search now appears.” The physical Spotlight Search visibility gate is therefore passed on Build 35. Because registration refresh and phrase changes were applied together, the exact contribution of each is not established. Search execution in the full Shortcuts page was already user-confirmed on Build 34. This does not guarantee any particular Top Hit slot or mark Siri, Lock Screen or real-order tests passed.

## Build 34 — concise labels and Search

Customer App Shortcuts now use Search, Grocery, Food, Basket and Track Order. Search is first in the provider's suggested order; iOS ultimately chooses Spotlight ranking and Top Hit placement. The original four Home Screen quick actions remain unchanged. A fifth native control, Dastak Search, is also included.

Search opens the existing search interface, focuses its field and preserves the selected Grocery/Food service. Repeated explicit Search requests reset exploration and reopen search. Normal Home, account, category and service navigation clears the shortcut's initial-search flag so it does not reopen later unexpectedly. No item is added and no order is submitted.

Verification: 485 DastakUI tests and 8 MarketplaceFoundation tests passed. Simulator and signed device builds passed; strict deep signature verification passed. Metadata exports five correctly titled automatic shortcuts in the main app and only the shared OpenIntent in the extension. The simulator Search route visibly opened the focused search field and keyboard for Grocery and Food; switching to Food dismissed the prior search. Build 34 installed on the physical iPhone. Physical Search shortcut execution and the new Spotlight presentation await the user's check; Build 33's earlier user-confirmed Food invocation checks remain recorded below and are not substituted for Build 34 Search verification.

The simulator's Dastak page inside Shortcuts visibly lists all five updated labels. The All Shortcuts overview showed the first four (Search, Grocery, Food, Basket); Track Order remains visible on the Dastak page. That overview limit is not removal of Track Order.

## Implemented

Four navigation actions: Grocery, Food, Basket, Track Order.

- Native ControlWidget buttons for Control Centre, Lock Screen and supported Action Button configurations (iOS 18+).
- Four named App Shortcuts with English Siri phrases and warm yellow shortcut tiles. App Shortcuts and quick actions remain available on the app's iOS 17 minimum target.
- Four static Home Screen long-press quick actions, including cold- and warm-launch scene callbacks.
- One OpenIntent shared by the app and widget target. Named shortcut wrappers/provider are app-only; the extension only exports the control's OpenIntent.
- Typed, validated, one-shot action mailbox persists through cold launch/sign-in for up to 15 minutes. No account, basket contents, order ID or phone number is stored in it.
- Customer actions switch out of Delivery mode without granting Delivery access or modifying availability rules.
- Grocery/Food select their own service and dismiss retained product/menu exploration. Basket preserves the remembered service and does not open an empty cart. Tracking opens the active order, or Orders if none is active.
- Existing Live Activity remains included in the widget bundle.

No action picks up the basket, adds an item, confirms/submits an order, takes payment, goes online as a rider, or modifies production data.

## Verification

- MarketplaceFoundation: 8 tests passed, including URL/quick-action validation, persistence, one-shot consumption, latest-action precedence and expiry.
- DastakUI: 483 tests passed, including selected-service routing, empty-basket gating and outgoing/incoming exploration reset.
- Simulator Debug build passed; App Intents metadata exported successfully. Main app exports four automatic shortcuts and the shared OpenIntent; extension exports the shared OpenIntent.
- Signed device Debug build passed; strict deep code-signature verification passed.
- Final Build 33 (including overlay-reset and app-only provider corrections) was installed and launched on the physical iPhone. Installed bundle version was verified as 33.
- Dedicated iOS 26.5 simulator: all four Home Screen quick actions visibly listed; Grocery quick action correctly switched from Food to Grocery. Validated Food navigation route visibly opened Food.
- Shortcuts app visibly listed Open Grocery, Open Food, Open Basket and Track Order. Attempting Open Food on the iOS 26.5 simulator displayed “Unable to run App Shortcut”; execution is not marked passed.
- Control Centre gallery visibly listed all four Dastak controls. Temporary Food control was added with permission, then removed after the attempted test.
- User physically tested final Build 33 on the iPhone: Home Screen long-press → Food, Shortcuts → Open Food, and Control Centre → Dastak Food all opened Food correctly. User reported “All three pass.” These three physical entry-point checks are passed; simulator failures do not override that evidence.

## Still pending — do not claim these passed

The iOS 26.5 simulator's widget process failed while serializing the OpenIntent through its system helper (NSCocoaErrorDomain 4097, interrupted VoiceShortcut XPC connection). Control previews were blank; tapping produced `viewModel?.action is nil`. This is an observed runtime failure, not proof that the controls work on a physical device. System Ambient Music/Reminders controls were also blank in that gallery. Shortcuts execution also failed in the simulator. A fresh iOS 27 test simulator stalled in OS first-boot migration; it was stopped and deleted without touching the existing simulator or phone. Reports on Apple's developer forums describe similar failures in these simulator versions, including Apple's sample project; that supports investigating a simulator limitation but does not substitute for our physical-device verification.

Physical Food invocation from Home Screen, Shortcuts and Control Centre is passed by the user's test. Siri voice invocation, Lock Screen invocation, signed-out-to-signed-in continuation, Delivery-to-Customer invocation, other physical action variants and active-order tracking still require final runtime verification. Real-order testing remains pending by the user's earlier instruction.

## Manual check on the updated iPhone

1. Long-press Dastak: Grocery, Food, Basket, Track Order should appear. Open Grocery then Food; confirm their correct service.
2. Open Shortcuts → Dastak: the four actions should appear. Run Open Food. For Siri, say “Open food in Dastak.”
3. Control Centre → Add a Control → Dastak: add Food and tap it. Confirm it opens Food. Users choose which controls to keep; the app cannot automatically place them.
4. Empty Basket action must stay on Home and explain the basket is empty. With existing items, it should open the correct service's cart without changing its contents.
5. Track Order without an active order should open Orders. Verify an active-order case separately without placing a new order for this test.

## Primary API references

- https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system
- https://developer.apple.com/documentation/appintents/openintent
- https://developer.apple.com/documentation/appintents/appshortcutsprovider
- https://developer.apple.com/documentation/swiftui/uiapplicationdelegateadaptor
- https://developer.apple.com/documentation/uikit/add-home-screen-quick-actions
