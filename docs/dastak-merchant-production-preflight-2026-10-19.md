# Merchant production preflight — read-only scoped match

19 October 2026, Asia/Calcutta. Follow-up to the [295-migration rebuild](dastak-merchant-full-rebuild-2026-10-18.md) and [activation plan](dastak-merchant-backend-activation-plan-2026-10-18.md).

**The inspected hosted baseline matches the reviewed pre-activation state. Exactly the four Merchant migrations are pending. No migration, Edge deployment, provider call or application mutation was performed.** This closes the scoped hosted preflight at the recorded time, not the source/release-runner gates, activation authorization, deployed feature acceptance or Merchant distribution.

Permanent sanitized evidence: [preflight receipt](evidence/dastak-merchant-production-preflight-2026-10-19.json).

## Identity, source and authorization boundary

- Verified the linked reference against the prior reviewed receipt and the accessible Management project: **Dastak**, `zmtsolkfxlrxepshnjdf`, `ap-south-1`, Management status `ACTIVE_HEALTHY`. That status is not an end-to-end app-health test.
- Worktree `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, unchanged HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`. Current 295-file chain hash still matches the rebuilt source and activation manifest: `631b55eee8ea11249c5831599b81d3b10176b313ab73c5802004bdf2a678657f`.
- Solo work. Existing Merchant implementation, unrelated Customer fixtures/artwork/release documents and dependency-lockfile changes preserved. This task adds the metadata query and evidence/report, and updates checkpoint navigation/status only; no runtime source was changed or committed/pushed.
- Hosted SQL used explicit `BEGIN READ ONLY`, short statement budgets and rollback. The new `Backends/Dastak/scripts/merchant-production-preflight.sql` reads migration/function/index/privilege/trigger metadata and coarse aggregate activity, not customer addresses, bank details, account/order identifiers or application payloads. No application RPC was invoked.
- CLI 2.90.0 command help was checked first. Queries/list/advisors use the existing authenticated CLI mechanism. The CLI initializes its own temporary database login role; no app credentials, service secrets, provider settings or business grants were deliberately changed. No migration `repair`, reset, apply, broad function deployment or provider request was run.

## Migration history and prerequisites

| Check | Observed result |
| --- | --- |
| Hosted history | **291 applied** versus **295 local** |
| First 289 historical receipt names/versions/SQL receipts | All unchanged against the independently revalidated 16 October production receipt |
| Two retention migrations | Installed; each stored SQL matches source after the CLI's terminal-semicolon omission |
| Installed retention command | Active; SHA-256 matches the final source command |
| Pending set | Exactly the four reviewed Merchant candidates, no extras |
| Existing new private function names | **0** across the nine names introduced by the candidates |
| Existing new public RPC signatures | **0** across all six new wrappers |
| New history index | Not installed, as expected before activation |
| Prerequisite function bodies | **12 / 12 match current pre-candidate source**, normalizing only outer whitespace/CRLF |

The first 289 receipt aggregate SHA-256 is `4cbc571f349ce856ee226935846acf05b49f2a441db15b4738f412ed428aeb48`, equal to the permanent earlier production receipt. The next two are `20261017173813_successful_cron_history_retention` and `20261017180844_optimize_successful_cron_history_retention`. Their raw file and installed-statement hashes are not claimed byte-identical: the CLI omitted the final statement semicolon. Exact remaining text matches; no broad comment/literal stripping was used to dismiss differences.

The 12 prerequisite bodies include the existing Merchant list, authenticated actor check, Merchant permission helper, fulfilment/opportunity/restaurant projections, catalogue prefix helper, Royalty permission/snapshot/registration/request and balanced-financial-transaction functions. Inspected owners, security mode, volatility, empty search paths and ACLs are recorded. This is not a full hosted schema diff or universal audit of every historical function.

The future CLI **dry run**, not an application, listed exactly:

1. `20261018003730_merchant_scoped_order_detail.sql`
2. `20261018014110_merchant_active_and_paged_history.sql`
3. `20261018131824_merchant_catalogue_and_location_pages.sql`
4. `20261018151210_merchant_payout_review_guards.sql`

Commands used for history and dry run:

```sh
supabase migration list --linked --workdir Backends/Dastak
supabase db push --linked --dry-run --workdir Backends/Dastak
supabase db query --linked --workdir Backends/Dastak --file scripts/merchant-production-preflight.sql --output json
```

The query-file path is relative to the CLI workdir. An initial duplicated workdir prefix failed before SQL execution and was corrected. No missing-file failure was counted as a query pass.

## Security and operational metadata

- Security advisor, **error level only**: succeeded with **No issues found**, exit 0. Warnings/info/performance advisors were not certified, and this is not a universal security assessment.
- An initial concurrent set of CLI reads encountered repeated temporary-login authentication/circuit-breaker errors on the advisor connection. That retry process was terminated; later database operations were run sequentially and the advisor succeeded on its next explicit attempt. This is not presented as proof of an application auth defect or proof of the CLI's underlying root cause.
- Direct anon/authenticated mutation/control grants in the checked public/private/audit/dastak_v1 table set: **0 violations**. Authenticated direct domain-schema USAGE remains false.
- Both legacy merchant-ledger immutable triggers and all four V1 financial immutable/balance guards remain enabled. No financial journal was modified or provider/account destination read or changed.
- Fulfilments table: **45 estimated rows**, 16,384 table bytes / 212,992 total bytes; RLS enabled, ten existing indexes ready/valid, zero observed relation locks/waiters. There was one other active session and no other transaction older than one minute at that snapshot.

The small current table supports planning a short ordinary-index creation, but **does not promise a lock-free release**. Runtime table size/load/locks can change. Recheck immediately before application and retain effective finite lock/statement deadlines; the release-runner rehearsal remains separate.

## Deployed functions and source drift

| Function | Version | Status | Gateway JWT setting |
| --- | ---: | --- | --- |
| `dastak-v1-orders` | 21 | ACTIVE | `verify_jwt=false`; existing handler verifies bearer/session |
| `dastak-v1-catalogue` | 27 | ACTIVE | `verify_jwt=false`; existing handler verifies bearer/session |
| `earnings` | 21 | ACTIVE | `verify_jwt=true`, plus existing handler verification |

All three settings match source. Versions/auth settings/bundle hashes were listed again at the end and remained unchanged. No tokens or secrets were downloaded/read as part of this comparison.

Each deployed function was downloaded through the Management API to its **own temporary directory**, so one deployment's shared files cannot overwrite another's evidence. The 18 extracted TypeScript source files match the committed pre-Merchant baseline by parsed structure after a narrowly defined normalization: ignore formatting/comments and unwrap only blocks containing exactly one `throw` statement. No other AST normalization was used. Shared authentication/HTTP/RPC and provider helper files are byte-identical to baseline. Several handlers/entrypoints differ textually in wrapping/braces/formatting; the raw hashes and normalized comparison results are retained rather than labelling raw files identical.

This comparison used the locally installed TypeScript parser and included node kinds, leaf text and child structure. It is a source-drift check, not formal behavioral equivalence or an HTTP/runtime acceptance test. New local Merchant operations deliberately differ from the deployed baseline and remain pending deployment. The pending tested source closure is separately fingerprinted in the activation manifest, not confused with these deployed-source hashes.

The downloaded source remains under `/private/tmp/dastak-merchant-deployed.yoUbZq/{orders,catalogue,earnings}/supabase/functions`. No repository source was overwritten. Public function invocation, authenticated end-to-end routing, APNs delivery and provider connectivity were not exercised.

## Remaining release gates

1. **Scoped source checkpoint and push authority.** Merchant changes remain local/uncommitted amid known unrelated dirty files. Do not use `git add .` or deploy an unreviewed workspace.
2. **Bounded release-runner rehearsal.** Demonstrate actual transaction/history/timeout behavior locally, including lock timeout for the shared fulfilments index. The earlier CLI timeout caveat remains relevant; a successful dry run does not establish transaction boundaries or effective timeouts.
3. **Explicit application/deployment approval.** Name the exact four migrations and three function updates. Approval must not silently include provider setup, payouts, secret/billing changes, data cleanup, web publication or app installation.
4. Recheck time-sensitive history/function revisions/load/advisors immediately before application; apply database first, independently verify, then deploy only the three reviewed functions with their individual auth settings.
5. Read-only deployed smoke checks, separate web publication, device operational/Keychain/notification acceptance, provider-readiness/financial acceptance and Merchant distribution remain distinct.

No evidence from this preflight alone marks Merchant wrapped or any of its new hosted features live. Supabase's migration-history/deployment guidance and the skills' privilege/locking guidance shaped the exact pending-set check and non-mutating inspection: [migrations](https://supabase.com/docs/guides/deployment/database-migrations), [Edge deployment](https://supabase.com/docs/guides/functions/deploy).

Temporary logs use `/tmp/dastak-merchant-preflight-*-20261019.*`. The permanent evidence omits raw function bodies and sensitive connection material, retaining source references/hashes, scoped metadata, deployment versions and explicit verification boundaries. No containers or simulator were started for this preflight; no personal/Codex/ChatGPT files were cleaned up.
