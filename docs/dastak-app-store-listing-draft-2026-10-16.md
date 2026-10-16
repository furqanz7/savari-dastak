# Dastak App Store listing draft

Status: partially saved to App Store Connect, not submitted. Customer + Delivery only; Merchant remains deferred. Release candidate: version 1.0.0, Build 58, with the owner-approved centred under-panel weather credit. Upload, processing and compliance clearance succeeded; a live Safari refresh confirmed Ready to Submit in the existing internal Testing group. The owner reported installing Build 58 and explicitly accepted the centred footer and its legal-text spacing. The existing App Store version is 1.0, English (U.K.). Its Add Build chooser offered Build 58 (1.0.0), which was selected and saved; keywords, support URL and marketing URL were also saved. Description/promotional text remain blank because Safari text-area input did not take; the copy below remains a draft. No version-number change was needed to select Build 58. Review contact/access, copyright, screenshots and other declarations remain unfinished.

## Public copy

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
| Coarse location (optional weather) | No | App functionality | No |
| Name, email, phone, physical address | Yes | App functionality | No |
| Precise location | Yes | App functionality | No |
| Photos/videos, customer support, other user content | Yes | App functionality | No |
| User ID, device ID, purchase history | Yes | App functionality | No |

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
