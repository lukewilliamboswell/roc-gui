-- The element each interactive cycle reached: its node kind and structural
-- identity, which name no application text. A cycle no element caused, such
-- as initialization or a task completion, has no target and is counted apart.
SELECT cycles.trigger,
       coalesce(cycles.target_kind,'(no target)') AS target_kind,
       cycles.target_identity,
       count(*) AS cycles,
       max(cycles.duration_ns) AS max_duration_ns
FROM cycles
GROUP BY cycles.trigger,cycles.target_kind,cycles.target_identity
ORDER BY count(*) DESC,cycles.trigger,cycles.target_kind,cycles.target_identity;
