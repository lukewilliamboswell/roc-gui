-- Compare attributed cycle distributions. Run the same executable twice for A/A noise.
WITH checks AS (
 SELECT
  (SELECT value FROM main.metadata WHERE key='schema_version')='5' AND
  (SELECT value FROM after.metadata WHERE key='schema_version')='5' AS schema_ok,
  (SELECT value FROM main.metadata WHERE key='clean_shutdown')='1' AND
  (SELECT value FROM after.metadata WHERE key='clean_shutdown')='1' AND
  (SELECT value FROM main.metadata WHERE key='final_state')='complete' AND
  (SELECT value FROM after.metadata WHERE key='final_state')='complete' AS captures_ok,
  (SELECT value FROM main.metadata WHERE key='spec_hash')=(SELECT value FROM after.metadata WHERE key='spec_hash') AND
  (SELECT value FROM main.metadata WHERE key='benchmark_scale')=(SELECT value FROM after.metadata WHERE key='benchmark_scale') AND
  (SELECT value FROM main.metadata WHERE key='benchmark_samples')=(SELECT value FROM after.metadata WHERE key='benchmark_samples') AND
  (SELECT value FROM main.metadata WHERE key='benchmark_iterations')=(SELECT value FROM after.metadata WHERE key='benchmark_iterations') AND
  (SELECT value FROM main.metadata WHERE key='benchmark_initial_size')=(SELECT value FROM after.metadata WHERE key='benchmark_initial_size') AND
  (SELECT value FROM main.metadata WHERE key='benchmark_change_size')=(SELECT value FROM after.metadata WHERE key='benchmark_change_size') AS workload_ok,
  (SELECT value FROM main.metadata WHERE key='backend')=(SELECT value FROM after.metadata WHERE key='backend') AND
  (SELECT value FROM main.metadata WHERE key='target_profile')=(SELECT value FROM after.metadata WHERE key='target_profile') AND
  (SELECT value FROM main.metadata WHERE key='host_os')=(SELECT value FROM after.metadata WHERE key='host_os') AND
  (SELECT value FROM main.metadata WHERE key='host_arch')=(SELECT value FROM after.metadata WHERE key='host_arch') AND
  (SELECT value FROM main.metadata WHERE key='cpu_model')=(SELECT value FROM after.metadata WHERE key='cpu_model') AND
  (SELECT value FROM main.metadata WHERE key='logical_cpu_count')=(SELECT value FROM after.metadata WHERE key='logical_cpu_count') AND
  (SELECT value FROM main.metadata WHERE key='requested_detail')=(SELECT value FROM after.metadata WHERE key='requested_detail') AND
  (SELECT value FROM main.metadata WHERE key='job_count')=(SELECT value FROM after.metadata WHERE key='job_count') AND
  (SELECT value FROM main.metadata WHERE key='buffer_mib')=(SELECT value FROM after.metadata WHERE key='buffer_mib') AS environment_ok
), before_ranked AS (
 SELECT c.duration_ns,row_number() OVER (ORDER BY c.duration_ns) n,count(*) OVER () count
 FROM main.cycles c JOIN main.runs r ON r.id=c.run_id
 WHERE c.measurement_phase='measured' AND r.phase='sample'
), after_ranked AS (
 SELECT c.duration_ns,row_number() OVER (ORDER BY c.duration_ns) n,count(*) OVER () count
 FROM after.cycles c JOIN after.runs r ON r.id=c.run_id
 WHERE c.measurement_phase='measured' AND r.phase='sample'
), before_values AS (
 SELECT count(*) samples,min(duration_ns) min_ns,
  avg(CASE WHEN n IN ((count+1)/2,(count+2)/2) THEN duration_ns END) median_ns,
  max(duration_ns)-min(duration_ns) spread_ns FROM before_ranked
), after_values AS (
 SELECT count(*) samples,min(duration_ns) min_ns,
  avg(CASE WHEN n IN ((count+1)/2,(count+2)/2) THEN duration_ns END) median_ns,
  max(duration_ns)-min(duration_ns) spread_ns FROM after_ranked
), verdict AS (
 SELECT *,schema_ok AND captures_ok AND workload_ok AND environment_ok comparable,
  CASE WHEN NOT schema_ok THEN 'schema version differs or is unsupported'
       WHEN NOT captures_ok THEN 'one or both captures are incomplete'
       WHEN NOT workload_ok THEN 'spec or benchmark policy differs'
       WHEN NOT environment_ok THEN 'backend, profile, system, CPU, recorder, or job policy differs'
       ELSE 'mechanically comparable; inspect A/A spread before interpreting timing' END reason
 FROM checks
)
SELECT CASE WHEN comparable THEN 'complete' ELSE 'incomparable' END evidence_status,reason,
 CASE WHEN comparable THEN b.samples END,CASE WHEN comparable THEN b.min_ns END,
 CASE WHEN comparable THEN b.median_ns END,CASE WHEN comparable THEN b.spread_ns END,
 CASE WHEN comparable THEN a.samples END,CASE WHEN comparable THEN a.min_ns END,
 CASE WHEN comparable THEN a.median_ns END,CASE WHEN comparable THEN a.spread_ns END,
 CASE WHEN comparable THEN a.median_ns-b.median_ns END,
 CASE WHEN comparable THEN a.median_ns/b.median_ns END
FROM verdict CROSS JOIN before_values b CROSS JOIN after_values a;
