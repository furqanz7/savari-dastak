# Food discovery and mixed-order rebuild — 2026-10-08

## Implemented

- Added a bounded cursor-page restaurant RPC and catalogue Edge operation. The original capped RPC remains unchanged for older app versions. New pages preserve the live function's customer assertion, active merchant/branch/zone checks, open-state visibility, menu visibility and operational-pause controls. Orders-paused restaurants remain discoverable while checkout eligibility stays authoritative.
- Each page reads at most 100 menus, with a deterministic organization-name/branch-ID cursor and an explicit next cursor. Further pages require Load more; there is no overall 100-restaurant ceiling or eager bulk download. Submitted Food searches query the server catalogue; typing still uses cached suggestions without per-keystroke requests.
- Session/query-scoped caches retain loaded menus, isolate account/token changes, cancel late requests, reject looping cursors and preserve menus on paging failure. Search failures are not presented as complete empty results. Category pagination extends exact shared-label memberships without replacing an existing selected category identity.
- Added exact branch lookup for old Food orders outside the initial discovery page. Lookup remains subject to the same public-discovery visibility rules; it does not expose private merchant data or bypass closed/paused branches.
- Mixed orders now offer Rebuild Grocery or Rebuild Food. Exact existing SKU/dish/options/quantities are reconstructed, the other service's cart is preserved, nonempty target carts require approval, and unresolved checkout attempts block replacement. Missing identities/options are not substituted. Late lookups after navigation/cart/session changes cannot overwrite shopping. No order is submitted by rebuilding.

## Verification

- An isolated local PostgreSQL cluster executed the new migration against 205 synthetic restaurants. Assertions covered all three pages, duplicate sort names, no dropped/duplicate branches, dish search beyond the first 100, exact lookup, closed/paused filtering, actor/cursor validation and anonymous execution denial. The test runner uses a private Unix socket with TCP disabled, stops the cluster and removes its own synthetic directory.
- Catalogue handler: 26 Deno tests passed, including new authenticated cursor/validation coverage. Handler and runtime entrypoint type checks passed.
- Final full web suite: 804 passed, 0 failed. Lint, TypeScript and production build passed. Focused tests cover paging, global query submission, cache/abort/retry behavior, malformed capped responses, exact mixed partitioning, approval, other-cart preservation and stale lookup rejection.
- After explicit production approval, applied only `20261007200623_customer_food_cursor_pages` to linked Dastak in one transaction with migration history. The CLI also listed an unrelated `20260929191745` catalogue-map activation; it was not replayed or marked applied. Verified both new functions are stable, anonymous execution is denied, and authenticated execution is granted. Deployed the catalogue Edge function before publishing Customer. No order, cart, inventory, account or payment data was written. No subagents or paid generation.

## Publishing dependency

The frontend now expects `customerRestaurantPage`. **Do not deploy Customer ahead of the backend.** Required order:

1. Apply the additive migration `20261007200623_customer_food_cursor_pages.sql` to linked Dastak after explicit production approval. It creates read-only discovery functions/grants; it does not update inventory, accounts, orders or payment data.
2. Deploy `dastak-v1-catalogue` with the page operation.
3. Push/deploy Customer and verify the normal address with read-only checks.

Customer publishing and read-only live checks are recorded in the release handoff. City trending, Parcel/Print and real fulfilment verification are outside this pass. Old mixed Food records still require the original restaurant identity and valid current menu/options; missing references cannot be invented.
