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

for variant in dastak-customer dastak-delivery dastak-merchant dastak-admin; do
  printf 'Building Dastak web variant: %s\n' "$variant"
  VITE_APP_VARIANT="$variant" \
  VITE_SUPABASE_URL=https://ci.supabase.co \
  VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_ci \
  VITE_DASTAK_PRIVACY_URL=https://example.test/privacy \
  VITE_DASTAK_TERMS_URL=https://example.test/terms \
  VITE_DASTAK_SUPPORT_URL=https://example.test/support \
  VITE_DASTAK_WEB_PUSH_PUBLIC_KEY=BNVx8M9WlK9nyJ8y8Q0XxPRm8sZ7CsYdlHBJtxMxoEQ8QXyzzYEbUnmdlsfKZQ1r6OUKo6IdHtVFwSXvbpC2ZIc \
  npm run build
done
