# Merchant category/choice editors and persistent local drafts

18 October 2026. Local M-07/M-08 follow-up to the [first menu-editing slice](dastak-merchant-menu-editing-implementation-2026-10-18.md) and [completion audit](dastak-merchant-completion-audit-2026-10-18.md). This closes the native editor/draft work described here, not Merchant release or device acceptance.

## Scope and guard

Solo work only in `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, unchanged HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`. Earlier Merchant changes, Customer screenshot fixtures, dependency-lockfile changes, artwork and release/evidence documents were preserved.

Native code, local tests and documentation only. No new backend/web implementation, migration, production query, deployment, push/commit, Apple change, phone installation, real menu/stock/order mutation, upload, payment or payout was performed. Supabase guidance was used to verify the existing authenticated/versioned command rather than introducing client-side authority or a privileged transport. The existing user-token/permission boundary is retained; see [official Edge authentication guidance](https://supabase.com/docs/guides/functions/auth).

## Editors

- Categories now have a disclosure editor for name, description and numeric display order, plus explicit Save, Discard and Hide/Activate actions. Description is bounded to 500 characters. Smaller order values appear first; equal values retain the backend's stable order. This is per-entity versioned ordering, not an atomic drag-to-reorder batch.
- Existing choice groups now edit name, SINGLE/MULTIPLE selection, minimum, maximum and display order. Minimum 0 is optional; a positive minimum is required. A SINGLE group must have maximum 1. Minimum/maximum and signed display-order values are validated against the server's integer bounds. New groups still start optional; after adding options the existing group editor can make a choice required.
- The choice editor displays active-option count and explains that customers must be able to satisfy the minimum using active options. It does not invent a new server policy that forbids saving a temporarily incomplete configuration; configuring required rules with insufficient active options can make that dish unorderable until corrected. Signed-in commerce acceptance remains necessary.
- Category/group availability no longer bypasses retained editor drafts. Saving or explicitly discarding dirty fields is required before Hide/Activate. A new server version stops both edit and availability commands until the exact latest record has been reviewed.
- Existing dish/extra editors retain their price/media safeguards. The shared field editor now displays category/group-specific names, rule/order review details and appropriate Save/Hide labels. Commands retain the exact entity, parent, selected location and expected version; no item/group reparenting was added.
- New category/dish forms now belong to the workspace draft store, alongside new choice/extra forms, instead of view-local `@State`. Filtering, navigation and lazy view recreation do not erase them. A new-dish draft whose category disappeared is retained with visible guidance, not silently retargeted.

The existing server contract already supports these category/group fields through `upsertRestaurantMenuEntity`. No new migration or Edge deployment is needed for this slice. Backend constraints and actor/branch/version checks remain authoritative. Web category/group editors were not implemented in this native slice; dish display ordering/reparenting is not invented where the current dish contract does not expose it.

## Local draft persistence

`DastakMerchantMenuDraftStorage.swift` adds Merchant-only, account-and-location-scoped archives. The normal Merchant root explicitly supplies file storage; model/test factories can keep isolated in-memory drafts.

- The archive contains dirty/review-needed entity records, new choice/extra forms and the category/dish composer. Clean full-menu snapshots, image bytes, credentials and action-journal payloads are not copied into this file.
- Archives are loaded only after a successful menu read with matching actor identity before and after the request. Fresh version/media/parent reconciliation occurs before restored fields can form a command. Missing entities remain copyable but unsaveable; changed entities require review. Restoration never automatically sends a mutation.
- Local path is the app's Application Support `DastakMerchantMenuDrafts` directory, with account/store UUID filenames. It is not an app-group/shared container. Writes are atomic, directories/files use `0700`/`0600`, backup exclusion is set, and the iOS code path uses complete-until-first-authentication file protection. This is OS-protected local JSON, not a claim of custom encryption or runtime verification of locked-device file access.
- Reads/writes are bounded to 2 MiB and 2,000 retained entity records plus 2,000 addition forms. Bad format, mismatched owner/location, invalid entity identity or excessive size fails visibly. The code never truncates a draft set to make a write appear successful.
- Revisions prevent a stale second workspace silently overwriting newer drafts. Unchanged reconciliation does not churn revisions; the archive revision is still checked before a critical flush. A storage conflict/failure leaves in-memory typing intact and displays that it is not safely stored yet.
- An unreadable archive is left untouched, not overwritten with an empty menu. Explicit read retry is available when it cannot replace new typing. Otherwise the user can copy text and explicitly discard local drafts for this account/store. A failed write can be retried without discarding fields.
- Discard is confirmed, store-scoped and independent of the saved-action journal. It remains available between saved-command attempts, even when an unreadable archive blocks draft cleanup. The live menu, other stores and the immutable saved command are not deleted by that action.
- Switching account/location clears presentation but preserves the corresponding isolated archive. Drafts remain local until explicitly discarded or app data is removed; this is not a cloud draft sync or a claim that Merchant persona deletion has been acceptance-tested to purge every local archive. That retention/deletion check remains part of Merchant distribution/privacy acceptance.

## Creation and recovery safety

The existing SQL creation routine includes the entity ID in its idempotency request hash. Letting SQL generate a different ID on each retry cannot establish an equal request hash. Newly secured native creation commands therefore retain a creation UUID **before the first request** in the protected restaurant command, and send that same target UUID with the same actor/location/key/version/payload on replay. This uses the existing optional entity-ID contract; it adds no backend privilege or schema change.

The optional `creationEntityID` field is backward-decodable. Existing old journals are not rewritten: an unresolved pre-change creation journal with no retained ID still has its original request semantics. This does not claim to repair old null-ID server receipts or silently adopt a newly generated target for an uncertain old action; any such pre-existing journal needs its authoritative outcome resolved before upgrade acceptance. No live journal was inspected or altered here.

After a confirmed menu response, only matching submitted edits/new-entry forms are reconciled. Later local typing survives. Clearing the persisted form must succeed **before** removing the immutable saved command. If local draft storage fails after server success, the original journal remains recoverable. A relaunch/retry uses that original command rather than permitting a duplicate-ready creation form as new work. The controlled receipt fixture verifies this lost-acknowledgement/relaunch path without creating a real category.

## Verification

| Check | Final result | Boundary |
| --- | --- | --- |
| Full DastakUI package | **731 passed**, zero failures | Includes 17 new tests; 40 menu-draft tests in total. macOS-hosted tests, not native touch acceptance |
| MarketplaceInfrastructure package | **189 passed**, zero failures | Existing transport/model regression suite |
| Full Edge test directory | **380 passed**, zero failures | Existing and prior-slice fixtures; no backend source change this slice |
| Merchant generic iOS Simulator Debug build | **BUILD SUCCEEDED**, signing disabled | iOS compilation, not installation/visual acceptance |
| Whitespace / branch / HEAD guard | Passed; unchanged | Existing unrelated changes preserved |

New coverage: category and choice command fields/validation; required and SINGLE/MULTIPLE limits; exact-version conflicts/review; all draft kinds and composers across relaunch/account/store changes; missing-entity/current-version restoration; matching creation cleanup versus later typing; file size/format/owner/mode checks; failed read/write retry; concurrent workspace protection; store-only discard; saved-command retention after cleanup failure; creation ID/key/payload stability across lost acknowledgement and relaunch; old-journal decoding; account change during a fresh menu read; and safe read retry without replacing new typing.

An initial concurrent-workspace test caught unnecessary revision churn during unchanged reconciliation. That was corrected, and the final full suite passed. Hosted SwiftUI rendering emits existing macOS helper/Contacts diagnostics; these are not test failures or a claim of address-book acceptance. No contacts workflow was used as part of this feature.

Logs: `/tmp/dastak-merchant-menu-completion-ui-final.log`, `/tmp/dastak-merchant-menu-completion-infra.log`, `/tmp/dastak-merchant-menu-completion-edge.log`, `/tmp/dastak-merchant-menu-completion-ios-final.log`.

## Remaining independent gates

Physical iPhone/iPad editing, keyboard, VoiceOver, large text and actual locked-device/relaunch/storage-failure acceptance remain separate, along with real signed-in required-choice/customer-order behavior. The later [native payout-controls slice](dastak-merchant-payout-controls-implementation-2026-10-18.md) implements financial setup/withdrawal/retry locally, with its own activation and acceptance gates. Earlier detail/history/discovery production activation, live notification acceptance and Merchant distribution remain open. No migration, deploy, push or device pass is inferred from these tests.
