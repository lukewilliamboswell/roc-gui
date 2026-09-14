# Scaling benchmark suite

These are small but realistic Roc GUI applications, not microbenchmarks. Every
case performs a user-visible operation through the production event, platform,
host graph, and (outside headless automation) GPUI path. Pathological cases are
created by varying realistic workload dimensions rather than introducing a
second implementation just for measurement.

Each case declares three independent sizes:

- `:initial-size`: items present when the marked operation begins;
- `:change-size`: items semantically changed by that operation;
- `:scale`: the verified resident workload relevant to the case.

The row application establishes the first workload family:

| Operation | Pathology exercised | Scale ladder |
| --- | --- | --- |
| Create | allocation, lowering, validation, entity construction | 100 / 1,000 / 10,000 |
| Append | growing retained state and graph | 1,000→2,000 / 10,000→11,000 |
| Update every tenth | sparse semantic change in a large collection | 1,000 / 10,000 |
| Select | one-item state change with a large retained collection | 1,000 / 10,000 |
| Reselect | realistic idempotent event producing no UI change | 1,000 / 10,000 |
| Delete | structural removal and retained sibling work | 1,000 / 10,000 |
| Clear | bulk removal | 1,000 / 10,000 |
| Swap | order change between distant retained items | 1,000 / 10,000 |

As the platform gains production features, add realistic families rather than
benchmark-only primitives:

| Family | Dimensions to cover | Blocked by |
| --- | --- | --- |
| Nested application/forms | depth, breadth, local/global update, validation failure distance | no blocker for basic cases |
| Text-rich content | string length, text-node count, repeated label change | honest layout/paint timing |
| Interaction streams | repeated clicks, no-change handlers, alternating targets | multi-operation measurement groups |
| Window/layout | viewport size, resize, wrapping, scrolling, clipping | test-driver window operations |
| Images/assets | count, dimensions, reuse, decode/upload churn | production image element |
| Lifecycle | cold start, first window, first frame, shutdown | startup/presentation spans |

A family is complete only when its cases verify semantic results and performed
work, cover at least two scale points, and expose the relevant evidence through
SQLite. Timing thresholds are never correctness gates.
