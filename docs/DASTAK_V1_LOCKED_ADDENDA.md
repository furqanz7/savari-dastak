# Dastak V1 Locked Addenda

This file records newer locked product decisions. It overrides conflicting wording in `DASTAK_V1_CODEX_MASTER_HANDOFF.md`; the master handoff remains authoritative everywhere else.

## Customer authentication

`Apple or Google OAuth → authenticated Dastak account → onboarding profile → name + phone + required details → immediate access`

- Apple or Google OAuth is mandatory primary authentication.
- Phone is profile/contact data collected after OAuth. It is never account-ownership proof.
- No SMS OTP, manual customer phone verification, or customer Admin approval.
- Matching phone/email (including Apple relay email) never heuristically merges accounts. Separate unlinked identities remain separate.
- Linking requires an explicit flow started by the already authenticated customer, proving control of the second Apple/Google identity.
- Linked identities restore the same account. Deletion invalidates access, anonymises permitted PII, and preserves immutable operational/financial history.

## Locked launch operating values

- Locality: Vaniyambadi, Tirupattur District, Tamil Nadu.
- Retail radius: 3,000 m. Retail prep choices: 10/15/20 min.
- Wave 2 timeout/hold: 180/180 sec. Maximum pickup route: 5,000 m. Operational reliability: 5,000 bps.
- Payment reservation: 300 sec.
- Rider offers: 30 sec; initial pool 3; expand by 3 per round.
- Delivery verification invalid-attempt limit: 5.
- Exact-SKU recovery radius/offer timeout: 5,000 m/30 sec.
- Retail issue window: 86,400 sec. Standard Admin refund approval limit: 200,000 paise.
- Merchant commission: 0 bps.
- Rider payout: 1,500 paise for 0–1,000 m, then 500 paise for every started additional 1,000 m (`STARTED_DISTANCE_BAND`), snapshotted per mission/settlement.

## Locked transport/load values

| Transport | Weight | Volume | Packages | Longest side |
|---|---:|---:|---:|---:|
| Walking | 5 kg | 20 L | 2 | 40 cm |
| Bicycle | 10 kg | 35 L | 3 | 50 cm |
| Motorbike | 20 kg | 60 L | 4 | 60 cm |
| Scooter | 25 kg | 75 L | 5 | 65 cm |
| Auto | 80 kg | 250 L | 12 | 100 cm |
| Car | 150 kg | 500 L | 20 | 120 cm |

Unknown-SKU fallback per unit: 1,000 g, 4 L, 30 cm longest side.

## Newer financial authority: platform fee and Royalty

This section is newer than, and overrides, conflicting settlement eligibility or payout wording in the master handoff and earlier addenda.

- Dastak platform-fee revenue is 2% of the immutable final successfully paid total, calculated server-side in integer paise with deterministic half-up rounding. It does not change checkout pricing and is not merchant commission; merchant commission remains 0 bps. Refund corrections are append-only compensating entries.
- `Royalty` is the Merchant/Delivery Partner-facing name for balances derived from the append-only financial ledger. There is no mutable wallet-balance authority.
- A Merchant Royalty earning is credited exactly once after complete verified Merchant → assigned Rider custody for that fulfilment. This applies equally to Retail and Restaurant/Cafe and does not wait for final delivery.
- A Delivery Partner Royalty earning is credited exactly once after evidence-backed, normally verified final delivery and complete Customer custody. Pickup alone does not qualify.
- Approved Merchant/Rider liability creates an append-only negative Royalty adjustment without altering the original earning, historical withdrawal, or independent customer refund. Later earnings offset a negative balance before any amount becomes withdrawable.
- Merchant and Delivery Partner may request any positive available Royalty at any time. Request/processing/paid/failed-retryable states, transactional reservation, immutable payout-destination snapshots, and idempotent results are mandatory. `Paid` requires external payout confirmation.
- No payout provider is authorized by this addendum. The provider-independent domain is required in code; an authorized external payout rail and credentials remain a production integration decision.

## Newest payout-rail authority: RazorpayX

This section is newer than, and overrides, only the preceding statement that no payout provider was authorized.

- RazorpayX is the external payout rail for Merchant and Delivery Partner Royalty withdrawals. Dastak's append-only ledger remains the sole balance authority.
- Supported destinations are Indian bank accounts and UPI VPAs, represented by Dastak-owned records with masked client projections and immutable per-withdrawal snapshots.
- Contact, Fund Account, and Payout operations remain behind a server-only adapter. A Dastak withdrawal UUID is the mandatory RazorpayX payout idempotency key, so one withdrawal can never create two external payouts.
- Provider success, failure, and reversal are verified, deduplicated, preserved, and reconciled without rewriting the original earning or withdrawal history. `Paid` requires authoritative provider confirmation.
- Integration is test-mode first. Live mode requires explicit credentials, source account, webhook secret/configuration, and confirmed fixed-egress IP allowlisting; no live payout is authorized by this addendum.
