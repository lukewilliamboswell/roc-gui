-- Deterministic component work reported by the owner for marked sample turns.
-- Sparse rows mean zero only when that cycle explicitly recorded an observation.
WITH kinds(kind,name) AS (
    VALUES (0,'rendered'),(1,'compared'),(2,'skipped'),(3,'mounted'),
           (4,'retired'),(5,'registry_visits'),(6,'ancestor_invalidations'),
           (7,'projection_gets'),(8,'projection_sets')
), evidence AS (
    SELECT status,reason FROM measurement_status WHERE name='component_work'
), measured AS (
    SELECT cycles.id,cycles.component_work_recorded
    FROM cycles JOIN runs ON runs.id=cycles.run_id
    WHERE cycles.measurement_phase='measured' AND runs.phase='sample'
), counts AS (
    SELECT kinds.kind,kinds.name,count(measured.id) AS cycles,
           sum(CASE WHEN measured.component_work_recorded=1
                    THEN coalesce(component_work_counts.count,0) END) AS total,
           max(CASE WHEN measured.component_work_recorded=1
                    THEN coalesce(component_work_counts.count,0) END) AS maximum
    FROM kinds LEFT JOIN measured ON true
    LEFT JOIN component_work_counts
      ON component_work_counts.cycle_id=measured.id AND component_work_counts.kind=kinds.kind
    GROUP BY kinds.kind,kinds.name
)
SELECT evidence.status AS evidence_status,evidence.reason AS evidence_reason,
       counts.name AS kind,counts.cycles,
       CASE WHEN evidence.status='complete' THEN counts.total END AS total_count,
       CASE WHEN evidence.status='complete' THEN counts.maximum END AS max_count
FROM evidence CROSS JOIN counts
ORDER BY counts.kind;
