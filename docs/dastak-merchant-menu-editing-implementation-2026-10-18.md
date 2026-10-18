# Merchant native menu editing — search, extras and retained drafts

18 October 2026. M-07/M-08 implementation follow-up to the [Merchant completion audit](dastak-merchant-completion-audit-2026-10-18.md). Source/local verification only; not a release or device sign-off.

**Later follow-up:** [Category/choice editors and persistent local drafts](dastak-merchant-menu-completion-2026-10-18.md) adds native category/group fields and ordering, required-choice rules, account/store-scoped relaunch persistence for edits and new-entry forms, and stable new-creation targets. This report preserves the earlier in-memory slice and its test counts; its native category/group/persistence gaps are no longer unimplemented. Backend activation of independent features and signed-in/device acceptance remain separate.

## Scope and guard

- Solo work in `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`.
- Continued the previous uncommitted Merchant work. Existing Customer screenshot fixtures, release/evidence/artwork files and Xcode-generated lockfile change were preserved.
- Native menu editor/model changes and local tests only. No web/backend contract, migration, production read/write, deployment, push/commit, iPhone installation, Apple submission, real menu/order/payment or payout change.
- The Supabase skill guided verification of the existing authenticated/versioned menu command and server field constraints. The existing backend actor/permission checks, immutable command journal, versions, owned media-upload paths and idempotency keys remain the security/recovery boundary.

## Implemented

### Search

Search the loaded restaurant menu by category name/description, dish name/description, choice-group name or extra name. Matching a category shows its dishes; matching a dish/group/extra shows the matching dish. Hidden entries remain searchable so they can be reactivated. Empty and matching-count presentation distinguish no match from an empty menu. Filtering does not mutate the menu or discard draft fields.

Search is over the current loaded menu, not a new server-search or pagination contract. Newly typed unsaved names are retained in the draft store but the search matches the server's menu snapshot.

### Existing extras and new multiple-choice limits

- Edit an existing extra's name and additional price, including a zero-price option, and save against its exact option ID, group ID, store ID and captured version.
- Hide/reactivate existing extras without deleting or duplicating them. Availability changes do not implicitly save dirty name/price fields: save or discard those fields first.
- New MULTIPLE choice groups have a whole-number maximum field rather than hardcoded 20. New SINGLE groups always send maximum 1. The server's positive 32-bit integer domain is respected; new groups remain optional with minimum 0. A maximum does not create options or require customers to select the maximum.
- Existing group hide/reactivate behaviour remains, with its existing selection constraints preserved. Editing existing group names/requiredness/limits or category/group reordering is not added or claimed as web parity by this slice.
- Menu-specific price parsing now rejects partial numeric strings, exponent/currency text and more than two decimal places. Invalid dish/extra values and new-group maxima disable the save and display guidance. The existing local price cap remains unchanged.

### Stable in-memory drafts and explicit conflict resolution

The workspace model owns `DastakMerchantMenuDraftStore`; individual dish/extra rows no longer own the only copy of edits. The old dish identity keyed by entity/media version has been removed. Drafts and new choice/extra fields survive same-location refresh, search filtering and lazy view recreation while the model remains alive.

- Clean drafts adopt current server fields.
- Dirty drafts retain name/description/price if entity version, media version, parent, status or other write metadata changes. They retain their original expected version; saving/availability changes are blocked.
- The editor shows retained text, latest server text/price/status and version/media-version information. “Use latest” is an explicit discard. “Keep my text after reviewing latest” explicitly rebases the text against the reviewed latest metadata and requires a later Save tap.
- Review confirmation captures the reviewed source. If the server changes again before confirmation, the review is refused and must be repeated. It does not silently accept the third version.
- Rebased dish writes preserve the latest image key, category, tax, logistics and availability metadata rather than sending old hidden metadata with a new version.
- Out-of-order older source versions cannot roll back the latest draft/conflict context.
- A matching, durably acknowledged save resets its draft. An acknowledgement cannot erase later local typing or a different payload. A timeout retains the original protected command/payload/key and blocks replacement work, as before.
- Acknowledged/recovered choice/extra creations clear only the matching new-entry form, including when the originating view callback is gone; different later text is retained.
- If an entry or parent disappears, dirty fields remain in a copyable unavailable-draft section, without a save path, until explicitly discarded. Draft counts include entries hidden by search.
- Account/location-context reset clears the store to prevent cross-account/location reuse. This continues the previous explicit location-switch behaviour, not cross-location draft persistence.

These are **in-memory drafts**, not crash/relaunch persistence. The screen says so. Submitted uncertain commands remain independently durable in the existing journal; unsent text does not. New category/dish creation fields retain their existing menu-view lifetime, while choice-group/extra additions use the workspace store. Photo replacement is paused while local dish text is dirty; remote photo changes retain the text and require review.

## Verification and limits

Added 23 tests covering clean/dirty refresh, entity/media conflicts, explicit keep/discard, a changed review, out-of-order reads, matching versus late acknowledgement, removed entries, location/account reset, category/dish/group/extra search including hidden dishes, retained additions, status controls, exact option payload scope, custom maximums, invalid prices/names/descriptions and acknowledged creation forms.

Three of those tests exercise the actual Merchant model and existing typed transport with controlled function responses: existing-option save/acknowledgement, rejection of an old version until explicit review, and timeout/exact-key-and-payload replay without replacement writes. They are not live endpoint or native tap tests.

Final verification after all source/copy changes:

| Check | Result | Boundary |
| --- | --- | --- |
| Full DastakUI package | 633 passed, zero failures | Includes all 23 new menu tests; macOS-hosted package/model tests, not tap-through |
| Full MarketplaceInfrastructure package | 189 passed, zero failures | Existing infrastructure regressions |
| Existing catalogue Edge-function suite | 32 passed, zero failures | Controlled handler fixtures, not live menu mutations |
| Focused existing web regressions | 4 files / 68 passed, zero failures | Menu drafts, operations, Merchant interactions and V1 transport; web source unchanged |
| Final Merchant Debug generic iOS Simulator build | BUILD SUCCEEDED, exit 0, signing disabled | Compiles actual SwiftUI for arm64/x86_64 Simulator; not native interaction or device acceptance |
| `git diff --check`, branch/HEAD guard | Passed | No whitespace errors; branch and HEAD unchanged |

Earlier full recompiles retained pre-existing Customer/account haptics and Account Sessions isolation warnings; those unrelated sources were not edited. No live database validation was performed, because this slice changes neither SQL nor backend source and deliberately avoids real menu mutations.

Local logs:

- `/tmp/dastak-merchant-menu-draft-tests.log`
- `/tmp/dastak-merchant-menu-ui-final.log`
- `/tmp/dastak-merchant-menu-infra.log`
- `/tmp/dastak-merchant-menu-edge.log`
- `/tmp/dastak-merchant-menu-web.log`
- `/tmp/dastak-merchant-menu-ios-verified.log`

Still separate: simulator/physical iPhone/iPad visual, keyboard, VoiceOver and signed-in multi-client acceptance; app installation/distribution; the earlier M-05 migration/Edge activation; M-09 catalogue search/completeness and M-10 active/history discovery; broader M-11 media/HEIC/error feedback; remaining Merchant notifications/polish/distribution items. No complete Merchant or financial-action sign-off follows from this slice.
