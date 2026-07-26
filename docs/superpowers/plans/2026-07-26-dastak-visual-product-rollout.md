# Dastak Visual Product Rollout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking. Do not use subagents. Before every
> task, explain its scope, reason, size, and estimated usage, then wait for the
> owner's explicit approval.

**Goal:** Finish Dastak on iOS first, then adapt each approved experience to
web using the shared Apple-native spatial-minimalist direction and the existing
server-authoritative backend.

**Architecture:** Existing Supabase contracts and typed infrastructure clients
remain the behavioural foundation. A small shared Swift package owns visual
tokens, reusable surfaces, and bilingual wordmarks. Each role is completed as
an iOS vertical slice and visually approved before its React equivalent is
adapted.

**Tech Stack:** SwiftUI, MapKit, XCTest, React 19, TypeScript, CSS, Vitest,
Playwright/browser screenshots, Supabase, Razorpay mock and test modes.

## Global Constraints

- Complete Dastak before starting Savari implementation.
- iOS is the visual source of truth; current web workflows are the behavioural
  reference.
- Preserve the approved direction in
  `docs/superpowers/specs/2026-07-26-savari-dastak-visual-direction-design.md`.
- Reuse existing backend contracts. Change backend code only when a verified
  defect blocks the approved product flow.
- Use mock or Razorpay Test Mode only. Real-money activation is outside this
  plan.
- The owner supplies app icons, launch experiences, and imagery later.
- The product team owns the bilingual `Dastak | دستک` wordmark.
- Do not add third-party UI frameworks or snapshot-test dependencies.
- Keep customer and partner web mobile-first; expand merchant and admin web
  into desktop workspaces.
- Every task ends with tests, visual evidence, a clean worktree, and one focused
  commit.

## Planned Structure

### Shared iOS visual system

- `Packages/MarketplaceDesignSystem/`: tokens, materials, controls, wordmark,
  accessibility rules, and tests shared by Dastak targets and later Savari.

### Dastak iOS

- `Apps/Dastak/Sources/Dastak/Customer/`: discovery, cart, checkout, orders,
  parcels, and live delivery.
- `Apps/Dastak/Sources/Dastak/Partner/`: availability, offers, active work, and
  earnings receipt.
- `Apps/Dastak/Sources/DastakMerchant/`: orders, catalogue, store, and account.
- `Apps/Dastak/Sources/DastakAdmin/`: today, orders, accounts, money, incidents,
  and settings.

### Dastak web

- `Web/MarketplaceWeb/src/design/`: shared CSS tokens and primitives.
- Existing role views remain behavioural entry points and are split only when
  a focused component boundary is required.

---

### Task 1: Approve and establish the visual foundation

**Files:**
- Create: `Packages/MarketplaceDesignSystem/Package.swift`
- Create: `Packages/MarketplaceDesignSystem/Sources/MarketplaceDesignSystem/MarketplaceVisualTokens.swift`
- Create: `Packages/MarketplaceDesignSystem/Sources/MarketplaceDesignSystem/MarketplaceSurfaces.swift`
- Create: `Packages/MarketplaceDesignSystem/Sources/MarketplaceDesignSystem/DastakWordmark.swift`
- Create: `Packages/MarketplaceDesignSystem/Tests/MarketplaceDesignSystemTests/MarketplaceVisualTokensTests.swift`
- Create: `Web/MarketplaceWeb/src/design/tokens.css`
- Modify: `Apps/Dastak/Dastak.xcodeproj/project.pbxproj`
- Modify: `Web/MarketplaceWeb/src/styles.css`

**Produces:** Approved colour roles, typography, spacing, materials, controls,
and bilingual wordmark used by every later task.

- [ ] Present exact light/dark colour swatches, wordmark proportions, type
  hierarchy, spacing, control, sheet, and material examples for visual approval.
- [ ] Write tests asserting neutral primary actions, distinct brand and
  destructive roles, 44-point minimum controls, and stable token names.
- [ ] Run `swift test --package-path Packages/MarketplaceDesignSystem` and
  verify the tests fail before the package implementation exists.
- [ ] Implement the approved tokens and primitives without app icon, launch, or
  imagery assets.
- [ ] Add equivalent CSS custom properties with the same semantic names.
- [ ] Run `swift test --package-path Packages/MarketplaceDesignSystem`,
  `scripts/test-dastak-ios.sh`, and `scripts/test-dastak-web.sh`.
- [ ] Capture light/dark iOS previews and responsive web samples for approval.
- [ ] Commit as `feat: establish Dastak visual system`.

### Task 2: Build Dastak Customer discovery and shopping on iOS

**Files:**
- Create: `Apps/Dastak/Sources/Dastak/Customer/DastakCustomerRootView.swift`
- Create: `Apps/Dastak/Sources/Dastak/Customer/CustomerHomeView.swift`
- Create: `Apps/Dastak/Sources/Dastak/Customer/CustomerSearchView.swift`
- Create: `Apps/Dastak/Sources/Dastak/Customer/CustomerProductView.swift`
- Create: `Apps/Dastak/Sources/Dastak/Customer/CustomerCartView.swift`
- Create: `Apps/Dastak/Sources/Dastak/Customer/CustomerCheckoutView.swift`
- Create: `Apps/Dastak/Sources/Dastak/Customer/CustomerShoppingModel.swift`
- Create: `Apps/Dastak/Tests/DastakTests/CustomerShoppingModelTests.swift`
- Modify: `Apps/Dastak/Sources/Dastak/DastakApp.swift`

**Consumes:** `MarketplaceDesignSystem`, `CatalogueClient`,
`MerchantOrderClient`, and `DastakPaymentClient`.

**Produces:** Native Home, Search, product, cart, quote, test-checkout, and
confirmation flows.

- [ ] Write model tests for 10–30 km discovery, single-merchant cart rules,
  quantity changes, quote invalidation, idempotent order creation, and retained
  state after payment dismissal.
- [ ] Run `scripts/test-dastak-ios.sh` and verify the new tests fail.
- [ ] Implement the customer tab root and API-backed shopping model.
- [ ] Implement product-first discovery using approved placeholders and stable
  product image proportions.
- [ ] Implement cart and checkout with one primary action per state.
- [ ] Route checkout only through mock or Razorpay Test Mode.
- [ ] Run `scripts/test-dastak-ios.sh`.
- [ ] Verify light/dark, English/Tamil, Dynamic Type, loading, empty, error, and
  populated screenshots before approval.
- [ ] Commit as `feat: build Dastak customer shopping`.

### Task 3: Build Customer orders, parcels, and live delivery on iOS

**Files:**
- Create: `Apps/Dastak/Sources/Dastak/Customer/CustomerOrdersView.swift`
- Create: `Apps/Dastak/Sources/Dastak/Customer/CustomerOrderDetailView.swift`
- Create: `Apps/Dastak/Sources/Dastak/Customer/CustomerLiveDeliveryView.swift`
- Create: `Apps/Dastak/Sources/Dastak/Customer/CustomerParcelView.swift`
- Create: `Apps/Dastak/Sources/Dastak/Customer/CustomerOrdersModel.swift`
- Create: `Apps/Dastak/Tests/DastakTests/CustomerOrdersModelTests.swift`

**Consumes:** `MerchantOrderClient`, `ParcelDeliveryClient`, MapKit, and the
approved customer root from Task 2.

**Produces:** Order history, parcel creation, cancellation, live map stages,
verification context, and receipt presentation.

- [ ] Write tests mapping every server order and parcel state to one human label
  and one permitted primary action.
- [ ] Verify the tests fail with `scripts/test-dastak-ios.sh`.
- [ ] Implement order and parcel repositories without client-authored status
  changes.
- [ ] Implement the stable live-delivery map sheet and contextual secondary
  actions.
- [ ] Implement cancellation, refund-state, failure, and receipt presentations.
- [ ] Run `scripts/test-dastak-ios.sh`.
- [ ] Complete a mock customer lifecycle and approve screenshots for every
  stage.
- [ ] Commit as `feat: add Dastak customer delivery lifecycle`.

### Task 4: Adapt the approved Customer experience to web

**Files:**
- Modify: `Web/MarketplaceWeb/src/DastakCustomerView.tsx`
- Modify: `Web/MarketplaceWeb/src/CatalogueView.tsx`
- Modify: `Web/MarketplaceWeb/src/ParcelCustomerView.tsx`
- Create: `Web/MarketplaceWeb/src/design/customer.css`
- Modify: `Web/MarketplaceWeb/src/styles.css`
- Test: `Web/MarketplaceWeb/src/catalogue.test.ts`
- Test: `Web/MarketplaceWeb/src/cart.test.ts`
- Test: `Web/MarketplaceWeb/src/orders.test.ts`
- Test: `Web/MarketplaceWeb/src/parcels.test.ts`

**Produces:** Behaviourally equivalent responsive Customer web using the
approved iOS hierarchy.

- [ ] Extend tests for the approved navigation, labels, action visibility, and
  state preservation.
- [ ] Run `npm test --prefix Web/MarketplaceWeb` and verify failures.
- [ ] Adapt discovery, cart, checkout, orders, parcels, and live delivery
  without changing server contracts.
- [ ] Run web tests, lint, and production build.
- [ ] Inspect mobile, tablet, and desktop screenshots in light and dark modes.
- [ ] Verify the deployed customer lifecycle in mock/test mode.
- [ ] Commit as `feat: align Dastak customer web`.

### Task 5: Build Dastak Delivery Partner on iOS

**Files:**
- Create: `Apps/Dastak/Sources/Dastak/Partner/PartnerRootView.swift`
- Create: `Apps/Dastak/Sources/Dastak/Partner/PartnerMapView.swift`
- Create: `Apps/Dastak/Sources/Dastak/Partner/PartnerOfferView.swift`
- Create: `Apps/Dastak/Sources/Dastak/Partner/PartnerActiveJobView.swift`
- Create: `Apps/Dastak/Sources/Dastak/Partner/PartnerEarningsReceiptView.swift`
- Create: `Apps/Dastak/Sources/Dastak/Partner/PartnerWorkModel.swift`
- Create: `Apps/Dastak/Tests/DastakTests/PartnerWorkModelTests.swift`
- Modify: `Apps/Dastak/Sources/Dastak/DastakApp.swift`

**Consumes:** `DeliveryPartnerClient`, `CourierDispatchClient`, and
`ParcelDeliveryClient`.

**Produces:** Access-gated mode switching, availability, offers, verified
pickup/delivery, active work, and earnings receipt.

- [ ] Write tests ensuring one primary action for each partner state and no
  offline transition during active work.
- [ ] Verify failures with `scripts/test-dastak-ios.sh`.
- [ ] Implement the map-first partner root and polling/recovery model.
- [ ] Implement offer, active job, verification, incident, and completion
  surfaces without raw IDs or statuses.
- [ ] Run `scripts/test-dastak-ios.sh`.
- [ ] Verify merchant-order and parcel lifecycles with two test accounts.
- [ ] Approve all partner screenshots and commit as
  `feat: build Dastak partner experience`.

### Task 6: Adapt Delivery Partner to web

**Files:**
- Modify: `Web/MarketplaceWeb/src/DeliveryPartnerView.tsx`
- Create: `Web/MarketplaceWeb/src/design/partner.css`
- Modify: `Web/MarketplaceWeb/src/styles.css`
- Test: `Web/MarketplaceWeb/src/delivery.test.ts`
- Test: `Web/MarketplaceWeb/src/parcels.test.ts`

- [ ] Add failing tests for state-specific actions and human-readable copy.
- [ ] Adapt the approved map, offer, active-job, and receipt hierarchy.
- [ ] Run web tests, lint, and production build.
- [ ] Verify mobile-first responsive screenshots and a full deployed lifecycle.
- [ ] Commit as `feat: align Dastak partner web`.

### Task 7: Build Dastak Merchant on iOS

**Files:**
- Create: `Apps/Dastak/Sources/DastakMerchant/MerchantRootView.swift`
- Create: `Apps/Dastak/Sources/DastakMerchant/MerchantOrdersView.swift`
- Create: `Apps/Dastak/Sources/DastakMerchant/MerchantCatalogueView.swift`
- Create: `Apps/Dastak/Sources/DastakMerchant/MerchantStoreView.swift`
- Create: `Apps/Dastak/Sources/DastakMerchant/MerchantWorkspaceModel.swift`
- Create: `Apps/Dastak/Tests/DastakMerchantTests/MerchantWorkspaceModelTests.swift`
- Modify: `Apps/Dastak/Sources/DastakMerchant/DastakMerchantApp.swift`

- [ ] Write tests for actionable order grouping, preparation transitions,
  catalogue availability, rejection, return, and refund visibility.
- [ ] Implement Orders, Catalogue, Store, and Account using existing clients.
- [ ] Run `scripts/test-dastak-ios.sh`.
- [ ] Approve loading, empty, active, failure, and history screenshots.
- [ ] Commit as `feat: build Dastak merchant experience`.

### Task 8: Adapt Merchant to web

**Files:**
- Modify: `Web/MarketplaceWeb/src/MerchantOrdersView.tsx`
- Modify: `Web/MarketplaceWeb/src/MerchantCatalogueView.tsx`
- Create: `Web/MarketplaceWeb/src/design/merchant.css`
- Modify: `Web/MarketplaceWeb/src/styles.css`
- Test: `Web/MarketplaceWeb/src/orders.test.ts`

- [ ] Add failing tests for the approved information and action hierarchy.
- [ ] Adapt Orders, Catalogue, Store, and Account for mobile and desktop.
- [ ] Run web tests, lint, and production build.
- [ ] Verify screenshots and the deployed merchant lifecycle.
- [ ] Commit as `feat: align Dastak merchant web`.

### Task 9: Build Dastak Admin on iOS

**Files:**
- Create: `Apps/Dastak/Sources/DastakAdmin/AdminRootView.swift`
- Create: `Apps/Dastak/Sources/DastakAdmin/AdminTodayView.swift`
- Create: `Apps/Dastak/Sources/DastakAdmin/AdminOrdersView.swift`
- Create: `Apps/Dastak/Sources/DastakAdmin/AdminAccountsView.swift`
- Create: `Apps/Dastak/Sources/DastakAdmin/AdminMoneyView.swift`
- Create: `Apps/Dastak/Sources/DastakAdmin/AdminIncidentsView.swift`
- Create: `Apps/Dastak/Sources/DastakAdmin/AdminWorkspaceModel.swift`
- Create: `Apps/Dastak/Tests/DastakAdminTests/AdminWorkspaceModelTests.swift`
- Modify: `Apps/Dastak/Sources/DastakAdmin/DastakAdminApp.swift`

- [ ] Write tests for exception counts, approval decisions, refund review,
  evidence access, and human-readable audit history.
- [ ] Implement the owner-only split-view workspace using existing admin
  contracts.
- [ ] Run `scripts/test-dastak-ios.sh`.
- [ ] Approve phone and large-screen screenshots for every primary area.
- [ ] Commit as `feat: build Dastak admin experience`.

### Task 10: Adapt Admin to web

**Files:**
- Modify: `Web/MarketplaceWeb/src/AdminDashboard.tsx`
- Create: `Web/MarketplaceWeb/src/design/admin.css`
- Modify: `Web/MarketplaceWeb/src/styles.css`
- Test: `Web/MarketplaceWeb/src/admin.test.ts`

- [ ] Add failing tests for navigation, exception-first summaries, decisions,
  audit visibility, and refund actions.
- [ ] Adapt the approved Admin hierarchy into a responsive operational sidebar.
- [ ] Run web tests, lint, and production build.
- [ ] Verify desktop and mobile screenshots plus deployed owner workflows.
- [ ] Commit as `feat: align Dastak admin web`.

### Task 11: Complete localization, accessibility, and motion

**Files:**
- Create: `Apps/Dastak/Resources/en.lproj/Localizable.strings`
- Create: `Apps/Dastak/Resources/ta.lproj/Localizable.strings`
- Create: `Web/MarketplaceWeb/src/localization/en.ts`
- Create: `Web/MarketplaceWeb/src/localization/ta.ts`
- Modify: all approved Dastak role roots only where hard-coded copy remains

- [ ] Add tests that every supported state resolves non-empty English and Tamil
  copy and that technical backend labels are absent.
- [ ] Move user-visible copy into localization resources.
- [ ] Verify Dynamic Type, VoiceOver labels, keyboard navigation, contrast,
  Reduce Motion, and touch-target sizes.
- [ ] Run all iOS and web tests.
- [ ] Capture the final accessibility evidence and commit as
  `feat: complete Dastak accessibility and localization`.

### Task 12: Verify and release the test-payment product

**Files:**
- Modify: `scripts/test-dastak-ios.sh`
- Modify: `scripts/test-dastak-web.sh`
- Create: `docs/runbooks/dastak-test-payment-release.md`

- [ ] Run all Swift package, iOS target, web unit, lint, build, database, and
  Edge Function tests.
- [ ] Complete customer, merchant, partner, and admin merchant-order lifecycle
  using test money.
- [ ] Complete the parcel lifecycle and cancellation/refund variants.
- [ ] Verify role isolation, no client-direct writes, and no real provider keys.
- [ ] Verify all four Vercel deployments and produce final responsive
  screenshots.
- [ ] Build all three Dastak iOS schemes and verify representative devices.
- [ ] Record known production gates: live Razorpay, KYC, settlements,
  notifications, legal review, and owner-supplied brand assets.
- [ ] Commit as `test: verify Dastak test-payment release`.

## Execution Rule

Tasks execute strictly in order. A task begins only after the owner receives its
scope, reason, size, estimated usage, and explicitly approves it. Completing
this plan does not start Task 1.
