#!/usr/bin/env bash
set -euo pipefail

backend="${1:?usage: scripts/test-backend-security.sh Savari|Dastak}"
case "$backend" in
  Savari|Dastak) ;;
  *)
    printf 'usage: %s Savari|Dastak\n' "$0" >&2
    exit 64
    ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root/Backends/$backend"

supabase db test supabase/tests/database/001_identity.pgtap.sql --local
supabase db test supabase/tests/database/002_security_audit_zones.pgtap.sql --local
supabase db query --local --file "$repo_root/scripts/assert-no-client-dml.sql"
