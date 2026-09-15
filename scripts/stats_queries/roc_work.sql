-- Roc callback and allocation work, attributed to measured specification steps.
WITH evidence AS (
    SELECT status,reason FROM measurement_status WHERE name='roc_work_spans'
), allocation_evidence AS (
    SELECT status,reason FROM measurement_status WHERE name='roc_allocations'
), measured AS (
    SELECT count(*) AS cycles, avg(roc_callback_ns) AS mean_callback_ns,
           max(roc_callback_ns) AS max_callback_ns,
           sum(roc_callback_ns) AS total_callback_ns
    FROM cycles JOIN runs ON runs.id=cycles.run_id
    WHERE runs.phase='sample' AND cycles.measurement_phase='measured'
), allocations AS (
    SELECT sum(end_roc_alloc_calls-start_roc_alloc_calls) AS alloc_calls,
           sum(end_roc_alloc_requested_bytes-start_roc_alloc_requested_bytes) AS allocated_bytes,
           sum(end_roc_dealloc_calls-start_roc_dealloc_calls) AS dealloc_calls,
           sum(end_roc_realloc_calls-start_roc_realloc_calls) AS realloc_calls,
           sum(end_roc_realloc_requested_bytes-start_roc_realloc_requested_bytes) AS reallocated_bytes
    FROM runs WHERE phase='sample' AND ended_ns IS NOT NULL
), spans AS (
    SELECT kind, avg(roc_work_spans.duration_ns) AS mean_ns,
           max(roc_work_spans.duration_ns) AS max_ns,
           sum(roc_work_spans.duration_ns) AS total_ns, sum(alloc_calls) AS alloc_calls,
           sum(allocated_bytes) AS allocated_bytes, sum(dealloc_calls) AS dealloc_calls,
           sum(realloc_calls) AS realloc_calls, sum(reallocated_bytes) AS reallocated_bytes
    FROM roc_work_spans JOIN cycles ON cycles.id=cycle_id
    JOIN runs ON runs.id=cycles.run_id
    WHERE runs.phase='sample' AND cycles.measurement_phase='measured'
    GROUP BY kind
)
SELECT evidence.status AS evidence_status,evidence.reason AS evidence_reason,
       allocation_evidence.status AS allocation_evidence_status,
       allocation_evidence.reason AS allocation_evidence_reason,measured.cycles,
       CASE WHEN evidence.status='complete' THEN measured.mean_callback_ns END AS mean_callback_ns,
       CASE WHEN evidence.status='complete' THEN measured.max_callback_ns END AS max_callback_ns,
       CASE WHEN evidence.status='complete' THEN measured.total_callback_ns END AS total_callback_ns,
       CASE WHEN allocation_evidence.status='complete' THEN allocations.alloc_calls END AS lifecycle_alloc_calls,
       CASE WHEN allocation_evidence.status='complete' THEN allocations.allocated_bytes END AS lifecycle_allocated_bytes,
       CASE WHEN allocation_evidence.status='complete' THEN allocations.dealloc_calls END AS lifecycle_dealloc_calls,
       CASE WHEN allocation_evidence.status='complete' THEN allocations.realloc_calls END AS lifecycle_realloc_calls,
       CASE WHEN allocation_evidence.status='complete' THEN allocations.reallocated_bytes END AS lifecycle_reallocated_bytes,
       spans.kind AS span_kind,
       CASE WHEN evidence.status='complete' THEN spans.mean_ns END AS span_mean_ns,
       CASE WHEN evidence.status='complete' THEN spans.max_ns END AS span_max_ns,
       CASE WHEN evidence.status='complete' THEN spans.total_ns END AS span_total_ns,
       CASE WHEN allocation_evidence.status='complete' THEN spans.alloc_calls END AS span_alloc_calls,
       CASE WHEN allocation_evidence.status='complete' THEN spans.allocated_bytes END AS span_allocated_bytes,
       CASE WHEN allocation_evidence.status='complete' THEN spans.dealloc_calls END AS span_dealloc_calls,
       CASE WHEN allocation_evidence.status='complete' THEN spans.realloc_calls END AS span_realloc_calls,
       CASE WHEN allocation_evidence.status='complete' THEN spans.reallocated_bytes END AS span_reallocated_bytes
FROM evidence CROSS JOIN allocation_evidence CROSS JOIN measured CROSS JOIN allocations
LEFT JOIN spans ON true
ORDER BY spans.kind;
