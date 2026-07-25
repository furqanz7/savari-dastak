#!/usr/bin/env bash
set -euo pipefail

backend="${1:?usage: scripts/test-backend-security.sh Savari|Dastak [--local|--linked]}"
scope="${2:---local}"
case "$backend" in
  Savari|Dastak) ;;
  *)
    printf 'usage: %s Savari|Dastak [--local|--linked]\n' "$0" >&2
    exit 64
    ;;
esac
case "$scope" in
  --local|--linked) ;;
  *)
    printf 'usage: %s Savari|Dastak [--local|--linked]\n' "$0" >&2
    exit 64
    ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root/Backends/$backend"

shopt -s nullglob
test_files=(supabase/tests/database/*.pgtap.sql)
if (( ${#test_files[@]} == 0 )); then
  printf 'No pgTAP database tests found for %s.\n' "$backend" >&2
  exit 1
fi

run_linked_pgtap() {
  local test_file="$1"
  local output
  local pooler_url

  pooler_url="$(< supabase/.temp/pooler-url)"
  if output="$(
    PGPASSWORD="$SUPABASE_DB_PASSWORD" psql "$pooler_url" \
      -X -qAt -v ON_ERROR_STOP=1 -f "$test_file" 2>&1
  )"; then
    printf '%s\n' "$output"
  else
    local status=$?
    printf '%s\n' "$output" >&2
    return "$status"
  fi

  if rg -q '^[[:space:]]*(not ok|# Looks like)' <<< "$output"; then
    printf 'pgTAP assertions failed in %s\n' "$test_file" >&2
    return 1
  fi
}

if [[ "$scope" == "--linked" ]]; then
  for command_name in psql rg; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      printf 'Missing required linked-test prerequisite: %s\n' "$command_name" >&2
      exit 127
    fi
  done
  if [[ -z "${SUPABASE_DB_PASSWORD:-}" ]]; then
    printf 'SUPABASE_DB_PASSWORD is required for linked database tests.\n' >&2
    exit 64
  fi
  if [[ ! -f supabase/.temp/pooler-url ]]; then
    printf '%s is not linked to a Supabase project.\n' "$backend" >&2
    exit 1
  fi

  for test_file in "${test_files[@]}"; do
    run_linked_pgtap "$test_file"
  done
else
  supabase db test "${test_files[@]}" "$scope"
fi

if [[ -n "${SUPABASE_PROFILE:-}" ]]; then
  supabase db query "$scope" \
    --file "$repo_root/scripts/assert-no-client-dml.sql" \
    --profile "$SUPABASE_PROFILE"
else
  supabase db query "$scope" --file "$repo_root/scripts/assert-no-client-dml.sql"
fi
