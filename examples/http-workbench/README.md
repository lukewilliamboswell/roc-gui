# HTTP Workbench

A single-document HTTP client. One request is on screen at a time: method, URL,
query string, one header, and a body. Sending it produces a read-only readout of
the status line, the response headers, and the response body.

The example exercises HTTP authority scoped to one exact origin. That authority
cannot be inspected, only exercised, so the bench names three honest states in
its authority bar — not yet exercised, granted for an origin, refused for an
origin — and a refusal names the exact grant that would answer it. Sends run as
worker tasks with generation tracking, so a superseded reply cannot overwrite a
newer one, and Dismiss retires a reply that is still in flight.

## Running

```sh
python3 build.py
roc build --output=http-workbench examples/http-workbench/main.roc
./http-workbench -- --host-cap-http-origin http://127.0.0.1:38191
```

The grant names the one origin the bench may reach; without it every send comes
back refused. `fixture_server.py` in this directory serves that origin and is
started automatically by the specifications.

## Not yet built

- No history, collections, environments, tabs, or import and export. Nothing is
  persisted; the document starts from the same default every run.
- No JSON formatting, syntax highlighting, search, or virtualisation. Headers
  and body are shown as plain monospaced text.
- One header per request, edited as a name and a value.
- No resizable panes; the two sides are fixed.
- The windowed runner cannot yet photograph a completed response, because a
  worker task does not finish under it.

## Assets

The three shield marks in `icons/` are vendored; their provenance and licences
are in `icons/NOTICE.md` and `THIRD_PARTY_LICENSES.md`.

## Specifications

Sixteen specifications run on the semantic runner against the fixture server,
covering the first send, keyboard submission, response headers, validation,
refusals, body limits, dismissal, and stale-response suppression. Two run
against the real window and assert the standing layout and the authority bar in
its unexercised and refused readings.
