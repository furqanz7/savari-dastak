# Merchant local sample — temporary iPadOS 26.5 comparison

19 October 2026, started approximately 05:12 IST. This comparison follows the
[iPad investigation](README.md). It is selected sample-component verification,
not full signed-in Merchant or release-binary acceptance.

## Scope and device

The owner explicitly authorized creating one temporary iPad using the already
installed iOS 26.5 runtime, running only the local sample and removing that exact
new device afterward. No runtime was downloaded or removed in this comparison.

- Device name: `Dastak Temporary iPad QA 2026-10-19`.
- UUID: `EAFE03CA-06B3-4499-BB38-07577A381CC7`.
- Device type: iPad Pro 13-inch (M4), 8 GB model.
- Runtime: iOS 26.5, `com.apple.CoreSimulator.SimRuntime.iOS-26-5`.
- Source worktree: `wave1-runtime-ci`, branch `codex/dastak-v1-launch`, unchanged
  HEAD `d751fb8c9945eec4ba043b4a349b6d633251d51d`.

Reused the existing simulator Debug bundle, version 61, copied from the existing
iOS 27 iPad's installed app bundle. Executable SHA-256 remained
`af275b081a0ffe08f6f975b00ce6ead8b05bf568b8b007de2d9289d3fb34759e`.
No new app build or source implementation change was made. Known unrelated
working changes were preserved. This is not testing the physical Build 63 binary.

The explicit `-DastakMerchantDesignPreview` entry uses static local data and
sample callbacks. `-MerchantAccessibility` sets accessibility3 Dynamic Type;
`-MerchantLightPreview` selects light appearance. The Store launch additionally
used `-MerchantStorePreview`. It does not authenticate or register notifications.

## Directly observed results

| Check | Observation and boundary |
| --- | --- |
| Fresh startup | Initial simulator data migration/boot completed in about 36 seconds; sample installation and launch succeeded. |
| Store accessibility3 | Headings, banner guidance and visible form content rendered with large text. The accessibility inspector exposed the fields and buttons. |
| Save sample activation | Activating Save dish changes opened `Sample only. No menu changes saved.` This verifies activation/callback only, not saving a real dish. |
| Software keyboard | Focusing the price field displayed the software keyboard and moved that field above it. The keyboard's accessible Hide keyboard control dismissed the keyboard. |
| Landscape | Device Hub's Rotate Left control produced a landscape Store layout; visible content stayed centred and text wrapped. This is not coverage of every scroll position. |
| Stop/relaunch | Normal termination completed within a 20-second bound, and relaunch into the Orders sample succeeded. No repeated-relaunch endurance claim is made. |
| Orders accessibility3 | Summary tiles stacked vertically and the queue became a labelled native menu. The inspector exposed all four incoming lines and prices. |
| Confirmation gate | Accept initially appeared disabled. Toggling `I can prepare this exact selection` changed its value from 0 to 1 and enabled Accept. Activating Accept opened `Sample only. No order accepted or declined.` |
| Preparing selection | Activating the `3 Preparing` summary selected Preparing and displayed the fulfilment component. |
| Four-line expansion | Show all 4 items exposed Chocolate cookie and changed to Show fewer items with Expanded state. |
| Package controls | One accessible decrement changed 2 to 1; one increment restored 2. This is accessible activation, not physical touch hit-testing. |
| Detail control | View full order opened `Read-only detail navigation sample.` The authenticated detail endpoint and actual full-order screen were not exercised. |

The sample's fields are constant bindings: no editable-field persistence or
validation pass follows from focusing them. Add photo is deliberately disabled;
no picker, photo library access or upload was attempted. The sample also does
not permit marking the order Ready.

## Evidence

Native captures were saved and inspected:

- [Store price field with software keyboard](ios265-store-accessibility3-keyboard.png)
- [Store landscape](ios265-store-accessibility3-landscape.png)
- [Expanded Preparing lines and package count in landscape](ios265-orders-expanded-accessibility3-landscape.png)
- [Local detail callback](ios265-local-detail-feedback.png)

| File | SHA-256 |
| --- | --- |
| `ios265-store-accessibility3-keyboard.png` | `d5a6afd1d70e21e99db34e24cae32765348f46901183309503a387f7f1860301` |
| `ios265-store-accessibility3-landscape.png` | `0ae2c3ad61a33a7b1c6deb0c02161cacabd39040784a3c2185ca758bc6c376cc` |
| `ios265-orders-expanded-accessibility3-landscape.png` | `9e3c1342a78d705ce07bd6551d049301d62c14167892f3154f4462529c4e24de` |
| `ios265-local-detail-feedback.png` | `3815b0dce0140a18995b8d969dd8e6f0958c95af6b2089e1bdfc5b22c0034f43` |

## Remaining limits

The automation tool still returned `noWindowsAvailable` for coordinate scrolling
and a coordinate tap, even though accessibility-based activation worked.
Fresh accessibility snapshots were necessary after one stale-element error.
Consequently gesture scrolling, coordinate/touch targets, the visible app Done
keyboard action and scroll retention are not passed. Native focus/activation
did move the content to lower controls, but that is not a gesture-scroll test.

The debug sample's Orders/Store chooser overlaps part of the lower Save region
in the field-focused captures. Save could be activated through accessibility,
but no claim is made that this debug chooser reproduces the real workspace's
four-tab layout or that the lower Save button has passed physical touch testing.

No VoiceOver speech, focus traversal or gesture test was performed. Split view,
every field, all text sizes, dark/contrast/transparency/motion combinations and
the complete signed-in Merchant workspace remain separate. Existing evidence
does not establish a new live workflow, provider, payment or payout result.

The same sample binary worked for these selected controls on this fresh iOS 26.5
device while previous iOS 27 attempts stalled. This is consistent with a local
runtime/device-state/resource problem, but is not proof of an iOS 27-only bug:
OS version, device model, fresh device data and host conditions differ. Coordinate
automation limitations occurred on both runtimes. No general performance or
stability guarantee follows from this comparison.

## Cleanup verified

After captures completed, the exact temporary UUID and name were re-resolved.
Only that device was shut down and deleted using `simctl shutdown` / `simctl
delete`. Its disposable sample state is gone; a new fixture device can be created
again. No pre-existing simulator was erased, deleted or booted for this comparison.

Final inventory contained the original 12 devices, all shut down: 11 on iOS 27 and
one iPhone on iOS 26.5. The iOS 26.5 runtime was retained. The physical iPhone,
source, archives, personal files and Codex/ChatGPT data were untouched. Free disk
space was about 5.5 GiB initially, 3.0 GiB during the later sample checks,
3.1 GiB at the first post-cleanup measurement and 2.4 GiB at the final measurement;
this is not an archive-capacity pass.

Only evidence files/documentation were added. No commit, push, deployment, Apple
upload, real account/menu/order change, notification, payment or payout action
was performed.
