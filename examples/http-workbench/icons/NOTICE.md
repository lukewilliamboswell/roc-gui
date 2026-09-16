# Icon notices

The SVG files in this directory come from [Lucide](https://lucide.dev), an open
icon set. Each file is redistributed here with one edit: the upstream
`stroke="currentColor"` is replaced by an explicit neutral grey, because these
files are rendered from bytes and inherit no colour from the element around
them. The grey is neutral, so the mark carries only the weight the authority bar
asks for and leaves colour to the verdict text beside it. Nothing else in any
file is changed.

The three marks are the three answers the bench can give about its own HTTP
authority, and they are the only place that distinction is drawn without words.

Lucide is licensed under the ISC License, Copyright (c) 2026 Lucide Icons and
Contributors. Icons marked below as Feather-derived are additionally covered by
the MIT License, Copyright (c) 2013-present Cole Bemis. Both licence texts are
reproduced in the single upstream licence file:
<https://github.com/lucide-icons/lucide/blob/main/LICENSE>

| File | Source | Upstream | Licence | Stroke | Used for |
| --- | --- | --- | --- | --- | --- |
| `shield.svg` | <https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/shield.svg> | Lucide | ISC and MIT (Feather-derived) | `#6e6e6e` | authority not yet exercised |
| `shield-check.svg` | <https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/shield-check.svg> | Lucide | ISC | `#6e6e6e` | authority granted for an origin |
| `shield-off.svg` | <https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/shield-off.svg> | Lucide | ISC and MIT (Feather-derived) | `#6e6e6e` | authority refused for an origin |
