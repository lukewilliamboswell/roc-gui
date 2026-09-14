-- Summarize marked operations while retaining honest evidence status.
WITH evidence AS (
    SELECT status,reason FROM measurement_status WHERE name='step_results'
), scale_evidence AS (
    SELECT status,reason FROM measurement_status WHERE name='scale_verification'
), measured AS (
    SELECT steps.kind,steps.duration_ns,
           row_number() OVER (PARTITION BY steps.kind ORDER BY steps.duration_ns) AS n,
           count(*) OVER (PARTITION BY steps.kind) AS c
    FROM steps JOIN runs ON runs.id=steps.run_id
    WHERE steps.role='operation' AND steps.status='pass' AND runs.phase='sample'
), summary AS (
    SELECT kind,count(*) AS samples,
           avg(duration_ns) AS mean_ns,
           max(CASE WHEN n=(c+1)/2 THEN duration_ns END) AS median_ns,
           max(CASE WHEN n=(c*95+99)/100 THEN duration_ns END) AS p95_ns
    FROM measured GROUP BY kind
), verified AS (
    SELECT count(*) AS checks,
           min(observed_count) AS min_observed_count,
           max(observed_count) AS max_observed_count,
           sum(CASE WHEN expected_count<>observed_count THEN 1 ELSE 0 END) AS mismatches
    FROM steps JOIN runs ON runs.id=steps.run_id
    WHERE runs.phase='sample' AND expected_count IS NOT NULL
)
SELECT evidence.status AS evidence_status,evidence.reason AS evidence_reason,
       scale_evidence.status AS scale_evidence_status,
       scale_evidence.reason AS scale_evidence_reason,
       (SELECT value FROM metadata WHERE key='spec_name') AS spec_name,
       CAST((SELECT value FROM metadata WHERE key='benchmark_scale') AS INTEGER) AS scale,
       CAST((SELECT value FROM metadata WHERE key='benchmark_initial_size') AS INTEGER) AS initial_size,
       CAST((SELECT value FROM metadata WHERE key='benchmark_change_size') AS INTEGER) AS change_size,
       verified.checks,verified.min_observed_count,verified.max_observed_count,
       verified.mismatches,
       summary.kind,summary.samples,
       CASE WHEN evidence.status='complete' AND scale_evidence.status='complete' THEN summary.mean_ns END AS mean_ns,
       CASE WHEN evidence.status='complete' AND scale_evidence.status='complete' THEN summary.median_ns END AS median_ns,
       CASE WHEN evidence.status='complete' AND scale_evidence.status='complete' THEN summary.p95_ns END AS p95_ns
FROM evidence CROSS JOIN scale_evidence CROSS JOIN verified
LEFT JOIN summary ON evidence.status='complete' AND scale_evidence.status='complete';
