# Device Configurator

A desktop utility for discovering and configuring an explicitly granted HID
peripheral. It uses the platform's bounded device transaction capability and a
small versioned protocol owned by the application.

The application discovers the granted device without exposing its
operating-system path or serial number, connects and synchronizes its current
sensitivity, lighting, profile, and ordinary control inventory, then applies
locally validated changes as one acknowledged transaction.

## What the design is for

The subject is a physical object on a desk, and the window is arranged the way
a person reasons about one: on the left, whether there is a device and whether
it is open; on the right, what it is set to. The right side stays empty until
the left is settled, because there genuinely is nothing to show -- every value
in it was read from the device rather than invented here.

Colour answers two questions before a word is read. Green means an open
connection and nothing else. Amber means an edit that is held in this window
and that the device has not been told about. Red means refused or lost. The
link light in the header, the device card, the profile control, and the apply
footer all use the same three, so a person can see at a glance whether the
device is plugged in and whether it agrees with what is on screen.

## States, not reports

Each state of the connection is drawn rather than announced: nothing
discovered, discovery refused, discovered but closed, open, and lost each have
their own surface and their own sentence about what to do next. A refusal says
what was and was not done -- nothing was searched for, nothing was opened --
and says that access is granted one device at a time, outside this window,
which is the part a person cannot guess.

Connect and Disconnect live on the device card, and are never both offered.
There is no card before discovery, so neither control exists until it could do
something; and the only control that is ever disabled -- Apply, when there is
nothing to send -- carries the reason beside it. This replaces two status
messages the old design could never reach, because the controls that would have
produced them were disabled in exactly the states that produced them.

Searching again empties the device list, and the open connection is offered
from a card in that list, so a discovery started while a handle is open would
strand it. That control is withheld while a connection is open and says why.

## Specifications

The host supports physical HID devices through the established `hidapi`
package. Specifications grant a deterministic virtual device which implements
the identical framed protocol and state machine; it is not a UI test double.
Semantic specs cover the first press before anything exists, authority denial,
discovery, a superseded discovery, connection and resynchronization, bounded
editing at both ends of the range, the acknowledged apply, a withheld second
discovery, resource ownership, and a realistic 100-control scaling case through
the ordinary virtualized controls view. `window-connection.scm` and
`window-refused.scm` open the production window and photograph each state of
the connection.
