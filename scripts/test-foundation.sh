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

deno test --allow-env Backends/Savari/supabase/functions/tests/
deno test --allow-env Backends/Dastak/supabase/functions/tests/
deno test --allow-read Backends/Savari/supabase/tests/database/001_identity_lock.test.ts Backends/Savari/supabase/tests/database/002_security_audit_zones.test.ts
deno test --allow-read Backends/Dastak/supabase/tests/database/001_identity_lock.test.ts Backends/Dastak/supabase/tests/database/002_security_audit_zones.test.ts
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
