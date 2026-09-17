-- GPUI-owned deterministic reconstruction and replay work by completed frame.
WITH metrics(metric,name) AS (
    VALUES (0,'cached_prepaint_subtrees'),(1,'replayed_hitboxes'),
           (2,'replayed_dispatch_nodes'),(3,'replayed_deferred_draws'),
           (4,'replayed_prepaint_element_states'),(5,'cached_paint_subtrees'),
           (6,'replayed_scene_operations'),(7,'replayed_mouse_listeners'),
           (8,'replayed_input_handlers'),(9,'replayed_cursor_styles'),
           (10,'replayed_paint_element_states'),(11,'replayed_tab_stops'),
           (12,'fresh_hitboxes'),(13,'fresh_mouse_listeners'),
           (14,'fresh_scene_operations'),(15,'fresh_element_state_accesses'),
           (16,'element_states_moved'),(17,'view_states_rebased_prepaint'),
           (18,'view_states_rebased_paint')
), source AS (
    SELECT coalesce(max(status),'unavailable') AS status,
           coalesce(max(reason),'GPUI frame work observation status is absent') AS reason
    FROM measurement_status WHERE name='gpui_frame_work'
), frames AS (
    SELECT count(*) AS count FROM gpui_frames
), counts AS (
    SELECT metrics.metric,metrics.name,
           sum(coalesce(work.count,0)) AS total,
           max(coalesce(work.count,0)) AS maximum,
           avg(coalesce(work.count,0)) AS mean
    FROM metrics LEFT JOIN gpui_frames ON true
    LEFT JOIN gpui_frame_work AS work
      ON work.frame_id=gpui_frames.id AND work.metric=metrics.metric
    GROUP BY metrics.metric,metrics.name
)
SELECT source.status AS evidence_status,source.reason AS evidence_reason,
       frames.count AS recorded_frames,counts.name AS metric,
       CASE WHEN source.status='complete' THEN counts.total END AS total_count,
       CASE WHEN source.status='complete' THEN counts.maximum END AS max_per_frame,
       CASE WHEN source.status='complete' THEN counts.mean END AS mean_per_frame
FROM source CROSS JOIN frames CROSS JOIN counts
ORDER BY counts.metric;
