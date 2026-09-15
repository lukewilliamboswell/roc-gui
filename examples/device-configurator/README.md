# Device Configurator

A profile-based utility for discovering and configuring a peripheral through a
documented local protocol, with a virtual device available for first-run use.

## Core capabilities

- Device discovery, connection lifecycle, capabilities, live status, and reconnect behavior.
- Profiles containing button mappings, sensitivity, toggles, ranges, and device-specific options.
- Dirty-state comparison, validation, read from device, apply transaction, revert, and restore defaults.
- Firmware information and an integrity-checked update workflow with explicit progress and cancellation policy.
- Permission guidance and hot-plug behavior across supported operating systems.

## Happy paths

- Discover the bundled virtual device, connect, inspect its capabilities, and select a profile.
- Change mappings and sensitivity, preview the pending difference, apply it, and read back confirmation.
- Save and switch profiles, reconnect the device, and verify the active profile is represented accurately.
- Complete a simulated firmware update through the same protocol and state machine as physical devices.

## Error paths

- No device, permission denial, disconnect, protocol mismatch, unsupported capability, and busy device are distinct states.
- Failed or partially acknowledged apply operations trigger read-back and never claim an unconfirmed configuration.
- Disconnect during firmware update follows the device protocol's recoverable and non-cancellable phases.
- Invalid profiles cannot reach the device and remain editable without overwriting the last valid profile.

## High-level goals

- Drive hot-plug events, permissions, sliders, mappings, profiles, transactional effects, and progress.
- Make the virtual device a deterministic implementation of the public protocol, not a UI-only test double.
- SCM specs cover discovery, connection, editing, apply/read-back, reconnect, permissions, protocol errors, and updates.
- A scaling case manages a device with a realistic number of configurable controls and profiles.
