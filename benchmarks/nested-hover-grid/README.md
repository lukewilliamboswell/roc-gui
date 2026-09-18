# Nested hover grid

A companion to [the flat hover grid](../hover-grid/README.md), with the same
100, 1,000, and 10,000 five-pixel cells and one-pixel gaps. Rectangles split
recursively into up to four quadrants, including uneven halves. Every quadrant
and leaf is an unmemoized keyed translation; each parent stores at most four
children in a persistent index. Keys are computed when creating the model.

Hover enters locally, exits launch a 200 ms reset task, and generation checks
protect reentry. Busy task workers can extend the trail. Clicking a cell
delegates until its depth-one quadrant accepts: cyan gaps mark that quadrant.
Inspect displays the total accepted clicks. Swap exchanges the first two
quadrants within their existing native row. Remove deletes the first quadrant
and preserves its empty geometric slot, so surviving quadrants keep their
native scope; creating a new grid gives every node a fresh key.

The adjacent specifications compare local enter, exit, and completion with the
flat benchmark at identical leaf counts. Native rows and columns have exact
geometry. Measure actual native renders and constructed view wrappers
separately: only the affected ancestor path should render in a controlled
interaction, but each rebuilt parent offers its immediate children. Nested
fanout is bounded; tree depth increases with grid dimensions.

One local component render and ancestor-invalidations describe rendering and
cache invalidation. Separate owner counters record actual configured getter
and setter invocations. Local enter, exit, and completion measure 13 getters
and 5 setters at 100 cells, and 22 getters and 8 setters at 1,000 and 10,000
cells along the selected Cell 1 path. The deeper Cell 10000 path measures
25 getters and 9 setters. The flat grid measures 3 getters and 1 setter at
all three sizes. Callback and dispatch timings report the associated work;
these counts do not establish elapsed-time scaling. Headless results do not
measure native frame work, copying, or retained memory.

The controlled 10,000-cell window specification marks each interaction window.
Cell 1 traverses seven boundary views and offers thirteen boundary wrappers;
Cell 10000 traverses eight and offers fifteen. Six ordinary chrome buttons
also render alongside the changed leaf. These budgets describe those marked
interactions, not every possible focus or layout invalidation.
