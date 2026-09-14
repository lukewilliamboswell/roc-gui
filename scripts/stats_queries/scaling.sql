-- Summarize marked operations while retaining honest evidence status.
WITH evidence AS (
    SELECT status,reason FROM measurement_status WHERE name='step_results'
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
)
SELECT evidence.status AS evidence_status,evidence.reason AS evidence_reason,
       (SELECT value FROM metadata WHERE key='spec_name') AS spec_name,
       CAST((SELECT value FROM metadata WHERE key='benchmark_scale') AS INTEGER) AS scale,
       summary.kind,summary.samples,
       CASE WHEN evidence.status='complete' THEN summary.mean_ns END AS mean_ns,
       CASE WHEN evidence.status='complete' THEN summary.median_ns END AS median_ns,
       CASE WHEN evidence.status='complete' THEN summary.p95_ns END AS p95_ns
FROM evidence LEFT JOIN summary ON evidence.status='complete';
