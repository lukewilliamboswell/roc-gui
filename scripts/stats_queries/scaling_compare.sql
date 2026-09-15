-- Compare component growth between two different scales of the same executable.
-- Timings are means per measured cycle. Allocation scopes are deliberately
-- separate: lifecycle covers the complete sample run, while span covers only
-- work attributed by the Roc callback spans of the measured cycle.
WITH compatibility AS (
 SELECT
  (SELECT value FROM metadata WHERE key='app_name')=
    (SELECT value FROM scaled.metadata WHERE key='app_name') AND
  (SELECT value FROM metadata WHERE key='executable_hash')=
    (SELECT value FROM scaled.metadata WHERE key='executable_hash') AND
  (SELECT value FROM metadata WHERE key='backend')=
    (SELECT value FROM scaled.metadata WHERE key='backend') AND
  (SELECT value FROM metadata WHERE key='target_profile')=
    (SELECT value FROM scaled.metadata WHERE key='target_profile') AND
  (SELECT value FROM metadata WHERE key='host_os')=
    (SELECT value FROM scaled.metadata WHERE key='host_os') AND
  (SELECT value FROM metadata WHERE key='host_arch')=
    (SELECT value FROM scaled.metadata WHERE key='host_arch') AND
  (SELECT value FROM metadata WHERE key='cpu_model')=
    (SELECT value FROM scaled.metadata WHERE key='cpu_model') AND
  (SELECT value FROM metadata WHERE key='logical_cpu_count')=
    (SELECT value FROM scaled.metadata WHERE key='logical_cpu_count') AND
  (SELECT value FROM metadata WHERE key='requested_detail')=
    (SELECT value FROM scaled.metadata WHERE key='requested_detail') AND
  (SELECT value FROM metadata WHERE key='timing_quality')='isolated' AND
  (SELECT value FROM scaled.metadata WHERE key='timing_quality')='isolated' AND
  (SELECT value FROM metadata WHERE key='job_count')='1' AND
  (SELECT value FROM scaled.metadata WHERE key='job_count')='1' AND
  (SELECT value FROM metadata WHERE key='benchmark_scale')<>
    (SELECT value FROM scaled.metadata WHERE key='benchmark_scale') AS compatible
), base_status AS (
 SELECT
  (SELECT status FROM measurement_status WHERE name='host_cycles') host_status,
  (SELECT reason FROM measurement_status WHERE name='host_cycles') host_reason,
  (SELECT status FROM measurement_status WHERE name='roc_work_spans') span_status,
  (SELECT reason FROM measurement_status WHERE name='roc_work_spans') span_reason,
  (SELECT status FROM measurement_status WHERE name='roc_allocations') allocation_status,
  (SELECT reason FROM measurement_status WHERE name='roc_allocations') allocation_reason
), scaled_status AS (
 SELECT
  (SELECT status FROM scaled.measurement_status WHERE name='host_cycles') host_status,
  (SELECT reason FROM scaled.measurement_status WHERE name='host_cycles') host_reason,
  (SELECT status FROM scaled.measurement_status WHERE name='roc_work_spans') span_status,
  (SELECT reason FROM scaled.measurement_status WHERE name='roc_work_spans') span_reason,
  (SELECT status FROM scaled.measurement_status WHERE name='roc_allocations') allocation_status,
  (SELECT reason FROM scaled.measurement_status WHERE name='roc_allocations') allocation_reason
), base_cycles AS (
 SELECT c.trigger,count(*) samples,avg(c.roc_callback_ns) callback_ns,
  avg(c.validate_ns) validate_ns,avg(c.graph_apply_ns) graph_ns
 FROM cycles c JOIN runs r ON r.id=c.run_id
 WHERE r.phase='sample' AND c.measurement_phase='measured' GROUP BY c.trigger
), scaled_cycles AS (
 SELECT c.trigger,count(*) samples,avg(c.roc_callback_ns) callback_ns,
  avg(c.validate_ns) validate_ns,avg(c.graph_apply_ns) graph_ns
 FROM scaled.cycles c JOIN scaled.runs r ON r.id=c.run_id
 WHERE r.phase='sample' AND c.measurement_phase='measured' GROUP BY c.trigger
), base_alloc AS (
 SELECT avg(end_roc_alloc_requested_bytes-start_roc_alloc_requested_bytes) lifecycle_bytes
 FROM runs WHERE phase='sample' AND ended_ns IS NOT NULL
), scaled_alloc AS (
 SELECT avg(end_roc_alloc_requested_bytes-start_roc_alloc_requested_bytes) lifecycle_bytes
 FROM scaled.runs WHERE phase='sample' AND ended_ns IS NOT NULL
), base_spans AS (
 SELECT sum(s.allocated_bytes)*1.0/count(DISTINCT c.id) span_bytes
 FROM roc_work_spans s JOIN cycles c ON c.id=s.cycle_id JOIN runs r ON r.id=c.run_id
 WHERE r.phase='sample' AND c.measurement_phase='measured'
), scaled_spans AS (
 SELECT sum(s.allocated_bytes)*1.0/count(DISTINCT c.id) span_bytes
 FROM scaled.roc_work_spans s JOIN scaled.cycles c ON c.id=s.cycle_id
 JOIN scaled.runs r ON r.id=c.run_id
 WHERE r.phase='sample' AND c.measurement_phase='measured'
)
SELECT CASE WHEN compatibility.compatible THEN 'complete' ELSE 'unavailable' END evidence_status,
 CASE WHEN compatibility.compatible THEN 'captures are mechanically compatible across scales'
      ELSE 'captures differ in executable, application, target, machine, detail, isolation, or scale identity' END evidence_reason,
 base_status.host_status base_host_status,base_status.host_reason base_host_reason,
 scaled_status.host_status scaled_host_status,scaled_status.host_reason scaled_host_reason,
 base_status.span_status base_span_status,base_status.span_reason base_span_reason,
 scaled_status.span_status scaled_span_status,scaled_status.span_reason scaled_span_reason,
 base_status.allocation_status base_allocation_status,base_status.allocation_reason base_allocation_reason,
 scaled_status.allocation_status scaled_allocation_status,scaled_status.allocation_reason scaled_allocation_reason,
 CAST((SELECT value FROM metadata WHERE key='benchmark_scale') AS INTEGER) base_scale,
 CAST((SELECT value FROM scaled.metadata WHERE key='benchmark_scale') AS INTEGER) scaled_scale,
 base_cycles.trigger,base_cycles.samples base_samples,scaled_cycles.samples scaled_samples,
 CASE WHEN compatibility.compatible AND base_status.host_status='complete' AND scaled_status.host_status='complete'
      THEN scaled_cycles.callback_ns/NULLIF(base_cycles.callback_ns,0) END callback_ratio,
 CASE WHEN compatibility.compatible AND base_status.host_status='complete' AND scaled_status.host_status='complete'
      THEN scaled_cycles.validate_ns/NULLIF(base_cycles.validate_ns,0) END validation_ratio,
 CASE WHEN compatibility.compatible AND base_status.host_status='complete' AND scaled_status.host_status='complete'
      THEN scaled_cycles.graph_ns/NULLIF(base_cycles.graph_ns,0) END graph_ratio,
 'complete sample lifecycle, mean allocated bytes per sample' lifecycle_allocation_scope,
 CASE WHEN compatibility.compatible AND base_status.allocation_status='complete' AND scaled_status.allocation_status='complete'
      THEN scaled_alloc.lifecycle_bytes/NULLIF(base_alloc.lifecycle_bytes,0) END lifecycle_allocation_ratio,
 'measured Roc work spans, mean attributed allocated bytes per measured cycle' span_allocation_scope,
 CASE WHEN compatibility.compatible AND base_status.span_status='complete' AND scaled_status.span_status='complete'
       AND base_status.allocation_status='complete' AND scaled_status.allocation_status='complete'
      THEN scaled_spans.span_bytes/NULLIF(base_spans.span_bytes,0) END span_allocation_ratio
FROM compatibility CROSS JOIN base_status CROSS JOIN scaled_status
CROSS JOIN base_alloc CROSS JOIN scaled_alloc CROSS JOIN base_spans CROSS JOIN scaled_spans
JOIN base_cycles JOIN scaled_cycles ON scaled_cycles.trigger=base_cycles.trigger;
