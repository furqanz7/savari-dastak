#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
web_root="$repo_root/Web/MarketplaceWeb"

for command_name in node npm; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required Dastak web prerequisite: %s\n' "$command_name" >&2
    exit 127
  fi
done

cd "$web_root"
npm ci
npm audit --omit=dev --audit-level=high
npm test
npm run lint

VITE_APP_VARIANT=dastak-customer \
VITE_SUPABASE_URL=https://ci.supabase.co \
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_ci \
npm run build
