-- Did the application and every specification assertion complete successfully?
WITH evidence AS (
    SELECT status,reason,rows_recorded,omitted_events
    FROM measurement_status WHERE name='step_results'
), totals AS (
    SELECT count(*) AS runs,
           sum(CASE WHEN outcome='fail' THEN 1 ELSE 0 END) AS failed_runs
    FROM runs
), step_totals AS (
    SELECT count(*) AS steps,
           sum(CASE WHEN status='fail' THEN 1 ELSE 0 END) AS failed_steps
    FROM steps
)
SELECT evidence.status AS evidence_status,
       evidence.reason AS evidence_reason,
       totals.runs,coalesce(totals.failed_runs,0) AS failed_runs,
       step_totals.steps,coalesce(step_totals.failed_steps,0) AS failed_steps,
       evidence.rows_recorded,evidence.omitted_events
FROM evidence CROSS JOIN totals CROSS JOIN step_totals;
