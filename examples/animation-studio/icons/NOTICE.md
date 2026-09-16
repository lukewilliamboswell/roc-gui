# Vendored artwork

Both files are single icons taken from the Lucide icon set and redistributed
under its ISC licence. The licence text is at
[`third_party/licenses/lucide/LICENSE`](../../../third_party/licenses/lucide/LICENSE).

| File | Upstream project | Source URL | Licence |
| --- | --- | --- | --- |
| `shape-rectangle.svg` | Lucide (`square`) | https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/square.svg | ISC |
| `shape-ellipse.svg` | Lucide (`circle`) | https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/circle.svg | ISC |

Both were renamed to say what they mean in this application, and both had
`stroke="currentColor"` replaced with the literal `#9fb4bd` of this
application's secondary text. A standalone SVG has no inherited colour to
resolve `currentColor` against, so an icon that keeps it draws black. The
geometry is otherwise byte-identical to the upstream file. The ISC licence
permits modification; this note records it.
