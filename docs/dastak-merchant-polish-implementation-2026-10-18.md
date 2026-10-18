# Merchant native visual and interaction polish

18 October 2026. M-13 local implementation follow-up to the [completion audit](dastak-merchant-completion-audit-2026-10-18.md). This is a focused operational design pass, not a Merchant release or full accessibility sign-off.

## Scope and guard

Solo work in `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, unchanged HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`.

Earlier M-01–M-12 changes, the five Customer screenshot-fixture files, generated dependency lockfile change, artwork and release/evidence documents were preserved. No new backend/web implementation, migration, production request, deployment, commit/push, physical-phone installation, Apple configuration, authenticated order/menu action, photo upload, payment or payout was performed. Only local simulator apps and isolated static sample data were used for visual checks.

## Design changes

`DastakMerchantDesign.swift` supplies Merchant-only components. Shared Customer/Delivery styles were not changed by this slice.

- Orders, Kitchen and Earnings use consistent editorial headings: the existing bundled Instrument Serif with Dynamic Type, a small bronze service label and a restrained separator. The operational location name remains in the persistent location context rather than being repeated in the hero.
- Orders has separate New / Preparing / Ready summary tiles. They select the existing queue; the large-text version stacks vertically. Queue chips are at least 44 points high; accessibility sizes use a native menu, and an externally selected chip is brought into the horizontal rail without resetting the main order scroll.
- Incoming and fulfilment cards place full-order navigation inside the card. Existing exact record/location targets, account checks and the separate detail endpoint remain unchanged. Historical/recovery/return detail links use the same 48-point control.
- Incoming confirmation cards still show **every item** before stock/preparation confirmation. Already-accepted fulfilments initially summarize three lines, with a local Show all / Show fewer control. No item is removed from the DTO or hidden behind another network request.
- Card headers, prices, preparation controls, action groups and location controls stack at accessibility sizes. Package direct entry is full width with a separately labelled native stepper rather than squeezing a text field inside the stepper label.
- Merchant primary/secondary buttons wrap long labels, retain a minimum 48-point content height plus padding, show disabled state, and use a small press transition only when Reduce Motion is off. Existing destructive roles, confirmation dialogs, disabled capability checks and action handlers are preserved.
- Menu fields move behind Edit dish details; unsaved and review-needed indicators remain outside the disclosure. Drafts still live in the existing versioned store, not view-local text copies. Category headings/actions adapt rather than forcing a horizontal row.
- The restaurant banner editor now uses the existing landscape restaurant-banner renderer at full available width, with its photo action below the description. Compact dish photos retain their smaller layout. Image processing, MIME/size checks, versions, upload callbacks and journal ownership were not changed.
- Catalogue accessibility layouts use one product column. The older fixed-width side-rail browser becomes labelled Category/Type menus at accessibility sizes. Search/filter/pending-selection semantics and loaded-data/truncation boundaries remain intact. Store headers, operating panels and the pending-selection bar adapt; tiny operating buttons were enlarged.
- Orders, current Store/menu, Earnings and full-order navigation stacks gain interactive keyboard dismissal and an explicit Done keyboard action. Large fixed bottom padding was removed from the restaurant menu; native tab and safe-area management remain responsible for the actual inset.
- Location discovery's non-critical explanation is a disclosure. Pending-selection/recovery restrictions and current load failures remain visible. A journal recovery notice keeps the lock/uncertainty summary and original-retry button visible; lengthy original-action context opens in its own scrollable sheet instead of expanding the persistent top inset indefinitely. Journal data, retry rules, keys, actor/location ownership and cleanup were not altered.
- Merchant navigation, queue changes and selected critical controls use the existing coalesced foreground-only haptic mechanism. Merchant has its own `dastak.merchant.hapticsEnabled` preference and Touch feedback toggle in Account, separate from Customer's preference. This is not a claim that every retained legacy button now emits a haptic, and a simulator cannot establish physical feel.

## Local component gallery and native observations

`DastakMerchantDesignPreview.swift` provides explicit DEBUG-only local sample content. The app entry bypass is additionally limited to the **Simulator** and the `-DastakMerchantDesignPreview` launch argument. The normal authentication/access-gated workspace remains the default. No release-mode or physical-device authentication bypass was added.

The sample uses the actual heading, summary, queue, incoming card, fulfilment card, media picker and button components. It is **not** a complete signed-in Merchant-root fixture: it does not exercise the real location model, journal/recovery model, all four tabs, authenticated detail endpoint, menu draft reconciliation, live photo picker/upload or account preference screen.

Observed through Device Hub on the existing iPhone 17 Pro simulator:

- Dark Orders heading, summary tiles, queue rail and incoming content rendered.
- Selecting Preparing from its summary tile selected the Preparing queue.
- Show all 4 items exposed the fourth line and changed its accessible state to Expanded.
- Package decrement changed 2 → 1 on one activation; increment then restored 2.
- View full order activated the sample's read-only feedback destination. This proves the control activation only, not a live detail read.
- The initial incoming Accept control remained disabled before physical confirmation. Enabling/tapping that acceptance was not completed in this interaction check.
- Field focus brought the package input into view. Hardware-keyboard mode did not display the software keyboard, so a software-keyboard safe-area pass is **not** claimed.
- Light Store and accessibility-size Orders captures were inspected. The heading scales and wraps without a fixed-height clip. This is not coverage of every lower-screen accessibility control.

Device Hub's scroll command repeatedly returned `noWindowsAvailable`, although several accessibility activations and field-focus scrolling worked. Further native inspection was intermittent. The iPad simulator stalled during startup; it was stopped and restored to its initial shutdown state. Its screenshot shows startup/Home, **not** a successful Merchant screen. No iPad appearance or interaction pass is claimed.

[Evidence index](verification/dastak-merchant-polish-2026-10-18/README.md).

## Automated verification

Three tests were added: heading wrapping at a constrained width, button minimum height/long-label wrapping, and local sample integrity (all four unique lines, reconciled product subtotal, no Ready capability or pickup code). The rendering tests run on macOS; macOS does not implement iOS Dynamic Type scaling. They deliberately test width/wrapping, while the iOS accessibility-size capture supplies the separate scaling observation.

| Check | Result |
| --- | --- |
| Full DastakUI hosted package | 697 tests passed, zero failures |
| MarketplaceDesignSystem package | 8 tests passed |
| Merchant generic iOS Simulator Debug build | BUILD SUCCEEDED, signing disabled |
| Whitespace and branch/HEAD guard | Passed; unchanged |

Logs: `/tmp/dastak-merchant-polish-ui-final.log`, `/tmp/dastak-merchant-polish-design.log`, `/tmp/dastak-merchant-polish-ios-final.log`.

An initial rendering assertion incorrectly expected macOS to scale iOS Dynamic Type. It failed, was corrected to a platform-appropriate narrow-width check, and the final full suite passed. Xcode retains its App Intents metadata warning because Merchant has no App Intents dependency. macOS helper/Contacts diagnostics appeared during hosted rendering; no address book was inspected or changed as part of this slice.

## Remaining acceptance and independent gaps

Still separate: signed-in Grocery/Food full-workspace navigation, saved-action/location banners with long real content, software-keyboard behavior on a physical phone, reliable gesture scrolling/retention, every large-text form/control, VoiceOver reading/activation, Reduce Motion/contrast/transparency combinations, physical haptic feel, iPad layouts and actual full-order/media endpoints. No production workflow pass is inferred from static gallery actions or the build.

M-05/M-10 migration/Edge activation, complete location enumeration and catalogue search beyond the existing cap, native financial-action parity, broader category/group editing and M-12 live notification acceptance retain their prior documented status. This pass does not close those items or Merchant distribution (M-14).
