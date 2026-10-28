# Merchant privacy — read-only hosted logging check

23 October 2026, Asia/Kolkata. Owner authorized the follow-up hosting check.
**No configuration changes, migration, deployment, publication, payout, order,
support-ticket submission, new role grant or App Store action was performed.**

Related: [review pack](dastak-merchant-privacy-review-pack-2026-10-21.md) and
[proposed policy](dastak-merchant-privacy-policy-proposed-2026-10-21.md).

## Access and scope

- Signed-in Safari: Dastak project `zmtsolkfxlrxepshnjdf`, main/production,
  organization Free plan. Customer's App Store tab was left unchanged.
- Supabase CLI 2.90.0; command flags inspected with `--help` before use. The
  existing linked project reference matched Dastak before database reads.
- No authentication token was extracted from Safari, no secret list/value was
  retrieved and no personal log payload was exported. UI log queries returned
  attribute names and aggregate counts only. Database reads returned settings
  and function-body digests, not application/user rows.
- The CLI printed its normal `Initialising login role...` connection message;
  no role/permission DDL or access expansion was requested by this task.
- Guard: branch `codex/dastak-v1-launch`, HEAD
  `21aaaf1f86b9383e7c0f3aa075857ef553cdfe8b` unchanged. Protected unrelated diff
  SHA-256 remains `89cb303d44be0291e8103a744cb49acf66052e15d35e60f9bd2fac5dadbeb473`.

## Hosted facts directly verified

1. **Supabase Log Drains:** project Settings → Log Drains shows the Free-plan
   upgrade/empty state, not a configured destination. No upgrade was selected.
   This is not an audit of arbitrary external infrastructure or Vercel drains.
2. **Postgres config overrides API:** `postgres-config get --experimental`
   returned `{}`. This only means no overrides in that API response, not that
   defaults, role settings or logging are absent.
3. **Retained log fields:** Explorer → Run SQL → source **Logs**, last hour,
   using the documented ClickHouse `logs`/`log_attributes` interface. No raw
   event message, body, user identifier, token, IP or location value selected.

First field-discovery query showed `request.cf.city`, `request.cf.country`,
`request.headers.cf_connecting_ip` and `request.headers.user_agent` each populated
in 1,498 sampled gateway events. The second query, run slightly later, summarized:

| Source | Events | Nonempty body/query-named structured attributes | Nonempty timing-named attributes | Nonempty city/country attributes |
| --- | ---: | ---: | ---: | ---: |
| edge_logs | 1497 | 0 | 0 | 1497 |
| function_edge_logs | 538 | 0 | 538 | 538 |
| function_logs | 1053 | 0 | 0 | 0 |
| pgbouncer_logs | 9 | 0 | 0 | 0 |
| postgres_logs | 4984 | 4984 | 0 | 0 |
| realtime_logs | 2 | 0 | 0 | 0 |
| storage_logs | 2 | 0 | 0 | 0 |

These are project-wide samples, not Merchant-only traffic or lifetime counts.
The shifting gateway count reflects the moving one-hour window. The match
expressions are heuristics over structured key names. A zero does not exclude
content embedded in an event message or hidden by another field name. In
particular, the Postgres query-field count does not establish that actual user
search strings occur in those fields; their values were deliberately not read.

```sql
SELECT source, count() AS events,
countIf(arrayExists(k -> match(k, '(?i)body|query') AND log_attributes[k] != '', mapKeys(log_attributes))) AS body_or_query_events,
countIf(arrayExists(k -> match(k, '(?i)duration|execution.time|response.time|latency') AND log_attributes[k] != '', mapKeys(log_attributes))) AS timing_events,
countIf(log_attributes['request.cf.city'] != '' OR log_attributes['request.cf.country'] != '') AS geography_events
FROM logs
WHERE timestamp >= now() - INTERVAL 1 HOUR
GROUP BY source ORDER BY source LIMIT 20;
```

## Actual Postgres logging settings

Read-only `pg_settings` inspection via the linked Management API:

| Setting | Live value | Interpretation |
| --- | --- | --- |
| log_statement | ddl | Ordinary catalogue SELECT calls are not enabled by this setting |
| log_min_duration_statement | -1 | Duration-based statement logging disabled |
| log_min_error_statement | error | Statements associated with qualifying errors can still be logged |
| log_parameter_max_length | -1 | Parameters would not be truncated when a separate statement-logging mode logs them; not a global guarantee of secrecy |
| log_parameter_max_length_on_error | 0 | Bound parameter values omitted from error logging |
| pgaudit.log | none | No pgAudit statement classes enabled in inspected session defaults |
| pgaudit.log_parameter | off | pgAudit parameter logging off |
| log_connections / log_disconnections | off / off | Connection/disconnection event logging off in these settings |
| pg_stat_statements.track | top | Top-level statement statistics enabled |
| pg_stat_statements.track_utility | on | Utility statistics enabled |
| pg_stat_statements.save | on | Statistics persist across clean restarts |
| track_activity_query_size | 1024 | Activity query-text size limit, not a deletion policy |

`pg_db_role_setting` was also checked for the listed logging parameters. The only
matching overrides returned were `log_statement=none` for `supabase_admin`,
`supabase_auth_admin` and `supabase_storage_admin`. This is not a statement that
all runtime SET commands or function-local settings are impossible. No logging
setting was modified to obtain this result.

## Live catalogue path tied back to inspected code

Both live SQL bodies matched the source migration
`20261018131824_merchant_catalogue_and_location_pages.sql` exactly:

| Routine | SHA-256 of prosrc body | Volatility |
| --- | --- | --- |
| dastak_v1_api.merchant_inventory_page | 1626675281d8ba1082f296764a577bcea7fcea735bb97ab734878c72a211e305 | stable |
| public.dastak_v1_merchant_inventory_page | 38c1f7844a4fa28f501bbf28fd519ec0d8e88a8db1bba9559f2de1cf513ef813 | stable |

These bodies implement authorized reads and do not insert a search-history row.
Only function names, volatility and digests were returned by the database query.

The deployed `dastak-v1-catalogue` bundle was downloaded read-only using the
official CLI into a new isolated temporary directory:
`/private/tmp/dastak-merchant-privacy-hosting.U8TY0E`.
No repository source was overwritten. Files were compared byte-for-byte:

| File | Matches repository | Deployed SHA-256 |
| --- | --- | --- |
| dastak-v1-catalogue/index.ts | yes | b3235b8c9f27e5a413898f76ec4a094eefec02da93df701ca4124a0c43abdccd |
| dastak-v1-catalogue/handler.ts | yes | 5f2e73b237f7c633d20db4cf50d4fd3ae51a99f5e5a1ad46499dbc891fcd76c9 |
| _shared/v1-rpc.ts | yes | 42951d9344cd7642802028719a582ec2cfe719f230f986086075d2890e5637d8 |
| _shared/http.ts | yes | f529c58c27b6de5d713031457fb15ed2addef399eac0ca9cf1ad09ad5eff8e07 |
| _shared/auth.ts | no | edc41745be80f59c6d118559f864d5aa763285f7602e3faf8b54ab3b125fa5fa |

The auth difference was inspected: deployed code lacks the newer optional
AbortSignal/cancellation plumbing added for the support endpoint. It still
performs bearer/session verification and revocation checks. No added search
logger or secondary recipient was present. This is not automatically a new bug
or authorization to redeploy a previously unchanged endpoint. No deployment was
performed. The inspected deployed search handler/RPC helper has no custom query
logging/telemetry implementation.

## Privacy decisions supported by this check

- **Coarse Location:** keep selected, App Functionality, linked, no tracking.
  IP-derived approximate city/country is retained in the actual project's logs.
- **Performance Data:** keep selected, App Functionality, linked, no tracking.
  Function request timing fields are actually retained. Do not claim native
  launch/hang/energy profiling from this evidence.
- **Other Diagnostic Data:** keep selected for retained technical/network/error
  metadata. No anonymization guarantee was established.
- **Search History:** propose leaving unselected for the current inspected
  Merchant path: source and live SQL do not save it; deployed function code has
  no query logger; sampled structured invocation metadata contains no readable
  body/query fields; current database settings do not log ordinary SELECT calls
  or bound parameter values on errors. This is a reasoned bounded conclusion,
  not proof of zero possible query retention in every provider/error condition.
  Reassess on logging/code/provider changes; do not infer absence solely from
  a zero count. No synthetic user search was performed to extend this evidence.
- No App Store Connect answers were entered, saved or published by this check.
  Owner approval of mappings and policy wording remains separate.

## Limits intentionally left explicit

Exact plan retention TTL was not independently read from a project-specific
setting; observed stored events prove collection beyond the immediate request,
not a guaranteed deletion schedule. The draft correctly promises no fixed
log-expiry period. No raw payload inspection, longer time-window export or
synthetic request was needed/performed. This check does not certify independent
provider secondary uses, all deployed functions, payout capability/credentials,
Vercel configuration, backups or data-deletion compliance.

The dashboard displayed general technical-issue and grace-period/quota banners.
Those banners alone do not establish a current outage or quota exhaustion;
aggregate logs and database reads succeeded. No billing purchase or cleanup was
performed, and no service-health guarantee is made here.

## References consulted on 23 October

- [Supabase log queries and safe bounds](https://supabase.com/docs/guides/observability/advanced-log-filtering)
- [Supabase log sources and fields](https://supabase.com/docs/guides/observability/log-field-reference)
- [Supabase function logging](https://supabase.com/docs/guides/functions/logging)
- [Supabase log drains](https://supabase.com/docs/guides/observability/log-drains)
- [Postgres logging parameter definitions](https://www.postgresql.org/docs/current/runtime-config-logging.html)
