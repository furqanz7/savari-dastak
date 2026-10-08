# Reimagined headings, account behaviour and Food panel

Local implementation after the owner's 9 October duplicate-heading screenshot and report of confusing Profile/Settings behaviour. Guarded branch `codex/dastak-v1-launch`, starting HEAD `fbb880d33c0fb82864ff2410dfa98b6595effe3f`. Existing catalogue drafts, release notes and unused staff assets preserved. No subagents, image generation, SKU/backend changes, deployment or push in this pass.

## Concrete defects fixed

- Orders rendered the shell's page heading plus another Orders heading inside the embedded old screen. Reimagined now has one Orders heading with a compact description/update status; standalone Orders keeps its original heading.
- Profile and Settings retained the previous panel's scroll position. Reproduced on the live release: Settings scroll 1029.5, then Profile scroll 341.5. Scope changes now reset panel scroll. Local browser check: Settings scroll 1409, then Profile scroll 0.
- Embedded Payments could return to a combined legacy Account inside the wrong outer workspace. Profile and Payments shortcuts now go through the outer navigation owner. Controller regression tests verify returning Payments to Profile without mounting the combined account screen. No authentication or payment contract was changed.
- Profile editing was possible before the latest profile read completed, and its failed-read message had no retry action. Editing is disabled while loading/failed, a working Retry profile action reloads the same existing read, and the editor opens with the successfully loaded details. Tested on the real CatalogueView/Profile components using mocked transport; no real profile save was performed.
- Removed competing large introductory headings in Profile/Settings. Wishlist's outer heading is now its single page heading. Food restaurant/dish names are owned by the shell rather than repeated inside the content.
- Added a medium-width wordmark spacing rule and removed the browser's unbranded focus outline around the entire main panel; interactive controls retain visible focus outlines.

## Food presentation changes

- Restaurant cards with clear names, actual descriptions when available, open/closed status, truthful distance and menu action. Two desktop columns become one compact column on smaller screens.
- Menu categories and compact dish cards, explicit prices, option prompts and touch-sized actions. Back/Refresh share one toolbar instead of consuming separate rows.
- Dish title follows the selected item. Option groups have clear selected states and readable price review; required options still block Add.
- Cart lines show dish/restaurant/options, exact estimates, quantity controls and removal. The existing last-item removal behaviour returns to browsing; Grocery remains untouched. Empty retained carts do not offer checkout.
- Long explanatory distance text is available under a disclosure; no ratings, delivery ETA, product photos or availability were invented. Existing real menu image keys are still used; synthetic previews intentionally have image fallbacks.
- Closed restaurants remain visible and disabled. Offline/read-only/other-restaurant/quantity guards, exact option IDs, Wishlist actions and server-calculated checkout remain intact.

## Verification

- Final full suite: **138 files, 931 tests passed**. Focused account/navigation/Food suite: 93 tests passed.
- TypeScript and final Vite production build passed. Existing oversized 3D chunk warning remains. Targeted ESLint and `git diff --check` passed.
- Local browser: Orders has exactly one visible Orders heading; Profile/Settings switching resets panel scroll; Food restaurant/dish/cart titles each have one page heading. Desktop restaurant cards checked at 1280×900, phone cards at 390×844 and menu/cart at 320×740.
- Food category jump scrolled the panel (217.5) without scrolling the page (0). Required Large option changed the estimate from ₹150 to ₹180; adding/reviewing/continuing retained the synthetic item. The 320px menu/cart panel had client width and scroll width 255, page width 320: no horizontal overflow.
- Live browser use was read-only to reproduce the original scroll bug. Local browser fixtures use synthetic content and inert backgrounds. Account loading/retry and navigation were exercised through real components with mocked resources, not claimed as live account-save or OAuth verification.

Proofs: `docs/verification/dastak-panel-polish-2026-10-09/` contains orders-single-heading-390.jpg, food-menu-320.jpg, food-cart-320.jpg and food-restaurants-desktop.jpg. Preview: http://127.0.0.1:5187/reimagined-food-check.html.

## Boundaries

These fixes are **not deployed**. No real cart, account, stock, order or payment changes were made. Background/staff redesign and SKU work remain paused. The owner did not identify a particular failing account write; this pass fixes the concrete reproduced/source-tested defects, not an unsupported claim that every possible Profile/Settings bug is eliminated. Physical phone keyboard, authenticated saves and destructive account controls remain untested.
