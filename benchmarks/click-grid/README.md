# Stationary click grid

An interactive grid of up to 10,000 native buttons for isolating click-driven
reconstruction from pointer travel. Repeatedly click a single cell without
moving the pointer; the cell alternates between slate and amber while the
remaining grid stays unchanged. Size controls select 100, 1,000, or 10,000
cells.

Each cell is an ordinary action button in an unmemoized keyed translation, with
state stored in the shared persistent `Index`. A press updates only that cell.
The scaling specifications assert semantic state, exact local patch work, and
component work at all three sizes. The native-window specification additionally
bounds button and boundary rendering and the number of elements visited in the
affected row. Repeated presses use the same semantic locator, which keeps the
target fixed and avoids hover actions; physical pointer stationarity remains a
manual profiling condition rather than an inferred measurement.
