# Hover trail

An interactive grid of 10,000 native buttons. Move across the grid to light
cells cyan. Leaving a cell turns it violet and starts a 200 ms reset task; a busy queue
can extend the trail. Use the size controls to select 100, 1,000, or 10,000 cells; Clear
trail starts a fresh grid.

Each cell is an unmemoized keyed translation with state stored in the shared
persistent `Index`. Enter and exit actions render only that cell. An exit
starts a cell-owned task that waits on `Timer`, cancels its timer after one
tick, and resolves against current state. A generation token prevents an old
completion from clearing a reentered cell or its newer trail. Replacing the
grid creates fresh keys so removed owners cannot deliver into new cells.

Adjacent specifications cover entry, exit, and delayed reset at each size,
reentry, replacement, independent trails, a 32-cell burst, and window
native hover delivery and container reuse across all three sizes. The window cases
check that a local enter renders at
most its one cell boundary and five button views: the changed cell plus the
four ordinary size/reset controls. Unrelated cell views must remain cached. The scaling case also bounds boundary
elements handed to GPUI by the affected row width (10 or 100), so a low render
count cannot hide traversal of all 10,000 cells.
The 100 by 100 default grid fits in the window without virtualization.
