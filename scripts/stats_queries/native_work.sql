-- Owner-recorded native work for completed GPUI frames. Sparse missing kinds
-- are zero only within those frames; missing/incomplete evidence is unavailable.
WITH metrics(metric,name) AS (
    VALUES (0,'node_view_renders'),(1,'view_elements_created')
), kinds(kind,name) AS (
    VALUES (0,'canvas'),(1,'button'),(2,'checkbox'),(3,'textarea'),
           (4,'image'),(5,'column'),(6,'dialog'),(7,'panel'),(8,'row'),
           (9,'scroll'),(10,'virtual_item'),(11,'virtual_list'),
           (12,'text_input'),(13,'text'),(14,'styled_text'),(15,'boundary'),
           (16,'keyed_container'),(17,'popover'),(18,'split_divider')
), source AS (
    SELECT coalesce(max(status),'unavailable') AS status,
           coalesce(max(reason),'native work observation status is absent') AS reason
    FROM measurement_status WHERE name='gpui_native_work'
), frames AS (
    SELECT count(*) AS count FROM gpui_frames
), evidence AS (
    SELECT CASE WHEN source.status='complete' AND frames.count=0
                THEN 'unavailable' ELSE source.status END AS status,
           CASE WHEN source.status='complete' AND frames.count=0
                THEN 'no completed GPUI frame was recorded' ELSE source.reason END AS reason
    FROM source CROSS JOIN frames
), counts AS (
    SELECT metrics.metric,metrics.name AS metric_name,kinds.kind,kinds.name AS kind_name,
           sum(coalesce(work.count,0)) AS total,
           max(coalesce(work.count,0)) AS maximum,
           avg(coalesce(work.count,0)) AS mean
    FROM metrics CROSS JOIN kinds
    LEFT JOIN gpui_frames ON true
    LEFT JOIN gpui_native_work AS work
      ON work.frame_id=gpui_frames.id AND work.metric=metrics.metric AND work.kind=kinds.kind
    GROUP BY metrics.metric,metrics.name,kinds.kind,kinds.name
)
SELECT evidence.status AS evidence_status,evidence.reason AS evidence_reason,
       frames.count AS recorded_frames,counts.metric_name AS metric,counts.kind_name AS kind,
       CASE WHEN evidence.status='complete' THEN counts.total END AS total_count,
       CASE WHEN evidence.status='complete' THEN counts.maximum END AS max_per_frame,
       CASE WHEN evidence.status='complete' THEN counts.mean END AS mean_per_frame
FROM evidence CROSS JOIN frames CROSS JOIN counts
ORDER BY counts.metric,counts.kind;
