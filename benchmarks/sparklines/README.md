# Service latency sparklines

A dashboard of 10, 100, or 1,000 services, each with a sparkline of its last
48 latencies. Every sparkline is a canvas that fills the column beside its
service's name and is drawn for the width the window lays it out at, which it
hears through `on_size`.

The scaling specifications mount every sparkline at once. Each new canvas is
one `resize` turn: the first carries the column's width into state and draws
every line for it, and the rest hear the width the lines were already drawn
for, so they change nothing and render nothing. The ladder shows that cost per
canvas stays flat as the number of sparklines grows.
