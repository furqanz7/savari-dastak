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

## Backend Commands

Always run backend commands from the relevant product directory under `Backends/`, never from the repository root or `Legacy/`.

```sh
# Savari backend
cd Backends/Savari
supabase start
supabase link --project-ref <savari-non-production-project-ref>

# Dastak backend
cd Backends/Dastak
supabase start
supabase link --project-ref <dastak-non-production-project-ref>

# Whole foundation gate from repository root
scripts/test-foundation.sh
```

After the owner creates the corresponding non-production project, execute `supabase link` independently from each backend directory. The Savari and Dastak project refs must differ. Neither backend may be linked to the archived prototype project `mxpszppootpltifzvjla`.
