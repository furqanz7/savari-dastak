# Checkout fee production release — 9 October 2026

User explicitly approved applying the fee migration and deploying the pricing API
and Customer checkout. Solo release; no paid AI, subagents or test orders.

## Released

- Commit: `427a4d89622c0831ab62bf7b3a989bfd60c2ab99`.
- Linked Supabase project: `zmtsolkfxlrxepshnjdf`.
- Applied ONLY `20261009111558_checkout_fee_quotes.sql` using isolated migration
  staging. Dry-run listed exactly this migration before application.
- The unrelated pending `20260929191745_activate_reference_catalogue_browse_map.sql`
  was excluded, and its absence in production migration history was rechecked.
- Deployed ONLY `dastak-v1-catalogue` through Supabase's API bundler, retaining
  the configured in-handler bearer verification and existing CORS behavior.
- Customer production deployment: `dpl_AnEm1Ecrm3igACAEUqoXVk9bHd9t`.
- Normal URL: <https://dastak-customer.vercel.app/>.
- Vercel release script verified production environment, Customer variant,
  release SHA, deployment ID and security headers. Browser refresh independently
  returned the same SHA, variant and production environment.
- Existing unrelated edits were not staged or released. Unused RPM staff assets
  were excluded by the established web deployment script. No Git push performed.

## Live read-only verification

- Delivery tariff boundaries: 0/1000m -> 1500 paise; 1001/2000m -> 2000;
  2001/3000m -> 2500; 3001m -> 3000.
- For 10000-paise items, corresponding platform fees: 230/240/250/260 paise.
- Half-paise rounding: 2% of 25 paise -> 1 paise.
- Real production PostGIS and eligible inventory executed the pickup selection
  and distance helpers for one existing merchant-origin route: 0m -> 1500 paise.
  This is native spatial execution, not a customer checkout or road-distance test.
- All 41 existing orders retain pricing version 0. New-order column default is 1;
  immutable version trigger is present.
- Snapshot counts remain SUBMITTED 41, FULLY_SECURED 27, PAID 16. Migration does
  not update those snapshots. Historical amounts were not recalculated.
- Quote RPC installed; authenticated execution allowed; anonymous access and
  customer execution of private pickup helpers denied. Unauthenticated public
  quote actually rejected by the customer guard.
- Supabase security advisors at error severity returned no issues, before and
  after release. This is not a claim of a complete database security audit.

## Verification limits

The signed-in verification browser has an empty Grocery basket and currently
shows no available delivery partner in the selected area. No cart items, saved
addresses, merchant stock, partner state, orders, reservations or payments were
changed to manufacture a test. Numeric fees in an actual live customer checkout
and collection of a new real order remain untested.

Local evidence is recorded in `dastak-checkout-fee-fix-2026-10-09.md`: 1,032
frontend tests, 32 API-handler tests, SQL fee contract, TypeScript and build.
That report's original not-deployed status describes the pre-release checkpoint;
this receipt records the subsequent authorized production activation.

For manual verification, refresh the normal Customer address, open a basket with
available items, select a saved address, and open Delivery & billing. Confirm
separate Delivery, Platform fee (2%) and Estimated total rows. Platform fee is 2%
of items plus delivery. Stop before order confirmation if only checking display.
