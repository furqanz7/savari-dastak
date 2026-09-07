#!/usr/bin/env bash
set -euo pipefail

# This gate inspects configuration only. It does not invoke the worker or send a push.
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "${1:-}" in
  --linked|--local) target="$1" ;;
  *) echo "Usage: bash scripts/check-merchant-notifications.sh --linked|--local" >&2; exit 2 ;;
esac
cd "$task_root/Backends/Dastak"
supabase db query "$target" --file scripts/check-merchant-notifications.sql --output json |
  node -e '
    let input = "";
    process.stdin.on("data", chunk => input += chunk);
    process.stdin.on("end", () => {
      const data = JSON.parse(input);
      const row = (data.rows ?? data)[0];
      if (!row) throw new Error("Notification configuration query returned no result");
      console.log(JSON.stringify(row, null, 2));
      if (!row.routes_ready || !row.worker_scheduled) process.exitCode = 1;
      if (!row.active_merchant_devices) console.warn("No active Merchant devices: native registration still required.");
    });'
