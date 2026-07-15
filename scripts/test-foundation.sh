#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required foundation prerequisite: %s\n' "$command_name" >&2
    exit 127
  fi
}

for command_name in swift deno supabase docker xcodebuild rg find xargs; do
  require_command "$command_name"
done

if ! docker info >/dev/null 2>&1; then
  printf 'Docker is installed but its daemon is unavailable; local Supabase tests cannot run.\n' >&2
  exit 1
fi

active_backend=""
cleanup_backend() {
  local status=$?
  trap - EXIT INT TERM
  if [[ -n "$active_backend" ]]; then
    (
      cd "$repo_root/Backends/$active_backend"
      supabase stop --no-backup
    ) || printf 'Warning: failed to stop the %s local Supabase stack.\n' "$active_backend" >&2
  fi
  exit "$status"
}
trap cleanup_backend EXIT INT TERM

swift test --package-path Packages/MarketplaceFoundation
swift test --package-path Packages/MarketplaceInfrastructure
swift package dump-package --package-path Packages/SavariDomain >/dev/null
swift package dump-package --package-path Packages/DastakDomain >/dev/null

if rg -n 'DastakDomain' Packages/SavariDomain \
  || rg -n 'SavariDomain' Packages/DastakDomain; then
  echo "Product domain packages must not depend on one another." >&2
  exit 1
fi

run_backend() {
  local backend="$1"
  local config="supabase/functions/deno.json"
  local lockfile="supabase/functions/deno.lock"
  local functions="supabase/functions"
  local database_tests="supabase/tests/database"

  active_backend="$backend"
  cd "$repo_root/Backends/$backend"
  supabase start
  supabase db reset --local
  "$repo_root/scripts/test-backend-security.sh" "$backend"
  deno test --config "$config" --lock "$lockfile" --frozen --allow-env "$functions/tests/"
  deno test --config "$config" --lock "$lockfile" --frozen --allow-read "$database_tests/"
  find "$functions" -name '*.ts' -print0 \
    | xargs -0 deno check --config "$config" --lock "$lockfile" --frozen
  deno fmt --config "$config" --check "$functions" "$database_tests"
  supabase stop --no-backup
  active_backend=""
  cd "$repo_root"
}

for backend in Savari Dastak; do
  run_backend "$backend"
done

for scheme in Savari SavariAdmin Dastak DastakMerchant DastakAdmin; do
  xcodebuild \
    -workspace SavariDastak.xcworkspace \
    -scheme "$scheme" \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build
done
