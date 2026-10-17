# Dastak Build 61 — read-only final submission preflight

## Latest authorized checkpoint — 18 October 2026

This section supersedes the original read-only checkpoint below where noted. The owner subsequently authorized a narrow Build 61 demo/release commit and push, and **Add for Review**, explicitly stopping before **Submit for Review**.

- Saved availability is **147 countries or regions**. The Asia Pacific availability table directly shows **China mainland — Not Available**, confirming the owner's manual exclusion. The previously verified 27 EU exclusions remain unchecked; India remains selected. The verification changed only the table's display filter, not country selections.
- The version page showed saved Build **61**, binary **1.0.0**, disabled Save and the persisted demo instructions before validation.
- **Add for Review** completed successfully. The sidebar now reads **1.0 Ready for Review**; **Draft Submissions (1)** contains **Item Ready to Submit**, **iOS App 1.0**, **1.0.0 (61)**. The **Submit for Review** button is present and was **not clicked**. This is Apple's draft validation, not submission, review acceptance or demo approval.
- Pre-push working-tree verification passed: DastakUI **555 tests**, MarketplaceInfrastructure **189 tests**, MarketplaceDesignSystem **8 tests**, all zero failures. Existing Debug-only screenshot fixture changes remain outside the intended source checkpoint, together with unrelated older evidence, assets and the declined database support draft. These runs are not a clean staged-tree or hosted CI pass.
- No new source implementation, binary, production deployment, database operation, trader declaration, pricing, privacy answer, account/order/payment operation or actual review submission was made during this checkpoint.

18 October 2026, Asia/Calcutta. The owner authorized the final check, not adding a draft submission or sending the app to review. This is a listing/link/capacity inspection, not App Review acceptance, a complete legal audit, fresh real-order testing or comprehensive production-health certification.

## Directly verified in App Store Connect

| Item | Observed result |
| --- | --- |
| App/version | Dastak دستک, Apple ID 6796518603, version 1.0, **Prepare for Submission** |
| Saved binary | Build **61**, binary version **1.0.0** |
| Saved review access | Sign-in required unchecked; full 2,938-character demo instructions persisted, with 1,062 characters remaining |
| Review contacts | Name, phone and email fields populated; private values not reproduced here |
| Release option | Automatic release on approval selected, unchanged |
| Save state | Save disabled at the final version checkpoint; no unsaved version edits |
| Metadata | Name, subtitle, description, promotional text, keywords, copyright, Support URL and Marketing URL populated |
| Categories / rating | Shopping; Food & Drink; 4+ global rating with displayed regional exceptions |
| Content rights | Existing necessary-third-party-rights declaration present; not independently certified by this inspection |
| Screenshots | Five saved iPhone screenshots and five saved iPad 13-inch screenshots: 01-grocery, 02-food, 03-menu, 04-basket, 05-delivery |
| Privacy | **Published**, 17 data types, privacy-policy URL present |
| Price | Current country-price popover showed **$0.00** for the base U.S. and displayed country rows; no price change made |
| Availability | **148** selected / **27** not available; saved EU exclusions and India retention were verified in the preceding checkpoint |
| Platforms | Apple silicon Mac and Apple Vision Pro availability both unchecked |
| Apple agreements | Free Apps Agreement and Paid Apps Agreement both **Active** |

The new optional product-page header asset is empty. Its presence as an empty optional editor is not treated as a missing required screenshot. Apple's automated required-field/binary validation has **not** run: **Add for Review** and **Submit for Review** were not clicked.

## Live public links

All three URLs returned HTTP 200, then their actual client-rendered content was read in Safari (HTTP success alone was not considered sufficient):

- [Privacy](https://dastak-customer.vercel.app/privacy): effective 17 October 2026; operational diagnostics, Apple/Google sign-in, optional weather, current doorstep-payment scope and removal of legacy iOS retries present.
- [Support](https://dastak-customer.vercel.app/support): order/account help links, Apple/Google recovery guidance, current doorstep-payment scope and account-deletion guidance present. Public support is through signed-in app flows; no public support email is claimed.
- [Terms](https://dastak-customer.vercel.app/terms): effective 17 October 2026; no charge at confirmation, doorstep collection, confirmation/preparation/cancellation rules and disabled legacy iOS online-payment retries present.

The web-search fetcher could not retrieve these client-rendered pages; the independent HTTP and native Safari observations above supplied the verification. Only task-created price-matrix/legal-page tabs were closed; unrelated tabs were retained.

## Refreshed backend-capacity snapshot

Using the Supabase skill's evidence and safety boundaries, the prior cleanup results were read, then the existing authenticated organization Usage page was refreshed. No query, cleanup, logging setting, purchase, permission or production record was changed.

- Plan: **Free**, cycle 4 October–4 November 2026.
- Organization database accounting: **0.46 / 0.5 GB (92%)**; displayed Dastak project database size **439.09 MB**.
- File Storage: **0.931 / 1 GB (93%)**; egress **0.951 / 5 GB (19%)**.
- Log Ingestion: **UPCOMING**, **2.831 / 1 GB (283%)**. Current [Logs Ingest documentation](https://supabase.com/docs/guides/platform/manage-your-usage/logs-ingest) explicitly says not yet billed, with its grace period running through the start of 2027. This is a forward-looking capacity concern, not evidence of a current billed charge or a proven current request block.
- The **Grace period is over** notice remains. The [billing FAQ](https://supabase.com/docs/guides/platform/billing-faq#what-is-a-grace-period-and-does-it-reset-after-usage-drops) says that notice can persist after usage falls below quota. The banner alone neither proves an active restriction nor proves all authenticated operations are healthy. Database/Storage headroom remains tight; no paid plan is authorized.

Historical cleanup archive/restore and real hourly retention success are recorded in [the cleanup results](verification/dastak-database-size-2026-10-17/RESULTS.md). They were not rerun during this preflight. No new physical-device/iPad/manual/remote-APNs/real-order pass is claimed.

## Follow-ups requiring decisions, not silent mutation

1. **China mainland:** remains selected. Its availability row currently reads **Available on App Release**, not an explicit missing-filing error. However, App Information shows the ICP section as **Set Up**, with no filing recorded. [Apple's app-information reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/) describes ICP and other documentation requirements where applicable. Applicability to this app is not a legal determination made by this check. Confirm the required filing exists/applicability, or authorize excluding China mainland; do not silently remove another country or claim Apple has cleared its regional compliance.
2. **Source checkpoint:** the new demo/release source, tests, five images and release evidence remain modified/untracked in the authoritative worktree. The archived and uploaded Build 61 includes the local implementation, but its source has not been committed/pushed by these distribution tasks. Preserve unrelated existing app/screenshot/assets, the declined support draft and private recovery material. A narrowly scoped commit/push requires explicit authorization.
3. **Apple validation and submission:** [Apple's documented flow](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app) separates **Add for Review** (creates/adds to a draft and changes status) from **Submit for Review** (sends it). Neither was performed. Further validation can reveal additional requirements; populated visible fields are not an automated validation pass or approval of the demo.

Guard: branch `codex/dastak-v1-launch`, HEAD `a62ed1377433ee45d2761e8b59c65f318c178dba`, existing dirty baseline unchanged apart from task verification documents. No source implementation edit, commit, push, deployment, trader change, country change, account/order/payment operation or review submission occurred during this preflight.
