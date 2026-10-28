# Sell on Dastak — Merchant privacy review pack

**Current distribution checkpoint, 28 October:** the owner explicitly confirmed
Apple's final accuracy/compliance/update agreement and authorized publication.
The 17-type App Store privacy declaration is now published. Build 69 remains
Prepare for Submission, with age rating 18+ and the owner-confirmed Content Rights
declaration saved. An authorized demo-access request was sent to Apple; acceptance
is pending. See the [release record](verification/dastak-merchant-privacy-implementation-2026-10-28/release-record.md).
Earlier draft/no-publication statements below describe their historical slices.

Prepared 21 October 2026 for the owner's review. **Draft answers, not a published
declaration, legal certification or claim of a completed live-provider audit.**
No App Store answers, production settings, app source or public copy changed.

**28 October approved distribution:** the owner subsequently authorized the
privacy-only source push, Merchant upload and policy deployments. Build 69 is
processed and Ready to Submit after the owner completed encryption compliance;
both public policy pages are live. See the
[release record](verification/dastak-merchant-privacy-implementation-2026-10-28/release-record.md).
The earlier no-change/no-distribution statements below are historical scope
boundaries. App Store privacy answers remain unpublished; no review submission.

**28 October implementation follow-up:** owner approved the policy/mappings and
local implementation against the current project baseline. A Merchant-specific
manifest and policy source changes are now local, with verification recorded in
[implementation evidence](verification/dastak-merchant-privacy-implementation-2026-10-28/README.md).
The initial pass's no-source-change statement above describes that historical
audit only. No upload, deployment, App Store privacy publication or submission
is authorized or claimed by this follow-up.

**23 October follow-up:** the separately authorized read-only hosting check is
recorded in [live hosting evidence](dastak-merchant-privacy-hosting-check-2026-10-23.md).
It confirms retained coarse geography and function timings. Search History is
now proposed **unselected for the inspected current Merchant path**, subject to
the explicit sampling/configuration limits in that report. This is not an
approval to publish the policy or App Store declaration.

## Outcome and approval boundary

The source/archive pass is complete for the flows below. The proposed label is
Merchant-specific; do not copy Customer's label or the shared app manifest.
The baseline below contains **17 proposed types**. The 23 October hosting check
narrows the original Search History question as described below. The count is a result of the mappings, not a goal
to match the existing 17-type manifest. Do not publish while the release gates at
the end remain unresolved. An accurate label is preferable to over-declaring a
type merely because an API is present in the binary.

Companion: [proposed public policy changes](dastak-merchant-privacy-policy-proposed-2026-10-21.md).
The earlier working audit and 20 October copy remain historical drafts; their
statements about what had not yet been activated are not a current deployment
inventory. This pass does not independently re-verify the previous deployment.

## What was directly checked

- Worktree: `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`;
  branch `codex/dastak-v1-launch`; HEAD
  `21aaaf1f86b9383e7c0f3aa075857ef553cdfe8b`. Known dirty native/artwork changes
  were preserved; no staging, commit or push.
- Signed Merchant archive: `com.dastak.merchant`, 1.0.0 (68), at
  `/Users/Furqan/Library/Developer/Xcode/Archives/2026-10-21/DastakMerchant Build 68.xcarchive`.
- Packaged privacy/support URLs, root and two dependency manifests, linked
  libraries, dependency pins and target dependencies were inspected.
- Thirteen key native files were byte-compared with the isolated Build 68 source
  copy at `/private/tmp/dastak-merchant-support68.rZJA3p`; all matched: Merchant
  entry point, infrastructure Package.swift, authentication shell/client,
  account sessions, Royalty client, Merchant application/model, payout controls/
  storage, menu draft storage, support section and restaurant menu view.
- The authenticated backend handlers and migrations were read, not executed.
  No real identity document, bank details, support message, token or log entry
  was fetched. No live financial/provider operation was performed.
- Current Apple definitions and Supabase logging documentation were consulted
  on 21 October. Live logging configuration, retention, drains, third-party
  secondary uses and environment-gated provider enablement were **not** verified.

## Evidence map

Paths below are relative to this checkout; the native comparison above ties the
main entry points to the archived build. Backend files establish source behavior,
not independently verified hosted configuration.

| Flow | Off-device information and persistence | Source evidence |
| --- | --- | --- |
| Apple/Google login and identity linking | Provider identity/token exchange, account ID, supplied email/name; Supabase Auth identity/session records. Apple sign-in requests full name/email. No Google native sign-in SDK is required by this path; Google uses the Supabase OAuth web-auth flow. | `Packages/MarketplaceInfrastructure/Sources/MarketplaceInfrastructure/AuthenticationClient.swift`, `AuthenticationShell.swift`, `AccountProfileClient.swift` |
| Profile and security sessions | Display name, phone; device name/model fallback, platform `ios`, application name, `Dastak iOS` user agent, session/account IDs, created/last-seen times. Sessions are retained in a table; its 90-day list filter is not an expiry/deletion policy. | `AccountSessionClient.swift`; `AuthenticationShell.swift` currentDevice; `Backends/Dastak/supabase/functions/account-sessions/index.ts`; migration `20260815235259_add_address_book_and_account_sessions.sql` |
| Merchant application | Legal/customer-facing business names, address, full-resolution selected store coordinates and one requested government identity or business-registration document. PDF/JPG/PNG bytes go to private evidence storage; application stores object reference and account association. | `Packages/DastakUI/Sources/DastakUI/DastakMerchantApplicationView.swift`; `MerchantApplicationClient.swift`; migration `20261009122717_india_wide_local_onboarding.sql` |
| Location picker | Explicit one-shot iOS When In Use request, map/search and reverse geocoding through Apple frameworks; selected pin submitted to Dastak. Device manager accuracy preference does not coarsen a manually selected map pin. No Merchant continuous/background location stream was identified. | `DastakLocation.swift`, `DastakLocationPicker.swift`, Merchant application submit |
| Orders and store | Decisions, prep estimates, package counts, evidence, issues, stock selections, operating state, menu names/descriptions/prices/images and related versions/audit history. Public food media is distinct from private verification/Ready evidence. | `DastakMerchantModel.swift`; `DastakMerchantRestaurantMenuView.swift`; `DastakV1MerchantClient.swift`; catalogue/order endpoints |
| Grocery catalogue search | Query goes to authenticated `merchantInventoryPage` and a stable SQL read. No search-history insert was found in that path. Restaurant menu filtering is local. Remote transmission alone is not proof of collection under Apple's retained-data definition; invocation bodies and database error/statement logging still need verification. | `DastakMerchantCatalogueView.swift`; `DastakMerchantCataloguePresentation.swift`; `dastak-v1-catalogue/handler.ts` and `index.ts`; migration `20261018131824_merchant_catalogue_and_location_pages.sql` |
| APNs | App-specific token, account association, platform, application ID, APNs environment and last-seen time. This is not evidence of IDFA. Notification routing uses order/fulfilment references. | `Apps/Dastak/Sources/DastakMerchant/DastakMerchantApp.swift`; `DastakMerchantNotifications.swift`; `register-device-token/handler.ts`; migration `20260907172722_merchant_app_notifications.sql` |
| Financial operations | Holder name, bank number/confirmation and IFSC or UPI identifier are explicitly entered in the native form and submitted to `earnings` when enabled. Server code can pass destination data to RazorpayX, then store provider references, masked presentation and a fingerprint. Ledger, adjustment, settlement and withdrawal history is retained. | `DastakMerchantPayoutControls.swift`, `DastakMerchantRoyaltyClient.swift`; `earnings/handler.ts`, `razorpayx.ts`, `provider-clients.ts`; `_shared/razorpayx.ts` |
| Financial availability | Direct destination registration is TEST-only in inspected server code; live direct egress fails closed. Withdrawals require configured payout gateway. No real provider mode, gateway or ability to pay was inferred from source. Disclose reachable conditional collection; do not claim a live payout is enabled. | `earnings/provider-clients.ts` |
| Public support conversation | Category, summary, body/replies, IDs, status, versions, timestamps, digests and token hash; Admin reply actor ID. Public calls do not require an account ID. Text may identify a person or business; this is not guaranteed anonymous data. Browser sends the recovery secret over HTTPS; Edge hashes it before the DB RPC, which stores only the hash. Hosting access to request bodies must be considered separately. | `Web/MarketplaceWeb/src/merchantSupport.ts`, `MerchantSupportPage.tsx`; `merchant-support/handler.ts`; migrations `20261020193411_merchant_support_inbox.sql`, `20261020203749_merchant_support_request_hardening.sql` |
| Support limits and retention | Per-worker in-memory bulkhead plus shared SQL capacity limits. No app-level IP tracking is implemented by the limiter; hosting may still log IP. No support TTL or automatic purge appears in these migrations. A 1,000-ticket cap is not retention/deletion. Owner previously chose retain tickets; no deletion was performed here. | `merchant-support/limits.ts`; support migrations |
| Platform diagnostics | Supabase documents retained gateway/auth/function/storage logs, including IP/user-agent and response/timing/error metadata. Logs can associate with account/session or request records; no pre-collection anonymization was established. Source native FunctionClient debug prints are DEBUG-only, not a Release crash/performance SDK. | `FunctionClient.swift`; Supabase sources listed below |

## Archive and SDK findings

- Infrastructure directly depends on Supabase Swift **2.37.0** and PhoneNumberKit
  **5.0.7**. Pins also contain Swift Crypto **4.5.1**, ASN1 **1.7.1**, HTTPTypes
  **1.6.0**, Clocks **1.1.0**, ConcurrencyExtras **1.4.1**, and
  XCTestDynamicOverlay **1.11.0**. These pins describe resolution, not proof every
  product is linked. Exact revisions remain in the Build 68 source copy.
- A stale Razorpay custom-UI **2.2.0** pin exists in that copy's Package.resolved.
  The inspected Merchant dependency graph has no Razorpay SDK dependency, and
  the app has no embedded Razorpay framework. Do not infer a native payment SDK
  from the stale pin, or infer absence of server RazorpayX processing from it.
- The archive has no embedded third-party dynamic frameworks. Its linked Apple
  frameworks include MapKit, CoreLocation, Contacts, WeatherKit, PhotosUI and
  others because code is shared. Linkage alone is not collection: no Merchant
  address-book read, audio recording, health API, advertising identifier or
  tracking request was identified in the reachable Merchant entry points.
- PhoneNumberKit and Swift Crypto packaged manifests declare no collected data
  and no tracking. PhoneNumberKit uses bundled numbering metadata; no telemetry
  or networking implementation was found in its inspected Swift source.
- Supabase client global logger defaults to nil; no custom remote telemetry
  logger was identified in the Merchant setup. It still sends normal Auth,
  REST/function, storage and operational requests to Dastak's Supabase project.
  Server/platform logging is a separate collection surface.
- No Firebase, Sentry, Crashlytics, Mixpanel, Amplitude, PostHog or advertising SDK
  integration was found in the Merchant entry point, target graph or inspected
  setup. This is an inspected-graph result, not certification of every byte or
  every provider's future practice.
- Merchant uses the ordinary Merchant authentication shell and branded launch
  media, not Customer's optional WeatherKit scenery. Do not add Coarse Location
  merely because WeatherKit is linked. The separate logging consideration below
  is why it remains a proposed category.

## Proposed App Store Connect answers — do not publish yet

Top level: **Yes, we collect data from this app.** This includes authenticated
Merchant operation and support, not only the local demo.

For every proposed type below, the draft common answers are:

- Purpose: **App Functionality** only.
- Linked to the user's identity: **Yes**. Operational records are account/business
  associated; support/log records are not reliably de-identified. Do not select
  unlinked simply because no sign-in is required for the public support form.
- Used for tracking: **No**, based on the implemented Dastak purposes and inspected
  integrations; owner must confirm no uninspected provider/marketing configuration.
- No Analytics, Product Personalization, Advertising or Other Purposes were
  identified for Merchant. Account-specific permissions/store data do not alone
  establish a recommendation/personalization feature.

| Group | Proposed exact data type | Basis / decision strength |
| --- | --- | --- |
| Contact Info | Name | Direct: profile, application, payout-holder name |
| Contact Info | Email Address | Direct: provider-supplied sign-in identity |
| Contact Info | Phone Number | Direct: account profile/application contact |
| Contact Info | Physical Address | Direct: store address, including home-based businesses |
| Financial Info | Payment Info | Direct conditional input: bank-account/IFSC or UPI destination inside app; external-only payment exemption does not apply |
| Financial Info | Other Financial Info | Direct: Merchant earnings, balances, adjustments, settlements and withdrawal records |
| Location | Precise Location | Direct: chosen pickup latitude/longitude retained without coarsening |
| Location | Coarse Location | Confirmed 23 October: retained gateway/function log metadata has populated approximate city/country fields. No actual location values were fetched. Not justified by Merchant weather. |
| User Content | Photos or Videos | Direct: selected image evidence and published food/store media; no general video feature claimed |
| User Content | Customer Support | Direct: new support request/conversation; optional-disclosure conditions are not assumed |
| User Content | Other User Content | Direct: menu descriptions, operational explanations, PDFs/business-verification documents and other submitted content |
| Identifiers | User ID | Direct: authenticated account/provider identity and business associations |
| Identifiers | Device ID | Push-token/device/session association; no claim of IDFA |
| Usage Data | Product Interaction | Direct: recorded sign-ins, order responses, stock/menu actions, fulfilment and operational interactions |
| Diagnostics | Performance Data | Confirmed 23 October: 538 sampled function invocation events had populated timing fields. This is not a claim of app launch/hang/energy instrumentation. |
| Diagnostics | Other Diagnostic Data | Hosting-doc-based recommendation: IP, user agent, technical request/runtime/error and security/session metadata, potentially linked |
| Other Data | Other Data Types | Proposed mapping for specifically requested government identity/business-registration identifiers in uploaded verification documents. This is an inference from Apple's catch-all definition, not explicit Apple guidance classifying Dastak's documents. Owner must confirm document scope; do not select Apple's Sensitive Info solely because a document is confidential. |

### Search History — updated draft decision, 23 October

**Proposed answer: do not select Search History for the current inspected
Merchant flow.** The downloaded deployed catalogue handler and RPC wrapper match
the source, have no query logger, and call the exact live read-only SQL bodies
whose hashes match the migration. The one-hour aggregate found no populated
body/query structured attributes in gateway/function events. Live Postgres
settings omit bound parameter values from error logs and do not log ordinary
SELECT statements. The source has no search-history insert.

This is a bounded, source-and-configuration-supported conclusion, not proof
that no provider anywhere can retain any query. No raw log messages, request
bodies, query text or real search values were retrieved; no synthetic search
was submitted. Revisit the answer if request/statement logging, app collection,
provider configuration or deployed code changes. Database error statement text
and normalized query statistics are distinct from a retained history of readable
Merchant search terms. See the dated evidence for exact settings and limits.

The initial 21 October reasoning, retained for context:

Do **not** silently mark either collected or uncollected as confirmed. The native
Grocery query is sent off-device, but the SQL read does not persist search terms.
Supabase's current function logging guide describes invocation request/response
data including bodies; its field reference is more granular and fields may not be
populated in every event. Inspect the project's actual body/statement/error
retention or obtain a provider configuration confirmation without exposing real
searches. If readable queries are retained beyond servicing the request, add
**Search History → App Functionality → Linked Yes → Tracking No**, making 18
types if all 17 baseline proposals apply. If queries are only transient and no
readable query logging persists, leave Search History unselected. Hash-only
idempotency metadata is not automatically a retained readable search history.

### Types not supported by this pass

- Purchase History / Product Personalization: no Merchant-user purchase or
  personalized shopping recommendation flow identified. Customer orders shown
  to a Merchant are fulfilment records, not proof of the Merchant user's purchases.
- Crash Data: no developer-implemented retained app crash-report pipeline found.
  Technical server errors fit Other Diagnostic Data. Do not treat Apple's own
  independent App Analytics as Dastak's SDK collection without checking what
  Dastak actually receives/uses.
- Contacts, Audio Data, Health, Fitness, Browsing History, Advertising Data,
  gameplay, environment/body scanning: no corresponding reachable collection
  found. Map search via Apple alone does not create a Dastak browsing history.
- Sensitive Info: no dedicated request for the sensitive characteristics in
  Apple's definition or biometric recognition found. A photograph on a document
  is not automatically a biometric template. If the accepted document policy
  specifically collects one of those characteristics, revisit this answer.
- Other Usage Data: no distinct category beyond recorded Product Interaction
  and technical diagnostics was established; do not add merely for the count.

## Shared manifest reconciliation before release

The root Build 68 PrivacyInfo.xcprivacy declares 17 types, all linked/non-tracking;
Purchase History additionally has Product Personalization. It does **not** declare
Other Data Types or Search History. It is shared with other Dastak apps.

For Merchant, Purchase History/Product Personalization lacks the evidence above,
while the document-ID mapping and hosting/search questions need resolution.
An App Store label is not generated by blindly copying this manifest. Before
submission, review a Merchant-specific manifest against the approved final
practices. If changing the packaged manifest, a new archive/upload is required;
no app source, manifest or build was changed by this preparation task. It is not
claimed that merely editing ASC resolves a binary manifest discrepancy.

## Public policy change plan

Keep the shared `/privacy` URL already in Build 68; no new native URL is required
if the existing page is updated. Preserve Customer/Delivery sections, especially
their payment/weather distinctions. Add Merchant identity/document, selected-pin,
operational, financial, local-recovery, demo and public-support coverage as in the
companion draft. Name service providers by function, with payout availability
qualified. Do not promise a particular retention period, automatic support
deletion, response SLA or identity recovery through the unverified support form.

## Remaining release gates and precise verification limits

1. Owner reviews document scope, policy wording and proposed category mappings.
   Neither this document nor the generic form upload prompt proves that every
   accepted document is necessary or lawful. Do not broaden accepted documents.
2. Read-only hosted configuration/field-presence check: log sources, readable
   request/search/body capture, IP-derived geography, durations, retention and any
   external log drains/analytics. Use metadata/aggregates or deliberate synthetic
   input, not raw real documents, support messages, tokens or financial requests.
   The initial pass had no live evidence; the dated 23 October follow-up now
   records the actual bounded check. Exact retention TTL, custom destinations
   outside the inspected Supabase surface, and provider secondary uses are not
   certified. The policy intentionally promises no fixed log-deletion period.
3. Confirm actual financial capabilities and processor configuration without a
   bank registration, payout, new order or payment. The draft includes conditional
   input already present in the app; never infer a working live payout.
4. Reconcile the final label and Merchant manifest; determine whether a new
   build is needed. Do not change Customer/Delivery manifests implicitly.
5. Obtain approval for public copy, implement/test it, and separately authorize
   push/deployment. Reopen the public URL to verify the deployed wording.
6. Enter the owner-approved ASC draft, verify each purpose/linkage/tracking answer,
   and obtain action-time confirmation before its final Publish agreement.
7. Age/content-rights and reviewer-access settings remain separate listing work.
   No review submission is authorized by approval of this preparation pack.

## Security boundary review

Inspected public support tables have RLS enabled and no direct anon/authenticated
table/RPC grants; verified Admin identity/current DB role controls Admin access.
The public capability is sent in a POST body, not a URL. Code uses a server-side
service key and a browser-safe public key for public callers. These are targeted
source checks, not an exhaustive security audit, live RLS test or assurance that
an existing JWT is invalidated merely by deleting its user.

## Primary references consulted

- [Apple privacy definitions, purposes, linkage, tracking and optional disclosure](https://developer.apple.com/app-store/app-privacy-details/)
- [Supabase log sources and fields](https://supabase.com/docs/guides/observability/log-field-reference)
- [Supabase function logging](https://supabase.com/docs/guides/functions/logging)
- [Supabase Auth audit logs](https://supabase.com/docs/guides/auth/audit-logs)
- [Supabase log retention depends on plan](https://supabase.com/docs/guides/observability/logs)

This source/archive work makes the proposed answers reviewable. It does not
certify every deployed collection practice or remove the unresolved gates above.
