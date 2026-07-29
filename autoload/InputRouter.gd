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
## `reserved_buttons` are selector-position banks where one button is always
## held — never bind actions to them.
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


## 0..1 forward thrust from the throttle profile's axis, 0 when absent or at
## idle. Two spec forms:
##   {idle_deadzone}   legacy X52 (idle=+1, full=-1; zero when raw >= deadzone)
##   {idle, full}      general — any rest/travel range and direction, with an
##                     optional normalized `deadzone` (default 0.02) near idle.
func throttle() -> float:
	if _throttle_device == -1:
		return 0.0
	var value := Input.get_joy_axis(_throttle_device, _throttle_axis as JoyAxis)
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
