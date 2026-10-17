-- SYNTHETIC LOCAL FIXTURE ONLY. Never run against a linked/production database.
-- The guarded runner creates a fresh isolated PostgreSQL cluster before running this.
\set ON_ERROR_STOP on
-- Fail before any DDL unless the caller selected the dedicated Unix-socket fixture DB.
SELECT 1 / CASE WHEN current_database() = 'retention_fingerprint_check'
  AND inet_server_addr() IS NULL THEN 1 ELSE 0 END AS local_fixture_guard;
SET timezone = 'UTC';
CREATE SCHEMA fixture;
CREATE TABLE fixture.job_run_details (
  runid bigint PRIMARY KEY, status text, end_time timestamptz, details text
);
-- Fixed cutoff is 2026-10-14 00:00 UTC. It never moves during the operation.
INSERT INTO fixture.job_run_details VALUES
  (1, 'succeeded', '2026-10-01T00:00:00Z', E'local, fixture\n"quoted" دستک'),
  (2, 'failed', '2026-10-01T00:00:00Z', 'old failure'),
  (3, 'running', NULL, 'unfinished'),
  (4, 'succeeded', '2026-10-14T00:00:00Z', 'exact boundary'),
  (5, 'succeeded', '2026-10-15T00:00:00Z', 'recent'),
  (6, 'succeeded', NULL, 'missing completion'),
  (7, 'cancelled', '2026-10-01T00:00:00Z', 'non-success terminal'),
  (8, 'succeeded', '2026-10-10T00:00:00Z', 'old success'),
  (9, 'succeeded', '2026-10-10T00:00:00Z', 'old success'),
  (10, 'succeeded', '2026-10-10T00:00:00Z', 'old success'),
  (11, 'succeeded', '2026-10-10T00:00:00Z', 'old success'),
  (12, 'succeeded', '2026-10-10T00:00:00Z', 'old success'),
  (13, 'succeeded', '2026-10-10T00:00:00Z', 'old success'),
  (14, 'succeeded', '2026-10-10T00:00:00Z', 'changes after backup');
CREATE TABLE fixture.original AS TABLE fixture.job_run_details;
CREATE TABLE fixture.recovery_archive AS
  SELECT * FROM fixture.job_run_details
  WHERE runid <= 14 AND status = 'succeeded'
    AND end_time < '2026-10-14T00:00:00Z'::timestamptz;
-- Represent a late insert and an unexpected modification after the archive snapshot.
INSERT INTO fixture.job_run_details VALUES
  (15, 'succeeded', '2026-10-01T00:00:00Z', 'late insert excluded by high-water mark');
UPDATE fixture.job_run_details SET details = 'changed after archive' WHERE runid = 14;

DO $$
DECLARE
  batch_count integer;
  total_count integer := 0;
BEGIN
  LOOP
    WITH candidates AS (
      SELECT h.runid
      FROM fixture.job_run_details AS h
      JOIN fixture.recovery_archive AS a ON a.runid = h.runid
      WHERE h.runid <= 14 AND h.status = 'succeeded'
        AND h.end_time < '2026-10-14T00:00:00Z'::timestamptz
        AND md5(to_jsonb(h)::text) = md5(to_jsonb(a)::text)
      ORDER BY h.runid LIMIT 2
    ), removed AS (
      DELETE FROM fixture.job_run_details AS h USING candidates AS c
      WHERE h.runid = c.runid RETURNING h.runid
    ) SELECT count(*) INTO batch_count FROM removed;
    IF batch_count > 2 THEN RAISE EXCEPTION 'batch limit exceeded'; END IF;
    total_count := total_count + batch_count;
    EXIT WHEN batch_count = 0;
  END LOOP;
  IF total_count <> 7 THEN RAISE EXCEPTION 'expected 7 deletions, got %', total_count; END IF;
  IF (SELECT array_agg(runid ORDER BY runid) FROM fixture.job_run_details)
       IS DISTINCT FROM ARRAY[2,3,4,5,6,7,14,15]::bigint[] THEN
    RAISE EXCEPTION 'protected rows were lost';
  END IF;
END;
$$;

-- Retry after completion must be harmless.
WITH removed AS (
  DELETE FROM fixture.job_run_details AS h USING fixture.recovery_archive AS a
  WHERE h.runid = a.runid AND h.runid <= 14 AND h.status = 'succeeded'
    AND h.end_time < '2026-10-14T00:00:00Z'::timestamptz
    AND md5(to_jsonb(h)::text) = md5(to_jsonb(a)::text) RETURNING h.runid
)
SELECT 1 / CASE WHEN count(*) = 0 THEN 1 ELSE 0 END AS retry_is_noop FROM removed;

-- Restore missing archived rows, without overwriting the row changed after backup.
INSERT INTO fixture.job_run_details
SELECT * FROM fixture.recovery_archive
ON CONFLICT (runid) DO NOTHING;
DO $$
BEGIN
  IF EXISTS (
    SELECT * FROM fixture.original WHERE runid <> 14
    EXCEPT SELECT * FROM fixture.job_run_details WHERE runid <> 14
  ) THEN RAISE EXCEPTION 'recovery did not reproduce original rows'; END IF;
  IF (SELECT details FROM fixture.job_run_details WHERE runid = 14)
       <> 'changed after archive' THEN RAISE EXCEPTION 'recovery overwrote changed row'; END IF;
  IF (SELECT count(*) FROM fixture.job_run_details) <> 15 THEN
    RAISE EXCEPTION 'unexpected recovered row count'; END IF;
END;
$$;
SELECT 'PASS: eligibility, boundary, batch bound, high-water mark, changed-row guard, retry and recovery' AS result;
