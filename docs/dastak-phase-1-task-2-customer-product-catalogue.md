# Dastak Phase 1 Task 2 Customer Product Catalogue

Recorded on 2026-08-13 from branch `codex/savari-dastak-execution` after the
Phase 1 Task 1 backend release. This is an evidence-based inventory of the
Dastak Customer product on iOS and web. It does not redesign screens, change
contracts, deploy applications, or activate live Razorpay credentials.

## Readiness verdict

The Customer product is a connected prototype, not a finished launch product.
Authentication, profile bootstrap, service-area catalogue browsing, basic
cart/quote/order creation, parcel creation, Test Mode checkout, order polling,
and cancellation contracts exist. The two clients are not product-equivalent,
and critical delivery, money, recovery, privacy, localization, and test gaps
remain.

The most serious issue is contractual: a store-order quote and order persist
only the drop-off coordinate. The structured house/flat/landmark entered on
iOS is never sent to Supabase, and web has no structured delivery-address flow
at all. A delivery partner therefore cannot receive a dependable doorstep
address for a merchant order. Parcel delivery does persist full pickup and
drop-off addresses and does not have this defect.

## Status language

- **Complete:** reachable, backed by the server, and has an appropriate user
  state for the current Test Mode scope.
- **Partial:** reachable but materially incomplete, misleading, or missing
  recovery.
- **Missing:** no customer entry point exists.
- **Backend only:** a server/client contract exists but neither customer app
  exposes it.
- **Deferred:** intentionally not a blocker for the current Test Mode build.

## Shared entry and account flow

| Step | iOS | Web | Status |
| --- | --- | --- | --- |
| Launch experience and app icon | Branded launch media and app icon are bundled | Browser entry has no native splash requirement | Complete |
| Restore session | Dedicated restore state | Loading/account evaluation state | Complete |
| Apple sign-in | Native Sign in with Apple | Supabase OAuth | Complete |
| Google sign-in | OAuth with multicolour Google mark | Supabase OAuth with multicolour Google mark | Complete |
| First profile | Requires display name and E.164 contact phone | Requires display name and E.164 contact phone | Complete |
| Role access | Server-approved Customer access | Server-approved `dastak-customer` route | Complete |
| Delivery address onboarding | Mandatory local address sheet after bootstrap | Not present | Partial |
| Account restoration | Restores authenticated account | Restores authenticated account | Complete |
| Edit profile or phone | Read-only account card | Read-only account page | Missing |
| Sign out | Account action | Account action | Complete |

The user has already verified the authentication flow manually. Authentication
is not a Task 3 rewrite target unless a regression is found.

## iOS customer surface

### App shell

The combined Dastak app can switch between Customer and Delivery Partner after
the backend confirms approved partner access. Customer mode has four tabs:
Home, Search, Orders, and Account. It can present address, basket, parcel, and
Razorpay sheets.

| Surface | Reachable actions | Current states | Assessment |
| --- | --- | --- | --- |
| Home | Choose location, change 10-30 km range, open Search, open basket, open parcel, add product, replace cross-store basket, pull to refresh | Location required, initial load, catalogue error/retry, no stores, stale-data notice, populated | Partial |
| Search | Type query, add product, replace cross-store basket, open basket | Location required, catalogue error/retry, no products, no matches, populated | Partial |
| Basket | Increment/decrement, clear, edit address, quote, choose payment method, create order | Empty, populated, quoting spinner | Partial |
| Address editor | Search location, request current location, choose Home/Work/Other, add house/flat/landmark, save | Editing and saving | Partial |
| Location picker | Search MapKit suggestions, resolve suggestion, request/use current location | Resolving overlay | Partial |
| Payment method | Choose generic UPI category/app label, card, net banking, wallet, or pay later | Selected/unselected | Partial, Test Mode |
| Razorpay checkout | Open official Standard Checkout, receive success/failure/cancel callback | Provider-owned UI plus short payment-confirmation overlay | Deferred real-device matrix |
| Orders | View store orders and parcels, pull/10-second refresh, open details | Initial load, offline/session/access/server recovery, empty, populated | Partial |
| Store-order detail | View static endpoint map, status, handoff code, lines and total; retry payment; request cancellation in some states | All order labels | Partial |
| Parcel detail | View static endpoint map, status, handoff code, route and fee; retry payment; cancel before pickup | All parcel labels | Partial |
| Send parcel | Choose pickup/drop-off, Bike/Auto, recipient, contents/value, quote, create and pay | Form, quoting, quoted | Partial |
| Account | View name, phone, email, local address/range, call 112, sign out | Profile-data recovery notice | Partial |

### iOS behavior that is present but incomplete

- Home ignores catalogue categories and renders every active product directly
  under its store.
- Product tiles ignore `imageObjectPath` and always render a generic SF Symbol.
- There is no store page, category page, or product-detail page.
- Search filters product name and description only. Its promise to search
  products, stores, and categories is inaccurate.
- The basket has no quantity ceiling even though the server rejects quantities
  above 99.
- Address search and Core Location maintain error messages that no customer
  view renders.
- Model errors raised while Basket, Parcel, or Razorpay is presented are shown
  on the covered root view, so the active sheet can appear to do nothing.
- A failed or cancelled Razorpay callback does not clear the checkout session
  or close checkout before presenting recovery.
- An order can be created successfully and checkout creation can then fail.
  The basket and quote remain, a fresh idempotency key is used on retry, and a
  second unpaid order can be created.
- Cancelling a paid store order can set `refund_pending`, but the iOS customer
  path never calls `processMerchantOrderRefund`.
- iOS prevents cancellation at `picked_up` and `in_transit`, although the
  backend supports a customer cancellation/refund-review request then and web
  exposes it.
- Store-order payment UI reduces every non-paid state (`not_collected`,
  `refund_pending`, `refunded`) to "Pending". Parcel UI similarly reduces
  failed/refund/cancelled payment states to "Pending".
- Order and parcel maps show fixed pickup/drop-off markers. They do not show a
  courier location or constitute live tracking.
- A notification tap opens the Orders tab but not the referenced order detail.
- APNs registration is attempted during customer bootstrap only. If the device
  token arrives after bootstrap, registration waits until a later bootstrap.
- The notification queue covers merchant-order status/payment changes, not
  parcel status changes.
- The customer safety UI only calls `112` from Account. It does not identify an
  active job or invoke the existing parcel safety-incident contract.

## Web customer surface

Web uses a four-item Home, Search, Orders, and Account navigation plus a
separate Parcel experience. Catalogue, cart, checkout, and store-order state
live inside one `CatalogueView` component rather than durable routes.

| Surface | Reachable actions | Current states | Assessment |
| --- | --- | --- | --- |
| Home | Search location/current location, change 10-30 km range, open Search/Parcel, edit cart, quote/pay, view one active order | Location required, loading, catalogue error/retry, no stores, populated, order refresh notice | Partial |
| Search | Search product/category/store, edit cart, quote/pay | Same catalogue states plus no matches | Partial |
| Cart/checkout | Quantity controls, clear, quote, create order, choose payment category, open Razorpay | Inline summary/quote/payment messages | Partial, no dedicated route |
| Orders | View compact store-order rows, pay, cancel, refresh | Loading, session/access/offline/server recovery, empty, populated | Partial |
| Account | View name/email/phone/range and sign out | No dedicated loading/edit/address/support state | Partial |
| Parcel | View compact history; create, quote, pay, cancel a parcel | Loading, refresh recovery, empty, form, quote, messages | Partial |

### Web behavior that is present but incomplete

- There is no mandatory or structured delivery-address onboarding. A selected
  geocoder label and coordinate are stored only in browser local storage.
- There is no basket route, order-review route, order-detail route, parcel
  detail route, map, timeline, or live-delivery route.
- Store and product cards are expanded in one long catalogue; there is no store
  page, product detail, category navigation, filter, sort, or availability ETA.
- The Account page cannot view/edit a structured address, change profile data,
  access order help, or inspect notification preferences.
- Store orders and parcels are split across Orders and the Parcel screen rather
  than one coherent customer history.
- `ordersRefreshIssue` is rendered above every Customer section, so an order
  refresh failure can appear on Home, Search, or Account even when that content
  is otherwise usable.
- Named UPI rows all reduce to the same generic Razorpay `upi` category. The UI
  implies app-specific selection that the integration does not preserve.
- Parcel offers Bike, Auto, Bicycle, and Walking while iOS offers only Bike and
  Auto. This conflicts with the agreed active vehicle types.
- Parcel declared value accepts zero on web but iOS requires a value greater
  than zero.
- Web cancellation describes refund progress better than iOS, but has no
  detailed refund timeline, receipt, or support path.
- There is no web push/notification center and no deep-link routing model.

## Backend contract trace

| Customer capability | Authoritative contract | Client use | Gap |
| --- | --- | --- | --- |
| Account/profile/access | Auth, `bootstrap-account`, `resolve-app-access` | iOS + web | No profile edit flow after bootstrap |
| Delivery address | None for customer saved addresses | Local `UserDefaults` / `localStorage` | Not account-scoped, cross-device, or server-authoritative |
| Catalogue discovery | `catalogue.browse` | iOS + web | iOS omits images/categories/store search in presentation |
| Store-order quote/create/snapshot/cancel | `merchant-orders` | iOS + web | Drop-off has latitude/longitude only; no doorstep address |
| Merchant-order dispatch | `courier-dispatch` | Partner clients only | Customer snapshot has no courier identity, phone, vehicle, or location |
| Parcel quote/create/snapshot/cancel | `parcel-deliveries` | iOS + web | Core contract is connected; presentation/recovery remains incomplete |
| Parcel safety report | `parcel-deliveries.reportSafetyIncident` | Backend/client only | No customer action invokes it |
| Payment checkout/refund | `dastak-payments` + signed Razorpay webhook | iOS + web | iOS store-order cancellation omits refund processing; real-device matrix deferred |
| Merchant-order push | device-token registration + order queue/worker | iOS only | Registration race, no exact-order route, no parcel events |
| Controlled categories | `controlled-categories` | Backend/client only | No customer age attestation, prescription, browse, quote, or compliance UX |
| Ratings/reports | No complete Customer contract | Neither | Missing after delivery |
| Invoice/receipt | Provider receipt exists internally | Neither | No customer receipt/invoice presentation |

## Cross-platform parity

| Capability | iOS | Web | Required convergence |
| --- | --- | --- | --- |
| Auth/profile | Complete | Complete | Preserve |
| Structured address onboarding | Local-only | Missing | One server-backed address contract and equivalent UI |
| Product images | Missing | Present | iOS must use catalogue images with robust placeholders |
| Store/category/product hierarchy | Missing | Categories grouped but no detail routes | Shared information architecture |
| Search promise | Product-only | Product/category/store | Shared behavior and copy |
| Basket | Dedicated sheet | Inline summary | Shared durable basket/review model |
| Store-order details | Present but static | Missing | Equivalent detail, timeline, money, and recovery |
| Parcel details | Present but static | Compact card only | Equivalent detail and tracking |
| Store-order cancellation after pickup | Hidden | Available | Match authoritative server policy |
| Refund states | Incorrectly collapsed | Partial | Exact states and amounts on both |
| Error recovery | Often hidden behind sheets | Mostly inline, sometimes globally misplaced | Screen-local loading/error/retry |
| Notifications | Merchant-order APNs only | None | Event/deep-link strategy by platform |
| Localization | English literals | English literals | English and Tamil resources |
| Automated UI/E2E coverage | None | None | State matrix and lifecycle coverage |

## Ordered repair backlog

### P0 - blocks a credible customer launch

1. **Persist a real merchant-order doorstep address.** Add an account-scoped
   saved-address contract and include a normalized address snapshot in every
   merchant quote/order/customer/courier response. Migrate iOS and web off
   unscoped local-only addresses.
2. **Make order creation interruption-safe.** Separate durable order creation
   from checkout, retain/recover the created order ID, reuse idempotency, clear
   the basket exactly once, and prevent duplicate unpaid orders.
3. **Repair money-state behavior on iOS.** Process eligible customer refunds,
   expose review/pending/refunded/denied states and amounts, and align
   cancellation actions with the server policy.
4. **Put failures on the active surface.** Basket, quote, parcel, checkout,
   location, and address failures need local loading/error/retry states; no
   action may fail behind a sheet or on an unrelated tab.
5. **Deliver an executable last-mile customer contract.** Customer snapshots
   need safe courier identity/contact/vehicle and latest location data; both
   clients need a genuine status timeline and live-delivery surface instead of
   endpoint-only maps.
6. **Complete customer notification reliability.** Register tokens when APNs
   returns, cover parcel and merchant-order events, route to the exact entity,
   and provide in-app recovery when push is unavailable.
7. **Implement job-aware safety.** Active deliveries need a 112 action plus a
   server-recorded incident/report path with honest copy about emergency scope.
8. **Ship English and Tamil resources.** No localization catalogue exists in
   either client despite the launch requirement.
9. **Gate controlled products safely.** If medicine or tobacco is enabled at
   launch, connect age attestation, prescription evidence, restricted browse,
   policy/exclusion messaging, handoff rules, and appropriate order states.
   Otherwise keep every controlled product unpublished for launch.

### P1 - required to call the Customer product finished

1. Build one approved navigation and information hierarchy covering Home,
   store/category/product discovery, Search, Basket, Orders, Parcels, and
   Account without duplicate or hidden workflows.
2. Add store, category, and product-detail experiences; render real product
   images on iOS; add filter/sort only where it improves discovery.
3. Make Account editable and add saved-address management, support, legal,
   privacy, notification, and account-deletion routes.
4. Add complete order/parcel details on web and converge labels/actions/state
   ordering across platforms.
5. Add receipts/invoices, refund details, contextual help, reorder, and
   delivered-order rating/report flows with server contracts where absent.
6. Align vehicle methods and field validation between clients; show field-level
   guidance rather than silently disabling the primary action.
7. Scope all local caches to the authenticated account and define sign-out,
   account-switch, stale-catalogue, quote-expiry, and offline behavior.
8. Replace fixed endpoint maps with stable live map framing, privacy-aware
   courier updates, ETA, and contact actions.

### P2 - polish and scale after correctness

1. Complete the Apple-native visual pass from iOS first, then reproduce its
   hierarchy on responsive web. Remove mixed legacy hard-coded styling.
2. Add skeletons, intentional empty states, motion/reduced-motion behavior,
   keyboard/focus treatment, Dynamic Type, VoiceOver, contrast, and responsive
   overflow verification.
3. Split oversized customer components and CSS ownership only where doing so
   makes state and visual behavior easier to verify.
4. Add performance budgets for product images, catalogue rendering, web bundle
   size, map updates, polling, and cold launch.

## Verification gap

Current automated coverage proves client parsers/contracts and a small part of
cart behavior. It does not prove the Customer product:

- iOS has two cart unit tests and two combined-app root tests, but no
  `DastakCustomerModel` state-machine tests, UI tests, snapshot tests, payment
  recovery tests, or accessibility/localization tests.
- Web has unit tests for auth/access, catalogue, cart, orders, parcels, and
  payments, but no React component tests, browser E2E suite, visual regression,
  accessibility gate, or responsive screenshot gate.
- No automated journey proves customer order -> merchant acceptance -> courier
  delivery -> customer status/payment/refund result.
- No real-device Test Mode matrix proves Razorpay success, failure,
  cancellation, card verification, UPI return, webhook confirmation, and
  interrupted-app restoration. This remains deferred by owner decision.

## Task 2 exit decision

The catalogue is complete enough to prevent blind visual implementation. Task
3 must define the unified Customer information architecture and navigation
state model, but its first implementation slice must include the P0 address,
idempotency, money-state, and active-surface error contracts. A cosmetic
redesign on the current contracts would preserve the failures documented here.
