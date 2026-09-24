## Discovery, connection, and the acknowledged apply.
##
## Every operation here takes the resources it needs rather than looking them up
## in the state and apologising when they are absent. `apply` cannot be called
## without a connection and a configuration because it asks for both, and
## `disconnect` cannot be called without a connection for the same reason. The
## application used to answer "Connect a device first" and "No device is
## connected" from branches the controls made unreachable; a message nobody can
## ever read is not a safety net, it is a claim the type system should have been
## making. The explanation a person actually needs is in the window, beside the
## control that will not move.
import pf.Gui
import Protocol

Configurator := [].{
	State : State

	## Where the application is with respect to one piece of hardware. The window
	## turns each of these into the sentence a person reads, so a refusal or a
	## lost connection is a state to design rather than a string to print.
	Status : Status

	## The bounds the device accepts, which the window shows and the editor
	## enforces before anything is sent.
	sensitivity_floor : U16
	sensitivity_floor = sensitivity_floor
	sensitivity_ceiling : U16
	sensitivity_ceiling = sensitivity_ceiling
	sensitivity_step : U16
	sensitivity_step = sensitivity_step

	## Authority arrives here and nowhere else, so it is held in state: the tasks
	## that acquire run later and need it where they run.
	init : Gui.Access -> State
	init = |access| { access, config: None, connected: None, devices: [], dirty: False, generation: 0, status: Ready }

	discover : State -> Gui.Action(State)
	discover = discover

	connect : State -> Gui.Action(State)
	connect = connect

	## One transaction carrying the whole configuration, which the device must
	## acknowledge before the application believes anything changed.
	apply : State, Gui.Device.Connection, Protocol.Config -> Gui.Action(State)
	apply = apply

	disconnect : State, Gui.Device.Connection -> Gui.Action(State)
	disconnect = disconnect

	change_sensitivity : State, Bool -> State
	change_sensitivity = change_sensitivity
	toggle_lighting : State, Bool -> State
	toggle_lighting = toggle_lighting
	select_profile : State, U8 -> State
	select_profile = select_profile
}

Status : [
	Applied,
	Applying,
	Connected,
	Connecting,
	Dirty,
	Disconnected,
	Disconnecting,
	Discovered(U64),
	Discovering,
	Lost(Str),
	Ready,
	Refused(Str),
]

State : {
	access : Gui.Access,
	config : [None, Some(Protocol.Config)],
	connected : [None, Some(Gui.Device.Connection)],
	devices : List(Gui.Device.Info),
	dirty : Bool,
	generation : U64,
	status : Status,
}

sensitivity_floor = 100.U16

sensitivity_ceiling = 3200.U16

sensitivity_step = 100.U16

message = |err| match err {
	AcquireDeviceErr(AccessDenied) => "Device access denied"
	DiscoverDeviceErr(NotFound) => "No granted device is connected"
	ConnectDeviceErr(NotFound) => "Device disconnected before connection"
	TransactDeviceErr(Disconnected) => "Device disconnected"
	TransactDeviceErr(Protocol) => "Device protocol rejected the request"
	_ => "Device operation failed"
}

## A refusal of authority and a device that went away are different situations
## with different remedies, so they are told apart where the error arrives.
refusal = |err| match err {
	AcquireDeviceErr(AccessDenied) => Refused(message(err))
	_ => Lost(message(err))
}

discover = |state| {
	next = state.generation + 1
	Gui.Action.task({
		pending: { ..state, generation: next, devices: [], status: Discovering },
		run: || match state.access.device!() {
			Err(err) => DiscoveryFailed(err)
			Ok(grant) => match grant.discover!() {
				Err(err) => DiscoveryFailed(err)
				Ok(devices) => Discovered(devices)
			}
		},
		resolve: |latest, result| if latest.generation != next Gui.Action.none else match result {
			DiscoveryFailed(err) => Gui.Action.update({ ..latest, status: refusal(err) })
			Discovered(devices) => Gui.Action.update({ ..latest, devices, status: Discovered(List.len(devices)) })
		},
	})
}

connect = |state| {
	next = state.generation + 1
	Gui.Action.task({
		pending: { ..state, generation: next, status: Connecting },
		run: || match state.access.device!() {
			Err(err) => ConnectFailed(err)
			Ok(grant) => match grant.connect!() {
				Err(err) => ConnectFailed(err)
				Ok(connection) => match connection.transact!(Protocol.read_request) {
					Err(err) => ConnectFailed(err)
					Ok(bytes) => match Protocol.decode_config(bytes) {
						Err(_) => ProtocolFailed
						Ok(config) => Connected({ config, connection })
					}
				}
			}
		},
		resolve: |latest, result| if latest.generation != next Gui.Action.none else match result {
			ConnectFailed(err) => Gui.Action.update({ ..latest, status: refusal(err) })
			ProtocolFailed => Gui.Action.update({ ..latest, status: Lost("Unsupported device protocol") })
			Connected(value) => Gui.Action.update({
				..latest,
				config: Some(value.config),
				connected: Some(value.connection),
				dirty: False,
				status: Connected,
			})
		},
	})
}

## A transaction that fails because the device went away leaves a handle that
## refers to nothing. Keeping it would offer Disconnect and Apply for hardware
## that is no longer there, so the connection is given up with the error.
apply = |state, connection, config| Gui.Action.task({
	pending: { ..state, status: Applying },
	run: || match connection.transact!(Protocol.apply_request(config)) {
		Err(err) => ApplyFailed(err)
		Ok(bytes) => match Protocol.decode_apply(bytes) {
			Ok(_) => Applied
			Err(_) => ApplyProtocolFailed
		}
	},
	resolve: |latest, result| match result {
		Applied => Gui.Action.update({ ..latest, dirty: False, status: Applied })
		ApplyProtocolFailed => Gui.Action.update({ ..latest, status: Lost("The device returned an invalid acknowledgement") })
		ApplyFailed(err) => Gui.Action.update({ ..latest, config: None, connected: None, dirty: False, status: Lost(message(err)) })
	},
})

disconnect = |state, connection| Gui.Action.task({
	pending: { ..state, status: Disconnecting },
	run: || connection.close!(),
	resolve: |latest, result| match result {
		Err(err) => Gui.Action.update({ ..latest, config: None, connected: None, dirty: False, status: Lost(message(err)) })
		Ok(_) => Gui.Action.update({ ..latest, config: None, connected: None, dirty: False, status: Disconnected })
	},
})

edited = |state, config| { ..state, config: Some(config), dirty: True, status: Dirty }

## The bounds are enforced here rather than at the transaction, so a person is
## never allowed to compose a request the device would refuse.
change_sensitivity = |state, increase| match state.config {
	None => state
	Some(config) => {
		next = if increase {
			if config.sensitivity + sensitivity_step >= sensitivity_ceiling sensitivity_ceiling else config.sensitivity + sensitivity_step
		} else if config.sensitivity <= sensitivity_floor + sensitivity_step {
			sensitivity_floor
		} else {
			config.sensitivity - sensitivity_step
		}
		edited(state, { ..config, sensitivity: next })
	}
}

toggle_lighting = |state, checked| match state.config {
	None => state
	Some(config) => edited(state, { ..config, lighting: checked })
}

select_profile = |state, profile| match state.config {
	None => state
	Some(config) => edited(state, { ..config, profile })
}
