-- Read-only metadata audit. No row contents or account identifiers are read.
WITH relations AS (
  SELECT c.oid, n.nspname AS schema_name, c.relname AS relation_name,
    pg_total_relation_size(c.oid) AS total_bytes,
    pg_table_size(c.oid) AS table_bytes,
    pg_indexes_size(c.oid) AS index_bytes,
    greatest(c.reltuples, 0)::bigint AS estimated_rows,
    coalesce(s.n_dead_tup, 0) AS estimated_dead_rows,
    s.last_autovacuum, s.last_autoanalyze
  FROM pg_class AS c
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  LEFT JOIN pg_stat_all_tables AS s ON s.relid = c.oid
  WHERE c.relkind IN ('r', 'm')
    AND n.nspname NOT IN ('pg_toast', 'information_schema')
    AND n.nspname NOT LIKE 'pg_temp_%'
), schema_totals AS (
  SELECT schema_name, sum(total_bytes)::bigint AS total_bytes,
    sum(table_bytes)::bigint AS table_bytes, sum(index_bytes)::bigint AS index_bytes,
    count(*) AS relations
  FROM relations GROUP BY schema_name
), largest AS (
  SELECT * FROM relations ORDER BY total_bytes DESC LIMIT 25
)
SELECT jsonb_build_object(
  'database_bytes', pg_database_size(current_database()),
  'database_size', pg_size_pretty(pg_database_size(current_database())),
  'transaction_read_only', current_setting('transaction_read_only'),
  'default_transaction_read_only', current_setting('default_transaction_read_only'),
  'relation_total_bytes', (SELECT sum(total_bytes)::bigint FROM relations),
  'schemas', (SELECT jsonb_agg(to_jsonb(s) ORDER BY total_bytes DESC) FROM schema_totals AS s),
  'largest_relations', (SELECT jsonb_agg(to_jsonb(l) ORDER BY total_bytes DESC) FROM largest AS l)
) AS size_audit;
