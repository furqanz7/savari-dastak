# Dastak isolated review demo proposal

Status: discussion and draft only. The owner asked to discuss this approach; implementation, production access changes and contacting Apple are not authorized by that choice. No demo code, reviewer account or role approval has been created. Build 58 contains no new review demo.

## Why this is separate from normal sign-in

Normal customers retain Continue with Apple and Continue with Google. Newly signed-in customers must not become approved Delivery partners automatically. Reviewers nevertheless need a practical way to exercise both Customer and Delivery without accessing real customer addresses, identity documents, delivery assignments or earnings.

Apple’s [App Review Guideline 2.1(a)](https://developer.apple.com/app-store/review/guidelines/#app-completeness), checked 16 October 2026, describes a built-in demo in lieu of an account when legal/security obligations prevent providing an account and requires prior Apple approval. The general pre-submission checklist also calls for full access. Do not assume owner preference alone satisfies that exception, invent a legal obligation, or claim Apple has approved a demo. Seek guidance/approval before relying on this route.

## Proposed experience

- A clearly named sample/demo entry, fully documented for App Review, with an obvious Demo badge, Exit Demo and Reset Demo. No hidden reviewer detection, special IP behavior, secret gestures or undocumented production bypass.
- The actual Customer and Delivery screens and business rules, backed by synthetic, isolated data. This must be interactive and stateful rather than a slideshow or prerecorded success responses.
- Customer scenarios cover Grocery and Food browsing, variants/stock, basket pickup and quantity controls, addresses, checkout, confirmation, cancellation and order tracking.
- Delivery scenarios cover accepting/declining offers, pickup arrival/collection, travelling, customer arrival, handoff/verification, eligible failure/return/recovery paths, full order detail, history and earnings presentation.
- Deterministic scenarios let a reviewer progress both sides without waiting for a real merchant or rider. State survives ordinary navigation/backgrounding as appropriate, and Reset restores the synthetic starting scenario.
- All names, addresses, contact details, orders and documents are non-private samples. Do not request real identity uploads, real bank/UPI details, real payments or real fulfilment in demo.
- Live Activities, widgets, shortcuts and notifications need an explicit demo test plan. Local sample notifications can demonstrate presentation but must not be described as proof of remote APNs delivery; server-driven behavior requires a genuinely isolated service/test environment and separate authorization/configuration.

## Safety boundary and implementation decision

Demo data and credentials must never mix with production sessions or persisted production carts/actions. Every demo operation must use a dedicated demo client/environment with no production fallback. Entering/exiting must tear down the relevant tasks, activity/token routing and session state so demo callbacks cannot mutate a live session.

Before implementation, decide whether a local interactive state engine can satisfy the approved review scope or a separate non-production backend is required for server-driven workflows. A fully featured demo is not a promise that a few existing Debug fixtures cover the app. The current fixtures may support visual testing, but they are not yet an approved, complete review-access solution.

Required verification includes zero production commerce/payout/account writes, no real notification recipients/calls, isolated storage and deep links, no role escalation, no live-session leakage, reset behavior, both order types and all applicable Delivery transitions. Any external demo infrastructure, credentials, role changes or data uploads need separate authorization. Shipping a demo would require a new archived/uploaded build and renewed testing; it cannot be added to the already uploaded Build 58.

## Draft request to Apple — not sent

> We are preparing Dastak (Apple ID 6796518603), which combines Customer grocery/food ordering and an approved Delivery partner workspace. Normal authentication uses Sign in with Apple and Google. Delivery workflows involve customer addresses, verification documents and account-linked delivery/earnings records. We would like to avoid exposing production customer or rider information during review.
>
> Before implementing a built-in demonstration mode in place of a shared review account, may we obtain your guidance and, if appropriate, prior approval under Guideline 2.1(a)? We propose the same interactive Customer and Delivery UI and workflow rules using clearly labelled synthetic data in an isolated environment, with resettable scenarios and no real orders, payments or dispatch. Normal sign-in and production role approvals would remain unchanged. Please advise whether this approach is acceptable and what additional access you require.

The owner should review the exact message before authorizing transmission. If Apple does not approve this route, retain the dedicated approved review-account option rather than weakening production authorization.
