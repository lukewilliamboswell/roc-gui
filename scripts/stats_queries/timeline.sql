-- Cycles, drawn frames, and virtual-list passes share one process-relative
-- clock. A frame names the cycles it was first to draw only through
-- gpui_frame_cycles, and a list pass its frame or cycle only through its own
-- recorded key; nothing here is inferred from ordering or overlap.
WITH frame_links AS (
    SELECT status,reason FROM measurement_status WHERE name='frame_cycle_linkage'
), list_links AS (
    SELECT status,reason FROM measurement_status WHERE name='virtual_list_linkage'
), frames AS (
    SELECT count(*) AS frames,
           count(*) FILTER (WHERE EXISTS(SELECT 1 FROM gpui_frame_cycles l WHERE l.frame_id=gpui_frames.id)) AS caused,
           (SELECT count(*) FROM gpui_frame_cycles) AS links,
           (SELECT count(DISTINCT cycle_id) FROM gpui_frame_cycles) AS drawn_cycles
    FROM gpui_frames
), passes AS (
    SELECT count(*) FILTER (WHERE origin='paint') AS paint_passes,
           count(*) FILTER (WHERE origin='paint' AND frame_id IS NOT NULL) AS paint_linked,
           count(*) FILTER (WHERE origin='patch') AS patch_passes,
           count(*) FILTER (WHERE origin='patch' AND cycle_id IS NOT NULL) AS patch_linked
    FROM virtual_list_frames
), span AS (
    SELECT min(start_ns) AS first_ns, max(end_ns) AS last_ns FROM (
        SELECT start_ns,end_ns FROM cycles
        UNION ALL SELECT start_ns,end_ns FROM gpui_frames
        UNION ALL SELECT start_ns,end_ns FROM virtual_list_frames)
)
SELECT frame_links.status AS evidence_status, frame_links.reason AS evidence_reason,
       (SELECT count(*) FROM cycles) AS cycles,
       frames.frames,
       CASE WHEN frame_links.status='complete' THEN frames.caused END AS frames_with_cycles,
       CASE WHEN frame_links.status='complete' THEN frames.frames-frames.caused END AS frames_without_new_cycle,
       CASE WHEN frame_links.status='complete' THEN frames.links END AS frame_cycle_links,
       CASE WHEN frame_links.status='complete' THEN frames.drawn_cycles END AS drawn_cycles,
       list_links.status AS list_linkage_status, list_links.reason AS list_linkage_reason,
       passes.paint_passes,
       CASE WHEN list_links.status='complete' THEN passes.paint_linked END AS paint_passes_linked,
       passes.patch_passes,
       CASE WHEN list_links.status='complete' THEN passes.patch_linked END AS patch_passes_of_cycles,
       span.first_ns, span.last_ns
FROM frame_links CROSS JOIN list_links CROSS JOIN frames CROSS JOIN passes CROSS JOIN span;
