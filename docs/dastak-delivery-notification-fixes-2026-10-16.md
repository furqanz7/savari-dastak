# Delivery notification corrections — 16 October 2026

Status: **activated in production** with the owner's explicit approval; local regression tests and production release checks passed. The owner subsequently reported **"All passed"** for the listed Delivery acceptance areas, including notifications, on 16 October 2026. This is owner-reported phone acceptance, not an agent-observed delivery trace or an exactly-once guarantee.

## Scope and prior evidence

The read-only audit found one rider mission-offer push accepted by APNs about 166 seconds after its event, after the matching offer's acceptance deadline. It also found 16 same-device event groups containing both `customer.rider_assigned` and `rider.assigned`. Both alert types shared `apns-collapse-id = eventId`, allowing Apple to merge distinct role alerts. No duplicate database delivery rows or unresolved created rider iOS jobs were found in that seven-day sample. APNs acceptance was not represented as proof of visible exactly-once phone delivery.

Customer and Delivery remain in the existing iPhone Build 52. The owner's fast, fully native normal delivery acceptance is unchanged. These notification corrections require no new iPhone binary.

## Implementation

- `process-v1-outbox` preflights every `rider.mission_offer` immediately before the job's provider attempt, including retries and jobs queued behind the worker's concurrency limit.
- One new migration, `20261015154016_delivery_notification_offer_expiry.sql`, provides a private definer function behind a service-role-only invoker RPC. It verifies the existing delivery claim owner and matches the exact event, rider and pool round against the current mission and offer. Expired, accepted, declined, reassigned, missing and obsolete-round offers are marked `SUPPRESSED` in notification storage only. It does not update any offer, mission, order, payment or device token.
- An actionable job receives its exact offer deadline. APNs checks expiry before and after signing, then sends `apns-expiration` bounded by that deadline. An expired job makes no APNs request and does not invalidate a device token. Web Push uses the same guard and a bounded TTL because it shares the worker.
- APNs collapse identity is now the stable delivery UUID: distinct Customer/Rider notifications have distinct identifiers, while a retry of the same notification reuses its identifier. The Web Push topic follows the same identity rule.
- Suppressed jobs are separately counted, not reported as sent or as failed/retrying. Existing provider failure completion and durable retry behavior remain in place. Other notification types do not depend on the new offer guard.
- The existing fast worker schedule and app notification permission/registration behavior are unchanged. No historical events are replayed and no test push was sent to a real device.

## Verification

- 37 Deno tests passed, zero failures: worker handling, APNs, Web Push, Live Activities, notification policy and registration. New tests include cross-role collapse isolation, stable retry IDs, expired/missing-deadline suppression, expiry while signing, exact APNs deadline, guard outage/malformed-result fail-closed behavior, original job identity preservation and bounded Web Push TTL.
- `deno check` passed for the actual `process-v1-outbox/index.ts` entry point.
- A new, isolated local PostgreSQL 14 database ran `tests/delivery-notification-expiry-isolated.sql` successfully. It checks fresh and expired claims, retry/replay behavior, accepted/declined/expired offers, assignment, pool/rider isolation, wrong and absent claim owners, unrelated notification preservation, unchanged offer rows and actual service-role execution through the invoker wrapper. Anon/authenticated access is denied.
- No Docker-backed Supabase stack was available. The CLI advisor could not connect to the isolated server because it required TLS; a second attempt with `sslmode=disable` did not resolve that CLI behavior. The usual local migration-list command also could not connect to the absent Supabase port. No clean advisor/full-stack migration claim is made. The migration itself was parsed and executed by the isolated SQL fixture.
- `git diff --check` passed. Test logs: `/private/tmp/dastak-notification-fix-provider-tests.log`, `/private/tmp/dastak-notification-fix-typecheck.log`, `/private/tmp/dastak-notification-fix-sql-tests.log`. Logs in temporary storage are not durable release artifacts.

## Production activation

The owner explicitly approved the single migration and notification-worker deployment. Applied only `20261015154016_delivery_notification_offer_expiry.sql` to linked project `zmtsolkfxlrxepshnjdf`, then recorded that exact migration version as applied. No broad migration push was used. Read-only catalog verification confirmed the private definer function, public invoker wrapper, empty search paths, service-role execution/schema access, and denied anon/authenticated execution.

Downloaded the old deployed worker before release and compared all bundled sources. Only the approved notification changes differed; Live Activity code, shared HTTP handling and the import map were unchanged. Deployed only `process-v1-outbox`, from version 12 to **version 13 / ACTIVE**, retaining its internal-secret authentication configuration. The before/after function inventory showed no other function version/status/auth changes. Downloaded version 13 and verified every bundled file matches local source byte for byte. An unauthenticated POST returned the expected HTTP 403 without running notification work.

The immediate post-deployment read-only health snapshot found **zero pending/in-flight rider iOS deliveries**. The seven-day sample remained 33 SENT rider iOS jobs: 16 assigned, 16 mission offers and one fulfilment-ready alert. The 10-second notification fast lane and one-minute main worker schedules remained active. No notification jobs had been created after deployment at that snapshot, so this is release/queue verification, not evidence of a new real-device delivery under version 13. The 37-test notification/registration suite was rerun before activation and passed again; `git diff --check` also passed.

No real order was created or advanced, no payment was collected, no availability was changed, no authenticated worker run was manually triggered, and no historical event or test push was sent as an activation test. No new iPhone binary is needed; Build 52 remains installed. Visible phone delivery under lock, offline conditions and Focus settings remains separate acceptance; neither APNs nor the local tests establish a universal exactly-once guarantee. Observe the next normal order for actionable offer arrival, role-distinct alerts, expiry suppression and provider latency.
