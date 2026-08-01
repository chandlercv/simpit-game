extends Node
## Raw joypad/keyboard input -> GameState intents. GameState never cares
## where an input came from: HOTAS axes, keyboard fallbacks, and the raw-HID
## switch panel all land here first.
##
## Devices are matched by GUID at runtime and their events injected into the
## named actions below — device *indices* shift across replugs, GUIDs don't,
## and gameplay code stays free of hardware numbers. Both sticks are read as
## RAW joysticks (no SDL controller mapping): a mapping would cap each device
## to the gamepad vocabulary (~21 buttons / 6 axes) and silently drop the
## rest, foreclosing controls future contributors may want to bind.
##
## X55 selector-button collision (InputEcho captures, 2026-07-17/19): the
## stick carries a bank of selector-position buttons 15-17 (1-based) of which
## exactly one is ALWAYS held — on this rig button 15, permanently, and its
## 0-based index 14 is JOY_BUTTON_DPAD_RIGHT. Godot also collapses the POV
## hat onto those same DPAD buttons, making hat-right and the held selector
## indistinguishable at the action layer (the old launch-glance bug: camera
## yawed 60 degrees right until the hat was touched). So glance NEVER uses
## the dpad: the hat is decoded from the stick's raw HID report instead
## (HidGlanceBridge), where hat and buttons are separate fields, and the
## glance_* actions keep only their arrow-key events. Indices 11-16 stay
## free for contributors — just never bind a profile's reserved_buttons.

## Per-device binding profiles — the shipped DEFAULTS. Supporting new hardware
## no longer means editing this file: a user JSON profile in
## user://input_profiles/ (see InputConfig) with the same GUID OVERRIDES the
## matching entry here, and one with a new GUID is added — so an arbitrary stick
## can be mapped without touching GDScript. _effective_profiles() merges the two.
##
## `axes`/`buttons` are raw Godot indices injected into the Input Map by
## _bind_hotas(). `throttle` is the one direct-read axis (a HOTAS throttle's
## idle..full range needs rescaling, which actions can't express): the X52 form
## is {axis, idle_deadzone} (idle=+1, full=-1); the general form is
## {axis, idle, full}. `hid_axes` bind a raw-HID virtual axis (e.g. the X52
## mouse nub, see X52MouseBridge / HID_SOURCES) to a direction-action pair.
## `keys` (only on the device-less "keyboard" profile) bind physical keycodes to
## actions — the shipped default keyboard mapping lives there, overridable like
## any profile. `reserved_buttons` are selector-position banks where one button
## is always held — never bind actions to them.
const BUILTIN_PROFILES := [
	{
		"name": "Saitek X52 Flight Control System",
		"guid": "0300ea18a30600005c07000000000000",
		"axes": [],
		"buttons": [
			# Throttle-side buttons observed as 6/7 (Fire E/D by feel — swap
			# here if the physical buttons turn out reversed).
			{"button": 7, "action": "ops_approach"},
			# POV hat -> lateral/vertical strafe. This throttle reports the hat as
			# plain buttons 19-22 (NOT the DPAD): 19 up / 20 right / 21 down /
			# 22 left, captured with InputEcho. Clear of the reserved selector bank
			# (23-25) below.
			{"button": 22, "action": "strafe_left"},
			{"button": 20, "action": "strafe_right"},
			{"button": 19, "action": "thrust_up"},
			{"button": 21, "action": "thrust_down"},
		],
		"throttle": {"axis": 2, "idle_deadzone": 0.95},
		"reserved_buttons": [23, 24, 25],
	},
	{
		"name": "Madcatz Saitek Pro Flight X-55 Rhino Stick",
		"guid": "03004934380700001522000000000000",
		## Axis 0 = X, 1 = Y (back = +1 = pitch up), 2 = twist rudder.
		"axes": [
			{"axis": 2, "neg": "roll_left", "pos": "roll_right"},
			{"axis": 1, "neg": "pitch_down", "pos": "pitch_up"},
			{"axis": 0, "neg": "yaw_left", "pos": "yaw_right"},
		],
		"buttons": [
			{"button": 0, "action": "ops_cut"},
		],
		"reserved_buttons": [14, 15, 16],
	},
	## Default keyboard mapping — a device-less pseudo-profile (guid "keyboard")
	## with a `keys` array (physical keycode -> action), injected by _bind_hotas
	## regardless of joypads. It's DATA, not hardcoded project.godot [input] events:
	## the remapper shows it, a user keyboard.json OVERRIDES it entirely, and
	## clearing every key in the remapper persists an empty override. Only flight /
	## glance / ops / the common panel+camera+tactical commands get a default key;
	## MFD paging, cargo, market and power axes ship unbound (bind in the remapper).
	{
		"name": "Keyboard (default)",
		"guid": "keyboard",
		"keys": [
			{"key": KEY_W, "action": "thrust_forward"},
			{"key": KEY_S, "action": "thrust_back"},
			{"key": KEY_A, "action": "strafe_left"},
			{"key": KEY_D, "action": "strafe_right"},
			{"key": KEY_R, "action": "thrust_up"},
			{"key": KEY_F, "action": "thrust_down"},
			{"key": KEY_I, "action": "pitch_up"},
			{"key": KEY_K, "action": "pitch_down"},
			{"key": KEY_J, "action": "yaw_left"},
			{"key": KEY_L, "action": "yaw_right"},
			{"key": KEY_Q, "action": "roll_left"},
			{"key": KEY_E, "action": "roll_right"},
			{"key": KEY_LEFT, "action": "glance_left"},
			{"key": KEY_RIGHT, "action": "glance_right"},
			{"key": KEY_UP, "action": "glance_up"},
			{"key": KEY_DOWN, "action": "glance_down"},
			{"key": KEY_V, "action": "ops_approach"},
			{"key": KEY_C, "action": "ops_cut"},
			{"key": KEY_M, "action": "sensor_mode_cycle"},
			{"key": KEY_COMMA, "action": "salvage_prev"},
			{"key": KEY_PERIOD, "action": "salvage_next"},
			{"key": KEY_N, "action": "contact_cycle"},
			{"key": KEY_G, "action": "mfd_a_menu"},
			{"key": KEY_H, "action": "mfd_b_menu"},
			{"key": KEY_T, "action": "tactical_view_cycle"},
			{"key": KEY_BRACKETRIGHT, "action": "view_cycle"},
			{"key": KEY_1, "action": "view_rear"},
			{"key": KEY_2, "action": "view_side"},
			{"key": KEY_3, "action": "view_chase"},
			{"key": KEY_4, "action": "view_top"},
		],
	},
]

const SwitchPanelBridgeScene := preload("res://systems/hardware/SwitchPanelBridge.gd")
const HidGlanceBridgeScene := preload("res://systems/hardware/HidGlanceBridge.gd")
const X52MouseBridgeScene := preload("res://systems/hardware/X52MouseBridge.gd")
const ControlsSetupScene := preload("res://scenes/displays/ControlsSetup.gd")

## Raw-HID virtual axes a profile's `hid_axes` may bind. Names only; the live
## value is fetched in _hid_source_value(). Adding a source = a name here + a
## case there (+ a bridge exposing it). The X52 nub lives here because Godot's
## joypad layer can't see it; the X52 scroll wheel does NOT — Godot exposes it as
## joypad buttons 32/33, bound through a profile's normal `buttons`.
const HID_SOURCES: Array[String] = ["x52_mouse_x", "x52_mouse_y"]

## Power channel -> its [lo, hi] axis-pair action names. A bound axis on the pair
## drives the channel 0..1 (see _process_power_axes). Kept as data so the remapper
## rows and the consumer stay in step.
const POWER_AXES: Dictionary = {
	"THRUST": ["power_thrust_lo", "power_thrust_hi"],
	"CUTTER": ["power_cutter_lo", "power_cutter_hi"],
	"SENSORS": ["power_sensors_lo", "power_sensors_hi"],
	"LIFE": ["power_life_lo", "power_life_hi"],
}

## Direct-select camera-view action -> the vantage it picks.
const VIEW_ACTIONS: Dictionary = {
	"view_rear": "REAR", "view_side": "SIDE", "view_chase": "CHASE", "view_top": "TOP",
}

var _throttle_device := -1
var _throttle_axis := 0
## Full throttle spec of the active profile ({idle_deadzone} or {idle, full});
## throttle() reads it directly so arbitrary throttle ranges rescale correctly.
var _throttle_spec: Dictionary = {}
## action name -> events we injected, so rebinding on replug is clean.
var _bound: Dictionary = {}
## `hid_axes` specs of the active profiles, composited in _process() because raw
## HID values can't live in the Input Map.
var _hid_axis_bindings: Array = []
var _glance_bridge: HidGlanceBridgeScene
var _mouse_bridge: X52MouseBridgeScene
var _controls_layer: CanvasLayer
var _controls_ui: Control


func _ready() -> void:
	add_child(SwitchPanelBridgeScene.new())
	_glance_bridge = HidGlanceBridgeScene.new()
	add_child(_glance_bridge)
	_mouse_bridge = X52MouseBridgeScene.new()
	add_child(_mouse_bridge)
	Input.joy_connection_changed.connect(
			func(_device: int, _connected: bool) -> void: _bind_hotas())
	# A saved/edited user profile rebinds live, same path as a replug.
	InputConfig.profiles_changed.connect(_bind_hotas)
	_bind_hotas()


## Shipped defaults overlaid with the user's JSON profiles: a user entry with the
## same GUID fully REPLACES the built-in (predictable override), a new GUID is
## appended. Matched by GUID in _bind_hotas() just like before.
func _effective_profiles() -> Array:
	var by_guid: Dictionary = {}
	var order: Array = []
	for profile: Dictionary in BUILTIN_PROFILES:
		var guid := String(profile["guid"])
		by_guid[guid] = profile
		order.append(guid)
	for profile in InputConfig.get_user_profiles():
		var guid := String(profile.get("guid", ""))
		if guid.is_empty():
			continue
		if not by_guid.has(guid):
			order.append(guid)
		by_guid[guid] = profile
	var out: Array = []
	for guid: String in order:
		out.append(by_guid[guid])
	return out


## The effective (built-in + user override) profile for a GUID, or {} if none.
## Deep-copied so the remapper can edit a working copy freely.
func profile_for_guid(guid: String) -> Dictionary:
	for profile: Dictionary in _effective_profiles():
		if String(profile.get("guid", "")) == guid:
			return profile.duplicate(true)
	return {}


## Open/close the in-game remapper overlay on our own CanvasLayer (kept separate
## from WindowManager's display-setup overlay so neither tears down the other).
func _toggle_controls_setup() -> void:
	if is_instance_valid(_controls_ui):
		_close_controls_setup()
		return
	_controls_layer = CanvasLayer.new()
	_controls_layer.layer = 25
	get_window().add_child(_controls_layer)
	_controls_ui = ControlsSetupScene.new()
	_controls_ui.closed.connect(_close_controls_setup)
	_controls_layer.add_child(_controls_ui)
	_controls_ui.start()


func _close_controls_setup() -> void:
	if is_instance_valid(_controls_ui):
		_controls_ui.queue_free()
	_controls_ui = null
	if is_instance_valid(_controls_layer):
		_controls_layer.queue_free()
	_controls_layer = null


## Re-resolve GUID -> device index and rebuild the injected Input Map events.
func _bind_hotas() -> void:
	for action: String in _bound:
		for event: InputEvent in _bound[action]:
			if InputMap.action_has_event(action, event):
				InputMap.action_erase_event(action, event)
	_bound = {}
	_throttle_device = -1
	_throttle_spec = {}
	_hid_axis_bindings = []
	var profiles := _effective_profiles()
	for device in Input.get_connected_joypads():
		var guid := Input.get_joy_guid(device)
		for profile: Dictionary in profiles:
			if profile["guid"] != guid:
				continue
			if profile.has("throttle"):
				_throttle_device = device
				_throttle_spec = profile["throttle"]
				_throttle_axis = int(_throttle_spec["axis"])
			for spec: Dictionary in profile.get("axes", []):
				_inject(spec["neg"], _motion(device, int(spec["axis"]), -1.0))
				_inject(spec["pos"], _motion(device, int(spec["axis"]), 1.0))
			for spec: Dictionary in profile.get("buttons", []):
				var event := InputEventJoypadButton.new()
				event.device = device
				event.button_index = int(spec["button"]) as JoyButton
				_inject(spec["action"], event)
			# Raw-HID virtual axes (e.g. the X52 mouse nub) can't live in the
			# Input Map, so record them for compositing in _process().
			for spec: Dictionary in profile.get("hid_axes", []):
				if HID_SOURCES.has(spec.get("source", "")):
					_hid_axis_bindings.append(spec)
	# Keyboard bindings live in a device-less "keyboard" pseudo-profile (written by
	# the remapper). There are no hardware keyboard defaults in project.godot any
	# more — every key mapping comes from here — so inject them regardless of which
	# joypads are connected.
	for profile: Dictionary in profiles:
		if String(profile.get("guid", "")) != "keyboard":
			continue
		for spec: Dictionary in profile.get("keys", []):
			var event := InputEventKey.new()
			event.physical_keycode = int(spec["key"]) as Key
			_inject(String(spec["action"]), event)
	# Only open the X52 mouse HID (which may enumerate as an OS-owned mouse) when
	# a profile actually binds it.
	if _mouse_bridge:
		_mouse_bridge.set_active(not _hid_axis_bindings.is_empty())


## Live value (-1..1) of a raw-HID virtual axis by source name; 0 if unknown.
func _hid_source_value(source: String) -> float:
	match source:
		"x52_mouse_x": return _mouse_bridge.axis.x
		"x52_mouse_y": return _mouse_bridge.axis.y
	return 0.0


## Signed contribution of the bound hid_axes to a (neg, pos) action pair, in the
## same -1..1 convention as Input.get_axis(neg, pos): + toward `pos`, - toward
## `neg`. Order-insensitive so a profile pairing the actions the other way still
## composes correctly. Summed so HID axes add alongside the Input Map ones.
func _hid_axis_amount(neg: String, pos: String) -> float:
	var amount := 0.0
	for spec: Dictionary in _hid_axis_bindings:
		var s_neg := String(spec.get("neg", ""))
		var s_pos := String(spec.get("pos", ""))
		if s_neg == neg and s_pos == pos:
			amount += _hid_source_value(spec["source"])
		elif s_neg == pos and s_pos == neg:
			amount -= _hid_source_value(spec["source"])
	return amount


func _motion(device: int, axis: int, direction: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis as JoyAxis
	event.axis_value = direction
	return event


func _inject(action: String, event: InputEvent) -> void:
	InputMap.action_add_event(action, event)
	if not _bound.has(action):
		_bound[action] = []
	_bound[action].append(event)


## -1..1 forward/back command from the throttle profile's axis, 0 when absent
## or at rest. Three spec forms:
##   {mode:"gamepad"}  bipolar, center-rest (a self-centering stick/trigger axis
##                     rather than a lever): raw value is the command directly,
##                     0 at center, ±1 at the stops; `invert` flips sign. The
##                     ship-wide reverse cap (SalvageSystem, secondary_thrust_
##                     fraction) does the asymmetric forward/reverse scaling,
##                     not this curve.
##   {idle_deadzone}   legacy X52 lever (idle=+1, full=-1; zero when raw >= deadzone)
##   {idle, full}      general lever — any rest/travel range and direction, with
##                     an optional normalized `deadzone` (default 0.02) near idle.
func throttle() -> float:
	if _throttle_device == -1:
		return 0.0
	var value := Input.get_joy_axis(_throttle_device, _throttle_axis as JoyAxis)
	if String(_throttle_spec.get("mode", "")) == "gamepad":
		var v := clampf(value, -1.0, 1.0)
		if _throttle_spec.get("invert", false):
			v = -v
		if absf(v) <= float(_throttle_spec.get("deadzone", 0.05)):
			return 0.0
		return v
	if _throttle_spec.has("idle_deadzone"):
		if value >= float(_throttle_spec["idle_deadzone"]):
			return 0.0
		return clampf((1.0 - value) / 2.0, 0.0, 1.0)
	var idle := float(_throttle_spec.get("idle", 1.0))
	var full := float(_throttle_spec.get("full", -1.0))
	var span := idle - full
	if is_zero_approx(span):
		return 0.0
	var norm := (idle - value) / span
	if norm <= float(_throttle_spec.get("deadzone", 0.02)):
		return 0.0
	return clampf(norm, 0.0, 1.0)


func _process(_delta: float) -> void:
	# Polled (not _unhandled_input) so the hotkey fires regardless of which window
	# has OS focus — same rationale as WindowManager's F5/F6 (see get_glance).
	if DisplayServer.get_name() != "headless" and Input.is_action_just_pressed("configure_controls"):
		_toggle_controls_setup()
	var thrust := Vector3(
		Input.get_axis("strafe_left", "strafe_right") + _hid_axis_amount("strafe_left", "strafe_right"),
		Input.get_axis("thrust_down", "thrust_up") + _hid_axis_amount("thrust_down", "thrust_up"),
		Input.get_axis("thrust_back", "thrust_forward") + _hid_axis_amount("thrust_back", "thrust_forward") + throttle())
	thrust = thrust.clampf(-1.0, 1.0)
	var rot := Vector3(
		Input.get_axis("pitch_down", "pitch_up") + _hid_axis_amount("pitch_down", "pitch_up"),
		Input.get_axis("yaw_right", "yaw_left") + _hid_axis_amount("yaw_right", "yaw_left"),
		Input.get_axis("roll_right", "roll_left") + _hid_axis_amount("roll_right", "roll_left"))
	rot = rot.clampf(-1.0, 1.0)
	SalvageSystem.set_manual_flight(thrust, rot)
	if Input.is_action_just_pressed("ops_approach"):
		SalvageSystem.toggle_approach()
	if Input.is_action_just_pressed("ops_cut"):
		SalvageSystem.request_cut()
	if Input.is_action_just_pressed("throttle_cmd_toggle"):
		SalvageSystem.toggle_throttle_cmd_mode()
	_process_panel_commands()


## Mapped equivalents of the MFD/Tactical/Camera touch controls, so every panel
## command is reachable from a bound button/axis (README: any input surface can
## drive the same intent). All go through the same GameState/system intents the
## on-screen buttons call, so touch and HOTAS stay in agreement.
func _process_panel_commands() -> void:
	# MFD page navigation (per unit, via the "mfd_unit" group).
	if Input.is_action_just_pressed("mfd_a_menu"):
		_mfd_call("A", "go_home")
	if Input.is_action_just_pressed("mfd_b_menu"):
		_mfd_call("B", "go_home")
	if Input.is_action_just_pressed("mfd_a_page_next"):
		_mfd_call("A", "page_step", 1)
	if Input.is_action_just_pressed("mfd_a_page_prev"):
		_mfd_call("A", "page_step", -1)
	if Input.is_action_just_pressed("mfd_b_page_next"):
		_mfd_call("B", "page_step", 1)
	if Input.is_action_just_pressed("mfd_b_page_prev"):
		_mfd_call("B", "page_step", -1)

	# Salvage / sensors.
	if Input.is_action_just_pressed("salvage_next"):
		SalvageSystem.cycle_member(1)
	if Input.is_action_just_pressed("salvage_prev"):
		SalvageSystem.cycle_member(-1)
	if Input.is_action_just_pressed("sensor_mode_cycle"):
		GameState.cycle_sensor_mode()
	if Input.is_action_just_pressed("contact_cycle"):
		GameState.cycle_tracked_contact(1)

	# Tactical display mode (SCOPE / CHART) — toggle or jump straight to one.
	if Input.is_action_just_pressed("tactical_view_cycle"):
		GameState.cycle_tactical_view()
	if Input.is_action_just_pressed("tactical_scope"):
		GameState.set_tactical_view("SCOPE")
	if Input.is_action_just_pressed("tactical_chart"):
		GameState.set_tactical_view("CHART")

	# Market. Dock has no unambiguous target from a single button, so it docks at
	# the first faction; SELL / DEPART are unambiguous.
	if Input.is_action_just_pressed("market_dock") and GameState.docked_faction == -1 \
			and not GameState.market_factions.is_empty():
		MarketSystem.request_dock(0)
	if Input.is_action_just_pressed("market_sell"):
		MarketSystem.sell_hold()
	if Input.is_action_just_pressed("market_depart"):
		MarketSystem.request_undock()

	# Cargo (via the "cargo_grid" group — acts on whichever grid(s) are up).
	if Input.is_action_just_pressed("cargo_next"):
		_cargo_call("select_step", 1)
	if Input.is_action_just_pressed("cargo_prev"):
		_cargo_call("select_step", -1)
	if Input.is_action_just_pressed("cargo_jettison"):
		_cargo_call("jettison_selected")

	# External camera views.
	if Input.is_action_just_pressed("view_cycle"):
		GameState.cycle_external_view()
	for action: String in VIEW_ACTIONS:
		if Input.is_action_just_pressed(action):
			GameState.set_external_view(VIEW_ACTIONS[action])

	_process_power_axes()


## How much a digital (key/button) POWER binding nudges its channel per press.
const POWER_STEP := 0.1

## Per power channel, split by how the row is bound (last writer wins, alongside
## the switch panel/touch):
##   * an analog axis on either row acts as a slider — the -1..1 axis maps to 0..1
##     and is re-asserted every frame from the lever's resting position;
##   * otherwise digital keys/buttons nudge the channel by POWER_STEP per press
##     (_hi steps up, _lo steps down) and hold — a digital event's idle state
##     never drives the channel, so it can't peg it to the midpoint.
## A row with neither bound is skipped, so an unbound channel isn't driven.
func _process_power_axes() -> void:
	for channel: String in POWER_AXES:
		var pair: Array = POWER_AXES[channel]
		if _row_has_analog(pair[0]) or _row_has_analog(pair[1]):
			var axis := Input.get_axis(pair[0], pair[1])
			GameState.set_power(channel, (axis + 1.0) / 2.0)
			continue
		_nudge_power(channel, Input.is_action_just_pressed(pair[1]),
				Input.is_action_just_pressed(pair[0]))


## Step a power channel by ±POWER_STEP from its current target on a digital
## up/down press, clamped to 0..1 by set_power. Split out from the input reading
## above so the stepping is testable without synthesising just-pressed input.
func _nudge_power(channel: String, up: bool, down: bool) -> void:
	var step := 0.0
	if up:
		step += POWER_STEP
	if down:
		step -= POWER_STEP
	if step != 0.0:
		GameState.set_power(channel, GameState.power_target(channel) + step)


## True if the action has at least one analog (joypad-motion) event bound, i.e.
## the row should be driven as a continuous slider rather than a digital nudge.
func _row_has_analog(action: String) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			return true
	return false


func _mfd_call(unit_id: String, method: String, arg: Variant = null) -> void:
	for node in get_tree().get_nodes_in_group("mfd_unit"):
		if node.unit_id == unit_id:
			if arg == null:
				node.call(method)
			else:
				node.call(method, arg)
			return


## Only the grid(s) actually on screen respond: both MFD units eagerly build a
## CARGO InventoryGrid that joins this group at _ready(), so a hidden page's grid
## would otherwise step its selection and — worse — jettison its stale selection
## from a screen the player isn't even looking at. is_visible_in_tree() enforces
## the "whichever grid(s) are up" contract this dispatch was always meant to have.
func _cargo_call(method: String, arg: Variant = null) -> void:
	for node in get_tree().get_nodes_in_group("cargo_grid"):
		if not node.is_visible_in_tree():
			continue
		if arg == null:
			node.call(method)
		else:
			node.call(method, arg)


## Digital glance direction, +x = right, +y = down: the X55 POV hat via raw
## HID (see header) combined with the arrow-key actions (the desk-free dev
## fallback). The Input singleton and the HID read are both process-global,
## so this keeps working no matter which of the four windows has OS focus
## (plan risk #6).
func get_glance() -> Vector2:
	var keys := Input.get_vector("glance_left", "glance_right", "glance_up", "glance_down")
	var hid := Vector2(
		_hid_axis_amount("glance_left", "glance_right"),
		_hid_axis_amount("glance_up", "glance_down"))
	return (keys + hid + _glance_bridge.glance).limit_length(1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
