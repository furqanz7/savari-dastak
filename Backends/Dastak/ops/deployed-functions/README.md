# Existing production catalogue helpers — source recovery, 16 October 2026

These three existing, ACTIVE Edge Functions were present in the linked Dastak project but had no source counterpart in the repository. Their source was retrieved through the authenticated Supabase source-download API during the Customer/Delivery repository handoff. This recovery did **not** deploy, invoke, enable, disable or change any function, catalogue item, image or queue.

| Function | Observed deployed version | Platform JWT verification |
| --- | --- | --- |
| `catalogue-packshot-ingest` | 2 | true |
| `process-catalogue-assets` | 3 | false; source checks its internal secret |
| `process-catalogue-sources` | 16 | false; source checks its internal secret |

The downloaded TypeScript was normalized with the repository's Deno formatter, with no authored behavior changes. Environment-variable names are retained; no environment-variable values or credentials were downloaded or added. Original remote dependency specifiers are intentionally preserved.

These files are **recovery archives**, not newly audited deployment entry points. They live outside `supabase/functions` deliberately: do not include them in a broad deployment or silently add them to active CLI configuration. A future maintenance release must review and pin their dependency imports, add focused tests, confirm the existing function authentication settings, and deploy only with separate authority. No claim of a functional/security certification of these older ingestion helpers is made by archiving their source.

The current repository-backed function sources were compared against downloaded production sources after the same formatting normalization: all 68 files with local counterparts matched. The three files archived here account for the remaining three of 71 downloaded files.
