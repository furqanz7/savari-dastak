# Merchant owner-reported iPhone and iPad acceptance — 20 October 2026

The owner reported **"All three passed"** for the three-check batch below in
the installed Dastak Merchant app on their iPhone. These are owner-reported
physical-device results, not agent-observed execution. The exact installed build
number, device settings and text-size value were not independently reverified
for this batch.

| Check requested | Result reported |
| --- | --- |
| Normal finger scrolling and control reachability in Orders/Store and an existing order's details, without changing an order; lower controls reachable, bottom navigation not covering them, no unexpected jump to the top | Passed |
| Focus a lower dish-edit field without typing, keep it visible above the keyboard, dismiss using Done, verify lower controls remain usable, leave without saving | Passed |
| Temporarily use an accessibility text size, recheck Orders/Store/existing order details for wrapping, reachability, clipping and overlap, then restore the preferred size | Passed |

This closes the owner-tested batch for these specific iPhone interaction and
large-text paths. It does not establish every form, every Dynamic Type size,
every orientation, repeated-use endurance or every possible account/order state.

VoiceOver was explicitly excluded from the initial batch and subsequently
checked in the separate owner-reported batch below. Signed-in iPad layout and
touch checks were subsequently reported separately below; iPhone results alone
do not establish iPad acceptance. See the separate
[local iPad sample comparison](ios265-comparison.md) for its narrower evidence.
Merchant TestFlight/App Store distribution remains a separate release task.

No new real order, saved menu edit or account change was requested for this
batch. The report does not infer any new live payment, payout or notification
acceptance. No production write, build, deployment, commit, push or Apple action
was performed while recording the result.

Local recording guard: branch `codex/dastak-v1-launch`, HEAD
`d751fb8c9945eec4ba043b4a349b6d633251d51d`; known unrelated working changes
were preserved. Only this acceptance record was added.

## Subsequent VoiceOver acceptance

The owner subsequently reported **"VoiceOver all three passed"** for these
read-only checks in the installed Merchant iPhone app:

| Check requested | Result reported |
| --- | --- |
| Navigate Merchant tabs, open an existing order and return using Back/Close; meaningful spoken names, sensible focus order and no focus trap | Passed |
| Read an existing order's number, status, items, quantities and prices in a coherent sequence; locate View full order and return | Passed |
| Open an existing dish-edit form without changing it; meaningful field names and current values, reach a lower field, dismiss the keyboard and leave without saving | Passed |

These are owner-reported physical-iPhone results, not agent-observed VoiceOver
speech or gestures. The installed build and VoiceOver configuration were not
independently reverified. They close this specific iPhone VoiceOver batch, not
every screen, workflow, language or accessibility configuration. No business
action, saved edit or new order was requested. Subsequent signed-in iPad layout
acceptance is recorded below; Merchant distribution remains separate. Only this local record was updated; no
source implementation, build, production write, deployment, commit, push or
Apple release action was performed.

## Subsequent signed-in iPad layout and touch acceptance

The owner then reported **"All three passed"** in response to the following
read-only signed-in Merchant iPad checks:

| Check requested | Result reported |
| --- | --- |
| Portrait: open Orders, Store, Earnings, Account and an existing order's full details; content and bottom controls reachable without clipping or overlap | Passed |
| Landscape: rotate while viewing an existing order and a dish-edit form; layout adapts, fields remain usable and the form can be left without saving | Passed |
| Narrower window, using resizing or Split View if supported: navigation, scrolling and keyboard dismissal remain usable without changing data | Passed |

These are owner-reported iPad results, not agent-observed execution. The exact
iPad model, installed build, OS, window dimensions and resizing mode were not
independently verified. The owner reported all three checks passed; no separate
configuration details were supplied. This closes the requested signed-in iPad
portrait, landscape and narrower-window layout/touch batch, not every possible
window size, state or device. No new order or saved edit was requested.

iPad-specific VoiceOver and larger-text acceptance were not part of the layout
batch; they were subsequently reported separately below. Merchant TestFlight/App
Store distribution remains separate. Only this local acceptance record was
updated; no source changes, build, production write, deployment, commit, push or
Apple release action was performed.

## Subsequent iPad accessibility acceptance

The owner subsequently reported **"All three passed"** for the following
read-only iPad accessibility batch:

| Check requested | Result reported |
| --- | --- |
| Temporarily increase text size and inspect Orders, Store, Earnings, Account and an existing order's details; text wraps, important content does not overlap, controls remain reachable; restore preferred size | Passed |
| With VoiceOver, navigate tabs and Back/Close, read an existing order in a sensible sequence, enter and leave full details without a focus trap | Passed |
| With VoiceOver, open an existing dish-edit form, check field names/current values, reach a lower field, dismiss the keyboard and leave without saving | Passed |

These are owner-reported iPad results, not agent-observed speech, gestures or
layout. The exact installed build, iPad model, text size and VoiceOver settings
were not independently verified. This closes the requested iPad larger-text and
VoiceOver batch. Together with the preceding records, all requested batches in
this document have owner-reported passes; this is not an exhaustive guarantee
for every device, configuration, workflow or order state.

Merchant TestFlight/App Store distribution remains a separate release task.
Only this local acceptance record was updated; no app source changes, build,
production write, deployment, commit, push or Apple release action was performed.
