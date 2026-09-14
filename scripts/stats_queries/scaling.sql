-- Headline timing comes from cycles whose boundary excludes locator resolution.
WITH evidence AS (SELECT status,reason FROM measurement_status WHERE name='host_cycles'),
scale_evidence AS (SELECT status,reason FROM measurement_status WHERE name='scale_verification'),
measured AS (
 SELECT cycles.trigger,cycles.duration_ns,
  row_number() OVER (PARTITION BY cycles.trigger ORDER BY cycles.duration_ns) n,
  count(*) OVER (PARTITION BY cycles.trigger) c
 FROM cycles JOIN runs ON runs.id=cycles.run_id
 WHERE cycles.measurement_phase='measured' AND runs.phase='sample'
), summary AS (
 SELECT trigger,count(*) samples,min(duration_ns) min_ns,
  avg(CASE WHEN n IN ((c+1)/2,(c+2)/2) THEN duration_ns END) median_ns,
  max(duration_ns)-min(duration_ns) spread_ns FROM measured GROUP BY trigger
), verified AS (
 SELECT count(*) checks,min(observed_count) min_observed_count,max(observed_count) max_observed_count,
  sum(CASE WHEN expected_count<>observed_count THEN 1 ELSE 0 END) mismatches
 FROM steps JOIN runs ON runs.id=steps.run_id
 WHERE runs.phase='sample' AND expected_count IS NOT NULL
)
SELECT evidence.status evidence_status,evidence.reason evidence_reason,
 scale_evidence.status scale_evidence_status,scale_evidence.reason scale_evidence_reason,
 (SELECT value FROM metadata WHERE key='spec_name') spec_name,
 CAST((SELECT value FROM metadata WHERE key='benchmark_scale') AS INTEGER) scale,
 CAST((SELECT value FROM metadata WHERE key='benchmark_initial_size') AS INTEGER) initial_size,
 CAST((SELECT value FROM metadata WHERE key='benchmark_change_size') AS INTEGER) change_size,
 (SELECT value FROM metadata WHERE key='timing_quality') timing_quality,
 verified.*,summary.trigger,summary.samples,
 CASE WHEN evidence.status='complete' AND scale_evidence.status='complete' THEN summary.min_ns END min_ns,
 CASE WHEN evidence.status='complete' AND scale_evidence.status='complete' THEN summary.median_ns END median_ns,
 CASE WHEN evidence.status='complete' AND scale_evidence.status='complete' THEN summary.spread_ns END spread_ns
FROM evidence CROSS JOIN scale_evidence CROSS JOIN verified
LEFT JOIN summary ON evidence.status='complete' AND scale_evidence.status='complete';
