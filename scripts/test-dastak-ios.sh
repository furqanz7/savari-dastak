#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="$repo_root/SavariDastak.xcworkspace"
derived_data="${RUNNER_TEMP:-/tmp}/dastak-quality-derived"

for command_name in xcodebuild sed tr; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required Dastak iOS prerequisite: %s\n' "$command_name" >&2
    exit 127
  fi
done

destination="$(
  xcodebuild -workspace "$workspace" -scheme Dastak -showdestinations 2>/dev/null \
    | sed -nE '/platform:iOS Simulator, arch:.*name:iPhone/ { p; q; }'
)"
simulator_id="$(
  sed -E 's/.*id:([^,]+),.*/\1/' <<< "$destination" \
    | tr -d '[:space:]'
)"

if [[ -z "$simulator_id" || "$simulator_id" == "$destination" ]]; then
  printf 'No concrete iPhone simulator is available for Dastak tests.\n' >&2
  exit 1
fi

for scheme in Dastak DastakMerchant DastakAdmin; do
  xcodebuild \
    -workspace "$workspace" \
    -scheme "$scheme" \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath "$derived_data" \
    -configuration Debug \
    -parallel-testing-enabled NO \
    -quiet \
    CODE_SIGNING_ALLOWED=NO \
    'MARKETPLACE_SUPABASE_URL=https:/$()/ci.supabase.co' \
    MARKETPLACE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_ci \
    test
done
