# Icon notices

The SVG files in this directory come from [Lucide](https://lucide.dev), an open
icon set. Each file is redistributed here with one edit: the upstream
`stroke="currentColor"` is replaced by an explicit neutral grey, because these
files are rendered from bytes and inherit no colour from the element around
them. The grey is neutral, so the mark sits on the ledger's near-white ground
without becoming a second accent. Nothing else in any file is changed.

The three marks are the three states of the browser's one authority: no folder
chosen yet, a folder granted by the person at the picker, and a grant the host
or the folder itself refused.

Lucide is licensed under the ISC License, Copyright (c) 2026 Lucide Icons and
Contributors. Icons marked below as Feather-derived are additionally covered by
the MIT License, Copyright (c) 2013-present Cole Bemis. Both licence texts are
reproduced in the single upstream licence file:
<https://github.com/lucide-icons/lucide/blob/main/LICENSE>

| File | Source | Upstream | Licence | Stroke | Used for |
| --- | --- | --- | --- | --- | --- |
| `folder.svg` | <https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/folder.svg> | Lucide | ISC and MIT (Feather-derived) | `#6e6e6e` | no folder granted yet |
| `folder-check.svg` | <https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/folder-check.svg> | Lucide | ISC | `#6e6e6e` | a folder granted at the picker |
| `folder-x.svg` | <https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/folder-x.svg> | Lucide | ISC | `#6e6e6e` | a folder grant that failed |
