#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

require_contains() {
  local path="$1"
  local expected="$2"
  if ! grep -F -q -- "$expected" "$path"; then
    printf 'RED: %s is missing required contract: %s\n' "$path" "$expected" >&2
    exit 1
  fi
}

require_contains Packages/MarketplaceInfrastructure/Package.swift 'exact: "2.37.0"'

require_contains Apps/Savari/Sources/Savari/SavariApp.swift 'MarketplaceAuthenticationShell'
require_contains Apps/Savari/Sources/Savari/SavariApp.swift 'product: .savari'
require_contains Apps/Savari/Sources/SavariAdmin/SavariAdminApp.swift 'MarketplaceAuthenticationShell'
require_contains Apps/Savari/Sources/SavariAdmin/SavariAdminApp.swift 'product: .savari'
require_contains Apps/Dastak/Sources/Dastak/DastakApp.swift 'MarketplaceAuthenticationShell'
require_contains Apps/Dastak/Sources/Dastak/DastakApp.swift 'product: .dastak'
require_contains Apps/Dastak/Sources/DastakMerchant/DastakMerchantApp.swift 'MarketplaceAuthenticationShell'
require_contains Apps/Dastak/Sources/DastakMerchant/DastakMerchantApp.swift 'product: .dastak'
require_contains Apps/Dastak/Sources/DastakAdmin/DastakAdminApp.swift 'MarketplaceAuthenticationShell'
require_contains Apps/Dastak/Sources/DastakAdmin/DastakAdminApp.swift 'product: .dastak'

for product in Savari Dastak; do
  require_contains "Apps/$product/Configuration/Defaults.xcconfig" 'MARKETPLACE_SUPABASE_URL = https:/$()/not-configured.invalid'
  require_contains "Apps/$product/Configuration/Defaults.xcconfig" 'MARKETPLACE_SUPABASE_PUBLISHABLE_KEY = not-configured'
  require_contains "Apps/$product/Supporting/Info.plist" '<key>MarketplaceSupabaseURL</key>'
  require_contains "Apps/$product/Supporting/Info.plist" '<key>MarketplaceSupabasePublishableKey</key>'
done

require_contains scripts/test-foundation.sh 'for backend in Savari Dastak'
require_contains scripts/test-foundation.sh 'supabase start'
require_contains scripts/test-foundation.sh 'supabase db reset --local'
require_contains scripts/test-foundation.sh '"$repo_root/scripts/test-backend-security.sh" "$backend"'
require_contains scripts/test-foundation.sh 'trap cleanup_backend EXIT INT TERM'
require_contains scripts/test-foundation.sh 'supabase stop --no-backup'

for product in Savari Dastak; do
  require_contains \
    "Backends/$product/supabase/migrations/20260715170000_revoke_authenticated_storage_delete.sql" \
    'revoke delete on table storage.objects from authenticated;'
  require_contains \
    "Backends/$product/supabase/functions/tests/issue-evidence-url/handler.test.ts" \
    'maps owner lookup failures to internal_error without signing'
done

require_contains scripts/assert-no-client-dml.sql "has_table_privilege('authenticated', format('%I.%I', table_schema, table_name), 'DELETE')"
require_contains scripts/assert-no-client-dml.sql "and not (table_schema = 'storage' and table_name = 'objects')"

printf 'final foundation repair contract passes\n'
