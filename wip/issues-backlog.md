# Issues backlog

Gaps between the documented ideal state in `docs/` and the repository as it is.
Each entry names its effect and the change that closes it. Remove an entry when
the change lands; do not soften the docs to match the gap.

## Trust: measurements that can mislead a decision

- [ ] **All benchmark captures come from the headless runner.** No GPUI stage is
  measured. The capture backend is `semantic-headless`. Closes with the
  end-to-end runner below.
- [ ] **Roc callback time is one span.** Platform lowering, routing, and the
  linear boundary lookup in `platform/Internal.roc` cannot be separated from
  application update and render. Add platform-owned spans and allocation
  attribution.
- [ ] **Observer effect is unmeasured.** Run one case at `summary` and `full`
  detail and record the bound.

## Performance findings from the suite

Defects in the platform or host that the benchmark suite has exposed. Each
names the evidence so a fix can be verified against the same case.

- [ ] **Graph apply is mildly superlinear on replace-with-removal at 10,000
  rows.** Apply grew 16x to 21x per 10x for select, swap, delete, and update
  every tenth between 1,000 and 10,000 rows, while validation and Roc stayed at
  10x. The map holds old and new subtrees simultaneously at about 120,000
  entries. Confirm with a 100,000-row point before optimising.
- [ ] **Full-tree rebuild is the cost of every rows-family operation.** Select,
  swap, delete, and update every tenth at 10,000 rows all stage and remove about
  60,000 nodes and cost 21 to 26 ms; they are indistinguishable from each other
  and from create. This is expected without boundaries and is the baseline the
  row-boundaries family exists to beat.
- [ ] **Text and tree-shape families currently measure node count only.** Long
  and short messages at 10,000 rows differ by under 15%, and depth has no
  measurable effect, because the headless path has no layout or paint. These
  families become informative only with the GPUI runner.

## Runner: test what we fly

- [ ] **End-to-end GPUI spec runner.** The driver runs inside the production
  `Application`, opens the real window, resolves a locator to a live node and its
  laid-out bounds, synthesises the input event through GPUI, and closes the cycle
  on the presented frame. Stages that cannot be timed honestly stay
  `unavailable`. GPUI 0.2.2 exposes input injection only through its mock test
  platform, so the driver must capture production prepaint bounds and inject through
  the compositor (Sway's virtual-pointer/seat interface is a viable seam) rather
  than call `Runtime::event_if_live`. The driver must also distinguish laid out
  from actually visible: current large row cases place targets outside the
  window and the platform has no scrolling feature with which to bring them on
  screen.
- [ ] **Layout, paint, and presentation spans** owned by the GPUI side of the
  host. Presentation may need a Wayland frame callback.
- [ ] **CI compositor.** Benchmark jobs run the real Wayland backend under a
  headless compositor such as sway or cage. For Sway this requires a headless
  wlroots output, software rendering on workers without a GPU, and pointer
  movement plus press/release over its IPC or virtual-pointer protocol. The job
  must prove that GPUI receives the real Wayland event before benchmark captures
  are accepted; merely opening a window is insufficient.
- [ ] **Demote the headless runner to smoke.** Remove benchmark policy from it
  and make the scaling and compare views refuse `semantic-headless` captures.
