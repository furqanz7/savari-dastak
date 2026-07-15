#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

swift test --package-path Packages/MarketplaceFoundation
swift test --package-path Packages/MarketplaceInfrastructure
swift package dump-package --package-path Packages/SavariDomain >/dev/null
swift package dump-package --package-path Packages/DastakDomain >/dev/null

if grep -R -n -E 'DastakDomain' Packages/SavariDomain \
  || grep -R -n -E 'SavariDomain' Packages/DastakDomain; then
  echo "Product domain packages must not depend on one another." >&2
  exit 1
fi

for backend in Savari Dastak; do
  config="Backends/$backend/supabase/functions/deno.json"
  lockfile="Backends/$backend/supabase/functions/deno.lock"
  functions="Backends/$backend/supabase/functions"
  database_tests="Backends/$backend/supabase/tests/database"

  deno test --config "$config" --lock "$lockfile" --frozen --allow-env "$functions/tests/"
  deno test --config "$config" --lock "$lockfile" --frozen --allow-read "$database_tests/"
  find "$functions" -name '*.ts' -print0 | xargs -0 deno check --config "$config" --lock "$lockfile" --frozen
  deno fmt --config "$config" --check "$functions" "$database_tests"
done

scripts/test-backend-security.sh Savari
scripts/test-backend-security.sh Dastak

for scheme in Savari SavariAdmin Dastak DastakMerchant DastakAdmin; do
  xcodebuild \
    -workspace SavariDastak.xcworkspace \
    -scheme "$scheme" \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build
done
