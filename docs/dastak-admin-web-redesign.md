# Dastak Admin Web — UX release review

Baseline: `d7d880f85fa18dbcdc82862879eeee3a09c245d3`. Scope is presentation and interaction only. No database, Edge, permission, product-data or financial changes.

## Audit before implementation

Reviewed every existing workspace: Overview, Live orders and execution trace, Approvals, Exceptions, Safety, Merchant governance, Rider governance, Customer recovery, Network, Catalogue and exact-SKU imagery, Audit History, Finance/payouts, legacy history, System health, Admin access and My account. Reviewed their loading/error/empty states, shared runtime, pagination, confirmation and modal code, and the Customer/Merchant/Delivery style references. Production was inspected read-only.

The main problems were an oversized duplicate application header/hero, 16 navigation peers distributed between separate mobile strips, 8–11px operational text, repeated nested card borders, inconsistent control heights and status treatments, catalogue filters in a fixed-width mobile scrolling strip, nested catalogue viewport scrolling, and long undifferentiated trace output. The SKU editor lacked the shared focus-management behavior. Privileged dialogs preserved the right safeguards but needed clearer identity/state hierarchy and reachable actions on short screens.

## Design and information architecture

- A single Admin-scoped presentation sheet uses the Dastak wordmark/system type pairing and semantic surface, text, accent, warning, destructive and success tokens. Warm light surfaces and restrained charcoal/olive dark surfaces retain the product identity without the previous large gold panels.
- Main text is 14px; dense metadata is normally 12–13px; mobile editable controls are 16px. Controls share 42px minimum height, 8px radius and visible keyboard focus. Record surfaces use a restrained 12px radius.
- Navigation groups: **Daily operations**, **Marketplace**, **Oversight**. All 16 existing workspaces and action handlers remain. Small screens use one focus-managed complete workspace drawer rather than two competing strips.
- One page header identifies the workspace and its responsibility. Subscription status is secondary. Navigation changes move keyboard focus to the new heading and reset page scroll, without replacing runtime infrastructure.

## Page-level changes

| Area | Presentation changes |
| --- | --- |
| Overview | Compact action-led overview, grouped metrics, readable action queue and fulfilment flow; six columns on large desktop, three on laptop, two on mobile. |
| Merchant/Rider governance | Strong identity and eligibility hierarchy, distinct status metadata, readable branch/work details and action footer; all custody and expected-version gates retained. |
| Customer recovery | Account identity stays visible; session/contact controls use explicit progressive disclosure. Single-session confirmation now also displays the already-reviewed session ID. |
| Catalogue | Non-scrolling wrapping filters, readable product records and long variants, document scrolling instead of a nested catalogue viewport, responsive department/rail/product layout. |
| Catalogue assets | Remain exclusively in the exact-SKU editor; primary/gallery distinction, separate reviewed-image disclosure and explicit permission-denied state. Native upload, validation, storage, authority and mutation logic unchanged. |
| SKU editor | Shared focus-managed dialog, contained header, no inherited negative-margin overflow; full record fields remain available. |
| Audit History | Dense but readable timeline rows, aligned actor/resource/reason/change fields, responsive filters and long IDs. Existing sanitization and cursors unchanged. |
| Live orders | Balanced list/detail proportions. Trace sections use native disclosures; diagnostic sections start collapsed, operational sections remain open. No trace information or actions removed. |
| Approvals/Exceptions/Safety | Consistent density and controls, explicit visible pause scope/ID/reason labels, readable review actions. Existing committed-work semantics clarified in copy. |
| Finance/legacy history | Payout terminology and aligned records; legacy rows expose column/cell semantics and mobile field labels. Financial behavior unchanged. |
| Access/Account/Health | Reduced panel chrome, cohesive status/identity hierarchy and control spacing. Existing account/access and monitoring controls preserved. |

## Privileged action and accessibility safeguards

The same Group A2 action framework continues to own intent, expected versions, stable idempotency, reconciliation, reason validation and double-submit prevention. Confirmations retain exact entity, current/resulting state and consequences. The scrolling body is separate from the action footer. Cancel remains the initial focus. “Other” is explicitly labelled as requiring detail; it was already required by the validation logic.

The shared modal hook has an **opt-in** layered mode used by Admin record/confirmation dialogs. Only the top layer handles Escape/Tab. Closed disclosure fields are excluded from the focus loop. Reference-counted scroll/inert ownership handles simultaneous unmount during session recovery. Existing non-Admin modal behavior remains the default. Tests cover focus return, both-layer cleanup and cancelling without mutation.

Additional improvements: skip-to-workspace link, current-page navigation semantics, complete drawer keyboard support, form labels, table cell/header semantics, visible focus, no required animation and reduced-motion rules.

## Verification

Full suite: **78 files, 472 tests passed**. Includes nine added interaction/presentation tests across `admin-design-interactions.test.tsx` and `admin-governed-design.test.tsx`, plus all existing Admin authority/runtime/contracts and shared web regressions. ESLint and TypeScript production build gates pass. All four Dastak variants are built; only Admin is deployed.

Production negative authorization preflight: all six read-only Admin requests (access, Audit History, Merchant governance, Delivery Partner governance, Customer recovery and catalogue page) return HTTP 401 / `authentication_required` without an authenticated session. No production identities, permissions or records are modified by these checks. Authenticated non-Admin role mutation testing is not claimed for this presentation-only release.

Browser checks use the running real React components in an isolated local fixture and read-only production inspection. Local viewport checks cover 1920, 1440, 834 and 390 CSS pixels, light/dark appearance, reduced motion, all navigation destinations, populated and empty records, loading/failure/denied responses, catalogue long names, recovery and image confirmations, Escape/focus return and scroll recovery. The responsive checks found and repaired an inherited mobile flex filter strip and negative SKU-header margins. No tested page or SKU/confirmation dialog retained horizontal overflow after correction.

`Web/MarketplaceWeb/verification/admin` is a serve-only fixture. It uses fictitious local data, blocks all real fetch requests and never writes catalogue/database records. It is not a production entrypoint. Run from the Web folder with `npx vite --config verification/admin/vite.config.ts`, then open `/verification/admin/index.html`. Optional `?state=empty|loading|failed|denied` exercises feed states. This fixture is not a backend/authorization test substitute.

## Release boundaries and limitations

- Deploy via the existing `scripts/deploy-dastak-web.sh admin --production` process after commit. Verify exact production HTML SHA, variant/environment/deployment metadata and security headers.
- Production privileged actions are reviewed and cancelled, not executed against genuine customers, merchants, riders or catalogue data for visual testing.
- No database migrations or Edge deployments are required; existing permission tests and backend architecture are unchanged.
- Chromium responsive runtime is verified; physical Safari/iPad/iPhone and screen-reader certification are not claimed.
- Existing production monitoring findings and catalogue QA backlog remain operational data, not defects fixed or suppressed by this visual release.
