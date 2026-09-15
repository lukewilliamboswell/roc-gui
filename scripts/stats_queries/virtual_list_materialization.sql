SELECT
    ms.status AS evidence_status,
    ms.reason AS evidence_reason,
    count(v.id) AS frames,
    max(v.visible_items) AS max_visible_items,
    sum(v.materialized_entities) AS materialized_entities,
    sum(v.recycled_entities) AS recycled_entities,
    max(v.live_entities) AS max_live_entities
FROM measurement_status ms
LEFT JOIN virtual_list_frames v ON ms.name='virtual_list_materialization'
WHERE ms.name='virtual_list_materialization';
