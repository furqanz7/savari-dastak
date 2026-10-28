# Merchant additions to the shared Dastak Privacy Policy

Prepared 21 October 2026 for Merchant Build 68. **Owner approved the wording,
implementation and subsequent publication on 28 October. The policy is now live
on Customer and Merchant, effective 28 October 2026.** Build 69 carries the new
Merchant manifest. Existing Customer and Delivery
payment/weather sections and Terms/Support content remain intact.

Distribution and live verification:
[release record](verification/dastak-merchant-privacy-implementation-2026-10-28/release-record.md).
The instructions below preserve the reviewed publication plan; App Store privacy
answers remain unpublished and no App Review submission is included.

Audit and proposed Apple answers:
[Merchant privacy review pack](dastak-merchant-privacy-review-pack-2026-10-21.md).

## Publication instructions (not public copy)

Target: `Web/MarketplaceWeb/src/publicInformation.ts`, privacy page only, served
at the existing `/privacy` route. Build 68 points to
`https://dastak-customer.vercel.app/privacy`; the Merchant support site's Privacy
link points to its own `/privacy` route from the same shared web content.
Verify both deployments after any separately approved publication.

1. Replace the summary with the text below.
2. Extend Authentication and contact details with the replacement first paragraph.
   Preserve the existing no-automatic-account-merge paragraph.
3. Insert the Merchant sections below before Optional weather scenery on iOS.
4. Extend Who receives information with the Merchant provider paragraph. Preserve
   existing Customer/Delivery provider and payment distinctions.
5. Extend Your choices and rights and Retention and security as below.
6. Set the privacy page's update date to the actual publication date. Do not alter
   the shared date for Terms/Support or imply a new effective date prematurely.
7. Public copy uses no claim of completed App Review, enabled live payouts,
   guaranteed support staffing, identity recovery by a message or fixed retention.

---

## Replacement summary

How Dastak collects, uses and protects information when you shop, operate a
Merchant store or fulfil deliveries.

## Authentication and contact details — replacement first paragraph

Customers and Merchants sign in with the Apple or Google options offered by the
app. We receive the identity information supplied through that sign-in, such as
an account identifier, name and email address. Your profile phone number is
contact information, not proof of account ownership. Merchant workspace access
also requires an approved application and the appropriate business permissions.
Signing in or editing a profile does not approve a Merchant application.

## Merchant applications and store verification — new section

When you apply to become a Merchant, we collect the legal and customer-facing
business names, business address, selected pickup location and the government
identity or business-registration document you submit. The document can include
your photograph, address and identity or registration information. Submit only
the document needed for the application; do not upload unrelated personal
records. We use these details to review the application, verify store access,
prevent misuse and coordinate fulfilment. Verification documents are private
evidence, not public storefront images.

You can search for a pickup address or choose a map pin. If you explicitly use
your current location, the iOS app requests location access while you are using
it. The map, place search and address lookup use Apple's map/location services.
The pickup address and the precise coordinates you choose are sent to Dastak and
associated with the application/store. Merchant pickup selection is not a
continuous background location-tracking feature. You can change location
permission in device Settings and choose an address or pin without a GPS fix.

## Operating a Merchant store — new section

Dastak records catalogue selections, stock and availability, restaurant menu
items and add-ons where applicable, descriptions, prices, operating settings,
order responses, preparation estimates, package counts, ready photos, handoffs,
problem reports and related operational history. These records are associated
with the authorized account and business so Dastak can manage fulfilment,
resolve disputes and maintain an audit trail. Restaurant/Café identity, menus
and published images may be visible to customers. Private verification documents
and fulfilment evidence are not treated as public storefront media.

Grocery catalogue search sends the search text to Dastak to find matching
products. Restaurant menu filtering may be performed on your device. Technical
request and error records may be retained as described under Retention and
security; this policy does not promise that all search requests are unlogged.

## Merchant earnings and payout information — new section

Merchant financial records include Royalty ledger entries, adjustments,
settlements, available balances and withdrawal requests. When payout-destination
setup is available for your business and you choose to use it, the app collects
the holder name and bank-account/IFSC or UPI details you enter. Dastak may send
the required destination information to the configured payout service, including
RazorpayX where used, and retain provider references, masked destination details,
verification fingerprints and transaction/status records needed to operate,
secure and audit the service.

Available payout actions depend on current business permissions and service
configuration. A displayed balance does not guarantee that withdrawals are
enabled or that money has reached a bank. Destination setup and withdrawal
requests are separate actions. Never send bank passwords or UPI PINs to Dastak
support. The current Customer iOS doorstep-payment flow is separate from
Merchant earnings and payout processing.

## Merchant data kept on your device — new section

The app may keep unsaved menu drafts, account-scoped preferences and the original
details of an uncertain action on your device so you can review or recover it
without silently changing the request. Submitted changes and their operational
records are handled by the server; an unresolved local action is not proof that
the server action failed.

Merchant payout-destination recovery details use device-only Keychain storage,
not menu draft files, UserDefaults or iCloud synchronization. The app retains
those original details for recovery until its confirmed cleanup flow completes.
Refreshing Earnings does not itself request a withdrawal. Local-only information
is not automatically a remote collection; data you submit for a real operation
is considered separately.

## Exploring the Merchant demo — new section

Explore the demo opens a clearly labelled sample workspace without signing in.
Its orders, store changes, evidence and financial actions are simulated locally;
they do not create real orders, upload your documents, dispatch a rider or
transfer money. Reset or Exit discards the sample session, and the demo's changes
are not added to a real Merchant account. Merchant support is disabled inside
the sample; exit the demo to use the real support page. The demo does not test
remote push delivery or actual provider operations.

## Merchant support conversations — new section

You can contact Merchant support through the form at
https://dastak-merchant.vercel.app/merchant-support without signing in or providing
an email address. We store the category, summary and message you submit, request
and message references, conversation status, replies and their timestamps.
Authorized Dastak Admin staff can review and respond, and staff replies are
associated with the replying Admin account. If your message includes an order
reference or identifying details, that information is part of the conversation.
No sign-in requirement does not mean a message is anonymous.

A private recovery code is generated in your browser. The code is sent securely
to the support service when you create, open or reply to the request. The service
hashes its secret before sending it to ticket storage, which stores the hash
rather than the original secret. This statement concerns ticket storage, not a
promise that no hosting/security request record can contain submitted data.
Anyone with the complete code can read and reply to that conversation. Keep it
private; do not send it to support. Save it before leaving, because a lost code
cannot be recovered through the form.

We do not email replies or guarantee a response time. Return to the page with
your saved code to check replies. Do not submit passwords, UPI PINs, bank-account
numbers, identity documents or active handoff codes. A support message is not
proof of account ownership and cannot authorize account approval, an account
change, an order change or a payment. This is not an emergency service.

## Who receives information — additional paragraph

For Merchant operations, Dastak uses Supabase for authentication, application and
operational records, evidence storage and service/security logging; Apple or
Google for the sign-in option you choose; Apple Push Notification service for
native notifications; Apple's map/location services for place lookup; and Vercel
for public web pages, including the Merchant support interface. Where an enabled
payout flow uses a configured gateway or RazorpayX, the information needed to
set up the destination or process and reconcile that payout is sent through
that service. Access to private Merchant records is limited by the authorized
workspace and operational/service-provider access required for those purposes.
These uses are not Dastak's third-party behavioural advertising or sale of
personal data. Providers also process data under their applicable terms and
security/legal obligations.

## Your choices and rights — additional paragraph

Merchant Account provides available profile, identity-linking, session and
privacy controls. You can request account deletion through its confirmed
signed-in flow. Required transactional, financial, custody and audit records
may remain, with personal identifiers minimized or anonymized where permitted.
The public support conversation is not automatically connected to your login;
signing out or deleting an account does not by itself identify and erase every
support conversation. You may raise a privacy concern through Merchant support,
but unverified text does not establish account ownership or authorize a change.

## Retention and security — additional paragraphs

Merchant applications, evidence, store operations and financial records are kept
as needed to operate the service, secure access, review applications, maintain
required history and handle accounting, legal obligations or disputes. Technical
hosting/authentication records may include request times, IP-derived network or
approximate geographic information, user agent, account/session identifiers,
response status, processing times and runtime/error details. Provider retention
depends on service configuration. Dastak does not promise a fixed deletion date
for those records in this policy.

The Merchant support service currently has storage-capacity limits but no
automatic conversation-expiry schedule. Closing or resolving a conversation
does not mean its stored messages have been deleted. Privacy requests and
retention decisions must take account of security, recordkeeping and applicable
obligations; this policy does not promise immediate or automatic erasure.

---

## Approval checklist (not public copy)

- Confirm necessary verification-document scope and the accuracy of the described
  financial availability/provider behavior. Do not interpret the draft as
  authority to collect additional document types or enable payouts.
- Confirm hosted log configuration, retained bodies/search text, geography,
  durations and any external drains. Revise the disclosure if actual practices
  differ; do not publish a claim based only on default provider documentation.
- Confirm that the owner will monitor the public support inbox and agrees with
  the accurate no-email/no-SLA/no-automatic-expiry wording.
- Approve this copy, then separately authorize implementation, tests,
  commit/push/deployment and public-URL verification. None occurred in this pass.
- Separately approve Apple's final data answers and action-time Publish agreement.
  The policy and App Store label must describe the same final practices.
