# Database Browser

A read-only SQLite browser scoped to one folder. It takes a directory grant from
the host's chooser, lists the files that folder holds, opens a direct child
read-only, shows the tables it contains, and runs SQL from a multiline editor.
Write statements are rejected before they reach the database.

Results keep their SQLite value types — integers, reals, text, blobs reported by
length, and nulls — and are presented as rows produced on demand: the page is
held once, and only the rows near the viewport are ever built, so a
ten-thousand-row answer costs the same rows as a hundred-row one. First- and
last-row keys move the list from state, a new page opens at its first row, and
the summary names the rows on screen as the list reports them. A
longer answer is read ten thousand rows at a time: the first page runs the
statement as written, and the next and previous pages bind their offset as a
query parameter. The file is read in place, so a database of any size opens,
and one another program is still writing shows its latest committed rows.
Successful schema and result state stay visible while a worker task is running,
and monotonic request identities mean a superseded open cannot overwrite a
newer one. Statements and page reads share one task key: running another
supersedes the one in flight, which the host interrupts where it runs, and a
Cancel key stops a long statement outright. Neither result is ever delivered.

A standing bar names the folder held, and distinguishes nothing asked for yet
from a dismissed chooser from a refusal, because each calls for a different next
step.

Every result cell clips to its column, so resting the pointer on one opens a
note with the whole value, its column, and its SQLite storage class; Escape
dismisses it. The folder key carries a note about the authority it asks for,
which keyboard focus opens at once. Both are popovers: the host decides when
they present, so opening one runs no application code, and a ten-thousand-row
answer mounts a note for each cell it builds and presents only the one under
the pointer.

## Running

```sh
python3 build.py
python3 examples/database-browser/generate_fixture.py
roc build --output=database-browser examples/database-browser/main.roc
./database-browser -- --host-cap-dir examples/database-browser/fixture
```

The fixture script writes `fixture/bookstore.db`, a deterministic bookstore of
10,000 books and 100,000 loans; it is generated rather than committed. `fixture/broken.db` is in the
repository already and is not a database, which is what the failure paths open.
`--host-cap-dir` provisions the folder the chooser answers with — development
provisioning, not a person's consent. With no grant the chooser refuses, and the
browser names the grant that would answer it.

## Assets

`icons/` holds three glyphs whose licences are recorded per file in
`icons/NOTICE.md` and in the repository's `THIRD_PARTY_LICENSES.md`.

## Specifications

The [specifications](specs/) exercise read-only queries, typed results, paging and cancellation.
