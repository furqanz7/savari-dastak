#!/usr/bin/env bash
set -euo pipefail
backend_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Host psql can resolve migration includes; the Supabase pgTAP Docker runner
# mounts only test files. All fixtures and schedule changes roll back locally.
PGPASSWORD=postgres psql -X -qAt -h 127.0.0.1 -p 54322 -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f "$backend_dir/scripts/notification-repair-regression.sql"
