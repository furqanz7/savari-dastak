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

for command_name in swift deno xcodebuild rg find xargs node npm; do
  require_command "$command_name"
done

swift test --package-path Packages/MarketplaceFoundation
swift test --package-path Packages/MarketplaceInfrastructure
swift test --package-path Packages/DastakDomain
swift package dump-package --package-path Packages/SavariDomain >/dev/null

if rg -n 'DastakDomain' Packages/SavariDomain \
  || rg -n 'SavariDomain' Packages/DastakDomain; then
  echo "Product domain packages must not depend on one another." >&2
  exit 1
fi

run_backend_static_checks() {
  local backend="$1"
  local config="supabase/functions/deno.json"
  local lockfile="supabase/functions/deno.lock"
  local functions="supabase/functions"
  local database_tests="supabase/tests/database"

  cd "$repo_root/Backends/$backend"
  deno test --config "$config" --lock "$lockfile" --frozen --allow-env "$functions/tests/"
  deno test --config "$config" --lock "$lockfile" --frozen --allow-read "$database_tests/"
  find "$functions" -name '*.ts' -print0 \
    | xargs -0 deno check --config "$config" --lock "$lockfile" --frozen
  deno fmt --config "$config" --check "$functions" "$database_tests"
  cd "$repo_root"
}

for backend in Savari Dastak; do
  run_backend_static_checks "$backend"
done

"$repo_root/scripts/test-dastak-web.sh"

for scheme in Savari SavariAdmin; do
  xcodebuild \
    -workspace SavariDastak.xcworkspace \
    -scheme "$scheme" \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build
done

"$repo_root/scripts/test-dastak-ios.sh"
