# Merchant iPad sample verification — 19 October 2026

## Scope and artifact

Local sample-component inspection only. Worktree: `wave1-runtime-ci`, branch
`codex/dastak-v1-launch`, HEAD `d751fb8c9945eec4ba043b4a349b6d633251d51d`.
Known unrelated working changes were preserved. No source implementation was
changed, no new build was compiled, and nothing was committed, pushed, deployed,
uploaded to Apple or changed on the physical iPhone during this check.

Reused the existing Debug iOS Simulator app at
`/private/tmp/dastak-quality-derived/Build/Products/Debug-iphonesimulator/DastakMerchant.app`.
Its bundle version is **61**, not the physical-device Build 63. Executable SHA-256:
`af275b081a0ffe08f6f975b00ce6ead8b05bf568b8b007de2d9289d3fb34759e`.
The preview/design source's last committed change is `6c379f6`. This is not a
fresh build or a release-binary iPad sign-off.

Device: existing iPad Pro 13-inch (M5), iPadOS 27.0 Simulator,
`2DC563BD-4808-4202-9B99-47A836C14FFA`.
Launch arguments for the successful capture:
`-DastakMerchantDesignPreview -MerchantLightPreview`.
The sample explicitly uses `.large` Dynamic Type by default. It uses static local
orders and sample callbacks, not the authenticated Merchant workspace.

## Verified observation

[Orders portrait, light](ipad-orders-portrait-light.png), native capture at
2064 × 2752 pixels, visually inspected:

- Heading, subtitle, summary tiles and queue controls are centred within the
  constrained content width.
- All four incoming-order item lines and their prices are visible.
- The physical-confirmation toggle, preparation selector, disabled Accept,
  Decline and View full order controls render without visible clipping.
- The sample's Orders/Store chooser is visible below the content.

Screenshot SHA-256:
`ba5ef24564243bf2238dac970eb4a3f4e96b74b9193ff1f527776dc0fdd8902d`.
These are appearance observations only: no control activation or VoiceOver pass is inferred from the
image. The sample's two-section chooser is not the real four-tab workspace.

## Blocked / not passed

After the successful initial launch, `simctl terminate` stalled. The sample
process and that command were stopped by their exact process IDs; a subsequent
launch with `-MerchantAccessibility` also stalled without a running Merchant
process being observed. Native UI reconnection repeatedly reported
`Sky Computer Use native pipe startup failed`; an earlier observation timed out.
The attempted large-text screenshot is not used as evidence because the intended
launch state was not established.

Not verified here: accessibility3 rendering, Store rendering, landscape,
split-screen/narrow iPad layouts, software keyboard, touch activation, scrolling,
VoiceOver reading/activation, Reduce Motion/contrast/transparency combinations,
or the complete signed-in Merchant workspace. No underlying app-versus-simulator
cause has been established for the stalled transitions.

The simulator was shut down after the attempt. No live order, account, upload,
notification registration, payment or payout was involved.

## Storage prerequisite

With explicit approval, only these four rebuildable compiler-cache directories
were removed before this retry:

- `/private/tmp/dastak-quality-derived/Build/Intermediates.noindex`
- `/private/tmp/dastak-quality-derived/ModuleCache.noindex`
- `/private/tmp/dastak-merchant-build62.5tpGXm/DerivedData/Build/Intermediates.noindex`
- `/private/tmp/dastak-merchant-build62.5tpGXm/DerivedData/ModuleCache.noindex`

Approximately 2.4 GiB was recovered. Simulator and preserved physical Build 63
executable hashes were identical before and after removal. Build products,
archives, source, package checkouts, personal files, simulator runtimes and
Codex/ChatGPT data were not cleanup targets. Around 2.2 GiB remained during this
retry; this is still limited headroom and is not a new archive/build capacity pass.

## Post-restart retry — 19 October 2026, approximately 04:38–04:46 IST

The owner restarted the Mac. Uptime confirmed the restart; initial free space was
about 13 GiB. No additional cleanup was performed. The same branch, HEAD and known
tracked edits were observed.

- The 13-inch iPad's boot-status command completed, but the requested Store sample
  launch with accessibility3 never produced an observed Merchant process. A
  screenshot showed Apple's startup logo, not Merchant. The stalled launch was
  stopped and that simulator was shut down.
- A second existing device, iPad Pro 11-inch (M5), iPadOS 27.0,
  `21188B5F-C815-479C-B4E4-0D9E6FB7FF3D`, completed its initial data migration.
- The temporary build-product directory did not survive the Mac restart. The
  already-installed 13-inch simulator app bundle was still present and its
  executable hash exactly matched the artifact recorded above. It was used as
  the input for installation on the 11-inch simulator; no new build was compiled.
- That install/launch sequence failed with `NSMachErrorDomain`, code `-308`,
  `(ipc/mig) server died`. Native Device Hub observation also timed out or failed
  to start its native pipe during this attempt.
- Host diagnostics showed simulator runtime cache-generation work and very high
  system load. Free space fell during this background work. No runtime/cache
  generator was terminated, and no additional directories were deleted.

The simulator-service failure is established; its underlying cause is not. No
new Merchant layout or interaction pass follows from this retry. The pending
checks listed above remain pending, and the earlier valid normal-text portrait
capture remains the only iPad Merchant appearance evidence in this folder.
Both test simulators were shut down after the retry. No physical-device, account,
backend, Apple submission, payment or payout action was performed.

## Safe tooling repair investigation — 19 October 2026

The owner authorized investigation/repair, with separate approval required before
simulator-data deletion or runtime removal/reinstallation. No such deletion or
reinstallation was performed in this slice.

Observed macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), 8 GiB host RAM,
multi-gigabyte swap usage and very high system load. iOS 18.4 and 18.5 were still
registered as available, despite earlier cleanup history. Neither runtime had
any simulator devices. Their per-host-build dyld caches each measured about
3.5 GiB. Runtime cache generation was observed; free disk headroom varied sharply
with background work and swap. This is a resource-pressure observation, not a
proved single root cause for every simulator failure.

Safe actions and results:

1. Checked `/private/tmp` and `/private/var/tmp`: both already had root-owned
   sticky world-writable permissions. No permissions or security settings changed.
2. Ran `xcrun simctl runtime dyld_shared_cache update com.apple.CoreSimulator.SimRuntime.iOS-27-0`
   **without** `--force`. It reported the iOS 27 cache usable. No cache removal was
   requested. This follows the readiness check described by an
   [Apple Developer Tools engineer](https://developer.apple.com/forums/thread/807025).
3. With every simulator shut down, sent SIGTERM to the exact user-owned
   CoreSimulatorService process and let the next simctl call restart the service.
4. The existing 13-inch iPad then completed boot status in about nine seconds.
   Apple Settings launched and was visually observed through Device Hub.
5. Merchant launched with
   `-DastakMerchantDesignPreview -MerchantLightPreview -MerchantAccessibility -MerchantStorePreview`.
   [Store at accessibility3, portrait/light](ipad-store-accessibility3-light.png)
   was captured natively and inspected: the heading, description, banner guidance
   and form values wrap without visible clipping in the initially visible region.
   Add photo is intentionally disabled by the sample. The Save button is only
   partly visible at the viewport boundary; scrolling to verify its full reach
   was not possible, so no lower-form or save-action pass is claimed.
6. Native scrolling reported `AXError.cannotComplete`; a drag reported
   `noWindowsAvailable`. A subsequent simctl termination/relaunch also stalled.
   The exact pending command and local sample process were stopped, then the
   simulator was shut down. Thus the repair is **partial, not a stability pass**.

All earlier limits still apply except that the initial accessibility3 Store
appearance now has evidence. Orders at accessibility3, lower Store interactions,
software keyboard, landscape, VoiceOver and full signed-in workspace acceptance
remain pending. No new release binary or implementation was produced.

Read-only removal audit: Apple's runtime tool lists iOS 18.4 image
`9A3DF108-88CC-472D-884A-7A18031A5EA5` as deletable, size 8.2G; its `--dry-run`
resolves that exact image. The corresponding cache is
`/Library/Developer/CoreSimulator/Caches/dyld/26A434/com.apple.CoreSimulator.SimRuntime.iOS-18-4.22E238`
(about 3.5 GiB). Removal was **not** executed. Actual reclaimed space would need
measurement rather than adding nominal sizes, particularly with APFS sharing.
The iOS 26.5/27 runtimes, all simulator data, source, archives, physical apps,
personal files, Codex and ChatGPT are outside this proposed removal scope.

## Approved iOS 18.4 removal and retry — 19 October 2026

The owner explicitly approved removal of only iOS 18.4 and its associated cache.
Before the action, the exact runtime image was re-resolved with `--dry-run`, the
root-owned cache was measured again, all simulators were shut down, and there
were no devices associated with iOS 18.4. Branch/HEAD and known tracked edits
remained unchanged.

Executed Apple's supported commands:

```sh
xcrun simctl runtime dyld_shared_cache remove com.apple.CoreSimulator.SimRuntime.iOS-18-4
xcrun simctl runtime delete 9A3DF108-88CC-472D-884A-7A18031A5EA5
```

Both commands exited successfully. Subsequent inventory confirmed iOS 18.4 was
absent and its exact dyld-cache directory no longer existed. iOS 18.5, iOS 26.5,
iOS 27.0 and tvOS 18.5 remained available. All 12 pre-existing simulator devices
remained: 11 on iOS 27 and one on iOS 26.5. No simulator was erased or deleted.
The installed Merchant executable still matched SHA-256
`af275b081a0ffe08f6f975b00ce6ead8b05bf568b8b007de2d9289d3fb34759e`.

Measured free space increased from about 1.1 GiB to 5.5 GiB immediately after
removal. This is the measured result, not the sum of nominal runtime/cache sizes.
The removed runtime can be downloaded again through Xcode; its cache can be
regenerated if that runtime is reinstalled. No other deletion was performed.

Retry observations:

- The existing iOS 27 iPad boot-status sequence completed in about eight seconds.
  The static Merchant accessibility3 Store sample launched with PID 4221.
- Native UI observation timed out. Switching Device Hub to a dedicated simulator
  window did not establish usable app-level accessibility controls; the normal
  Device Hub window was restored afterward.
- A bounded normal `simctl terminate` completed successfully. However, the next
  Orders accessibility3 launch stalled for more than two minutes without an
  observed running Merchant process. Its exact simctl process was stopped.
- [The attempted Orders capture](attempt-orders-accessibility3-home-not-a-pass.png)
  shows the iPad Home Screen, **not an Orders rendering pass**.
- Free space fell to roughly 1.5 GiB while the simulator was running, then was
  about 5.5 GiB after shutdown. High system load and disk-image activity were
  observed. The deletion improved capacity but did not establish simulator
  stability or prove the underlying cause.

All simulators were shut down at the end. No new app build, physical-device
installation, business-data action, push, deployment or Apple upload occurred.
The remaining native acceptance limits above are unchanged. No further runtime
removal or simulator-data deletion is authorized by this completed cleanup.

## Temporary iPadOS 26.5 comparison

The owner subsequently authorized one new disposable iPadOS 26.5 sample device
and its cleanup. Selected large-text Store/Orders controls, software-keyboard
focus and landscape rendering were verified. The exact temporary device was
removed afterward; all 12 original devices remained intact and shut down.
See the [comparison report and captures](ios265-comparison.md) for individual
results, remaining gesture/VoiceOver/full-workspace limits and artifact hashes.
This does not retroactively turn the failed iOS 27 attempts into passes.
