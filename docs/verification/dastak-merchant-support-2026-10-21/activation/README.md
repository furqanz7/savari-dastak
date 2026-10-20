# Merchant support production activation

21 October 2026. Worktree `wave1-runtime-ci`, branch `codex/dastak-v1-launch`.
Base HEAD before publication: `61f51b7bcf691370c121e977b95b050311988267`.

## Authority and scope

The owner separately approved applying the two support migrations, deploying
the new Edge function and Merchant/Admin web integrations, enabling intake and
testing a deliberately disposable public request through the signed-in Admin.
They then approved committing and pushing only support source, migrations,
tests and verification. Existing native-app, artwork and unrelated work stays
outside this commit. Local safeguards only; keep the cap and delete nothing.
No paid provider, account/role grant, real order, payment or delivery mutation.

## Production changes verified

- Linked Supabase project `zmtsolkfxlrxepshnjdf`; preflight found 295 migrations.
  Dry-run listed exactly `20261020193411_merchant_support_inbox.sql` and
  `20261020203749_merchant_support_request_hardening.sql`. Both applied; hosted
  history now contains 297. No historical migration was rewritten.
- New `merchant-support` function deployed ACTIVE, version 1, gateway
  `verify_jwt=false`. All 29 existing deployed function versions were unchanged.
  Admin operations still require verified OAuth/session plus the current DB role.
- Public RPC permissions: anon/authenticated denied; service_role executable.
  Private command retains empty search_path and 500ms lock_timeout.
- Disabled gate returned HTTP 503 before enabling. Only
  `MERCHANT_SUPPORT_ENABLED=true` was set; enabled missing-capability read returned
  safe HTTP 404. No other secret or environment setting was changed.
- Merchant and Admin production web artifacts built with their explicit project,
  production variant and browser configuration. Customer/Delivery not deployed.
  Public domains returned the correct variant and deployment provenance headers.
- The final Safari check found an inherited dark text-contrast issue in the
  support safety notice. An explicit dark foreground on its pale surface and a
  regression test were added before final publication.

Live entry: https://dastak-merchant.vercel.app/merchant-support
Admin: https://dastak-admin.vercel.app/ → Merchant support.

Initial deployments (before the contrast-only follow-up):

| Project | Deployment | Immutable URL |
|---|---|---|
| Merchant | `dpl_58auRvCodpNcSFSLqmYw71Cy1HoC` | https://dastak-merchant-nwu7mxvzw-liquiflows-projects.vercel.app |
| Admin | `dpl_7jPxSNSvZpfyV57TJVY6DAzFcTBd` | https://dastak-admin-6pjo7fe6g-liquiflows-projects.vercel.app |

Final contrast-corrected production artifacts:

| Project | Deployment | Immutable URL |
|---|---|---|
| Merchant | `dpl_8ePDyjDq5bt17GMnpfj6a2JSPn1M` | https://dastak-merchant-3clktqgmf-liquiflows-projects.vercel.app |
| Admin | `dpl_DCQZg6S3hDk8j1TJRu2YDyLwoigM` | https://dastak-admin-mhtdhshiw-liquiflows-projects.vercel.app |

Both exact artifacts were promoted successfully. Public production HTML identifies
these deployment IDs; the served support stylesheet contains the corrected
foreground/background pair. Fresh authenticated Safari navigation confirmed the
notice is readable in the dark Admin appearance. [Final Admin proof](admin-final-contrast.png).
Agent-created QA tabs were closed afterward; pre-existing tabs were retained.

Deployments were built from the tested working-tree snapshot. Their Git metadata
uses the existing base HEAD, not a claim that the support change was committed
before deployment. [Source hashes](source-snapshot.json) identify the final
support runtime files (including the contrast correction).

## Live end-to-end check

1. Submitted the actual public form in Safari with synthetic text only:
   **Activation check — disposable support ticket**.
2. Receipt issued a private recovery code. It was kept only in transient QA
   memory; never included in a URL, report, screenshot or committed log.
3. The existing signed-in, authorized Admin opened Merchant support, selected
   that ticket and saved an acknowledgement with Resolved status. No service-role
   impersonation or new Admin assignment was used for this UI check.
4. Reloaded the public page to remove its in-memory conversation, chose Read a
   reply, entered the saved code and verified the same acknowledgement and
   Resolved status from the server.
5. Read-only hosted SQL independently confirmed ticket
   `095b46cd-d2cc-466c-b535-b1ed8e4c9dad`: RESOLVED, version 2, exactly 2 messages.
   The disposable ticket remains stored intentionally; nothing was deleted.

The acknowledgement states no account, order or payment action was taken.
No email or push was sent, as explicitly shown by the UI. Manual owner monitoring
and private-code return visits are the supported workflow.

## Verification and honest limits

Earlier isolated checks remain recorded in the parent reports: all 297 migrations,
2,081 existing SQL assertions, 40 full-schema support assertions, 48 fast-fixture
assertions, 423 Edge tests and 1,112 web tests passed. The final full web run passes
**154 files / 1,113 tests**; the 3 targeted support files pass 29 tests. Scoped
ESLint passes. [Final full-suite log](web-tests.log). Production builds
pass with the pre-existing large 3D-scene chunk warning.

Initial deployment-scoped Vercel error-log scans returned no entries in the
bounded last-30-minute window. This is not a claim of exhaustive production
monitoring, APNs verification or an outage guarantee.

Shared admission can still be exhausted; per-worker limiting is not distributed
bot protection. Resolving tickets does not free the 1,000-ticket storage cap.
No deletion/retention task or external CAPTCHA provider was introduced.

Native Build 67 and its shared support link are unchanged. App Store Support URL,
Merchant-specific policy copy and privacy declarations remain separate release
steps; none was published or submitted by this activation. This report does not
claim that all Merchant/App Store release work is complete.

Live proof: [recovered public reply](public-recovered-resolved.png).
The private capability field is outside the captured view.
