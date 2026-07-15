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

supabase db test supabase/tests/database/001_identity.pgtap.sql "$scope"
supabase db test supabase/tests/database/002_security_audit_zones.pgtap.sql "$scope"
supabase db query "$scope" --file "$repo_root/scripts/assert-no-client-dml.sql"
