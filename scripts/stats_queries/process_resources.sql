-- Process-wide deltas sampled outside the measured operation timing boundary.
WITH evidence AS (
    SELECT status,reason FROM measurement_status WHERE name='process_resources'
), measured AS (
    SELECT count(*) AS runs,
           sum(end_cpu_user_ns-start_cpu_user_ns) AS cpu_user_ns,
           sum(end_cpu_system_ns-start_cpu_system_ns) AS cpu_system_ns,
           max(end_max_rss_bytes) AS peak_rss_bytes
    FROM runs WHERE phase='sample' AND ended_ns IS NOT NULL
)
SELECT evidence.status AS evidence_status,evidence.reason AS evidence_reason,
       measured.runs,
       CASE WHEN evidence.status='complete' THEN measured.cpu_user_ns END AS cpu_user_ns,
       CASE WHEN evidence.status='complete' THEN measured.cpu_system_ns END AS cpu_system_ns,
       CASE WHEN evidence.status='complete' THEN measured.peak_rss_bytes END AS peak_rss_bytes,
       'unavailable: startup phase decomposition is not instrumented' AS startup_decomposition
FROM evidence CROSS JOIN measured;
