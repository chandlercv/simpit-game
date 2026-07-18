extends Node
## Raw joypad/keyboard input -> GameState intents. GameState never cares
## where an input came from: HOTAS axes, keyboard fallbacks, and the raw-HID
## switch panel all land here first.
##
## HOTAS bindings (Phase 5, from tools/InputEcho.tscn discovery on the real
## hardware, log of 2026-07-17): devices are matched by GUID at runtime and
## their events injected into the named actions below — device *indices*
## shift across replugs, GUIDs don't, and gameplay code stays free of
## hardware numbers. The X52 throttle can't go through an action (its
## +1(idle)..-1(full) range needs rescaling), so it's the one axis read
## directly, still resolved by GUID.
##
## The X55 primary POV hat arrives as JOY_BUTTON_DPAD_* (plan risk #1) and
## already drives the glance actions bound in project.godot.
##
## X55 quirk (confirmed on joy.cpl video + InputEcho logs, 2026-07-17): the
## stick's driver holds raw button 15 (1-based) down PERMANENTLY, and its
## 0-based index 14 collides with Godot's JOY_BUTTON_DPAD_RIGHT. Godot's
## per-poll hat processing stomps that raw state back to released, so the
## held button only leaks through once at launch — which used to leave the
## glance camera yawed 60 degrees right until the hat was touched. The
## glance latch below swallows that launch artifact: glance reads zero until
## the raw vector first CHANGES from whatever it was at startup.

const X52_GUID := "0300ea18a30600005c07000000000000"
const X55_GUID := "03004934380700001522000000000000"

## X55 stick: axis 0 = X, 1 = Y (back = +1 = pitch up), 2 = twist rudder.
const AXIS_ACTIONS := [
	{"guid": X55_GUID, "axis": 0, "neg": "roll_left", "pos": "roll_right"},
	{"guid": X55_GUID, "axis": 1, "neg": "pitch_down", "pos": "pitch_up"},
	{"guid": X55_GUID, "axis": 2, "neg": "yaw_left", "pos": "yaw_right"},
]

## X52 throttle-side buttons observed as 6/7 (Fire E/D by feel — swap here
## if the physical buttons turn out reversed).
const BUTTON_ACTIONS := [
	{"guid": X52_GUID, "button": 7, "action": "ops_approach"},
	{"guid": X52_GUID, "button": 6, "action": "ops_cut"},
]

## X52 axis 2: +1 at idle, -1 at full — rescaled to 0..1 forward thrust.
const THROTTLE_GUID := X52_GUID
const THROTTLE_AXIS := 2
const THROTTLE_IDLE_DEADZONE := 0.95

const SwitchPanelBridgeScene := preload("res://systems/hardware/SwitchPanelBridge.gd")

var _throttle_device := -1
## action name -> events we injected, so rebinding on replug is clean.
var _bound: Dictionary = {}

## Glance startup latch (see X55 quirk above). While latched, get_glance()
## returns zero; the latch clears the first time the raw vector changes from
## its at-launch sample, i.e. on the first real hat (or arrow-key) input.
var _glance_latched := true
var _glance_initial := Vector2.INF


func _ready() -> void:
	add_child(SwitchPanelBridgeScene.new())
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
		if guid == THROTTLE_GUID:
			_throttle_device = device
		for spec: Dictionary in AXIS_ACTIONS:
			if spec["guid"] != guid:
				continue
			_inject(spec["neg"], _motion(device, spec["axis"], -1.0))
			_inject(spec["pos"], _motion(device, spec["axis"], 1.0))
		for spec: Dictionary in BUTTON_ACTIONS:
			if spec["guid"] != guid:
				continue
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


## 0..1 forward thrust from the X52 throttle, 0 when absent or at idle.
func throttle() -> float:
	if _throttle_device == -1:
		return 0.0
	var value := Input.get_joy_axis(_throttle_device, THROTTLE_AXIS as JoyAxis)
	if value >= THROTTLE_IDLE_DEADZONE:
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


## Digital glance direction from the POV hat (arrow keys as the desk-free dev
## fallback), +x = right, +y = down. The Input singleton is process-global, so
## this keeps working no matter which of the four windows has OS focus
## (plan risk #6).
func get_glance() -> Vector2:
	var raw := Input.get_vector("glance_left", "glance_right", "glance_up", "glance_down")
	if _glance_latched:
		if _glance_initial == Vector2.INF:
			_glance_initial = raw
		elif raw != _glance_initial:
			_glance_latched = false
			return raw
		return Vector2.ZERO
	return raw


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
