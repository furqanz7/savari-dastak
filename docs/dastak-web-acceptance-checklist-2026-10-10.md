# Dastak web acceptance checklist

## Scope and evidence

Owner decision, 10 October 2026: finish Customer, Merchant, Delivery and Admin
web apps first. Once accepted, use the finished web product as the reference for
building/finishing native apps. Native implementation is not started by this decision.

Passed means owner-tested and reported working; it is not independent agent
verification. Automated/backend/security verification remains a separate gate.
Failed items require a fix and retest; unavailable scenarios remain Not tested.
Deferred items are excluded from this release, not declared implemented.

Wider SKU work and further environment-graphics refinement remain deferred under
earlier owner instructions, subject to final scope confirmation.

## Batch 1: sign-in and cart

Owner reported "All passed" on 10 October 2026 after Customer release 94f531d.

| ID | Check | Status | Evidence |
|---|---|---|---|
| 1 | Stay signed in through Home, Orders, Profile and Settings | Passed | Owner report |
| 2 | Single Customer tab gains cart editing without stuck lock message | Passed | Owner report |
| 3 | Add, change quantity and remove; cart totals update | Passed | Owner report |
| 4 | Refresh preserves cart item and quantity | Passed | Owner report |
| 5 | Switch Customer tabs; regain editing without item loss/duplication | Passed | Owner report |
| 6 | Orders/Settings/background tab does not permanently block shopping tab | Passed | Owner report |

## Batch 2: location and availability

Owner reported "All passed" for checks 7–14 on 10 October 2026.
Statuses below are owner-reported, not independent backend verification.

| ID | Check | Status |
|---|---|---|
| 7 | Header location control opens picker and can be dismissed | Passed |
| 8 | Address typing produces relevant selectable suggestions | Passed |
| 9 | Selecting suggestion centers map/pin on selected location | Passed |
| 10 | Dragging pin or tapping map updates chosen coordinates without glitches | Passed |
| 11 | Save/select address updates delivery location and persists on refresh | Passed |
| 12 | Area with no eligible merchant/restaurant within 30 km shows correct Grocery/Food unavailability, without wrong-area listings | Passed |
| 13 | Onboarded but closed restaurant stays visible with Store closed and disabled ordering entry | Passed |
| 14 | Area without active eligible delivery partner allows available cart additions but blocks order placement with explanation | Passed |

Do not change live merchant/rider availability solely to manufacture these tests.
Scenarios unavailable to the owner remain Not tested; verify backend distance and
eligibility enforcement separately with controlled tests.

## Batch 3: Grocery shopping

Owner reported "All passed" for checks 15–24 on 10 October 2026.

| ID | Check | Status |
|---|---|---|
| 15 | Category/subcategory navigation opens correct shelf and updates selection/title | Passed |
| 16 | Shelf scrolling/arrows reveal products; images, names, prices and controls remain legible/unclipped | Passed |
| 17 | Product details open/close normally and match selected product/pack | Passed |
| 18 | Same-product pack sizes stay grouped; selecting a pack updates price/availability correctly | Passed |
| 19 | Different packs can be added with independent quantities and correct Bucket totals | Passed |
| 20 | Out-of-stock packs cannot be added; other available packs remain selectable | Passed |
| 21 | Typing search shows suggestions without replacing panel before selection/submission | Passed |
| 22 | Submitted/selected search returns matching products; clearing/back restores usable browsing | Passed |
| 23 | Wishlist add/remove and saved-product opening work and persist on refresh | Passed |
| 24 | Bucket review shows correct packs/quantities/subtotal; Take to Cart and back preserve contents | Passed |

Use currently supported product families (for example the approved Milk pack
groups) for pack checks. Broader SKU classification/content completion remains
deferred and is not certified by this batch. Do not place an order in this batch.

## Batch 4: Food shopping and service separation

Owner reported "All passed" for checks 25–34 on 10 October 2026.

| ID | Check | Status |
|---|---|---|
| 25 | Switching to Food shows Food controls/content without leftover Grocery UI | Passed |
| 26 | Food categories show appropriate restaurants and switching/clearing restores usable listing | Passed |
| 27 | Open accepting restaurant, browse menu, open/close dish details and return to listing | Passed |
| 28 | Food search typing shows suggestions without replacing main panel | Passed |
| 29 | Restaurant/dish search works on explicit submission; clear/back restores browsing | Passed |
| 30 | Offered dish choices enforce required selections/limits and update price/cart identity | Passed |
| 31 | Add/increase/decrease/remove Food items; quantity and item subtotal remain correct | Passed |
| 32 | Unavailable dishes cannot be added while available dishes can | Passed |
| 33 | Food cart and Grocery Bucket remain separate through service switches and refresh | Passed |
| 34 | Food cart review/checkout navigation/back preserves items; empty cart recovers normally | Passed |

Do not submit or pay for an order in this batch. If required menu options or an
unavailable dish cannot be found, record the scenario as Not tested rather than
assuming a pass. Category availability depends on the actual regional menu.

## Batch 5: checkout review, fees and address

Owner reported "All passed" for checks 35–44 on 10 October 2026.

| ID | Check | Status |
|---|---|---|
| 35 | Grocery billing shows item subtotal, delivery, platform fee and total with numeric values | Passed |
| 36 | Food billing shows item subtotal, delivery, platform fee and total with numeric values | Passed |
| 37 | Both services calculate platform fee as rounded 2% of items plus delivery; UI label omits percentage | Passed |
| 38 | Tax wording is Tax is included, without duplicate added tax or unwanted fee explanation | Passed |
| 39 | Both displayed totals equal items plus delivery plus platform fee, without missing/duplicate charges | Passed |
| 40 | Cart quantity edits refresh item amount, platform fee and total without stale quote | Passed |
| 41 | Selecting another serviceable saved address refreshes eligibility and billing for that location | Passed |
| 42 | Review shows correct selected delivery address, recipient/contact and doorstep details | Passed |
| 43 | Missing/invalid delivery address blocks progression with actionable explanation | Passed |
| 44 | Back/refresh preserves cart and restores valid billing without unintended order submission | Passed |

Do not reserve, confirm, submit or pay for an order in this batch. If the current
region cannot produce a quote, record numeric checks as Not tested. Address
validation may be unavailable to exercise without deleting data; do not delete
saved addresses solely to test it. Historical orders retain historical charges.
Food and Grocery share the tariff, not necessarily identical fees for different
pickup origins. Exact distance boundaries remain a separate backend gate.

## Batch 6: real Grocery order lifecycle

Owner reported "All passed" for checks 45–54 on 10 October 2026. No order
reference or independent production trace was supplied; this is owner acceptance.

This batch is an owner-operated real purchase, not authorization for the agent
to place/pay for orders, message staff, or mutate merchant/rider availability.
Use one genuine low-value purchase the owner intends to receive and pay for;
coordinate an eligible stocked merchant and delivery partner. If unavailable,
leave checks Not tested. Never falsely mark an order paid or delivered.

| ID | Check | Status |
|---|---|---|
| 45 | Normal Grocery checkout creates a fresh order/reservation with correct items and identity, not a recovered historical order | Passed |
| 46 | Eligible merchant receives that order/offer with correct items, packs and quantities | Passed |
| 47 | Merchant accepts/confirms through normal flow; Customer reflects updated availability/status | Passed |
| 48 | Normal customer confirmation/merchant preparation leads to correct delivery-partner assignment and pickup details | Passed |
| 49 | Customer sees assigned partner contact; Call opens dialer for that partner | Passed |
| 50 | Genuine pickup/delivery progress updates Customer status and tracking correctly | Passed |
| 51 | Server-final bill has correct item, delivery, platform-fee and total amounts | Passed |
| 52 | Actual doorstep UPI/cash collection is recorded once using chosen supported method for correct amount | Passed |
| 53 | After actual delivery/completion, history/details update and active strip clears; other service cart remains intact | Passed |
| 54 | Refresh relevant Customer/Merchant/Delivery/Admin views; same order has consistent state without duplicate order/payment | Passed |

Stop on a failure and record its check number, non-sensitive order reference,
and statuses seen. Payment or recovery flows must not be repeatedly submitted
just to test retry behaviour; controlled failure/recovery cases are later gates.

## Batch 7: real Food order lifecycle

Owner reported "All passed" for checks 55–64 on 10 October 2026. No order
reference or independent production trace was supplied; this is owner acceptance.

Owner-operated genuine purchase only. Proceed only with Food the owner wants to
receive and pay for, with an accepting restaurant and available delivery partner.
No agent authority to transact is implied. Otherwise leave Not tested.

| ID | Check | Status |
|---|---|---|
| 55 | Fresh Food checkout creates correct restaurant, dish/options, quantity and address order | Passed |
| 56 | Customer confirmation succeeds once with order reference and understandable next status | Passed |
| 57 | Correct restaurant receives order with matching dishes/options/quantities | Passed |
| 58 | Restaurant accepts/prepares/readies through normal flow; Customer sees updates | Passed |
| 59 | Delivery partner receives correct assignment, restaurant pickup and destination | Passed |
| 60 | Customer sees correct assigned-partner contact and working call action | Passed |
| 61 | Final bill and genuine supported payment/collection match; record exists once | Passed |
| 62 | Actual pickup and delivery update Customer tracking/status correctly | Passed |
| 63 | Actual completion moves order to history and clears active status without altering Grocery Bucket | Passed |
| 64 | Refresh relevant four app views; order, payment and status remain consistent without duplicates | Passed |

Stop at the first failure. Do not falsely mark paid/delivered or repeatedly submit
to provoke duplicate orders/payments. Non-sensitive Grocery/Food order references
can be recorded to tie later read-only verification to the accepted journeys.

## Batch 8: Orders, receipts, cancellation and recovery

Owner reported "All passed" for checks 65–74 on 10 October 2026.

Use existing order history wherever possible; no extra purchase is required.
Do not cancel genuine fulfilment or lodge a false support/refund complaint solely
to test controls. Cancellation/recovery scenarios unavailable in real use remain
Not tested and require a later controlled verification path.

| ID | Check | Status |
|---|---|---|
| 65 | Active/Past tabs classify and count Grocery/Food orders correctly, without duplicates | Passed |
| 66 | Details/back navigation shows correct order identity, items/options, bill and status | Passed |
| 67 | Existing receipt/bill view or download matches correct order and amounts | Passed |
| 68 | Order again prepares review using current availability/pricing, with no automatic submission | Passed |
| 69 | Help/support entry opens for correct order and can be dismissed without false report | Passed |
| 70 | Genuinely unwanted cancellable unpaid reservation cancels normally and updates relevant apps | Passed |
| 71 | Cancelled order has no stale Finding your items/active strip or enabled confirmation | Passed |
| 72 | Legitimate unfinished checkout refresh/recovery restores same order, without duplicate submission | Passed |
| 73 | Finished-order recovery is recognized as historical and cannot resubmit/reconfirm it as new | Passed |
| 74 | Refresh after cancellation/completion preserves terminal state and does not revive active-order strip | Passed |

Never repeatedly confirm/pay to provoke duplicate handling. Payment retries,
merchant rejection/timeout, refund/return execution and immutable recipient/address
snapshots remain separate checks, not certified by history display alone.

## Batch 9: Profile and Settings

Owner reported "All passed" for checks 75–84 on 10 October 2026.

| ID | Check | Status |
|---|---|---|
| 75 | Repeated Profile/Settings/Home navigation, editor open/cancel and scrolling remain stable with one correct heading | Passed |
| 76 | Save valid own profile details; displayed profile/greeting update and persist after refresh | Passed |
| 77 | Invalid/blank required profile input shows validation; cancelling preserves saved details | Passed |
| 78 | Saved-address add/edit/select/default controls work and persist; past orders retain submitted address | Passed |
| 79 | Merchant and Delivery Settings entries open correct workspace/application state and allow return | Passed |
| 80 | Notification preferences show correct state and save chosen settings without permission/reload loop | Passed |
| 81 | Devices/sessions and linked identities show own data and dismiss correctly | Passed |
| 82 | Download your data produces readable own-account export or actionable error, not endless loading | Passed |
| 83 | Delete Customer opens clear Customer-only confirmation; cancelling causes no deletion/state loss | Passed |
| 84 | Normal sign-out and own sign-in work; session remains stable and saved cart/orders return | Passed |

Owner enters credentials/verification codes privately. Do not unlink identities,
revoke sessions, confirm deletion, or alter working partner accounts to test
these screens. Use only accurate own profile/address details; deleting addresses
is not required. Notification permission is optional; retain owner preferences.
Exports are private and should not be uploaded into chat.

## Batch 10: Merchant Grocery catalogue and operations

Grocery canonical identity/price remain centrally controlled; stock/selection
are merchant-branch controls. This is not wider SKU content/classification work.
Only make genuine intended inventory/operational changes; do not falsify stock,
pause a working store, or disturb live fulfilment to manufacture test scenarios.

| ID | Check | Status |
|---|---|---|
| 85 | Merchant sign-in/navigation/refresh remain stable and show correct own branch | Not tested |
| 86 | Own-branch switching scopes inventory/orders correctly and persists selection | Not tested |
| 87 | Product library and In my store distinguish canonical library from branch selection | Not tested |
| 88 | Merchant catalogue categories, search and back navigation open correct products | Not tested |
| 89 | Existing Grocery product/pack/image/customer-price identity matches Customer and canonical Admin data | Not tested |
| 90 | Genuine stock/selection update saves to correct branch and persists after refresh | Not tested |
| 91 | Zero stock blocks new Customer additions if no other eligible nearby merchant has stock | Not tested |
| 92 | Genuine positive stock restores Customer addability once local merchant eligibility holds | Not tested |
| 93 | Intended pause/close respects new-order eligibility without cancelling existing confirmed orders | Not tested |
| 94 | Intended reopen/resume restores new-order eligibility and persists, not merely optimistic UI | Not tested |

Single-branch owners cannot test branch switching without a second authorized
branch; retain Not tested. Operational changes affect live customers; otherwise
use a later controlled environment rather than counting unavailable cases passed.

## Remaining batches to detail and execute

- Grocery Product Type filters where approved metadata exists; wider SKU work remains deferred.
- Real city-trending discovery and approved Food imagery/content scope.
- Server-final bill, immutable recipient/address snapshot, payment/recovery and retries.
- Merchant receipt, accept/reject, inventory and order fulfilment.
- Delivery assignment, tracking, contact, collection and completion.
- Admin operations, permissions and cross-app consistency.
- Orders, cancellation, reordering, support, receipts and payment records.
- Payments workspace, legal/support links, auth renewal and destructive account-operation verification in a safe environment.
- Phone/tablet/desktop navigation, keyboard, accessibility, offline and performance.
- Final regression and approved release scope; no critical failures or untested
  required journeys before declaring the web product finished.
