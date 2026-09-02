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
## Fraction of a lever's travel that counts as idle when its profile names no
## `deadzone` of its own — the general {idle, full} form's default, and the same
## 5% the shipped X52 profile's raw threshold works out to. It was 0.02, which on
## a ±1 lever puts the idle edge at raw 0.96: TIGHTER than the legacy X52 form it
## was meant to generalize, so a throttle re-bound in the remapper came back with
## less idle margin than the shipped default it replaced. A lever's mechanical
## rest wanders by more than 2% between units and over a stick's life.
const IDLE_DEADZONE := 0.05

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
		# Idle band widened from 0.95 to 0.90 (5% of the lever's raw travel).
		# Measured with InputEcho, the X52 this was written on rests at +0.9524 —
		# 0.0024 clear of the old threshold, close enough that where the lever
		# happened to settle decided whether it commanded anything at all. 0.90
		# leaves 0.05 of margin, room for the spread between units and for wear,
		# and costs only the bottom 5% of travel. See _throttle_curve for what
		# the band edge means and why crossing it is now continuous.
		"throttle": {"axis": 2, "idle_deadzone": 0.90},
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
	## the remapper shows it, a user keyboard.json overrides it key for key, and
	## clearing every key in the remapper persists an empty override. That override
	## is PER KEY, not wholesale: an action the file was never offered keeps its
	## default from here (see _merge_keyboard).
	##
	## THE LAYOUT IS A SHAPE, NOT A PILE. Keys are reserved in contiguous blocks by
	## function, so a pilot learns regions rather than 40 individual keys, and so a
	## new action has an obvious home instead of landing on whatever was free:
	##
	##   NUMBER ROW ...... the systems panel, read left to right: the four power
	##                     channels as -/+ pairs, then the two masters, then the
	##                     drive selector. Everything you SET UP, in one row.
	##   LEFT HAND ....... flight. WASD translates, R/F is vertical, Q/E rolls,
	##                     and SPACE (thumb) holds the drive boost.
	##   RIGHT HAND ...... attitude on IJKL, glance on the arrows.
	##   BOTTOM LEFT ..... the ops verbs, under the flight hand: Z X C V B.
	##   BOTTOM RIGHT .... selection, under the attitude hand: N M , .
	##   T Y G H [ ] ..... displays: tactical mode, the navigation reference,
	##                     the two MFD menus, and the cameras.
	##
	## The camera keeps two keys, not six: ] steps every view and [ jumps straight
	## to BELLY, which is the one the landing procedure requires. REAR/SIDE/CHASE/
	## TOP are reachable by stepping and ship unbound rather than eating the number
	## row that the ship's systems now need. MFD paging, cargo and market also ship
	## unbound — bind any of them in the remapper (F7).
	{
		"name": "Keyboard (default)",
		"guid": "keyboard",
		"keys": [
			# --- Number row: the systems panel -------------------------------------
			# Digital presses nudge a channel by POWER_STEP (see _process_power_axes),
			# so each pair reads as "less / more" of that channel.
			{"key": KEY_1, "action": "power_thrust_lo"},
			{"key": KEY_2, "action": "power_thrust_hi"},
			{"key": KEY_3, "action": "power_cutter_lo"},
			{"key": KEY_4, "action": "power_cutter_hi"},
			{"key": KEY_5, "action": "power_sensors_lo"},
			{"key": KEY_6, "action": "power_sensors_hi"},
			{"key": KEY_7, "action": "power_life_lo"},
			{"key": KEY_8, "action": "power_life_hi"},
			{"key": KEY_9, "action": "master_bat"},
			{"key": KEY_0, "action": "master_alt"},
			{"key": KEY_MINUS, "action": "drive_mode_prev"},
			{"key": KEY_EQUAL, "action": "drive_mode_next"},
			# --- Left hand: flight -------------------------------------------------
			{"key": KEY_W, "action": "thrust_forward"},
			{"key": KEY_S, "action": "thrust_back"},
			{"key": KEY_A, "action": "strafe_left"},
			{"key": KEY_D, "action": "strafe_right"},
			{"key": KEY_R, "action": "thrust_up"},
			{"key": KEY_F, "action": "thrust_down"},
			{"key": KEY_Q, "action": "roll_left"},
			{"key": KEY_E, "action": "roll_right"},
			{"key": KEY_SPACE, "action": "drive_boost"},
			# --- Right hand: attitude and glance -----------------------------------
			{"key": KEY_I, "action": "pitch_up"},
			{"key": KEY_K, "action": "pitch_down"},
			{"key": KEY_J, "action": "yaw_left"},
			{"key": KEY_L, "action": "yaw_right"},
			{"key": KEY_LEFT, "action": "glance_left"},
			{"key": KEY_RIGHT, "action": "glance_right"},
			{"key": KEY_UP, "action": "glance_up"},
			{"key": KEY_DOWN, "action": "glance_down"},
			# --- Bottom left: the ops verbs ----------------------------------------
			{"key": KEY_Z, "action": "dock_request"},
			{"key": KEY_X, "action": "landing_gear"},
			{"key": KEY_C, "action": "ops_cut"},
			{"key": KEY_V, "action": "ops_approach"},
			{"key": KEY_B, "action": "cargo_hatch_open"},
			# --- Bottom right: selection -------------------------------------------
			{"key": KEY_N, "action": "contact_cycle"},
			{"key": KEY_M, "action": "sensor_mode_cycle"},
			{"key": KEY_COMMA, "action": "salvage_prev"},
			{"key": KEY_PERIOD, "action": "salvage_next"},
			# --- Displays ----------------------------------------------------------
			{"key": KEY_T, "action": "tactical_view_cycle"},
			{"key": KEY_Y, "action": "nav_ref_cycle"},
			{"key": KEY_G, "action": "mfd_a_menu"},
			{"key": KEY_H, "action": "mfd_b_menu"},
			{"key": KEY_BRACKETLEFT, "action": "view_belly"},
			{"key": KEY_BRACKETRIGHT, "action": "view_cycle"},
			{"key": KEY_BACKSLASH, "action": "audio_mute"},
		],
	},
]

## GUID of the device-less pseudo-profile above. Not a device: its `keys` are
## injected regardless of which joypads are connected, and a user file under this
## GUID is merged with the built-in rather than replacing it (_merge_keyboard).
const KEYBOARD_GUID := "keyboard"

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
	"view_belly": "BELLY",
}

var _throttle_device := -1
var _throttle_axis := 0
## Full throttle spec of the active profile ({idle_deadzone} or {idle, full});
## throttle() reads it directly so arbitrary throttle ranges rescale correctly.
var _throttle_spec: Dictionary = {}
## True once the engine has actually REPORTED a value for the bound throttle axis.
## Input.get_joy_axis() answers 0.0 for an axis it has never sampled — the value is
## a cached last-known reading, not a live query — and 0.0 on a lever is MID-TRAVEL,
## which every lever form in _throttle_curve maps to HALF OPEN. So a throttle whose
## first sample hasn't landed yet (enumeration racing the first unpaused frame; a
## replug, which clears the cached value) would fly the ship off the wreck with the
## lever shut. Until the sample lands the lever reads idle. _bind_hotas clears it,
## so a rebind re-arms the gate rather than trusting a cache the replug emptied.
var _throttle_seen := false
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
	# The launch title card pauses the tree, and a paused node stops processing —
	# which would take the F7 hotkey (and the remapper's poll-based capture) down
	# with it. Keep running; _process gates the gameplay intents on the pause
	# instead, so nothing leaks into a scenario that hasn't launched.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# ...but the raw-HID bridges must NOT inherit that. SwitchPanelBridge routes a
	# panel toggle straight into GameState (masters, power channels, cargo hatch),
	# so running it while the title card holds the world frozen would let a flicked
	# switch rewrite state behind a scenario that hasn't started. They stay
	# PAUSABLE; on unpause the first report re-syncs every switch anyway, since
	# GameState.panel_switches has no entry yet to compare against.
	_add_hardware_bridge(SwitchPanelBridgeScene.new())
	_glance_bridge = HidGlanceBridgeScene.new()
	_add_hardware_bridge(_glance_bridge)
	_mouse_bridge = X52MouseBridgeScene.new()
	_add_hardware_bridge(_mouse_bridge)
	Input.joy_connection_changed.connect(
			func(_device: int, _connected: bool) -> void: _bind_hotas())
	# A saved/edited user profile rebinds live, same path as a replug.
	InputConfig.profiles_changed.connect(_bind_hotas)
	_bind_hotas()


## Parent a raw-HID bridge, pinning it to the pause state of the world it feeds
## rather than to this router's ALWAYS (see _ready). Their polling is only ever
## consumed by a running scenario — _process bails out while paused, and the
## camera rig reading glance is paused itself — so no one loses a value here.
func _add_hardware_bridge(bridge: Node) -> void:
	bridge.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(bridge)


## Shipped defaults overlaid with the user's JSON profiles: a user entry with the
## same GUID fully REPLACES the built-in (predictable override), a new GUID is
## appended. Matched by GUID in _bind_hotas() just like before.
##
## The keyboard profile is the one exception — it is merged, not replaced (see
## _merge_keyboard). It carries the shipped default LAYOUT rather than one
## device's mapping, and it is the only way to reach an action when no HOTAS is
## plugged in, so a file written before an action existed must not leave that
## action unreachable.
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
		if guid == KEYBOARD_GUID and by_guid.has(guid):
			by_guid[guid] = _merge_keyboard(by_guid[guid], profile)
			continue
		if not by_guid.has(guid):
			order.append(guid)
		by_guid[guid] = profile
	var out: Array = []
	for guid: String in order:
		out.append(by_guid[guid])
	return out


## A user keyboard.json still overrides the shipped layout key for key — clearing
## a key in the remapper has to stick, and ControlsSetup keeps a profile alive
## with an empty `keys` array precisely so that clearing every key persists.
##
## What it must NOT do is silently drop an action that did not exist when the file
## was written. A profile saved before the masters and the drive selector arrived
## leaves a keyboard pilot with no way to switch the bus back on or start the
## drive, and the AFTER LANDING checklist calls for all three OFF — so the trap is
## sprung by flying the procedure correctly, and nothing on any display says why.
##
## So a shipped default is re-added only when all three hold:
##   * the file's `known_actions` does not list it — the remapper writes every row
##     it offered, so an action missing from that list is one the pilot was never
##     given the chance to bind, not one they cleared;
##   * the file does not already bind the action; and
##   * the default's key is still free — a default whose key the pilot reassigned
##     is left out rather than double-bound to two actions.
##
## A file predating `known_actions` is treated as having been offered nothing,
## which is what repairs the profiles already on disk. The cost is one-time and
## visible: a key cleared before that field existed comes back once, until the
## next SAVE writes the field. A softlock nobody can diagnose is the worse half of
## that trade.
func _merge_keyboard(builtin: Dictionary, user: Dictionary) -> Dictionary:
	var merged := user.duplicate(true)
	var keys: Array = merged.get("keys", [])
	var offered: Dictionary = {}
	for action: Variant in user.get("known_actions", []):
		offered[String(action)] = true
	var bound: Dictionary = {}
	var taken: Dictionary = {}
	for spec: Dictionary in keys:
		bound[String(spec["action"])] = true
		taken[int(spec["key"])] = true
	for spec: Dictionary in builtin.get("keys", []):
		var action := String(spec["action"])
		if offered.has(action) or bound.has(action):
			continue
		var key := int(spec["key"])
		if taken.has(key):
			push_warning(("InputRouter: %s has no binding and its default key is " +
					"already in use; bind it in the remapper (F7)") % action)
			continue
		keys.append({"key": key, "action": action})
		taken[key] = true
	merged["keys"] = keys
	return merged


## The effective (built-in + user override) profile for a GUID, or {} if none.
## Deep-copied so the remapper can edit a working copy freely.
func profile_for_guid(guid: String) -> Dictionary:
	for profile: Dictionary in _effective_profiles():
		if String(profile.get("guid", "")) == guid:
			return profile.duplicate(true)
	return {}


## The live throttle binding as {device, axis, spec}, or {} when no connected
## profile carries one. The throttle is read straight off its axis (an idle..full
## range can't be an action), so it's invisible to the Input Map — a surface that
## reports what's bound has to ask here (see scenes/ui/BindingLabel.gd).
func throttle_binding() -> Dictionary:
	if _throttle_device < 0 or _throttle_spec.is_empty():
		return {}
	return {
		"device": _throttle_device,
		"axis": _throttle_axis,
		"spec": _throttle_spec.duplicate(true),
	}


## True when the fitted throttle is a SELF-CENTRING axis (a gamepad stick or
## trigger) rather than an absolute lever that stays where it is put.
##
## The two shapes want opposite throttle command laws and ShipMotion picks its
## default from this — see ShipMotion.ThrottleCmdMode for why they cannot share
## one. Nothing bound reads idle as centring: an absent throttle is a lever's
## problem, not a stick's, and the lever law is the safer default.
func throttle_is_centering() -> bool:
	return String(_throttle_spec.get("mode", "")) == "gamepad"


## The active raw-HID axis bindings (the X52 nub), which are composited in
## _process rather than injected into the Input Map — so, like the throttle,
## they're invisible to anything reading bindings back from it.
func hid_axis_bindings() -> Array:
	return _hid_axis_bindings.duplicate(true)


## Open/close the in-game remapper overlay (the F7 hotkey).
func _toggle_controls_setup() -> void:
	if is_instance_valid(_controls_ui):
		_close_controls_setup()
		return
	open_controls_setup()


## Raise the remapper overlay on our own CanvasLayer (kept separate from
## WindowManager's display-setup overlay so neither tears down the other, and
## above both it and the title card so it draws over whichever is up). Idempotent,
## so the title card's CONTROLS button can't stack a second copy on the hotkey's.
func open_controls_setup() -> void:
	if is_instance_valid(_controls_ui):
		return
	_controls_layer = CanvasLayer.new()
	_controls_layer.layer = 25
	# ALWAYS so the remapper's capture polling and its buttons keep working while
	# the title card holds the tree paused.
	_controls_layer.process_mode = Node.PROCESS_MODE_ALWAYS
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


## Throttle lines already written, so a rebind that resolves to the same binding
## stays silent. Windows fires joy_connection_changed once PER DEVICE, and every
## one of them re-runs _bind_hotas — four sticks on this rig meant the same line
## five times before the log had a single frame of flight in it.
var _throttle_noted: Array[String] = []


func _note_throttle(line: String) -> void:
	if _throttle_noted.has(line):
		return
	_throttle_noted.append(line)
	WindowLog.note("input", line)


## Re-resolve GUID -> device index and rebuild the injected Input Map events.
func _bind_hotas() -> void:
	for action: String in _bound:
		for event: InputEvent in _bound[action]:
			if InputMap.action_has_event(action, event):
				InputMap.action_erase_event(action, event)
	_bound = {}
	_throttle_device = -1
	_throttle_spec = {}
	_throttle_seen = false
	_hid_axis_bindings = []
	var profiles := _effective_profiles()
	for device in Input.get_connected_joypads():
		var guid := Input.get_joy_guid(device)
		for profile: Dictionary in profiles:
			if profile["guid"] != guid:
				continue
			if profile.has("throttle"):
				# FIRST match wins, not last: enumeration order is the OS's
				# business, and a second stick whose profile happens to carry a
				# throttle must not silently take the lever off the one you fly.
				if _throttle_device == -1:
					_throttle_device = device
					_throttle_spec = profile["throttle"]
					_throttle_axis = int(_throttle_spec["axis"])
					_note_throttle("throttle bound: %s axis %d (device %d)"
							% [profile.get("name", "?"), _throttle_axis, device])
				else:
					_note_throttle("throttle already bound — ignoring %s"
							% profile.get("name", "?"))
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
		if String(profile.get("guid", "")) != KEYBOARD_GUID:
			continue
		for spec: Dictionary in profile.get("keys", []):
			var event := InputEventKey.new()
			event.physical_keycode = int(spec["key"]) as Key
			_inject(String(spec["action"]), event)
	# Only open the X52 mouse HID (which may enumerate as an OS-owned mouse) when
	# a profile actually binds it.
	if _mouse_bridge:
		_mouse_bridge.set_active(not _hid_axis_bindings.is_empty())
	# A profile load is the only moment the FITTED THROTTLE can change shape, and
	# the throttle's shape decides which command law suits it. Tell the motion
	# pipeline now rather than having it poll — it honours a pilot who has already
	# chosen (ShipMotion.sync_throttle_law).
	ShipMotion.sync_throttle_law()


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


## -1..1 forward/back command from the throttle profile's axis, 0 when absent,
## at rest, or not yet sampled (see _throttle_seen — an unsampled lever reads
## idle, NOT the half-open its raw 0.0 would otherwise curve to).
func throttle() -> float:
	if _throttle_device == -1:
		return 0.0
	var value := Input.get_joy_axis(_throttle_device, _throttle_axis as JoyAxis)
	if not _throttle_seen:
		# Belt and braces behind the _input latch below: a non-zero reading is
		# proof of a real sample too. A gate that ONLY an event could open would
		# make a dead throttle out of any case where those don't reach us; this
		# one can't. The cost is a lever parked at EXACTLY raw 0.0 (mid-travel)
		# reading idle until it next moves — the safe direction, and it self-heals
		# on the first nudge.
		if is_zero_approx(value):
			return 0.0
		_throttle_seen = true
	return _throttle_curve(value, _throttle_spec)


## The throttle's first real sample. Godot emits a motion event the first time it
## reads an axis (its cache holds no prior value to compare against), so this
## fires even for a lever that has sat untouched since boot — which polling for a
## non-zero reading cannot tell from a lever parked at mid-travel.
func _input(event: InputEvent) -> void:
	if _throttle_seen or _throttle_device == -1:
		return
	var motion := event as InputEventJoypadMotion
	if motion and motion.device == _throttle_device and int(motion.axis) == _throttle_axis:
		_throttle_seen = true


## Pure raw-axis -> command mapping for one throttle spec. Split out of throttle()
## so ThrottleIdleSmoke can drive every form headless, where no stick is attached.
## Three spec forms:
##   {mode:"gamepad"}  bipolar, center-rest (a self-centering stick/trigger axis
##                     rather than a lever): 0 inside `deadzone` (default 0.05),
##                     ±1 at the stops; `invert` flips sign. The ship-wide
##                     reverse cap (SalvageSystem, secondary_thrust_fraction)
##                     does the asymmetric forward/reverse scaling, not this curve.
##   {idle_deadzone}   legacy X52 lever (full=-1; the raw threshold is the idle edge)
##   {idle, full}      general lever — any rest/travel range and direction, with
##                     an optional normalized `deadzone` (default 0.05) near idle.
##
## Every form RESCALES the travel past its idle band rather than clipping to it.
## Clipping leaves the smallest commandable throttle equal to the band itself —
## a floor, not a null — with nothing available between that and zero. On the
## legacy form that floor was (1 - 0.95) / 2 = 2.5%, about 0.9 m/s of permanent
## creep: invisible at cruise, and the difference between holding a marker and
## sliding through it in a 3 m/s docking hold. It sat just under ShipMotion's
## CMD_DEADBAND (0.032), so the fly-by-wire went on nulling the axis it was
## pushing — the two fought to a slow crawl instead of an obvious runaway, which
## is why this read as "the throttle won't zero" rather than as a stuck lever.
## Measured with InputEcho, this rig's X52 rests at +0.9524 against its 0.95
## threshold: a margin of 0.0024 on a 2.0 range, so which side of the step it
## settled on was very nearly a coin toss.
##
## NOTE mid-travel still curves to roughly HALF OPEN, which is why throttle()
## gates on a real sample before calling this at all — an axis the engine has
## never reported reads a cached raw 0.0.
static func _throttle_curve(value: float, spec: Dictionary) -> float:
	if String(spec.get("mode", "")) == "gamepad":
		var v := clampf(value, -1.0, 1.0)
		if spec.get("invert", false):
			v = -v
		var pad_dead := float(spec.get("deadzone", 0.05))
		return signf(v) * clampf((absf(v) - pad_dead) / maxf(1.0 - pad_dead, 0.0001), 0.0, 1.0)
	if spec.has("idle_deadzone"):
		# The idle threshold IS the zero point; the travel below it becomes the
		# whole 0..1 command. (Legacy form: full is -1 by definition.)
		var stop := float(spec["idle_deadzone"])
		return clampf((stop - value) / maxf(stop + 1.0, 0.0001), 0.0, 1.0)
	var idle := float(spec.get("idle", 1.0))
	var full := float(spec.get("full", -1.0))
	var span := idle - full
	if is_zero_approx(span):
		return 0.0
	var dead := float(spec.get("deadzone", IDLE_DEADZONE))
	var norm := (idle - value) / span
	return clampf((norm - dead) / maxf(1.0 - dead, 0.0001), 0.0, 1.0)


func _process(_delta: float) -> void:
	# Polled (not _unhandled_input) so the hotkey fires regardless of which window
	# has OS focus — same rationale as WindowManager's F5/F6 (see get_glance).
	if DisplayServer.get_name() != "headless" and Input.is_action_just_pressed("configure_controls"):
		_toggle_controls_setup()
	# Paused means the launch title card is up and the scenario hasn't started:
	# the remapper hotkey above still works (that's half of what the card offers),
	# but no flight or ops intent may reach a world that isn't running yet.
	if get_tree().paused:
		# Hands off — and clear anything latched BEFORE the card came up. This
		# ran once on the boot frame, ahead of WindowManager's deferred _setup()
		# pausing the tree, so a command read there would otherwise sit in
		# ShipMotion across the whole card and be spent by the first physics tick
		# after LAUNCH (physics runs ahead of idle within a frame). Zeroing is the
		# opposite of the intent leak guarded against above, and it goes straight
		# to ShipMotion rather than through SalvageSystem.set_manual_flight, so it
		# cannot trip the autopilot's manual-override disengage.
		ShipMotion.set_command(Vector3.ZERO, Vector3.ZERO)
		return
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
	# While the pre-cut alignment mini-game is live, pitch/yaw aim the cutting head
	# instead of flying the ship. Route them to the crosshair and zero those two
	# components before set_manual_flight, so aiming doesn't trip the manual-override
	# that disengages the match (strafe/throttle/roll still bail out as usual).
	# Negate both so the reticle tracks the ship's nose, not against it: yaw-right
	# moves the aim screen-right, pitch-up moves it screen-up — matching how the same
	# stick deflection swings the nose in normal flight. (rot.y is +yaw-left, rot.x is
	# +pitch-up; the reticle's +x is screen-right and +y is screen-down.)
	if GameState.align_state == "ALIGNING":
		SalvageSystem.set_align_input(Vector2(-rot.y, -rot.x))
		rot.x = 0.0
		rot.y = 0.0
	SalvageSystem.set_manual_flight(thrust, rot)
	if Input.is_action_just_pressed("ops_approach"):
		SalvageSystem.toggle_approach()
	if Input.is_action_just_pressed("ops_cut"):
		SalvageSystem.request_cut()
	if Input.is_action_just_pressed("cargo_hatch_open"):
		GameState.toggle_cargo_hatch()
	if Input.is_action_just_pressed("landing_gear"):
		GameState.toggle_landing_gear()
	if Input.is_action_just_pressed("dock_request"):
		DockingSystem.request_clearance()
	if Input.is_action_just_pressed("throttle_cmd_toggle"):
		SalvageSystem.toggle_throttle_cmd_mode()
	if Input.is_action_just_pressed("fbw_mode_cycle"):
		ShipMotion.toggle_fbw()
	# The drive boost is HELD, not toggled: it burns both tanks fast enough that a
	# latch would empty the LOX on a press you forgot about. Asserted every frame
	# so releasing the key (or the panel losing the button) drops it.
	GameState.set_drive_boost(Input.is_action_pressed("drive_boost"))
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

	# Electrical masters and the drive selector — the panel equivalents of the
	# Saitek MASTER BAT / MASTER ALT toggles and the five-position magneto, so a
	# pilot without the switch panel can still run the departure and arrival
	# procedures (both of which require all three).
	if Input.is_action_just_pressed("master_bat"):
		GameState.set_master_battery(not GameState.master_bat)
	if Input.is_action_just_pressed("master_alt"):
		GameState.set_master_alt(not GameState.master_alt)
	if Input.is_action_just_pressed("drive_mode_next"):
		GameState.step_drive_mode(1)
	if Input.is_action_just_pressed("drive_mode_prev"):
		GameState.step_drive_mode(-1)

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

	# Navigation reference — the datum the Tactical band's altitude, heading,
	# range and attitude are all measured against (see NavReference). PAD and
	# TARGET are direct selects for the two that matter under workload.
	if Input.is_action_just_pressed("nav_ref_cycle"):
		GameState.cycle_nav_reference()
	if Input.is_action_just_pressed("nav_ref_pad"):
		GameState.set_nav_reference("PAD")
	if Input.is_action_just_pressed("nav_ref_target"):
		GameState.set_nav_reference("TARGET")
	if Input.is_action_just_pressed("tactical_band_toggle"):
		GameState.toggle_tactical_band()
	if Input.is_action_just_pressed("audio_mute"):
		AudioSystem.toggle_mute()

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
