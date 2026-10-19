# Merchant header polish — 20 October 2026

The owner rejected the visual quality of the Build 65 header. This is a new
design revision, not a restatement of the earlier single-store wording pass.

## Design implemented

- One integrated page heading replaces the separate material banner and generic
  promotional headline. The actual store name is the serif title, with a small
  page label, short supporting line, quiet business-type caption and a fine
  accent rule. There is no "Your store" banner or background panel.
- Orders, restaurant menu and grocery storefront have coherent contextual
  variants. In category browsing and access-error states the compact identity
  remains a plain row rather than a second full heading.
- Refresh is a subtle outlined 44-point circular control with a progress state,
  accessibility name and existing busy/unsaved-selection guards. It invokes the
  existing store refresh path; no new authority or business mutation is added.
- Headings remain in normal page flow, not the global tab-container inset. No
  fixed title height or one-line truncation is used. Typography is relative to
  Dynamic Type. Order IDs, permissions, recovery and business actions are intact.

## Verification

The full `swift test --package-path Packages/DastakUI --jobs 2` suite passed
**766 tests**, zero failures. Four new header-design tests cover long names,
compact height, light/dark and accessibility environments, and rendering a
local Orders composition. Existing identity/access and inline-height tests pass.

The PNG files are rendered by `ImageRenderer` from the actual SwiftUI heading
component, using local sample data and the shared design palette. The agent
visually inspected both Orders color schemes and both Store variants. These are
macOS component renders: they are not iPhone screenshots, complete system-bar
renders or proof of native iOS Dynamic Type/VoiceOver/scroll interaction. Sample
order values and counts are not live business data.

- [Orders header, light](orders-header-light.png)
- [Orders header, dark](orders-header-dark.png)
- [Restaurant menu header](menu-header-light.png)
- [Grocery storefront header](catalogue-header-light.png)
- [Orders local composition, light](orders-light.png)
- [Orders local composition, dark](orders-dark.png)

The simulator-only design gallery also uses the same new heading. It remains
local/static and does not perform account or order operations.

## Build / acceptance boundary

Build 66 compiled successfully in Release configuration from the isolated build copy based on
`d751fb8c9945eec4ba043b4a349b6d633251d51d` plus the scoped Merchant corrections.
Unrelated Customer source and dependency-lockfile drift remain excluded. The
prior signed Build 65 is retained as `Build65.app` in the task directory.
Strict/deep signature verification passed. Artifact build number is **66** and
executable SHA-256 is
`ceca548907c587bcf7f0dcdbb351275d5018497cd84ced5343820a7074b62d3c`.

Native Device Hub inspection was initially blocked by the Mac lock. After the
owner unlocked it, the device preview connected but showed another app in use;
interaction stopped rather than interrupting the owner. The owner was asked to
leave Merchant on Orders. Agent-observed native Merchant visual verification was
not completed; subsequent owner design acceptance is recorded below. No commit, push, migration, administrative production write,
deployment or TestFlight/App Store action was performed.

## Installation outcome

The initial installation attempt returned a connection-reset error. A bounded
retry succeeded: Apple's `devicectl` reported `com.dastak.merchant` installed
successfully, replacing Build 65. Receipt:
`/private/tmp/dastak-merchant-build64.YXh2Pk/install66-retry.json`.
The signed source artifact was independently verified as Build 66 before install.

The first subsequent installed-version query failed with CoreDevice error 4000 /
connection reset, including one retry after refreshing device discovery. Since
the query failed, that chained launch did not execute. After the owner unlocked
the Mac and the device connection recovered, a fresh independent installed-apps
query confirmed **1.0.0 (66)** and the normal Merchant launch command succeeded.
Receipts are `installed-version66-final.json` and `launch66-final.json` in the
same task directory. This supersedes the earlier version/launch uncertainty;
it does not establish a native visual pass because Merchant was not in the
foreground at the observed screen check. Customer and Delivery were not
installed or replaced, and no order, menu, availability or account controls were
exercised. Source guard remained `codex/dastak-v1-launch` at the same HEAD with
known unrelated changes preserved; only this report was updated after the
unlock/connection check.

## Owner visual acceptance

The owner subsequently reported **"i've seen it, it looks good now"** after
Build 66 installation and independent installed-version confirmation. This
accepts the header's visual polish as owner-reported on-device feedback and
closes this design correction. It does not assert separately observed results
for every Store variant, iPad size, scroll state or accessibility configuration,
nor an agent-observed native visual pass.

Only this local verification note was updated when recording acceptance. No
additional source change, build, device interaction, commit, push, deployment or
Apple distribution action was performed.

## Source checkpoint scope

After accepting the design, the owner separately authorised committing and
pushing only the Merchant corrections, tests and verification evidence. The
checkpoint includes the single-store wording, integrated page heading and
placement correction, three test files, local rendered previews, and the
preceding Merchant iPad investigation/owner acceptance evidence. Historical
sample limitations and failed captures remain explicitly labelled.

Unrelated Customer files, dependency-lockfile drift, release/privacy work,
artwork, all backend files and migrations remain outside the checkpoint. The
base HEAD and remote branch were both verified as
`d751fb8c9945eec4ba043b4a349b6d633251d51d` before staging. The full UI suite
was rerun before the checkpoint. This source approval does not authorise a
TestFlight upload, App Store submission, merge or production deployment.
