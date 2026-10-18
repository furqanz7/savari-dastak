# Merchant validation and actionable feedback

18 October 2026. Local native M-11 follow-up to the [Merchant completion audit](dastak-merchant-completion-audit-2026-10-18.md).

## Scope

Solo work in `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, unchanged HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`. Earlier local Merchant changes, Customer screenshot fixtures, artwork/evidence/release documents and the generated dependency lockfile change were preserved.

This slice changes native Merchant presentation, validation and regression fixtures only. No new migration, Edge/web source change, production write, deployment, commit/push, installation, Apple change, real order, payment or payout.

The Supabase skill was used to inspect existing storage/media contracts and preserve authenticated upload/version/journal boundaries. The relevant current [upload guidance](https://supabase.com/docs/guides/storage/uploads/standard-uploads) was checked. This is not a live Storage integration test.

## Photo handling

Added shared `DastakMerchantPhoto` preparation used by menu/banner, Ready evidence and retained earlier product editors.

- Menu/banner/catalogue accepts JPEG, PNG and WebP up to the existing **5 MB output limit**. HEIC/HEIF inputs up to **20 MB** are converted on device to an oriented JPEG, with a longest edge of at most 2,560 pixels and the same 5 MB output cap.
- The HEIC conversion writes fresh pixel data without copying the source GPS/EXIF dictionary. Existing JPEG/PNG/WebP bytes pass through unchanged; this is not a claim that all original formats have their metadata stripped.
- Ready evidence retains JPEG/PNG/HEIC with its existing **10 MB** limit; supported HEIC evidence is not converted or relabelled JPEG. WebP is not accepted for Ready evidence.
- Actual ImageIO type and a bounded pixel decode are checked, rather than trusting the picker filename/type. Empty, corrupt, animated/multiframe and unsupported formats receive an explanation. Source dimensions are limited to 20,000 per side and 64 million pixels as a native processing safety limit.
- The photo load/preparation has a 20-second overall deadline. A non-cooperative iCloud/photo-library load cannot leave the originating loading state waiting forever.
- Picker state has generation/disappearance guards so a late prepared image cannot start a new upload from an abandoned picker. Existing model target/version and account checks remain authoritative.
- Photo failures and saved/not-confirmed outcomes are visible inline. A not-confirmed save points to the existing saved-action recovery rather than encouraging a new command.
- Earlier product editing no longer guesses JPEG for unknown bytes. A failed replacement retains the previous valid selection, with an explicit option to continue without that replacement.
- The model checks new media's bytes/type and filename before creating a new journal entry. Previously secured pending commands retain their original replay bytes/payload/key; their recovery format was not changed.

## Packages and prices

- Package controls now support the verified server range **1–1,000**, including direct whole-number entry plus a stepper. The server constraint was inspected in `declare_fulfilment_packages`; this is not an invented range expansion.
- Invalid package input explains the range and disables confirmation. Model guards also reject out-of-range values before journaling/network. Stale, wrong-location or blocked-recovery package actions explain the need to refresh/recover first.
- A changed package draft must be confirmed before Mark Ready. Ready still uses the existing irreversible confirmation and server-authoritative workflow.
- Merchant prices reject partial strings, exponents, signs, grouping commas, sub-paise precision, zero base prices and values above the existing native ₹10,00,000 limit. Free extras remain valid at zero.
- Dish, extra and legacy product forms explain the accepted bounds/required details. Names/descriptions and choice limits get explicit issues; model checks reject invalid new menu payloads before journaling.
- Existing version-conflict/dirty-draft review is preserved. New validation does not rebase a stale draft or replace an uncertain command.

## Store state and business names

- Mismatched Store service types have specific recovery guidance: refresh locations and choose Grocery versus Restaurant / Café. A wrong-service response is not published as the current Store.
- A wrong-location response cannot replace the last verified same-location snapshot. Existing retained data remains stale/read-only; it is not treated as a successful refresh.
- Menu/media/operating actions explain blocked reads, saved-action recovery, stale targets and missing operating authority/version instead of silently returning false.
- Store load failures are exposed on the relevant Store screen. Restaurant failures do not show an unrelated Grocery retry banner.
- Onboarding now says **Business names**, explains **legal business name** versus **customer-facing name**, and removes user-facing branch wording. Technical branch IDs remain unchanged.
- Grocery and Restaurant headers use the same customer-facing location name as the location context. The Grocery header no longer repeats organization display name as a second unlabelled name. Organization display name is not mislabelled as a legal name.

## Verification and boundaries

Added **14 tests**: photo decoding/type/size/HEIC orientation and metadata handling, Ready HEIC passthrough, deadline recovery, package boundaries including 1,000, strict prices, menu payload errors, pre-journal rejection and wrong-service read recovery.

The existing restaurant recovery tests had a legacy `RESTAURANT` type label and arbitrary fake bytes labelled as images. Their fixtures were corrected to `RESTAURANT_CAFE` and real PNG bytes; exact original-key/payload/byte replay assertions remain intact. One initial failure also confirmed that wrong-location stale retention must remain distinct from wrong-service invalidation; the previous valid snapshot remains retained safely.

| Check | Result |
| --- | --- |
| Full DastakUI hosted package | 676 tests, zero failures |
| Full Infrastructure hosted package | 189 tests, zero failures |
| Catalogue + orders Edge fixture tests | 78 tests, zero failures; server source unchanged |
| Merchant generic iOS Simulator Debug build | BUILD SUCCEEDED, signing disabled |
| Whitespace and branch/HEAD guard | Passed; unchanged |

The HEIC conversion tests executed successfully; they were not skipped. New actor-isolation warning from the photo button label was corrected by computing the label before the Sendable closure. Existing unrelated project/tooling warnings are not a claim of new runtime failures.

Logs: `/tmp/dastak-merchant-validation-ui-final.log`, `/tmp/dastak-merchant-validation-infra.log`, `/tmp/dastak-merchant-validation-edge.log`, `/tmp/dastak-merchant-validation-ios-final.log`.

Still separate: native tap-through/keyboard/large-text/VoiceOver acceptance, physical-device iCloud photos, live Storage permissions/uploads, cross-role/multi-location operations and production-volume acceptance. No simulator visual acceptance or real upload is inferred from compilation/model/image fixtures.

This slice adds no production activation requirement of its own. Earlier M-05/M-10 migration/Edge activation remains pending independently. Notification navigation/delivery acceptance (M-12), broader visual polish, complete catalogue search/location discovery, native payout actions and other remaining audit work are not marked finished here.
