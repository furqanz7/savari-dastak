# Savari and Dastak

This repository contains the native iOS launch workspace for Savari and Dastak.

## Project Layout

- `SavariDastak.xcworkspace` - shared Xcode workspace for all launch applications.
- `Apps/` - product-specific iOS application projects and sources.
- `Backends/` - product-specific backend projects and migrations.
- `Packages/` - shared Swift packages.
- `Legacy/SavariPrototype/` - preserved pre-launch prototype; never use it as a deployment source.

## Build

```sh
xcodebuild -workspace SavariDastak.xcworkspace -scheme Savari -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

## Dastak Web Deployments

Each Dastak role is a separate Vercel project. Do not run `vercel deploy` directly from the repository or web directory; local Vercel links are intentionally unsupported because they can deploy one role to another role's domain.

```sh
# Verify project roots and production role variables without deploying
scripts/deploy-dastak-web.sh all --check

# Explicit preview or production deployment
scripts/deploy-dastak-web.sh customer --preview
scripts/deploy-dastak-web.sh customer --production
```

Supported roles are `customer`, `delivery`, `merchant`, and `admin`.

The non-secret Dastak environment and ownership inventory is recorded in `docs/dastak-phase-0b-environment-inventory.md`.

## Backend Commands

Always run backend commands from the relevant product directory under `Backends/`, never from the repository root or `Legacy/`.

```sh
# Link Savari only after its non-production project is approved
cd Backends/Savari
supabase link --project-ref <savari-non-production-project-ref>
cd ../..

# Link Dastak only after its separate non-production project is approved
cd Backends/Dastak
supabase link --project-ref <dastak-non-production-project-ref>
cd ../..

# Mac source, package, function, and iOS gate; Docker is not required
scripts/test-foundation.sh

# Linked non-production database gate; this does not push migrations
REMOTE_FOUNDATION_CONFIRM=nonproduction-only \
SAVARI_NONPROD_PROJECT_REF=<savari-non-production-project-ref> \
DASTAK_NONPROD_PROJECT_REF=<dastak-non-production-project-ref> \
scripts/test-foundation-remote.sh
```

After the owner creates the corresponding non-production project, execute `supabase link` independently from each backend directory. The Savari and Dastak project refs must differ. Neither backend may be linked to the archived prototype project `mxpszppootpltifzvjla`.

`scripts/test-foundation.sh` runs without Docker on the developer Mac. GitHub Actions keeps the isolated container-backed migration and pgTAP jobs on hosted runners. `scripts/test-foundation-remote.sh` verifies the two explicitly named, already-linked databases through lint, pgTAP, and grant checks. It never links a project, pushes a migration, deploys a function, provisions an owner, or resets a database. Supabase project refs do not identify their environment to the script, so both refs must be owner-approved non-production projects before it is run; every remote mutation remains a separately approved task.
