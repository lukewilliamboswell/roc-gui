# Database Browser

A read-only SQLite browser scoped to one folder. It takes a directory grant from
the host's chooser, lists the files that folder holds, opens a direct child
read-only, shows the tables it contains, and runs SQL from a multiline editor.
Write statements are rejected before they reach the database.

Results keep their SQLite value types — integers, reals, text, blobs reported by
length, and nulls — and are presented through the production virtual list, so a
ten-thousand-row answer costs the same rows on screen as a hundred-row one.
Successful schema and result state stay visible while a worker task is running,
and monotonic request identities mean a superseded open or query cannot
overwrite a newer one.

A standing bar names the folder held, and distinguishes nothing asked for yet
from a dismissed chooser from a refusal, because each calls for a different next
step.

## Running

```sh
python3 build.py
python3 examples/database-browser/generate_fixture.py
roc build --opt=dev --output=database-browser examples/database-browser/main.roc
./database-browser -- --host-cap-dir examples/database-browser/fixture
```

The fixture script writes `fixture/bookstore.db`, a deterministic 10,000-row
bookstore; it is generated rather than committed. `fixture/broken.db` is in the
repository already and is not a database, which is what the failure paths open.
`--host-cap-dir` provisions the folder the chooser answers with — development
provisioning, not a person's consent. With no grant the chooser refuses, and the
browser names the grant that would answer it.

## Not yet built

- No editing of any kind: no write statements, no schema changes, no import or
  export.
- No query history, no saved queries, no result sorting, filtering, or paging.
- One database open at a time, and only a direct child of the granted folder.
- The dismissed-chooser state is reachable only interactively; a specification
  configures the picker rather than opening one.

## Assets

`icons/` holds three glyphs whose licences are recorded per file in
`icons/NOTICE.md` and in the repository's `THIRD_PARTY_LICENSES.md`.

## Specifications

Eleven specifications run on the semantic runner and cover the first frame,
schema browsing, typed results, an empty result, an invalid database, a rejected
write, recovery after each kind of failure, a refused folder grant, the
authority readout, reopening, and a superseded query. Each asserts the SQLite
capability counters, so a query that never reached the host cannot pass by
looking right. `scale-100.scm`, `scale-1k.scm`, and `scale-10k.scm` are the
scaling cases. `window-ledger.scm` drives the real window and photographs the
ledger.
