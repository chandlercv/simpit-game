extends RefCounted
## Human-readable names for whatever a control is CURRENTLY bound to, so a
## surface can print "press this" instead of hardcoding a key that the remapper
## may have changed (see PilotManual, which prints one per checklist step).
##
## The Input Map is the source of truth: InputRouter._bind_hotas() injects every
## effective binding — built-in profiles overlaid with the user's JSON — into it,
## so reading it back gives the live mapping without re-parsing any profile, and
## it re-reads correctly after an F7 save (which rebinds through the same path).
##
## Three things never reach the Input Map and are resolved separately:
##  - the THROTTLE, read directly off its axis because an idle..full range can't
##    be expressed as an action (InputRouter.throttle_binding);
##  - raw-HID virtual axes like the X52 nub, composited in InputRouter._process
##    (InputRouter.hid_axis_bindings);
##  - the SWITCH PANEL, which isn't an input device at all — SwitchPanelBridge
##    calls GameState intents by switch name, so its legends are static (for_switch).

## What a control with no binding at all prints as. One constant so a surface can
## test for it rather than string-matching prose.
const UNBOUND := "NOT ASSIGNED"

## Switch-panel legend per GameState intent the panel routes to
## (SwitchPanelBridge._route_intent). Power channels are derived from
## GameState.CHANNEL_SWITCHES instead — see for_switch — so the thematic pairing
## stays defined in exactly one place.
const SWITCH_LEGENDS := {
	"MASTER_BAT": "MASTER BAT",
	"MASTER_ALT": "MASTER ALT",
	"COWL": "COWL",
	"GEAR_DOWN": "GEAR DOWN",
	"GEAR_UP": "GEAR UP",
}


## Every live binding for `action`, joined for display — e.g.
## "Button 0 · X-55 Rhino Stick / C". Returns UNBOUND when nothing drives it.
##
## Joypad entries name their device, since a HOTAS split across a stick and a
## throttle makes "button 7" ambiguous on its own; keyboard entries are bare.
static func for_action(action: String) -> String:
	if not InputMap.has_action(action):
		return UNBOUND
	var parts: PackedStringArray = []
	for event: InputEvent in InputMap.action_get_events(action):
		var text := _event_text(event)
		if not text.is_empty() and not parts.has(text):
			parts.append(text)
	if parts.is_empty():
		return UNBOUND
	return " / ".join(parts)


## The two actions of a direction pair as one label — "A / D", or the single axis
## driving both. An analog axis binds to BOTH actions of the pair (one event per
## direction), so naming it once is the honest reading; per-direction keys and
## buttons are listed neg-then-pos.
static func for_axis(neg: String, pos: String) -> String:
	var shared := _shared_axis_text(neg, pos)
	if not shared.is_empty():
		return shared
	var hid := _hid_axis_text(neg, pos)
	var neg_text := for_action(neg)
	var pos_text := for_action(pos)
	if neg_text == UNBOUND and pos_text == UNBOUND:
		return hid if not hid.is_empty() else UNBOUND
	var pair := "%s / %s" % [neg_text, pos_text]
	return "%s / %s" % [pair, hid] if not hid.is_empty() else pair


## The throttle lever, which is read off its axis rather than through an action.
static func for_throttle() -> String:
	var spec: Dictionary = InputRouter.throttle_binding()
	if spec.is_empty():
		return UNBOUND
	return "Axis %d · %s" % [int(spec.get("axis", 0)),
			_device_name(int(spec.get("device", -1)))]


## The switch-panel legend that drives `channel`'s power, per
## GameState.CHANNEL_SWITCHES — "DE-ICE" for CUTTER, etc. Empty if no switch does.
static func for_power_switch(channel: String) -> String:
	for switch_name: String in GameState.CHANNEL_SWITCHES:
		if GameState.CHANNEL_SWITCHES[switch_name] == channel:
			return _legend(switch_name)
	return ""


## A switch-panel legend by switch name, for the switches wired to a non-power
## intent (COWL, the masters, the gear lever).
static func for_switch(switch_name: String) -> String:
	return _legend(switch_name)


# --- internals -------------------------------------------------------------

static func _legend(switch_name: String) -> String:
	if SWITCH_LEGENDS.has(switch_name):
		return SWITCH_LEGENDS[switch_name]
	# The channel switches carry no entry of their own: their names ARE their
	# legends once the underscore is a space (FUEL_PUMP -> FUEL PUMP), except
	# DE_ICE, which the panel silkscreens hyphenated.
	if switch_name == "DE_ICE":
		return "DE-ICE"
	return switch_name.replace("_", " ")


## The axis text shared by BOTH directions of a pair, or "" when they aren't
## driven by one analog axis. An InputEventJoypadMotion is injected once per
## direction with opposite axis_value, so the pair is "one axis" exactly when the
## same device+axis appears on each side.
static func _shared_axis_text(neg: String, pos: String) -> String:
	if not (InputMap.has_action(neg) and InputMap.has_action(pos)):
		return ""
	for event: InputEvent in InputMap.action_get_events(neg):
		if not event is InputEventJoypadMotion:
			continue
		for other: InputEvent in InputMap.action_get_events(pos):
			if other is InputEventJoypadMotion \
					and other.device == event.device and other.axis == event.axis:
				return _event_text(event)
	return ""


## Raw-HID virtual axes bound to this pair (the X52 nub), which are composited
## outside the Input Map. Order-insensitive, matching InputRouter._hid_axis_amount.
static func _hid_axis_text(neg: String, pos: String) -> String:
	var parts: PackedStringArray = []
	for spec: Dictionary in InputRouter.hid_axis_bindings():
		var s_neg := String(spec.get("neg", ""))
		var s_pos := String(spec.get("pos", ""))
		if (s_neg == neg and s_pos == pos) or (s_neg == pos and s_pos == neg):
			var text := _hid_source_name(String(spec.get("source", "")))
			if not parts.has(text):
				parts.append(text)
	return " / ".join(parts)


static func _hid_source_name(source: String) -> String:
	match source:
		"x52_mouse_x": return "X52 nub X"
		"x52_mouse_y": return "X52 nub Y"
	return source


static func _event_text(event: InputEvent) -> String:
	if event is InputEventKey:
		return _key_name(int(event.physical_keycode))
	if event is InputEventJoypadButton:
		return "Button %d · %s" % [int(event.button_index), _device_name(event.device)]
	if event is InputEventJoypadMotion:
		return "Axis %d · %s" % [int(event.axis), _device_name(event.device)]
	return ""


static func _key_name(keycode: int) -> String:
	var name := OS.get_keycode_string(keycode as Key)
	return name if not name.is_empty() else "Key%d" % keycode


## A connected joypad's name, trimmed to the part that identifies it. OS joystick
## names carry a lot of boilerplate ("Madcatz Saitek Pro Flight X-55 Rhino Stick",
## "Saitek X52 Flight Control System") and a checklist step that names two devices
## runs off the line, so the vendor prefix and the generic suffix both come off —
## leaving "X-55 Rhino Stick" and "X52". Falls back to the device index for a
## stick that has since been unplugged (its injected events outlive the
## connection).
static func _device_name(device: int) -> String:
	if device < 0 or not Input.get_connected_joypads().has(device):
		return "device %d" % device
	var name := Input.get_joy_name(device)
	for prefix in ["Madcatz Saitek Pro Flight ", "Saitek Pro Flight ", "Madcatz ", "Saitek "]:
		if name.begins_with(prefix):
			name = name.substr(prefix.length())
			break
	for suffix in [" Flight Control System", " Flight Controller", " Controller", " Joystick"]:
		if name.ends_with(suffix):
			name = name.substr(0, name.length() - suffix.length())
			break
	return name
