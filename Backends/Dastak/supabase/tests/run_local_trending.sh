#!/usr/bin/env bash
set -euo pipefail
task_test_root="$(mktemp -d /tmp/dastak-trending-test.XXXXXX)"
task_supabase_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cleanup() {
  pg_ctl -D "$task_test_root/data" -m fast stop >/dev/null 2>&1 || true
  find "$task_test_root" -depth -delete
}
trap cleanup EXIT
mkdir "$task_test_root/socket"
initdb -D "$task_test_root/data" -A trust --no-locale > "$task_test_root/init.log"
pg_ctl -D "$task_test_root/data" -o "-k $task_test_root/socket -h '' -p 55487" -l "$task_test_root/server.log" start >/dev/null
psql -h "$task_test_root/socket" -p 55487 -d postgres -v ON_ERROR_STOP=1 \
  -f "$task_supabase_root/tests/local_trending_fixture.sql" \
  -f "$task_supabase_root/migrations/20261013233951_customer_local_trending.sql" \
  -f "$task_supabase_root/tests/local_trending_assertions.sql"
