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

## Not yet built

- No editing of any kind: no write statements, no schema changes, no import or
  export.
- No query history, no saved queries, no result sorting or filtering.
- One database open at a time, and only a direct child of the granted folder.
- The dismissed-chooser state is reachable only interactively; a specification
  configures the picker rather than opening one.

## Assets

`icons/` holds three glyphs whose licences are recorded per file in
`icons/NOTICE.md` and in the repository's `THIRD_PARTY_LICENSES.md`.

## Specifications

Sixteen specifications run on the semantic runner and cover the first frame,
schema browsing, typed results, an empty result, an invalid database, a rejected
write, recovery after each kind of failure, a refused folder grant, the
authority readout, reopening, a superseded query, a running statement cancelled
and one superseded where it runs, a result turned page by page, and a result
that fits one page. Each asserts the SQLite capability counters or the task
counters, so a query that never reached the host, or a superseded one whose
result arrived anyway, cannot pass by looking right.
`scale-supersede-10.scm`, `scale-supersede-100.scm`, and
`scale-supersede-1k.scm` run the statement again that many times in a row over
a 10,000-row result and prove that each run superseded the last.
`scale-100.scm`, `scale-1k.scm`, and `scale-10k.scm` scale the rows in a result
and prove with `expect-rows` that the same 64 rows are built at every size;
`scale-pages-20k.scm`, `scale-pages-50k.scm`, and `scale-pages-100k.scm` keep one
page resident and scale how deep in the result it lies. `window-ledger.scm`
drives the real window and photographs the ledger, and `window-rows.scm`
scrolls ten thousand rows, jumps to the last and first rows, and photographs
each. `window-cancel-query.scm` types a statement that would run for minutes,
photographs its Cancel key, and cancels it.
