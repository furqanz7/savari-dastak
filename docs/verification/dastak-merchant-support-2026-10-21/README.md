# Merchant help — implementation and verification

21 October 2026. **Production activation and live workflow verified.**
See [the activation record](activation/README.md) for deployment targets, the
disposable real-Admin reply/recovery check and unchanged release boundaries.
The sections below preserve the earlier local implementation/test record; their
"not deployed" statements describe that earlier slice, not current production.
Authoritative worktree `wave1-runtime-ci`, branch `codex/dastak-v1-launch`,
HEAD `61f51b7bcf691370c121e977b95b050311988267`.

## User-approved scope

The owner approved a Merchant support form, an inbox in the existing Admin web
workspace and a private reply/status path, with the owner monitoring the inbox.
No paid service, public email address, real account grant, financial action,
production write, push or deployment was authorized or performed in this slice.

## Implemented story

Merchant opens `/merchant-support` without signing in, submits category/summary/
message and receives a browser-generated private recovery code. The Edge hashes
the secret and calls a service-only database command. An active authorized Admin
can list/read tickets, reply and set Open / Awaiting your reply / Resolved. The
merchant returns with the recovery code to read/reply; a new merchant reply
reopens a resolved request. Most recently updated conversations appear first.

- Public form uses restrained sage/ivory/gold styling, responsive single-column
  layout, labelled native controls, visible focus, plain-text messages, reduced-
  motion support and clear warnings. No attachments or email address field.
- Public entry needs only browser-safe Supabase URL/key, not authentication,
  VAPID, app variant or Customer legal-link setup. Missing configuration shows a
  failure message rather than claiming a request was delivered.
- Merchant web sign-in/error recovery and Merchant Account link to the new page.
  Admin navigation exposes Merchant support. Existing Customer/Delivery flows
  and public policy text are unchanged.
- This slice does not change the native Build 67 binary or its existing shared
  in-app support link. The new App Store Support URL can point at the web route
  only after activation. Any native-link adjustment requires a separate build.

## Access, safety and recovery

- Recovery code = random UUID reference + 32 random bytes encoded as hexadecimal.
  Secret travels only in a no-store POST body, not a URL/query/hash. Ticket tables
  store its SHA-256 hash, never the original secret. No capability in cookies,
  localStorage or sessionStorage. Code must be saved manually; lost codes cannot
  be recovered. Anyone holding it can read and reply.
- No submitted claim, ticket or order reference proves identity. This feature
  cannot approve access, mutate orders, initiate refunds or move money. Admin
  must use existing authorized procedures for any separate operational action.
- Admin actor comes from the existing verified OAuth/session helper, not request
  JSON or editable user metadata. The database rechecks the actual active Admin
  assignment, account state, membership and matching email on each command.
- Tables live in the private schema, have RLS enabled and no direct client or
  service-role table grants. Exposed RPC is security-invoker and executable only
  by service_role; its definer implementation lives in private with empty search
  path. No new privileged account is created.
- Actual streamed request body capped at 12 KB; summary 5–100 UTF-16 units and
  message 5–2000 on the Edge, with database constraints as defense in depth.
  Server emits only selected fields and safe errors, no raw database errors.
- Identical request IDs/content replay safely. Changed replay conflicts; stale
  expected versions do not overwrite replies. Concurrent duplicate replies
  serialize and produce one message/version step. Public UI/Admin retain the
  exact uncertain action for explicit retry; readback of its original message
  ID clears the pending state. Client deadline 15s; database HTTP client 10s.
- New-ticket admission is serialized and capped at 30/hour, 100/day and 1000
  stored tickets. Max 20 messages/ticket, 30s between Merchant messages. Existing
  ticket reads/recovery remain available when admission is full. These are
  conservative unpaid storage guards, not CAPTCHA, per-IP throttling or a
  denial-of-service guarantee. An attacker could exhaust shared admission.
- No email/push alert or response-time guarantee. Owner checks Admin manually;
  merchant uses Refresh replies. No auto-delete/retention promise or background
  cleanup job was introduced. Retention and admission exhaustion remain explicit
  operational decisions for activation, not invented legal-policy claims.

## Source boundaries

- Migration: `Backends/Dastak/supabase/migrations/20261020193411_merchant_support_inbox.sql`
  (created with `supabase migration new`, not applied to a hosted database).
- Edge: `Backends/Dastak/supabase/functions/merchant-support/{index,handler}.ts`.
- Client/types/recovery: `Web/MarketplaceWeb/src/merchantSupport.ts`.
- Public form: `MerchantSupportPage.tsx`; lazy entry in `main.tsx`; Vercel rewrites.
- Admin: `AdminMerchantSupportPanel.tsx`, integrated in AdminDashboard navigation
  and manual/pull-to-refresh registry. No Realtime or background-alert claim.
- `merchant-support-check.html` / `merchantSupportLocalCheck.tsx` are loopback,
  development-only QA. No QA admin token/port strings appeared in production
  assets. QA is not a new public demo or production authentication bypass.

## Evidence

- [Web tests](web-tests.log): **153 files / 1,108 tests pass**, including the new
  support, recovery and standalone configuration checks.
- [Database assertions](database-tests.log): **48 assertions pass**, new migration and actual existing
  `admin_role_for_actor` helper, using minimal dependency tables in a disposable
  socket-only PostgreSQL 14 cluster. Creation, private reads, reply/status,
  idempotency, conflicts, concurrent retry, access revocation/email mismatch,
  table/RPC permissions, paging, cooldown, message/admission/storage caps and
  recovery after admission exhaustion are exercised.
- [Edge tests](edge-tests.log): **24 tests pass**, fail-closed gate, safe errors, bearer derivation,
  hashing/field stripping, body size, validation and version/cursor checks.
- [Production web build](web-build.log): TypeScript + Vite build; pre-existing
  large 3D-scene chunk warning remains. Scoped ESLint and `git diff --check` pass.
- Browser: actual React form → actual new Edge handler → actual new SQL command
  and actual role helper → receipt; fixture Admin reply/Resolved → reopen with
  recovery code → correct reply/status. The loopback HTTP adapter substitutes
  only a local fixture Admin identity, not real OAuth, and routes database calls
  through local psql rather than PostgREST.
- Separately checked the actual `/merchant-support` lazy entry with explicit
  loopback configuration; no VAPID/sign-in configuration required. No hosted
  database, live OAuth, real upload, financial action or actual APNs was tested.
- Phone-width DOM check: content width equals viewport, no horizontal page
  overflow; readonly recovery field remains within its card. Temporary browser
  viewport override restored. Screenshots contain only disposable sample data.
- Temporary browser tabs and loopback HTTP/Vite servers were closed after QA;
  the serving fixture's PostgreSQL cluster was stopped. Retained fixture/log
  artifacts contain only synthetic records. No existing simulator/runtime or
  personal data was removed.

Screenshots: [form preview](merchant-form-preview.jpg),
[phone form](merchant-form-phone.jpg), [desktop conversation](merchant-reply-desktop.jpg),
[phone conversation](merchant-reply-phone.jpg).

## Reproduction

From `Web/MarketplaceWeb`: `./node_modules/.bin/vitest run --maxWorkers 2`,
`npm run build`, scoped ESLint on the support/integration files.

From `Backends/Dastak/supabase/functions`:
`deno test --config deno.json --lock deno.lock --frozen tests/merchant-support/handler.test.ts`
and `deno check --config deno.json --lock deno.lock --frozen merchant-support/index.ts`.

From `Backends/Dastak`: `node scripts/test-merchant-support.mjs`.
The script creates a named disposable `/private/tmp/dastak-support-fixture.*`
cluster, uses no TCP database listener, runs assertions, stops that cluster and
retains small fixture/log artifacts. No hosted URL/secrets are read.
`--serve` additionally offers a loopback-only sample handler on port 56430.
The active development QA adapter must not be deployed.

For the actual support route during QA only, launch Vite with process-local
`VITE_SUPABASE_URL=http://127.0.0.1:56430`,
`VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_local_fixture`, and
`VITE_MERCHANT_SUPPORT_LOCAL_API=1`. Loopback access is rejected in production
build mode or from a non-loopback page. No .env/secrets file was changed.

## Full-chain verification and review follow-up

The [full-chain rebuild and abuse review](FULL_CHAIN_AND_ABUSE_REVIEW.md) is now
complete: **296/296 migrations**, **76 existing files / 2,081 assertions**, and
**37 additional full-schema support assertions** pass in an isolated Supabase
PostgreSQL 17.6 runtime. The old PG14 fixture description above remains accurate
for that earlier test, but is no longer the only compatibility evidence.

The subsequent [local hardening](HARDENING.md) corrects read-lock contention,
body/backend deadlines and invalid-text handling, and adds a fixed-size per-worker
limiter. **297/297 migrations, 2,081 regressions, 40 full-schema support assertions,
423 Edge tests and 1,112 web tests pass.** The owner chose local safeguards only,
no external bot provider, and no ticket deletion. Shared allowance exhaustion
remains a documented residual risk; no distributed bot-protection claim is made.
Public activation remains separate and has not occurred.

## Remaining activation gates — not performed

1. Local hardening and the owner's local-only/no-deletion decision are documented
   above. Explicit production activation must account for the remaining shared
   allowance risk; no external provider or automatic retention is assumed.
2. Final 297-file compatibility and existing-ticket upgrade are verified. Hosted
   PostgREST/OAuth behavior and production migration state remain unverified by
   this local run.
3. Get explicit production authorization: apply the final reviewed support migrations,
   deploy `merchant-support`, deploy the public route and Admin/Merchant web
   integrations, and set `MERCHANT_SUPPORT_ENABLED=true`. Default is disabled.
   `verify_jwt=false` is only for this new public function; Admin calls still
   require verified session + current DB role. Other functions are unchanged.
4. Verify deployed public intake/recovery and Admin reply using a deliberately
   disposable non-personal ticket; confirm owner can monitor the inbox. Do not
   add the live App Store Support URL before this check.
5. Review/publish the separate Merchant policy copy, finalize Merchant privacy
   answers (including support collection as applicable), age/content rights and
   review contact. Do not silently submit or accept legal declarations.

Known unrelated tracked diff remains byte-identical at SHA-256
`89cb303d44be0291e8103a744cb49acf66052e15d35e60f9bd2fac5dadbeb473`.
No source push/commit, deployed migration, production data mutation, App Store
change or privacy publication occurred.
