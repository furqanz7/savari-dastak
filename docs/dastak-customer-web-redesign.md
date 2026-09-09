# Customer Web design release

## Scope and reference

Customer Web only. Reference: the current `DastakCustomerRootView`, `DastakHomeView`, and `DastakDeliveryTrackingView` in Customer iOS. Home / Orders / Account remain the primary destinations; Search belongs to shopping, and saved items/payment activity belong to Account.

The web expression uses a wide desktop storefront, tablet grids, and a compact mobile bottom navigation. It preserves the floating swipeable product card and independent circular product picker, with explicit desktop previous/next controls. It does not introduce another component framework, tracking provider, or backend architecture.

## Design system and implementation

- `Web/MarketplaceWeb/src/design/customer-experience.css`: Customer-scoped light/dark tokens, typography, spacing, controls, rounded surfaces, responsive grids, modal sizing, focus treatments, and reduced-motion rules. Warm neutrals and restrained gold reuse Dastak's existing type and icon assets.
- `CustomerUI.tsx`: common page headings, empty states, loading skeletons, scoped notices and quiet synchronization status.
- `DastakCustomerView.tsx`: one brand header, Home / Orders / Account navigation, offline context, and a keyboard skip link that does not overwrite the hash route.
- `DastakV1CustomerExperience.tsx`: product-led Home using actual catalogue images, discovery shortcuts, category navigation, lightweight Search, separate title/purchase controls, restaurant images/options/feedback, basket thumbnails, accessible modal ownership, secured checkout, and order presentation.
- `CustomerLiveDelivery.tsx` / `customerDeliveryPresentation.ts`: assigned rider and journey phase, map and freshness presentation. A local freshness clock does not refresh the order tree or reload the map each second.

The existing request deadlines, aborts, refresh queues, reconnect/fallback behavior, session recovery and cart persistence are retained. No backend, iOS, order mutation, notification or payment collection code was changed. The Customer total and the single `Pay via UPI/Cash on Delivery` option remain authoritative.

## Verified presentation corrections

- Product titles have an explicit full-width text control instead of inheriting the square Add button dimensions. Long titles wrap/clamp separately from pack, price and purchase actions.
- Mobile category discovery uses a bounded horizontal category rail and two-column product grid. Desktop uses a sticky side rail with normal page scrolling.
- Orders has quiet automatic-sync feedback and scoped retry/sign-in recovery; no prominent manual Refresh control. A failure with only historical cached orders cannot claim there are no active orders.
- Basket and restaurant dialogs use the existing focus/scroll-isolation hook. Address editing temporarily replaces the basket dialog to avoid competing focus traps.
- Optional existing backend `tracking` data is read by Web. A missing/malformed tracking extension cannot invalidate an otherwise valid order. Existing access-controlled order requests remain the only source of coordinates.
- Tracking follows assignment, pickup and arrival. The arrival label uses `riderArrivedAt` or the server's `ARRIVED` phase. It does not mark the order completed or alter handoff gates.
- The live badge follows the iOS precision/expiry contract: location present, accuracy 0–35 metres, before `liveUntil`, no device timestamp over five seconds in the future, and connected. Legacy coordinates without this authority are explicitly last-known.
- The new tracking view uses the embedded map's own marker. It opts out of the old fixed-position marker/straight-line overlay, which could imply a road route and drift when panning. Other consumers keep their default behavior.

## Verification

Directly executed:

- Full Web suite: **297 tests across 46 files passed**; 15 new checks added to the existing 282.
- ESLint: passed without warnings.
- TypeScript and Vite builds: Customer, Delivery, Merchant and Admin passed. Only Customer is released by this task; shared changes use opt-in props with existing defaults.
- Production dependency audit: zero vulnerabilities. The install audit still reports two moderate development-only dependency advisories; no forced dependency upgrade was applied.
- Customer production project/root/variant/required-configuration preflight: passed using the repository deployment script.
- Source-level responsive checks: bounded grids and narrow breakpoints, long-name markup, readable inputs, focus/semantic controls, reduced motion and light/dark token coverage.
- Shared text/primary-action color combinations meet a computed 4.5:1 contrast threshold against the tested light/dark surfaces.

Browser, simulator and iPhone tests were not performed, following the owner's restriction. No live order, stock, payment, saved address or account was changed for testing. CSS/markup checks and successful builds are not browser visual proof.

Remaining browser acceptance, when explicitly authorized: 320/375/768/1024/1440 widths, both color schemes, zoom/keyboard navigation, swipe and picker behavior, basket-to-address focus restoration, real catalogue images, actual order tracking and offline recovery. Confirm no document-level horizontal overflow and no fixed controls obscuring content.

## Release

Use the existing Customer-only script after committing: `bash scripts/deploy-dastak-web.sh customer --production`. The release response should record the resulting commit, deployment ID, public alias and HTTP/asset checks. No migration or Edge Function deployment is needed.
