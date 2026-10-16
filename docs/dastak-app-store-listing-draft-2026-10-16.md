# Dastak App Store listing draft

Status: partially saved to App Store Connect, not submitted. Customer + Delivery only; Merchant remains deferred. Release candidate: version 1.0.0, Build 58, with the owner-approved centred under-panel weather credit. Upload, processing and compliance clearance succeeded; a live Safari refresh confirmed Ready to Submit in the existing internal Testing group. The owner reported installing Build 58 and explicitly accepted the centred footer and its legal-text spacing. The existing App Store version is 1.0, English (U.K.). Its Add Build chooser offered Build 58 (1.0.0), which was selected and saved; keywords, support URL and marketing URL were also saved. Copyright, review contact and the privacy-policy URL are saved. The latest owner choice is free download in all 175 countries/regions, iPhone/iPad only, with automatic release on approval; saved zero prices and Mac/Vision Pro exclusions are verified below. Description/promotional text remain blank because Safari text-area input did not take; the copy below remains a draft. No version-number change was needed to select Build 58. Reviewer access, screenshots and other declarations remain unfinished.

## Public copy

### Latest checkpoint — 17 October

This checkpoint supersedes the earlier incomplete-form observations below; those are historical receipts.

- The owner pasted and saved the promotional text and description. Subtitle **Groceries, food & deliveries**, primary Shopping and secondary Food & Drink categories were subsequently observed in Safari.
- The owner completed age ratings (4+ in the main storefront summary) and content-rights setup. These are owner declarations, not an independent legal/content-license audit.
- App Privacy currently has 14 draft types, linked to identity and not used for tracking: name, email, phone, physical address, precise/coarse location, photos/videos, customer support, other user content, user/device IDs, purchase history, payment information and other financial information. Purchase history includes Product Personalization for city-popularity recommendations; the others currently list App Functionality.
- Product Interaction still needs to be added to the App Store Connect draft for account-linked saved/favourite item activity. The Build 59 manifest includes it. Hosted operational logging/diagnostic collection and retention still require reconciliation; do not treat a source inventory as proof of production log configuration.
- The owner chose **current Grocery/Food doorstep payment only; disable older retries and exclude Razorpay**. Build 59 is being prepared with that scope. Old merchant/parcel history remains readable; legacy online retries and new prepaid parcel creation are blocked. Backend payment/payout configuration is unchanged.
- No privacy Publish or Add for Review action has been taken. Required screenshots, reviewer Delivery access and the existing trader declaration remain separate submission gates. Build 58 remains the confirmed selected/available build until Build 59 upload and processing are verified.

Preserve the owner's current App Store Connect name, last observed as **Dastak دستک**. Inspect the live version and localization before replacing existing copy.

Subtitle (28 characters): **Groceries, food & deliveries**

Promotional text:

> Everyday essentials and local food, with your order's journey close at hand. Discover Dastak's immersive storefront, quick picks and native order tracking.

Description:

> Welcome to Dastak — your local stop for groceries, everyday essentials and food from nearby restaurants and cafés.
>
> Browse thoughtfully arranged categories, explore Quick picks, search for what you need and choose the right pack size. Save favourites and manage quantities from product cards or your basket.
>
> Keep delivery addresses organised, review your basket and see your order progress in the app. Supported iPhones can also show order updates in Live Activities and the Dynamic Island. Widgets, Shortcuts and Control Centre controls offer quick ways back to Dastak.
>
> For approved delivery partners, the same app provides a delivery workspace for assignments, pickup and handoff steps, directions, order details, recent work and earnings information.
>
> Sign in with Apple or Google. Grocery, restaurant and delivery availability depend on your service location. Notification and Live Activity features require the relevant device settings and permissions.

Keywords (under 100 characters):

`grocery,groceries,food,delivery,essentials,local,restaurants,cafe,basket,shopping`

Existing public destinations (verify live before saving):

- Marketing: https://dastak-customer.vercel.app
- Support: https://dastak-customer.vercel.app/support
- Privacy: https://dastak-customer.vercel.app/privacy
- Terms: https://dastak-customer.vercel.app/terms

Do not claim universal coverage, a guaranteed delivery time, guaranteed notification timing, unimplemented services or a public release date. Preserve the owner's selected release policy; do not enable automatic public release without confirming the intended release timing.

## Review notes draft and unresolved access

> Dastak combines Customer grocery/food ordering and an approved Delivery partner workspace. Merchant functionality is outside this submission's scope.
>
> Customer sign-in uses the visible Continue with Apple or Continue with Google options. Complete the displayed customer profile steps if prompted. Shopping availability depends on the selected delivery location.
>
> Location-based weather is optional and affects only the outside/sign-in scenery. Denying weather/location access does not prevent sign-in; time-based scenery is the fallback. Attribution links identify Apple Weather data sources when live weather is used.
>
> Delivery workspace access requires an approved Delivery partner account. New Customer sign-ins do not receive that access automatically.

**Do not submit these notes as a complete access solution.** Still required: an owner-approved, working way for Apple reviewers to access the approved Delivery role and exercise its core workflow while retaining the requested Apple/Google sign-in. Do not invent credentials, disclose the owner's credentials, grant broad access or weaken role approval. Also verify the serviceable review location and account-creation/profile prerequisites; do not publish the owner's private address as review data.

Apple's guidance asks for working access to account-based features and information for each account type: https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review

## Privacy cross-check

The current combined-app manifest (`Apps/Dastak/Supporting/PrivacyInfo.xcprivacy`) declares:

| Data | Linked to identity | Purpose | Tracking |
| --- | --- | --- | --- |
| Coarse location (also used by account-linked address flows) | Yes | App functionality | No |
| Name, email, phone, physical address | Yes | App functionality | No |
| Precise location | Yes | App functionality | No |
| Photos/videos, customer support, other user content | Yes | App functionality | No |
| User ID, device ID, payment info, other financial info, product interaction | Yes | App functionality | No |
| Purchase history | Yes | App functionality, product personalization | No |

This is a manifest cross-check, **not a completed App Store privacy audit or a substitute for App Store Connect answers**. Reconcile the live privacy form with the app, its services and third-party SDK behavior before publishing. In particular, review Delivery onboarding documents and earnings/payment-related information, diagnostics, retention and optional-collection conditions; do not infer that unlisted data is absent just because this manifest does not list it.

## Screenshots and remaining listing checks

The project supports iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`). Inspect the required device slots in the live App Store Connect Media Manager before preparing uploads. Use the current native UI, with no private addresses, phone numbers, order identifiers or account information. No screenshot uploads have been made for this draft.

Suggested truthful sequence:

1. Customer Grocery home / Quick picks.
2. Category browsing and product pack-size choices.
3. Food restaurant banner and menu navigation.
4. Basket and delivery-address selection using clearly non-private sample data.
5. Native order tracking, including a representative supported Live Activity state.
6. Approved Delivery workspace and full-order detail using isolated sample data.

Screenshots must reflect the Build 58 release-candidate experience, not a proposed redesign. Any sample data must remain representative and must not be presented as a real fulfilled order. Check both required iPhone and iPad display slots. Do not repurpose old pre-polish screenshots as current release assets.

Live checks still needed: existing version/localization, selected build, screenshots, app description and URLs, category, age-rating questionnaire, pricing/territories, content rights, App Privacy, review contact/access, release timing and submission validation. Any legal attestations or agreements require owner confirmation at action time. No App Review submission has occurred in this preparation step.

## Live setup checkpoint after Build 58 acceptance

- Saved and subsequently observed after navigation: keywords, support URL, marketing URL and selected Build 58 (1.0.0) in the existing version 1.0 draft. Save returned disabled after each save. No Add for Review action was taken.
- Promotional text and description remain empty. Native Safari text-area setters/clicks failed to focus them; an attempted paste landed in Marketing URL instead, was detected, and the URL was restored and verified before saving. No erroneous description-as-URL value was saved.
- The subtitle was entered on App Information but its persistence was not verified; do not count it complete. Category remained Primary/Secondary placeholders, and Set Up Content Rights Information and Set Up Age Ratings were still present. No answers or legal declarations were selected.
- App Information currently reports non-trader status. This is an observed existing declaration, not an audited conclusion or a declaration made by the agent; it must be assessed with the intended storefronts before submission.
- The owner was asked for the exact copyright-holder name, a manual-versus-automatic release decision, and to enter review contact details directly in Apple's form. Native interaction was paused when the contact form became active to avoid interfering with the owner's entry.
- Pricing/territories and App Privacy have not yet been inspected in this checkpoint. Do not treat them as completed.

## Owner decisions and subsequent live inspection

- Owner supplied the exact copyright text **2026 Dastak دستک**. This was entered, saved and observed with Save disabled afterward.
- Owner explicitly chose **Automatic release on approval**. The existing automatic setting was verified selected and retained; this authorizes that setting, not a claim that App Review submission or approval has occurred.
- Owner confirmed entering/saving review contact directly in Apple’s form. A live inspection confirmed first name, last name, phone and email all populated while Save was disabled. Their values are deliberately not copied here.
- App Privacy initially showed no policy URL and a **Get Started** data-collection questionnaire. The existing public privacy URL was entered and saved; the modal closed and the page showed `https://dastak-customer.vercel.app/privacy`. No privacy answers were selected or published.
- Pricing and Availability showed **Add Pricing** and **Set Up Availability**: app-download price and storefront countries are not configured. Mac and Apple Vision Pro availability were both enabled by default and remain untested. Owner was asked whether to configure free download, India only, iPhone/iPad only and disable those two defaults. No such availability change has been applied yet.
- Reviewer Delivery access remains undecided. Owner was asked whether to use a dedicated Google review account approved for Delivery or discuss a fully featured isolated demo. No review account, role approval or demo implementation was created.

## Read-only privacy inventory follow-up

The Supabase-guided source review made no backend, role, payout or runtime configuration changes. It confirms additional areas to reconcile before publishing labels; this is not a complete production privacy audit:

- `DastakDeliveryPartnerAccessView.swift`: government identity proof and, for applicable delivery methods, vehicle registration/make/model and vehicle evidence are uploaded to account-scoped paths in `dastak-evidence`. Classify document contents accurately; a document photo is not automatically biometric processing merely because it contains a face.
- `DastakDeliveryEarningsClient.swift` and `DastakDeliveryEarningsView.swift`: account-linked earnings balances, credits, adjustments and withdrawals; conditional bank-account/IFSC/account-holder or UPI registration. Apple’s **Other Financial Info** and **Payment Info** categories need explicit consideration. These financial data types are not listed in the current app privacy manifest.
- `earnings/provider-clients.ts` gates destination registration and withdrawal availability on configuration. Source inspection does not establish the current production gate values. Do not activate payouts or infer live collection solely from the presence of code.
- `DastakDeviceTokenClient.swift`: notification registration sends APNs token, platform, app ID and APNs environment to the backend; the existing Device ID declaration must be reconciled with actual use.
- A targeted source search did not find named Sentry/Crashlytics/Firebase Analytics/Mixpanel/PostHog/IDFA integrations in the inspected app/infrastructure directories. This is not proof of absence of server logs, diagnostics or third-party collection.

Apple’s [current privacy-data definitions](https://developer.apple.com/app-store/app-privacy-details/) require accounting for developer and third-party collection. Bank account numbers fall under Payment Info, and income/balances under Other Financial Info. Review storage/retention, purpose, linkage, optional-disclosure criteria and third-party behavior before confirming answers. Do not publish an incomplete label or infer it mechanically from the current manifest.

## Historical distribution configuration and verification gap

The owner approved free download, India only, iPhone/iPad only, with Mac and Vision Pro disabled. The Mac and Vision Pro checkboxes were unchecked and Save invoked; subsequent pricing-page observations showed both unchecked. A dedicated reload verification is still required before closing the device-availability gate.

The free-price wizard selected India (INR) and ₹0.00, reviewed its all-country zero-price equivalents and confirmed. The resulting summary now contains a current price schedule for 175 countries, but reports United States as base country despite the wizard’s India selection. The exact saved India price/base needs verification in the price matrix; do not claim that discrepancy is resolved. Price entries for all countries are separate from which storefronts are enabled.

The country-availability picker repeatedly reverted under automation, including after resetting the UI connection. The owner was asked to complete None → India → Next → confirmation manually and reported done. A subsequent refreshed page still listed Afghanistan, Albania, Algeria and Angola as Available on App Release. India-only availability is therefore **not verified**; the owner was asked to reopen Manage Availability and confirm exactly one selected country (India). Do not submit while this remains unresolved. An unrelated pre-order dialog was dismissed without a date or confirmation; no pre-order was scheduled.

Subtitle save/category selection also remain unfinished: the subtitle is visible but persistence is not verified, and the category picker did not expand reliably. No content-rights, age-rating or privacy declaration was answered.

The owner chose to **discuss** an isolated full-featured demo. The proposal and unsent Apple guidance request are in `docs/dastak-app-review-demo-proposal-2026-10-16.md`. This is not authorization to implement, grant roles, create external infrastructure or contact Apple. Prior Apple approval is a separate gate under the conditions in Guideline 2.1(a); no approval or message transmission has occurred.

## Current verified distribution settings

This checkpoint supersedes the historical India-only requirement and its verification gap. The owner explicitly clarified that **all countries/regions were intentionally selected**.

- **Countries:** live Safari displayed 175 countries/regions available on app release. This is the intended setting, not an unresolved mismatch.
- **Download price:** Apple's saved current-price export (`/Users/Furqan/Downloads/Prices.zip`, entry `Current Price .csv`) contains 175 rows and 175 distinct countries/regions. Read-only CSV analysis using decimal comparisons confirmed every Price and Proceeds value is zero. India's row is INR 0.0. The persisted base country is United States (USD); the saved prices still establish a free download everywhere. No further base-country change was made.
- **Devices:** after navigating away and returning, both Mac and Apple Vision Pro availability checkboxes remained off. Device-exclusion persistence is verified. The release targets iPhone/iPad.
- **Release:** retain the owner's automatic-release-on-approval decision. This setting is separate from submission, approval and actual publication; none has occurred.

No App Store setting was mutated during this final verification. Remaining gates are listing text/subtitle/categories, screenshots, truthful age/content-rights/privacy answers and assessment of the existing trader declaration, plus a working reviewer-access solution. Do not treat the demo discussion as implementation approval or prior approval from Apple.
