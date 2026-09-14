-- Attach the after capture as `after`, then compare mechanically equivalent cases.
WITH checks AS (
    SELECT
      (SELECT value FROM main.metadata WHERE key='schema_version')='2'
      AND (SELECT value FROM after.metadata WHERE key='schema_version')='2' AS schema_ok,
      (SELECT value FROM main.metadata WHERE key='clean_shutdown')='1'
      AND (SELECT value FROM after.metadata WHERE key='clean_shutdown')='1'
      AND (SELECT value FROM main.metadata WHERE key='final_state')='complete'
      AND (SELECT value FROM after.metadata WHERE key='final_state')='complete' AS captures_ok,
      (SELECT value FROM main.metadata WHERE key='spec_hash')=(SELECT value FROM after.metadata WHERE key='spec_hash')
      AND (SELECT value FROM main.metadata WHERE key='benchmark_scale')=(SELECT value FROM after.metadata WHERE key='benchmark_scale')
      AND (SELECT value FROM main.metadata WHERE key='benchmark_samples')=(SELECT value FROM after.metadata WHERE key='benchmark_samples')
      AND (SELECT value FROM main.metadata WHERE key='benchmark_iterations')=(SELECT value FROM after.metadata WHERE key='benchmark_iterations')
      AND (SELECT value FROM main.metadata WHERE key='benchmark_initial_size')=(SELECT value FROM after.metadata WHERE key='benchmark_initial_size')
      AND (SELECT value FROM main.metadata WHERE key='benchmark_change_size')=(SELECT value FROM after.metadata WHERE key='benchmark_change_size') AS workload_ok,
      (SELECT value FROM main.metadata WHERE key='backend')=(SELECT value FROM after.metadata WHERE key='backend')
      AND (SELECT value FROM main.metadata WHERE key='target_profile')=(SELECT value FROM after.metadata WHERE key='target_profile')
      AND (SELECT value FROM main.metadata WHERE key='host_os')=(SELECT value FROM after.metadata WHERE key='host_os')
      AND (SELECT value FROM main.metadata WHERE key='host_arch')=(SELECT value FROM after.metadata WHERE key='host_arch')
      AND (SELECT value FROM main.metadata WHERE key='cpu_model')=(SELECT value FROM after.metadata WHERE key='cpu_model')
      AND (SELECT value FROM main.metadata WHERE key='logical_cpu_count')=(SELECT value FROM after.metadata WHERE key='logical_cpu_count')
      AND (SELECT value FROM main.metadata WHERE key='requested_detail')=(SELECT value FROM after.metadata WHERE key='requested_detail')
      AND (SELECT value FROM main.metadata WHERE key='buffer_mib')=(SELECT value FROM after.metadata WHERE key='buffer_mib') AS environment_ok
), before_values AS (
    SELECT avg(duration_ns) AS mean_ns FROM main.steps s JOIN main.runs r ON r.id=s.run_id
    WHERE s.role='operation' AND s.status='pass' AND r.phase='sample'
), after_values AS (
    SELECT avg(duration_ns) AS mean_ns FROM after.steps s JOIN after.runs r ON r.id=s.run_id
    WHERE s.role='operation' AND s.status='pass' AND r.phase='sample'
), verdict AS (
    SELECT *,schema_ok AND captures_ok AND workload_ok AND environment_ok AS comparable,
      CASE WHEN NOT schema_ok THEN 'schema version differs or is unsupported'
           WHEN NOT captures_ok THEN 'one or both captures are incomplete'
           WHEN NOT workload_ok THEN 'spec or benchmark policy differs'
           WHEN NOT environment_ok THEN 'backend, profile, system, CPU, or recorder policy differs'
           ELSE 'mechanically comparable; machine timing remains report-only' END AS reason
    FROM checks
)
SELECT CASE WHEN comparable THEN 'complete' ELSE 'incomparable' END AS evidence_status,
       reason AS evidence_reason,
       CASE WHEN comparable THEN before_values.mean_ns END AS before_mean_ns,
       CASE WHEN comparable THEN after_values.mean_ns END AS after_mean_ns,
       CASE WHEN comparable THEN after_values.mean_ns-before_values.mean_ns END AS mean_delta_ns,
       CASE WHEN comparable THEN after_values.mean_ns/before_values.mean_ns END AS ratio
FROM verdict CROSS JOIN before_values CROSS JOIN after_values;
