# Merchant production activation — database and three Edge updates

19 October 2026, Asia/Kolkata. **The four reviewed Merchant migrations are installed and the three approved Edge updates are active on Dastak production.** This supersedes the pending-activation status in the earlier preparation documents at this timestamp. It does not mark Merchant device testing, web publication or distribution complete.

Source: committed and pushed `6c379f61653cac81b0ec0a227b23f28097cf6983` on `codex/dastak-v1-launch`, worktree `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`. The owner explicitly approved a fresh production preflight, exactly four migrations and exactly three function deployments. Solo execution. Unrelated Customer/Delivery fixtures, artwork, release work and dependency-lock changes were preserved. No merge, additional Git commit/push, app installation or website publication occurred during activation.

Machine-readable [activation receipt](evidence/dastak-merchant-production-activation-2026-10-19.json); preceding [release rehearsal](dastak-merchant-release-rehearsal-2026-10-19.md) and [read-only preflight](dastak-merchant-production-preflight-2026-10-19.md).

## Project and refreshed gates

- Independently matched the linked reference and accessible Management project: **Dastak**, `zmtsolkfxlrxepshnjdf`, `ap-south-1`, `ACTIVE_HEALTHY`. Savari was not targeted.
- All candidate migration hashes, the complete 295-file chain, recursively reviewed deployment source closure, configuration and dependency lock matched the reviewed manifest and committed source.
- All **291 prior migration receipts** matched the previous raw metadata, including names, versions, statement counts and SQL fingerprints. Exactly the four Merchant candidates were pending.
- All **12 prerequisite bodies and their inspected ownership/security/volatility/search-path/ACL metadata** matched. No new RPC/index was already installed.
- Error-level security advisors: **No issues found**, before and after application. Other advisor levels are not certified.
- Shared fulfilments table: 45 estimated rows, 16 KiB table / 208 KiB total before installation, RLS enabled, zero observed relation locks/waiters and no other transaction older than one minute at the release snapshots. These are observations, not a promise of universally lock-free operation.

## Hosted transaction and application

The existing reviewed SQL builder was used unchanged. Supabase CLI 2.90.0 linked `db query` sends the SQL as one Management API request; the official CLI implementation was checked. Before commit, the entire transaction was sent with its default **ROLLBACK**. It reached all installation and verification statements with effective **2-second lock / 15-second per-statement timeouts**, reported 295 in-transaction receipts, and rolled back. A separate request confirmed the original 291 receipts/functions and absence of the new index.

The explicit commit request then executed the same guarded release body and installed, in order:

1. `20261018003730_merchant_scoped_order_detail.sql`
2. `20261018014110_merchant_active_and_paged_history.sql`
3. `20261018131824_merchant_catalogue_and_location_pages.sql`
4. `20261018151210_merchant_payout_review_guards.sql`

Each unchanged source SQL was recorded in migration history inside that same transaction. No repair, reset, broad push, seed or role inclusion was used. The hosted rollback call took 3,548 ms including CLI/auth/transport overhead; the commit call took 3,188 ms. These are whole client-call measurements, not database-only execution times or an SLA. The statement timeout applies per statement, not to the entire release; the caller had a 45-second budget. The successful explicit response and subsequent independent state inspection resolved the commit outcome—no blind retry was necessary.

The temporary snapshots and advisory lock were transaction scoped. The only persistent writes were the approved migration DDL/grants/index and four migration-history rows. No business command, order transition, inventory change, destination registration, withdrawal or provider operation was invoked.

## Independent installed-state verification

- **295 history entries**, previous 291 unchanged; each of the four new receipts matches the exact source SHA-256.
- **16 affected functions**: all installed bodies match migration source; owner, security mode, volatility and empty search paths match. This includes the intentionally replaced existing Merchant list, nine new private functions and six new public wrappers.
- Anonymous execution is absent; authenticated Merchant reads and service-only payout wrappers retain their reviewed split. Helper functions are not directly granted to client/service roles.
- The history index is ready and valid on `(branch_id, committed_at DESC, id DESC)`.
- Inspected predecessor metadata/grants and non-list bodies remain unchanged, financial immutable/balance guards remain enabled and unchanged, and checked direct client table-mutation grants remain at zero.
- Final `supabase db push --linked --dry-run --workdir Backends/Dastak`: **Remote database is up to date.** The dry run applied nothing.

## Exact function deployments

Database verification preceded all deployments. Each function was individually deployed with `--use-api`, without pruning or changing secrets:

| Function | Before | Active after | Gateway JWT setting |
| --- | ---: | ---: | --- |
| `dastak-v1-orders` | 21 | **22** | `false`, existing bearer/session verification in handler |
| `dastak-v1-catalogue` | 27 | **28** | `false`, existing bearer/session verification in handler |
| `earnings` | 21 | **22** | `true`, plus existing handler verification |

All other **26 functions** retained their observed version, status, auth setting and bundle hash. The three deployed bundles were downloaded to separate directories under `/private/tmp/dastak-merchant-activated.th6lPQ`, not over repository source. All **18 extracted runtime TypeScript files are byte-for-byte identical** to reviewed source; deployed `deno.json` content also matches. Type-only dependencies omitted by the deployment bundle are not misrepresented as downloaded runtime files. Preceding source bundles remain retained separately for incident inspection.

## Read-only smoke checks and their limits

Eight actual unauthenticated HTTP requests to new/existing read operations returned **401**, as intended. Orders/Catalogue returned the handler's `authentication_required`; Earnings retained its gateway rejection. No signed-in token or new identity was created for this check.

The checked-in [read-smoke SQL](../Backends/Dastak/scripts/merchant-activation-read-smoke.sql) ran inside `BEGIN READ ONLY` / `ROLLBACK`, using only existing actors selected inside the database. SQL roles and local claim settings exercised the authenticated wrappers and service-only read path; returned output was exclusively booleans/counts, with no account/order identifiers, customer addresses, bank data or application payloads.

The **14 successful boolean checks** cover locations, inventory and its continuation cursor, history and its continuation cursor, full-order detail, old Merchant list/catalogue, Merchant royalty capabilities, foreign-branch denial, non-Merchant denial, existing Customer active-order read, and existing Delivery snapshot/royalty reads. Location continuation was not exercised because the selected actor had no continuation cursor. Existing data was sufficient for the other recorded cases; no sample records were inserted.

An initial smoke-script attempt passed `DELIVERY` instead of the existing `RIDER` royalty-kind argument and deliberately failed its status assertion. That read-only transaction was corrected and rerun successfully. No deployed source or data was changed to make it pass. An earlier comparison also rejected an extra evidence-only `commandMatchesSource` annotation; explicit comparable retention fields were then used. Neither verification-script issue was treated as a production feature defect or silently counted as a pass.

SQL role/claim simulation is **not a signed-in HTTP, PostgREST or physical-device acceptance test**. The local full rebuild, 2,081 database contract assertions, 113 integrated assertions and package/handler suites remain separately timestamped evidence; they were not rerun against production or relabelled as live-order tests here.

## Remaining boundaries

- Signed-in Merchant iPhone/iPad operational acceptance, Keychain lifecycle, notifications/APNs timing, keyboard/VoiceOver/large-text and recovery checks remain separate.
- Merchant web screens are committed, but this backend activation does not publish a website.
- Merchant archive/signing, installation, screenshots, TestFlight and App Store distribution remain separate.
- Provider availability gates are unchanged. No secrets, billing, provider setup, bank/UPI registration, payout request/execution or money movement was authorized or performed. Backend activation does not guarantee that gated financial controls are available.
- This new release receipt and read-smoke script are local verification artifacts until separately checkpointed; activation did not silently create another commit or push.

Supabase/Postgres skill guidance shaped the exact-source/history, privilege, transaction and timeout checks. Current references checked during execution: [CLI linked-query implementation](https://github.com/supabase/cli/blob/v2.90.0/internal/db/query/query.go), [Management query API](https://supabase.com/docs/reference/api/v1-run-a-query), [Edge deployment](https://supabase.com/docs/guides/functions/deploy). These references describe mechanisms, not independent proof of this project's health.
