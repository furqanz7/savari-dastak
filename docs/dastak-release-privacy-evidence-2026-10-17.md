# Customer + Delivery release privacy checkpoint

Status: corrections prepared and locally tested, not published or deployed. Build 59 remains the owner-tested distributed build; the manifest changes below are not in that binary. No new release version/build has been archived from these changes yet.

This checkpoint is kept as a local draft commit, not pushed, because the revised public privacy-policy wording still needs owner review before any deployment/publication. Hosted CI has not run for this draft; the exact local checks are listed below. No auto-deploy settings were assumed.

## Scope and method

Work was confined to the authoritative `codex/dastak-v1-launch` worktree, starting at `ea88e6323e8ccaea45a3209c939bbecf0ea10ba0`, with no pre-existing tracked changes. Existing untracked models/screenshots were retained. Inspection used the Supabase skill, current official documentation, live configuration reads and aggregate log queries. No application order, payment, account, role approval, logging setting, log drain or retention configuration was changed.

Existing CLI authentication was reused without printing, persisting or changing credentials. Log queries returned aggregate counts and field names, not user identifiers, IP addresses, request bodies or raw private log messages. Captured result values are deliberately limited below.

## Directly verified

- The linked production project is Dastak, `zmtsolkfxlrxepshnjdf`. The Management API returned an empty custom Postgres override object; this is not evidence that logging is off.
- Live `pg_settings` inspection returned `log_statement=ddl`, `log_min_error_statement=error`, `log_min_duration_statement=-1`, `log_duration=off`, `log_connections=off`, `log_disconnections=off`, `pgaudit.log=none`, `pgaudit.log_parameter=off`, and `log_parameter_max_length_on_error=0`. Separate role overrides showed `log_statement=none` for the internal admin/auth/storage roles. No parameters were changed.
- A log field-name-only query found request IP/user-agent, account/session subject, request/response status and execution timing fields on API/function events; auth events also have account/request identifiers. Function runtime events include CPU/memory/boot metadata. Field availability alone does not prove a value is present on each event.
- The decisive bounded aggregate query requested **15 October 2026 20:36:22 UTC to 16 October 2026 20:36:22 UTC** (16–17 October in India). `function_edge_logs` contained **288 Dastak/Apple URLSession requests**, all 288 with non-empty account-subject and execution-time fields. Returned min/max event timestamps matched the requested recent window. No subject, timing value or IP was retrieved.
- Separate broader historical aggregates were exploratory and do **not** establish a configured retention limit. No exact retention period is asserted.
- The documented v2 log-drains read endpoint returned **403**, specifically that the organization does not have access to that API. Therefore external drain destinations/count and their retention are **not verified**. This is not evidence that no drains exist. No access was expanded to bypass that limitation.
- First-party iOS request debug prints are guarded by `#if DEBUG`. The removed Razorpay SDK's conditional implementation is not present in the Build 59 distribution package. Neither fact eliminates the hosted operational logs above.

## Declaration correction

The evidence supports **Performance Data** for retained request execution timing and **Other Diagnostic Data** for retained operational/error/request metadata. Configure both for **App Functionality**, **linked to identity**, **not tracking**. Linkage is conservative and evidence-based: the request records retain account subjects; no pre-collection anonymisation was verified. This does not assert third-party advertising analytics or device crash-report collection.

The first-party manifest now has 17 data types with these two additions. Its configuration regression test enforces both types, the app-functionality purpose, identity linkage and no tracking. App Store Connect still has the previously owner-saved **15-type unpublished draft** until the owner adds/configures these two. Do not click Publish yet.

The public-policy source draft now explains operational diagnostics, Delivery onboarding/earnings/conditional payout information, and current iOS doorstep payment separately from older online payment on other platforms. This corrects the old wording that implied all current customer payments used Razorpay. This is an unpublished source draft requiring owner review before production policy deployment; it does not change payment behavior or activate payouts.

Remaining privacy gates: verify dashboard log destinations/configured retention (or obtain an explicit owner confirmation), review the policy draft, add the two diagnostics entries to App Store Connect, ship a build with the updated manifest, verify the live policy after approved deployment, and only then approve privacy publication. Do not label this checkpoint a completed privacy/legal audit.

## Local checks

- `swift test --package-path Packages/MarketplaceInfrastructure --jobs 1 --filter DastakProjectConfigurationTests`: 4 tests passed, zero failures.
- `npm test -- --run src/publicInformation.test.ts`: 3 tests passed, zero failures.
- Full web `npm test`: **149 files / 1,063 tests passed**. `npm run build`: TypeScript/Vite production build passed, with the existing large-chunk warning; no production deployment was run.
- Privacy plist lint and `git diff --check`: passed.
- A current-source Debug simulator build succeeded before the manifest/policy-only edits; sample renderer launch has no live authentication/commerce fallback. No claim is made that sample screenshot generation is live end-to-end testing or reviewer access.

## Listing and review gates

The live TestFlight list now shows Build 59 in the existing internal Testing group. The owner reported installing it and passing the two release-scope smoke checks. The App Store version form still displayed selected Build 58, saved marketing/description text, empty review credentials/notes and automatic release on approval. The Mac locked before the build attachment could be changed; no attachment replacement or submission is claimed.

The existing review-demo proposal is still only a proposal. Normal Apple/Google sign-in does not give a reviewer approved Delivery access. An owner choice was requested between preparing the Apple demo-approval message for the owner to send and using a dedicated approved reviewer Google account. No message, account grant, demo implementation or review submission was performed.

The prior non-trader declaration requires owner assessment for the selected worldwide storefronts. Free download is not by itself a determination of trader status. Public trader contact/verification details must be handled by the owner, not inferred from private review contacts. No trader declaration was changed.

A 1206 × 2622 iPhone sign-in screenshot draft was captured without private account data. Populated shopping fixtures were not suitable for final marketing screenshots, and iPad first-start migration stalled. Capture attempts were stopped and the iPad returned to its original shut-down state. No screenshots were uploaded. Details are in `verification/dastak-app-store-2026-10-17/README.md`.

## Primary references checked

- [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/): retained off-device collection includes non-advertising functionality; defines diagnostics, linkage and treatment of IP addresses.
- [Supabase Log Sources and Fields](https://supabase.com/docs/guides/observability/log-field-reference): gateway/function/auth metadata and runtime log sources.
- [Supabase Logs in Studio](https://supabase.com/docs/guides/observability/logs): hosted logs and plan-dependent retention.
- [Supabase Management API specification](https://github.com/supabase/supabase/blob/master/apps/docs/spec/api_v2_openapi.json): documented read-only log-drains route; no undocumented write route used.
- [Apple App Review Guideline 2.1(a)](https://developer.apple.com/app-store/review/guidelines/#app-completeness): complete review access and prior approval when relying on a demo instead of an account under that exception.
- [Apple DSA trader guidance](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/): owner self-assessment and verified public contact information.
