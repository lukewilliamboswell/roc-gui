import pf.Action
import pf.Device
import pf.Elem
import Protocol

Configurator := [].{
	State : State
	init : State
	init = { config: None, connected: None, devices: [], dirty: False, generation: 0, status: "Ready to discover devices" }
	discover : State -> Action.Action(State)
	discover = discover
	connect : State -> Action.Action(State)
	connect = connect
	apply : State -> Action.Action(State)
	apply = apply
	disconnect : State -> Action.Action(State)
	disconnect = disconnect
	render : State -> Elem.Elem(State)
	render = render
}

State : { config : [None, Some(Protocol.Config)], connected : [None, Some(Device.Connection)], devices : List(Device.Info), dirty : Bool, generation : U64, status : Str }

message = |err| match err {
	AcquireDeviceErr(AccessDenied) => "Device access denied"
	DiscoverDeviceErr(NotFound) => "No granted device is connected"
	ConnectDeviceErr(NotFound) => "Device disconnected before connection"
	TransactDeviceErr(Disconnected) => "Device disconnected"
	TransactDeviceErr(Protocol) => "Device protocol rejected the request"
	_ => "Device operation failed"
}

discover = |state| {
	next = state.generation + 1
	Action.task({
		pending: { ..state, generation: next, devices: [], status: "Discovering devices" },
		run: || match Device.acquire!() { Err(err) => DiscoveryFailed(err), Ok(grant) => match Device.discover!(grant) { Err(err) => DiscoveryFailed(err), Ok(devices) => Discovered(devices) } },
		resolve: |latest, result| if latest.generation != next Action.none else match result { DiscoveryFailed(err) => Action.update({ ..latest, status: message(err) }), Discovered(devices) => Action.update({ ..latest, devices, status: "Found ${List.len(devices).to_str()} device" }) },
	})
}

connect = |state| {
	next = state.generation + 1
	Action.task({
		pending: { ..state, generation: next, status: "Connecting" },
		run: || match Device.acquire!() {
			Err(err) => ConnectFailed(err)
			Ok(grant) => match Device.connect!(grant) {
				Err(err) => ConnectFailed(err)
				Ok(connection) => match Device.transact!(connection, Protocol.read_request) { Err(err) => ConnectFailed(err), Ok(bytes) => match Protocol.decode_config(bytes) { Err(_) => ProtocolFailed, Ok(config) => Connected({ config, connection }) } }
			}
		},
		resolve: |latest, result| if latest.generation != next Action.none else match result { ConnectFailed(err) => Action.update({ ..latest, status: message(err) }), ProtocolFailed => Action.update({ ..latest, status: "Unsupported device protocol" }), Connected(value) => Action.update({ ..latest, config: Some(value.config), connected: Some(value.connection), dirty: False, status: "Connected and synchronized" }) },
	})
}

change_sensitivity = |state, increase| match state.config {
	None => state
	Some(config) => {
		next = if increase { if config.sensitivity >= 3100 3200 else config.sensitivity + 100 } else { if config.sensitivity <= 200 100 else config.sensitivity - 100 }
		{ ..state, config: Some({ ..config, sensitivity: next }), dirty: True, status: "Unsaved changes" }
	}
}

toggle_lighting = |state, checked| match state.config { None => state, Some(config) => { ..state, config: Some({ ..config, lighting: checked }), dirty: True, status: "Unsaved changes" } }
select_profile = |state, profile| match state.config { None => state, Some(config) => { ..state, config: Some({ ..config, profile }), dirty: True, status: "Unsaved changes" } }

apply = |state| match { connection: state.connected, config: state.config } {
	{ connection: Some(connection), config: Some(config) } => Action.task({
		pending: { ..state, status: "Applying configuration" },
		run: || match Device.transact!(connection, Protocol.apply_request(config)) { Err(err) => ApplyFailed(err), Ok(bytes) => match Protocol.decode_apply(bytes) { Ok(_) => Applied, Err(_) => ApplyProtocolFailed } },
		resolve: |latest, result| match result { Applied => Action.update({ ..latest, dirty: False, status: "Configuration applied" }), ApplyProtocolFailed => Action.update({ ..latest, status: "Device returned an invalid acknowledgement" }), ApplyFailed(err) => Action.update({ ..latest, status: message(err) }) },
	})
	_ => Action.update({ ..state, status: "Connect a device first" })
}

disconnect = |state| match state.connected {
	None => Action.update({ ..state, status: "No device is connected" })
	Some(connection) => Action.task({
		pending: { ..state, status: "Disconnecting" },
		run: || Device.close!(connection),
		resolve: |latest, result| match result { Err(err) => Action.update({ ..latest, status: message(err) }), Ok(_) => Action.update({ ..latest, connected: None, config: None, dirty: False, status: "Disconnected" }) },
	})
}

control_items = |count| {
	var $items = []
	var $index = 0
	while $index < U16.to_u64(count) {
		key = $index
		$items = $items.append(Elem.VirtualListItem.{ key, content: Elem.text("Control ${($index + 1).to_str()}: Primary action") })
		$index = $index + 1
	}
	$items
}

render = |state| {
	connected = match state.connected { Some(_) => True, None => False }
	device_rows = state.devices.map_with_index(|device, index| Elem.text("Device ${index.to_str()}: ${device.manufacturer} ${device.product}"))
	settings = match state.config {
		None => [Elem.text("Connect to inspect configuration")]
		Some(config) => [
			Elem.text("Sensitivity: ${config.sensitivity.to_str()} DPI"),
			Elem.row(Elem.RowProps.{ label: "Sensitivity controls" }, [
				Elem.action_button(Elem.ActionButtonProps.{ caption: "Decrease", label: "Decrease sensitivity", on_press: |current, _| Action.update(change_sensitivity(current, False)) }),
				Elem.action_button(Elem.ActionButtonProps.{ caption: "Increase", label: "Increase sensitivity", on_press: |current, _| Action.update(change_sensitivity(current, True)) }),
			]),
			Elem.checkbox(Elem.CheckboxProps.{ label: "Device lighting", checked: config.lighting, on_change: |current, event| Action.update(toggle_lighting(current, event.checked)) }),
			Elem.row(Elem.RowProps.{ label: "Profile controls" }, [1, 2, 3, 4, 5].map(|profile| Elem.action_button(Elem.ActionButtonProps.{ caption: "Profile ${profile.to_str()}", label: "Select profile ${profile.to_str()}", on_press: |current, _| Action.update(select_profile(current, profile)) }))),
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Apply changes", label: "Apply configuration", enabled: state.dirty, on_press: |current, _| apply(current) }),
			Elem.virtual_list(Elem.VirtualListProps.{ name: "Device controls", row_height: 28, items: control_items(config.controls) }),
		]
	}
	Elem.col(Elem.ColProps.{ label: "Device Configurator", width: Fill, height: Fill, grow: True, gap: 12 }, [
		Elem.text("Device Configurator"),
		Elem.row(Elem.RowProps.{ label: "Device actions" }, [
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Discover devices", label: "Discover devices", on_press: |current, _| discover(current) }),
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Connect", label: "Connect device", enabled: List.len(state.devices) > 0 and !connected, on_press: |current, _| connect(current) }),
			Elem.action_button(Elem.ActionButtonProps.{ caption: "Disconnect", label: "Disconnect device", enabled: connected, on_press: |current, _| disconnect(current) }),
			Elem.text(state.status),
		]),
	].concat(device_rows).concat(settings))
}
