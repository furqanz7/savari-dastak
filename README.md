# Savari

Savari is currently scoped to the native iOS app and Supabase backend.

## Project Layout

- `Savari.xcodeproj` - Xcode project for the iOS app.
- `Savari/` - SwiftUI app source, assets, Info.plist, and entitlements.
- `supabase/` - Supabase project config and database migrations.

## Build

```sh
xcodebuild -project Savari.xcodeproj -scheme Savari -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

## Supabase

The project is linked to Supabase through the local Supabase CLI metadata. Apply migrations with:

```sh
SUPABASE_DB_PASSWORD='<database-password>' supabase db push --linked --include-all --yes
```
