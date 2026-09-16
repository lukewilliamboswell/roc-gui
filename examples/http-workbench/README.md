# HTTP Workbench

A local-first desktop client for composing, sending, inspecting, and organizing
HTTP requests. It should be credible for everyday API development while remaining
immediately useful with a bundled local sample service.

The executable composes bounded canonical HTTP requests asynchronously with a
method, URL, query string, one explicit header, and multiline body. It presents
response status, headers, and body independently, retains operation-tagged
errors, supports retry and dismissing obsolete results, and uses generation
tracking so a superseded response cannot replace the latest one. Grant its
development destination with
`roc examples/http-workbench/main.roc -- --host-cap-http-origin http://127.0.0.1:38191`.
Run its colocated specifications with
`python3 scripts/run_specs.py 'examples/http-workbench/specs/*.scm'`.

## The bench

The window is one instrument with two sides. A header names it; an **authority
bar** runs the full width underneath and is the only thing on screen that is
never about the document: it reports the origin the URL field currently points
at, and the verdict the last exercised send returned for whichever origin that
send was about. The left side is the request document, a labelled gutter with
every editor starting on one vertical line. The right side is a readout, never
editable, monospaced, with the status line as the single piece of type larger
than body text.

Its palette, type scale, and spacing live in `Theme.roc`.

## Authority as a designed state

HTTP authority here is scoped to one exact origin and cannot be discovered
without exercising it, so the bench has three honest states and says which one
it is in at all times:

- **not yet exercised** — the first frame. Nothing has been sent, so nothing is
  known. The bar still names the origin the URL field would ask for.
- **granted for `<origin>`** — a send returned a reply from that origin.
- **refused for `<origin>`** — the host said no. The refusal band names the
  exact grant that would answer it, down to the origin:
  `Restart with --host-cap-http-origin http://127.0.0.1:38191`.

Every failure carries the same two lines: what happened, and the one thing a
person can do next. Only a refusal changes what the bench claims to hold; a
timeout or a body-limit failure says nothing about authority and leaves the
verdict where it was.

## Core capabilities

- Request documents with method, URL, query, header, and body editors.
- Asynchronous HTTP execution with explicit redirects, timeouts, response limits, and stale-result suppression.
- Structured JSON and text response views, search, syntax highlighting, and large-content virtualization.
- Secret-safe request history, named collections, environment values, and import/export.
- Resizable panes, keyboard commands, focus management, and accessible status reporting.

## Happy paths

- Open the sample collection, send a request, and inspect status, headers, timing, and formatted JSON.
- Edit parameters and headers, duplicate a request, cancel an in-flight request, and resend it.
- Save requests into a collection, reopen the application, and recover tabs and non-secret state.
- Import a cURL request and export a collection without changing its meaning.

## Error paths

- Invalid URLs, unsupported methods, malformed headers, and invalid structured bodies are rejected at the owning field.
- DNS, connection, TLS, timeout, redirect-loop, cancellation, and truncated-response failures remain distinguishable.
- Stale responses cannot replace a newer request, and a failed save never destroys the last valid collection.
- Secrets are redacted from diagnostics, captures, history previews, and exported examples.

## High-level goals

- Establish the production pattern for tasks, cancellation, stale-result suppression, and progress.
- Drive multiline editing, large text, tree views, split panes, and clipboard interoperability.
- SCM specs cover request editing, send/cancel/retry, persistence, import/export, errors, and keyboard-only use.
- A scaling case loads a realistically large paginated response through the same bundled service and response renderer.
