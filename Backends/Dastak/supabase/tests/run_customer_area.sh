#!/usr/bin/env bash
set -euo pipefail
for task_binary in initdb pg_ctl psql; do command -v "$task_binary" >/dev/null; done
task_test_root="$(mktemp -d /tmp/dastak-area-test.XXXXXX)"
task_supabase_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cleanup() {
  pg_ctl -D "$task_test_root/data" -m fast stop >/dev/null 2>&1 || true
  find "$task_test_root" -depth -delete
}
trap cleanup EXIT
mkdir "$task_test_root/socket"
initdb -D "$task_test_root/data" -A trust --no-locale > "$task_test_root/init.log"
pg_ctl -D "$task_test_root/data" -o "-k $task_test_root/socket -h '' -p 55489" -l "$task_test_root/server.log" start >/dev/null
psql -h "$task_test_root/socket" -p 55489 -d postgres -v ON_ERROR_STOP=1 \
  -f "$task_supabase_root/tests/customer_area_fixture.sql" \
  -f "$task_supabase_root/migrations/20261007200623_customer_food_cursor_pages.sql" \
  -f "$task_supabase_root/migrations/20261008095639_customer_area_availability.sql" \
  -f "$task_supabase_root/tests/customer_area_assertions.sql" \
  -f "$task_supabase_root/tests/customer_visibility_fixture.sql" \
  -f "$task_supabase_root/migrations/20261008114655_admin_customer_restaurant_visibility.sql" \
  -f "$task_supabase_root/tests/customer_visibility_assertions.sql" \
  -f "$task_supabase_root/tests/customer_active_orders_fixture.sql" \
  -f "$task_supabase_root/migrations/20261008130951_customer_active_order_discovery.sql" \
  -f "$task_supabase_root/tests/customer_active_orders_assertions.sql"
