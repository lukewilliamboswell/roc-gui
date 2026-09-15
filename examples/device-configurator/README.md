# Device Configurator

A desktop utility for discovering and configuring an explicitly granted HID
peripheral. It uses the platform's bounded device transaction capability and a
small versioned protocol owned by the application.

The application discovers the granted device without exposing its
operating-system path or serial number, connects and synchronizes its current
sensitivity, lighting, profile, and ordinary control inventory, then applies
locally validated changes as one acknowledged transaction.

The host supports physical HID devices through the established `hidapi`
package. Specifications grant a deterministic virtual device which implements
the identical framed protocol and state machine; it is not a UI test double.
Semantic specs cover discovery, authority denial, bounded editing and apply,
resource ownership, and a realistic 100-control scaling case through the
ordinary virtualized controls view.
