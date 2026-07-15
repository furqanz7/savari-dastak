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

require_not_contains() {
  local path="$1"
  local rejected="$2"
  if grep -F -q -- "$rejected" "$path"; then
    printf 'RED: %s contains forbidden contract: %s\n' "$path" "$rejected" >&2
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
require_not_contains scripts/test-foundation.sh 'docker'
require_not_contains scripts/test-foundation.sh 'supabase start'
require_not_contains scripts/test-foundation.sh 'supabase db reset --local'
require_contains scripts/test-foundation-remote.sh 'REMOTE_FOUNDATION_CONFIRM'
require_contains scripts/test-foundation-remote.sh 'nonproduction-only'
require_contains scripts/test-foundation-remote.sh 'SAVARI_NONPROD_PROJECT_REF'
require_contains scripts/test-foundation-remote.sh 'DASTAK_NONPROD_PROJECT_REF'
require_contains scripts/test-foundation-remote.sh 'supabase/.temp/project-ref'
require_contains scripts/test-foundation-remote.sh 'supabase db lint --linked --fail-on error'
require_contains scripts/test-foundation-remote.sh '"$repo_root/scripts/test-backend-security.sh" "$backend" --linked'
require_not_contains scripts/test-foundation-remote.sh 'supabase link'
require_not_contains scripts/test-foundation-remote.sh 'supabase db push'
require_not_contains scripts/test-foundation-remote.sh 'supabase db reset'
require_not_contains scripts/test-foundation-remote.sh 'supabase functions deploy'
require_contains scripts/test-backend-security.sh 'scope="${2:---local}"'

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
