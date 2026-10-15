# Dastak Home Screen widgets — Build 38

## Collection

- The Daily Edit: medium and large Home Screen widgets. Search plus direct Grocery, Food, Basket and Track Order links. The large version includes an hourly local-time greeting and illustrated Grocery/Food tiles.
- Everyday Essentials: small and medium Grocery widgets, forest-green backgrounds, cream serif typography and a lightweight native illustration of a grocery bag.
- Something Delicious: small and medium Food widgets, espresso/terracotta backgrounds and an illustrated ceramic coffee cup.
- Find with Dastak: circular, rectangular and inline Lock Screen Search widgets.

Instrument Serif is packaged in the widget extension with its OFL license. The artwork is drawn in SwiftUI; it does not require remote assets. Tinted and clear rendering use simple line art instead of overlapping coloured shapes. Backgrounds use WidgetKit's containerBackground API so the system can adapt them. English copy and the existing bilingual brand mark follow the app's branding.

## Behaviour

All widget links go through the existing validated com.dastak.app://open action router. Authentication, service selection, empty-basket gating and order access continue to be enforced by the app. These widgets do not display stock, live account/basket state, ETA or service availability. Track Order is a navigation action, not a displayed tracking snapshot. Live order information remains in the existing Live Activity.

The hourly timeline contains actual local date entries; it does not make network requests. Existing controls and Live Activity are retained in the bundle. The app requests widget timeline reloads once per installed build using WidgetCenter. Widget placement remains user-controlled.

## Verification

- Simulator Debug build passed.
- Signed iPhone Debug build and strict deep signature verification passed.
- Four targeted hosted iOS tests passed: all five widget URLs resolve to their advertised customer routes, and the existing Search quick-action/Shortcut metadata checks pass.
- Project/plist lint and diff whitespace checks passed.
- The packaged extension includes Instrument Serif and its license.
- Local simulator rendering of the exact widget views was inspected. Small Grocery/Food artwork initially crowded the copy; the final smaller illustrations and shorter headings were visually rechecked and were clear. Medium Daily Edit and the visible large Daily Edit layout were also inspected.
- Dastak appears in the simulator Home Screen widget search results. Opening the gallery details and scrolling were blocked by computer-use noWindowsAvailable, including after the user reported unlocking the Mac. Actual gallery size previews, tinted/clear system rendering and Lock Screen rendering are pending runtime checks, not marked passed.
- Build 38 was installed and launched on the physical iPhone; installed bundle version was verified as 38. The user checked the widget gallery and reported “Widgets appear and both open correctly.” Discovery of The Daily Edit, Everyday Essentials and Something Delicious, plus Grocery/Food widget navigation to the correct service, are therefore user-confirmed passed. This does not mark Lock Screen, tinted/clear rendering, other sizes or the remaining Daily Edit links passed.

## Sources

- https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity
- https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass
