# Working in this repository

These are the boundaries for any agent, human or automated, making changes
here. They are principles, not procedures. When a procedure conflicts with a
principle, the principle wins and the procedure gets fixed.

## Test what we fly

There is one mounted graph, one GPUI path, and one event route. Verification
and measurement drive that implementation; they never reimplement it. If a test
needs behaviour the production path does not expose, add it to the production
path.

## Evidence is honest or it is absent

A measurement is recorded by the component that owns the work. What was not
measured is reported as unavailable, never as zero, never inferred from another
timer. Timing is report-only. Correctness gates are semantic results and
deterministic counters. Do not add a query for a column that does not exist,
and do not add a column that is not yet populated by production code.

## Realistic before pathological

Benchmarks are real applications made difficult by their dimensions. Do not add
benchmark-only primitives, alternate renderers, or synthetic graphs. If a
pathology cannot be reached through the application, the application is
missing a feature, and that feature is the work.

## Small surface, complete features

A feature is done when it has its ABI, host behaviour, semantic locators,
deterministic counters, specifications, a scaling case, and its documentation.
Half a feature is not merged. Prefer fewer complete features to many partial
ones.

## Documentation states the ideal; the backlog states the gap

`docs/` is authored guidance in AsciiDoc and describes the intended, enduring
state. It does not carry caveats, TODOs, or "currently". Gaps, defects, and
unfinished work go in `wip/issues-backlog.md` and are removed when closed. Never
weaken a document to match a shortcoming; record the shortcoming instead.

`README.md` is the landing page. It orients a newcomer and points into `docs/`.
It does not accumulate detail.

## Privacy and identity

Captures include only comparison-relevant, non-secret identity. Never record
usernames, paths under a home directory, hostnames, environment variables,
command lines, application text, or machine identifiers.

## Change discipline

- Read the owning code before changing a counter, span, or schema. Increment the
  schema version rather than aliasing.
- Keep specifications beside the application they exercise.
- Do not commit captures, build outputs, or generated archives.
- Do not commit or push unless asked. Do not rewrite history.
- When a request conflicts with these principles, say so in a sentence, then do
  the work the principles allow.
