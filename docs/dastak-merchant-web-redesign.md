# Merchant Web operational redesign

## Scope

Presentation and interaction changes for Merchant Web only. The finished Customer Web design system supplies the palette, type assets, controls, notices, skeletons, empty states, profile editor and modal focus management. Merchant keeps its own operational shell, density and screen composition. Merchant iOS supplies preparation-choice and handoff workflow references.

No backend, schema, permissions, fulfilment rules, payment semantics, iOS code or other application's behavior changed. Shared Account and Earnings components opt into Merchant presentation; their other role branches remain unchanged. No new runtime dependencies were added; jsdom is development-only component-test infrastructure.

## Delivered surfaces

- Orders-first desktop sidebar and mobile bottom navigation: Orders, Store, Earnings, Account. Keyboard navigation has visible focus, a skip link and content focus on section changes. Inactive sections unmount.
- Authorized branch context remains visible across sections with the same account-scoped persistence and server permissions.
- All / New / Preparing / Ready / History queues retain their lifecycle counts. Incoming kitchen, recovery and retail requests precede fulfilments in both DOM and visual order.
- Operational cards separate order identity, quantities, exact selections, timing, payment-at-delivery information and actions. Countdown clocks remain small isolated components; parent cards wake at their expiry boundary rather than every second.
- Restaurant requests use Merchant iOS's bounded preparation choices, exact-selection confirmation, soft kitchen-capacity warnings and a reasoned decline confirmation dialog. The dialog traps/restores focus, respects pending mutations and retains the reason after failure.
- Preparation is visibly organized into package count, preparation photo and irreversible Ready confirmation. Existing server capability flags remain the action gates. Assigned-rider maps, pickup verification codes and custody information remain connected to their existing projections.
- Orders uses quiet automatic synchronization status and scoped recovery notices instead of a dominant Refresh action. Existing feed isolation, concurrency reconciliation, session recovery, fallback and realtime code is retained.
- Retail Store has readable product cards, stock summaries, clear pending selections, bounded pages, document-level catalogue scrolling and a mobile subcategory selector. Product detail retains swipe/picker/stock behavior and adopts Dastak tokens with desktop paging controls.
- Restaurant Store has labeled fields, local menu search and native disclosures for creation and options. Search does not unmount dirty drafts. Existing version reconciliation and mutation keys are unchanged.
- Earnings has clearer balance hierarchy and a secondary balance check. Account has a restrained identity card, shared profile form, accessible detail dialogs and the real notification controller.
- Light/dark colors share Customer tokens. Responsive zero-minimum grids, readable inputs, reduced-motion and forced-color rules are Merchant-scoped. The Merchant entry explicitly imports the shared palette before its layout so it does not depend on Customer being visited.

## Verification and limits

The complete repository Web gate runs clean installation, production dependency audit, all tests, lint and TypeScript/Vite builds for Customer, Delivery, Merchant and Admin. The redesign adds 18 regressions, including mounted React tests for request actions, keyboard focus, server capability gates, expiry, menu drafts, branch persistence and inactive-section unmounting. Existing Customer contrast tests also validate the shared light/dark palette; their layout-isolation check permits only token sharing.

Browser, simulator and iPhone testing is deliberately not performed under the owner's standing restriction. Responsive stylesheet and DOM tests do not constitute rendered visual verification. No live orders, stock, evidence, accounts or payments were mutated for testing.

When browser checks are authorized, verify real content at 320/375/768/1024/1440 px in both color schemes, keyboard/zoom behavior, mobile safe areas, product swipe, file selection, offline notices and live pickup maps.

## Release

Commit and push the reviewed Web changes, then deploy only Merchant using `bash scripts/deploy-dastak-web.sh merchant --production`. Verify the production alias, deployment READY status, metadata commit SHA, HTML and referenced assets. No migrations or Edge Function deployments are required. Record deployment details in the task's release response.
