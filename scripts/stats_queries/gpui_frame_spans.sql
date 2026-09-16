-- GPUI frame work owned by the host's own root element. Taffy's layout solve
-- and window presentation are performed by GPUI outside any host-owned element
-- and are reported by their own unavailable status rows, never derived here.
WITH evidence AS (
    SELECT status,reason FROM measurement_status WHERE name='gpui_frame_spans'
), solve AS (
    SELECT status,reason FROM measurement_status WHERE name='gpui_layout_solve'
), presentation AS (
    SELECT status,reason FROM measurement_status WHERE name='gpui_presentation'
), frames AS (
    SELECT count(*) AS frames,
           avg(layout_request_ns) AS mean_layout_request_ns,
           max(layout_request_ns) AS max_layout_request_ns,
           avg(prepaint_ns) AS mean_prepaint_ns,
           max(prepaint_ns) AS max_prepaint_ns,
           avg(paint_ns) AS mean_paint_ns,
           max(paint_ns) AS max_paint_ns
    FROM gpui_frames
)
SELECT evidence.status AS evidence_status,evidence.reason AS evidence_reason,
       frames.frames,
       CASE WHEN evidence.status='complete' THEN frames.mean_layout_request_ns END AS mean_layout_request_ns,
       CASE WHEN evidence.status='complete' THEN frames.max_layout_request_ns END AS max_layout_request_ns,
       CASE WHEN evidence.status='complete' THEN frames.mean_prepaint_ns END AS mean_prepaint_ns,
       CASE WHEN evidence.status='complete' THEN frames.max_prepaint_ns END AS max_prepaint_ns,
       CASE WHEN evidence.status='complete' THEN frames.mean_paint_ns END AS mean_paint_ns,
       CASE WHEN evidence.status='complete' THEN frames.max_paint_ns END AS max_paint_ns,
       solve.status AS layout_solve_status,solve.reason AS layout_solve_reason,
       presentation.status AS presentation_status,presentation.reason AS presentation_reason
FROM evidence CROSS JOIN solve CROSS JOIN presentation CROSS JOIN frames;
