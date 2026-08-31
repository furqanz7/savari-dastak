- Authoritative spec paths: `docs/DASTAK_V1_CODEX_MASTER_HANDOFF.md`, then newer overrides in `docs/DASTAK_V1_LOCKED_ADDENDA.md`.
- Authoritative branch: `codex/dastak-v1-launch`.
- Source checkpoint before the Admin command-center batch: `29f8ff15f123eddbcd2f50f4116c5daa670e212a`.
- Completed V1 capabilities: full Retail, Restaurant/Cafe and mixed-order lifecycle through recovery; independent Customer, Merchant and Delivery personas; governed identity recovery; fixed Admin roles; canonical Merchant controls; transport/custody safety; append-only Royalty/platform-fee accounting; RBAC; durable notifications; invariant monitoring; and launch Web/iOS gates.
- Current launch payment: the single server-authoritative **Pay via UPI/Cash on Delivery** option across Customer, Merchant, Delivery Partner and Admin surfaces; provider checkout remains dormant for the launch path.
- Native scope: Customer, Merchant and Admin schemes plus the Delivery Partner experience housed in the Customer app; Android remains deferred.
- Previously reported production launch baseline: checkpoint `d8b67c7168c435a29697d1d515b2a9e7b1c3ebad` and its launch-payment backend/Web rollout. Any later source promotion still requires release-state verification.

## Admin command center — 2026-09-01

- Added one permission-bound command center joining action queues, identity/persona state, order and fulfilment flow, rider operations, catalogue readiness, safety signals and system health.
- Added a cursor-paginated Admin network directory connecting each canonical identity to independently onboarded Customer, Merchant, Delivery and Admin state without exposing raw private tables.
- Rebuilt Admin Web for desktop and mobile with Overview, Approvals, Live Orders, Network, Catalogue, Exceptions, Safety, Finance & Royalty, Health, historical diagnostics, account and Superadmin-only access management.
- Rebuilt native Admin iOS around Overview, Approvals, Orders/Exceptions, Network and More, with governed Catalogue, Safety/Health, Finance and Superadmin-only access workspaces.
- Added database-authoritative catalogue activation readiness, Draft-only import guidance, permission-checked paging, RLS hardening and missing foreign-key indexes.
- Full local verification passed: clean database replay; 43 pgTAP files / 1,406 assertions; 103 database security contracts; 292 Edge tests; 225 Web tests; Web lint/build/audit; 159 Swift package tests; and the DastakAdmin simulator scheme test.
- This Admin batch has not changed production. Deployment and signed-in founder UAT remain separate, explicitly authorized release steps.
