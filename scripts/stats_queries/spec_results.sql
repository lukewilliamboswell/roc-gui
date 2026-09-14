-- Which semantic steps passed or failed?
WITH evidence AS (
    SELECT status,reason FROM measurement_status WHERE name='step_results'
)
SELECT evidence.status AS evidence_status,evidence.reason AS evidence_reason,
       runs.phase,runs.sample_index,runs.iteration_index,
       steps.ordinal,steps.source_line,steps.kind,steps.role,steps.status,
       steps.expected_count,steps.observed_count,
       steps.expected_patch_kind,steps.observed_patch_kind,
       steps.expected_staged_nodes,steps.observed_staged_nodes,
       steps.expected_removed_nodes,steps.observed_removed_nodes,
       CASE WHEN evidence.status='complete' THEN steps.duration_ns END AS duration_ns,
       steps.diagnostic
FROM evidence LEFT JOIN steps ON evidence.status='complete'
LEFT JOIN runs ON runs.id=steps.run_id
ORDER BY runs.id,steps.ordinal;
