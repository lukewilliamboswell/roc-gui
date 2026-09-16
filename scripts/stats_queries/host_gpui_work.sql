-- Host graph and GPUI materialization work. Frame stages are in gpui_frame_spans.
WITH evidence AS (
    SELECT status,reason FROM measurement_status WHERE name='host_cycles'
), gpui AS (
    SELECT status,reason FROM measurement_status WHERE name='gpui_application'
), measured AS (
    SELECT count(*) AS cycles,avg(validate_ns) AS mean_validate_ns,
           avg(graph_apply_ns) AS mean_graph_apply_ns,
           avg(gpui_apply_ns) AS mean_gpui_apply_ns,
           sum(staged_nodes) AS staged_nodes,sum(removed_nodes) AS removed_nodes,
           max(live_nodes) AS peak_live_nodes,
           sum(parent_nodes_scanned) AS parent_nodes_scanned,
           sum(retained_nodes) AS retained_nodes,sum(validation_visits) AS validation_visits
    FROM cycles JOIN runs ON runs.id=cycles.run_id
    WHERE runs.phase='sample' AND cycles.measurement_phase='measured'
)
SELECT evidence.status AS evidence_status,evidence.reason AS evidence_reason,
       gpui.status AS gpui_evidence_status,gpui.reason AS gpui_evidence_reason,
       measured.cycles,
       CASE WHEN evidence.status='complete' THEN measured.mean_validate_ns END AS mean_validate_ns,
       CASE WHEN evidence.status='complete' THEN measured.mean_graph_apply_ns END AS mean_graph_apply_ns,
       CASE WHEN gpui.status='complete' THEN measured.mean_gpui_apply_ns END AS mean_gpui_apply_ns,
       CASE WHEN evidence.status='complete' THEN measured.staged_nodes END AS staged_nodes,
       CASE WHEN evidence.status='complete' THEN measured.removed_nodes END AS removed_nodes,
       CASE WHEN evidence.status='complete' THEN measured.peak_live_nodes END AS peak_live_nodes,
       CASE WHEN evidence.status='complete' THEN measured.parent_nodes_scanned END AS parent_nodes_scanned,
       CASE WHEN evidence.status='complete' THEN measured.retained_nodes END AS retained_nodes,
       CASE WHEN evidence.status='complete' THEN measured.validation_visits END AS validation_visits,
       'see the gpui_frame_spans view; layout solve, presentation, and GPU timing remain unavailable' AS later_gpui_stages
FROM evidence CROSS JOIN gpui CROSS JOIN measured;
