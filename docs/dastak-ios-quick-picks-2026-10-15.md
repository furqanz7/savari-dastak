# iOS Quick picks — Build 40

The user requested periodically shuffled Quick picks and pictures for every displayed subcategory instead of generic icons.

## Behaviour

- Build the complete eligible browse-rail pool before selecting six.
- Give the pool a stable daily shuffle and rotate its visible window every 15 minutes. Repeated rendering within a time slot preserves the same order. A minute-based TimelineView refreshes the time slot while Grocery discovery is visible; browsing into a category does not change its selected route.
- Use the matching subcategory's approved product preview first, then matching loaded product photos and dedicated subcategory photos as relevant backups. Exclude shared `canonical/taxonomy/` department artwork so different picks do not use the same broad department image. Blank/missing image keys do not produce icon-only shortcuts.
- Use server-provided approved preview photos to include populated subcategories beyond the first loaded 250-SKU page. This avoids making initial pagination a permanent discovery filter.
- Render 72-point photo circles using the existing cached image loader. Try up to four relevant image keys, each through the thumbnail/original URL fallback. Loading shows a progress indicator; total network/image failure shows a small “Photo unavailable” message instead of a basket icon.
- Existing browse destination and rail identities are preserved. This changes native iOS presentation only; web Quick picks was not changed in this build.

## Evidence

Live read-only catalogue inspection found 538 active subcategories, 489 with primary image keys. Only five populated subcategories lacked a primary image; each had an available matching product image. The existing public milk subcategory photo URL returned HTTP 200 with image/avif content. No Supabase data, storage or product availability was changed for this task.

Build 39's six focused DastakUI host tests passed. They cover greeting boundaries; correct rail/destination routing; invalid, excluded and wrong-category rejection; stable order inside a 15-minute window, changed order at the next interval and coverage of all eight candidates over two windows; photo choice and omission when no photo exists; and inclusion through approved preview photos when no matching SKU is in the loaded page. The seven-test Build 40 follow-up additionally rejects shared department artwork.

Build 39 simulator Debug and signed iPhone Debug builds and strict deep signature verification passed. Build 39 was installed/launched after a device reconnect and the installed bundle version was verified. Its physical screen showed photo circles and rotated subcategory labels, but inspection found repeated broad department artwork. Build 40 changes the photo preference and excludes those shared department placeholders. Final Build 40 installation and verification are recorded below when completed.

Final Build 40: seven focused host tests passed, both simulator and signed device builds passed, and strict deep signature verification passed. It was installed and launched on the physical iPhone. Device Hub's physical screen visibly showed distinct photographs for Ready Masala, Paneer and Tofu, and Ghee with their matching labels. No basket icons or shared department placeholders appeared in those visible picks. The row's tap behaviour remains a physical user check; its canonical destination/rail routing passes the focused tests. The 15-minute boundary is verified with injected dates in tests rather than a 15-minute manual wait.

The user subsequently tapped two different Quick picks on the physical iPhone and reported “Both open correctly.” Physical navigation to the matching subcategories is therefore user-confirmed passed on Build 40.
