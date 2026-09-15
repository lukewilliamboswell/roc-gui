# HTTP Workbench

A local-first desktop client for composing, sending, inspecting, and organizing
HTTP requests. It should be credible for everyday API development while remaining
immediately useful with a bundled local sample service.

The executable example sends bounded HTTP requests asynchronously: it provides
a controlled URL and multiline request body, an inline portable-error surface,
a read-only response view, and request-generation tracking so a superseded
response cannot replace the latest one. Run it with
`roc examples/http-workbench/main.roc` and run its colocated specifications with
`python3 scripts/run_specs.py 'examples/http-workbench/specs/*.scm'`.

## Core capabilities

- Tabbed request documents with method, URL, query, headers, authentication, and body editors.
- Asynchronous HTTP execution with explicit redirects, timeouts, response limits, and stale-result suppression.
- Structured JSON and text response views, search, syntax highlighting, and large-content virtualization.
- Request history, named collections, environment values, import/export, and secret-safe persistence.
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
