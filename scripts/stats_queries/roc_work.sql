-- Roc callback and allocation work, attributed to measured specification steps.
WITH evidence AS (
    SELECT status,reason FROM measurement_status WHERE name='host_cycles'
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
)
SELECT evidence.status AS evidence_status,evidence.reason AS evidence_reason,
       allocation_evidence.status AS allocation_evidence_status,
       allocation_evidence.reason AS allocation_evidence_reason,measured.cycles,
       CASE WHEN evidence.status='complete' THEN measured.mean_callback_ns END AS mean_callback_ns,
       CASE WHEN evidence.status='complete' THEN measured.max_callback_ns END AS max_callback_ns,
       CASE WHEN evidence.status='complete' THEN measured.total_callback_ns END AS total_callback_ns,
       CASE WHEN allocation_evidence.status='complete' THEN allocations.alloc_calls END AS alloc_calls,
       CASE WHEN allocation_evidence.status='complete' THEN allocations.allocated_bytes END AS allocated_bytes,
       CASE WHEN allocation_evidence.status='complete' THEN allocations.dealloc_calls END AS dealloc_calls,
       CASE WHEN allocation_evidence.status='complete' THEN allocations.realloc_calls END AS realloc_calls,
       CASE WHEN allocation_evidence.status='complete' THEN allocations.reallocated_bytes END AS reallocated_bytes
FROM evidence CROSS JOIN allocation_evidence CROSS JOIN measured CROSS JOIN allocations;
