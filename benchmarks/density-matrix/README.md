# Visual × interaction density

This operations dashboard varies non-interactive visual payload independently
from the number of interactive controls. Its four configurations combine 25 or
2,500 telemetry cards with 25 or 2,500 action buttons. Every card uses ordinary
layout, background, radius, and text primitives; every action is a production
button on the normal GPUI event route.

Clicking an action increments only that action's visible run count. Actions are
keyed projected components, so the host can retain unrelated controls and the
telemetry field through a local update. Configuration changes deliberately
replace the dashboard population with fresh identities.

The four adjacent specifications perform the same single-control update at all
matrix corners. Comparing the low/high visual pair isolates extra scene and
layout payload at fixed listener count. Comparing the low/high interaction pair
isolates listener and hitbox density while holding the telemetry payload fixed.
Buttons necessarily contribute their own visual primitives, so the interaction
axis measures complete usable controls rather than invisible hit regions.
