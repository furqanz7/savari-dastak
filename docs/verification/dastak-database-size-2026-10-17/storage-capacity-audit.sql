-- Aggregate metadata only. Do not return object names, owners, URLs, or contents.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '10s';
SELECT bucket_id, count(*) AS objects,
  count(*) FILTER (WHERE coalesce(metadata ->> 'size', '') !~ '^[0-9]{1,18}$')
    AS objects_without_valid_size,
  coalesce(sum(CASE WHEN metadata ->> 'size' ~ '^[0-9]{1,18}$'
    THEN (metadata ->> 'size')::bigint ELSE 0 END), 0) AS known_bytes
FROM storage.objects
GROUP BY bucket_id ORDER BY known_bytes DESC;
ROLLBACK;
