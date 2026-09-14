# Issues backlog

Gaps between the documented ideal state in `docs/` and the repository as it is.
Each entry names its effect and the change that closes it. Remove an entry when
the change lands; do not soften the docs to match the gap.

## Trust: measurements that can mislead a decision

- [ ] **All benchmark captures come from the headless runner.** No GPUI stage is
  measured. The capture backend is `semantic-headless`. Closes with the
  end-to-end runner below.
- [ ] **Patch evidence is incomplete across benchmark families.** `expect-patch`
  records and verifies kind plus exact staged/removed counts, and the original
  rows operation cases use it, including `no_change` reselect. Add an honest patch contract to the
  remaining benchmark families; captures without one report patch verification
  as not recorded.
- [ ] **Roc callback time is one span.** Platform lowering, routing, and the
  linear boundary lookup in `platform/Internal.roc` cannot be separated from
  application update and render. Add platform-owned spans and allocation
  attribution.
- [ ] **Observer effect is unmeasured.** Run one case at `summary` and `full`
  detail and record the bound.

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

## Coverage: rows family

- [ ] **The row-boundaries family only covers one-row updates.** First, middle,
  and last replacement now measure localised work, but Select, Delete, Swap,
  and Update every tenth do not yet have boundary-family counterparts.
