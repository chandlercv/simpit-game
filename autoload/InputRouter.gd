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

## Per-device binding profiles — supporting new hardware means adding an
## entry here, not touching gameplay code. `axes`/`buttons` are raw Godot
## indices injected into the Input Map by _bind_hotas(). `throttle` is the
## one direct-read axis (the X52's +1(idle)..-1(full) range needs rescaling,
## which actions can't express). `reserved_buttons` are selector-position
## banks where one button is always held — never bind actions to them.
const PROFILES := [
	{
		"name": "Saitek X52 Flight Control System",
		"guid": "0300ea18a30600005c07000000000000",
		"axes": [],
		"buttons": [
			# Throttle-side buttons observed as 6/7 (Fire E/D by feel — swap
			# here if the physical buttons turn out reversed).
			{"button": 7, "action": "ops_approach"},
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

var _throttle_device := -1
var _throttle_axis := 0
var _throttle_deadzone := 1.0
## action name -> events we injected, so rebinding on replug is clean.
var _bound: Dictionary = {}
var _glance_bridge: HidGlanceBridgeScene


func _ready() -> void:
	add_child(SwitchPanelBridgeScene.new())
	_glance_bridge = HidGlanceBridgeScene.new()
	add_child(_glance_bridge)
	Input.joy_connection_changed.connect(
			func(_device: int, _connected: bool) -> void: _bind_hotas())
	_bind_hotas()


## Re-resolve GUID -> device index and rebuild the injected Input Map events.
func _bind_hotas() -> void:
	for action: String in _bound:
		for event: InputEvent in _bound[action]:
			if InputMap.action_has_event(action, event):
				InputMap.action_erase_event(action, event)
	_bound = {}
	_throttle_device = -1
	for device in Input.get_connected_joypads():
		var guid := Input.get_joy_guid(device)
		for profile: Dictionary in PROFILES:
			if profile["guid"] != guid:
				continue
			if profile.has("throttle"):
				_throttle_device = device
				_throttle_axis = profile["throttle"]["axis"]
				_throttle_deadzone = profile["throttle"]["idle_deadzone"]
			for spec: Dictionary in profile["axes"]:
				_inject(spec["neg"], _motion(device, spec["axis"], -1.0))
				_inject(spec["pos"], _motion(device, spec["axis"], 1.0))
			for spec: Dictionary in profile["buttons"]:
				var event := InputEventJoypadButton.new()
				event.device = device
				event.button_index = spec["button"] as JoyButton
				_inject(spec["action"], event)


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
## idle.
func throttle() -> float:
	if _throttle_device == -1:
		return 0.0
	var value := Input.get_joy_axis(_throttle_device, _throttle_axis as JoyAxis)
	if value >= _throttle_deadzone:
		return 0.0
	return clampf((1.0 - value) / 2.0, 0.0, 1.0)


func _process(_delta: float) -> void:
	var thrust := Vector3(
		Input.get_axis("strafe_left", "strafe_right"),
		Input.get_axis("thrust_down", "thrust_up"),
		clampf(Input.get_axis("thrust_back", "thrust_forward") + throttle(), -1.0, 1.0))
	var rot := Vector3(
		Input.get_axis("pitch_down", "pitch_up"),
		Input.get_axis("yaw_right", "yaw_left"),
		Input.get_axis("roll_right", "roll_left"))
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
	return (keys + _glance_bridge.glance).limit_length(1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
