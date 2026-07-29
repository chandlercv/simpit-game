extends Control
class_name ControlsSetup
## In-game HOTAS remapper, opened with the configure_controls hotkey (see
## InputRouter._toggle_controls_setup). It writes a user profile JSON via
## InputConfig — the same files the file-based loader reads — so binding an
## arbitrary stick needs no code edit and no log-reading.
##
## Flow: pick a connected joystick, then for each control press BIND and either
## wiggle the axis / press the button, or (for an axis) pick an X52 mouse source.
## SAVE writes user://input_profiles/<guid>.json and InputRouter rebinds live.
##
## Reuses tools/InputEcho's capture idea (next JoypadButton/Motion event). Held
## selector buttons (the X55/X52 mode banks, always down) are sampled at BIND
## start and refused, so they can't be captured by accident.

signal closed

## Axis-pair controls: BIND captures a joypad axis (or an X52 mouse source) that
## drives `neg`..`pos`. `group` only organises the list.
const AXIS_TARGETS := [
	{"label": "Pitch", "neg": "pitch_down", "pos": "pitch_up", "group": "ROTATION"},
	{"label": "Yaw", "neg": "yaw_left", "pos": "yaw_right", "group": "ROTATION"},
	{"label": "Roll", "neg": "roll_left", "pos": "roll_right", "group": "ROTATION"},
	{"label": "Strafe L/R", "neg": "strafe_left", "pos": "strafe_right", "group": "TRANSLATION"},
	{"label": "Thrust U/D", "neg": "thrust_down", "pos": "thrust_up", "group": "TRANSLATION"},
	{"label": "Thrust F/B", "neg": "thrust_back", "pos": "thrust_forward", "group": "TRANSLATION"},
	{"label": "Glance X", "neg": "glance_left", "pos": "glance_right", "group": "GLANCE"},
	{"label": "Glance Y", "neg": "glance_up", "pos": "glance_down", "group": "GLANCE"},
]
const BUTTON_TARGETS := [
	{"label": "Approach", "action": "ops_approach", "group": "OPS"},
	{"label": "Cut", "action": "ops_cut", "group": "OPS"},
]
## X52 nub virtual axes offered as explicit picks for an axis row (matches
## InputRouter.HID_SOURCES). The X52 wheel is joypad buttons 32/33 — bind it on
## an OPS row with BIND instead.
const HID_SOURCE_LABELS := {
	"x52_mouse_x": "X52 nub X", "x52_mouse_y": "X52 nub Y",
}
## A motion past this magnitude counts as "the user moved this axis".
const AXIS_CAPTURE_THRESHOLD := 0.6
const MAX_SCAN_BUTTONS := 40

var _device := -1
var _guid := ""
## key "neg|pos" -> {"kind":"joy","axis":int,"reverse":bool}
##                | {"kind":"hid","source":String,"reverse":bool}
var _axis_binds: Dictionary = {}
var _button_binds: Dictionary = {}  # action -> button int
var _throttle: Dictionary = {}      # {} or {"axis":int,"invert":bool}
## The loaded profile's throttle spec, verbatim, so an untouched throttle keeps
## its calibration (idle_deadzone / custom idle-full endpoints / deadzone) on SAVE.
var _throttle_orig: Dictionary = {}
## True once the user re-captures the throttle axis: a fresh bind has no
## calibration, so it writes plain ±1 endpoints instead of preserving _throttle_orig.
var _throttle_rebound := false

## Active BIND capture, or {} when idle.
var _listening: Dictionary = {}     # {"kind":"axis"|"button"|"throttle", "key":..}
var _held_at_start: Dictionary = {} # button indices held when BIND began

var _device_option: OptionButton
var _status: Label
var _rows_box: VBoxContainer
var _value_labels: Dictionary = {}  # row key -> Label


func start() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh_devices()


# --- UI construction -------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.03, 0.05, 0.94)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "CONFIGURE CONTROLS"
	title.add_theme_font_size_override("font_size", 34)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Pick your joystick, then BIND each control: press the button or " \
		+ "wiggle the axis. For an axis you can instead pick an X52 mouse source. " \
		+ "REV flips an axis. SAVE writes a profile for this device. Esc closes."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
	vbox.add_child(hint)

	var dev_row := HBoxContainer.new()
	dev_row.add_theme_constant_override("separation", 10)
	vbox.add_child(dev_row)
	var dev_label := Label.new()
	dev_label.text = "Device:"
	dev_row.add_child(dev_label)
	_device_option = OptionButton.new()
	_device_option.focus_mode = Control.FOCUS_NONE
	_device_option.item_selected.connect(_on_device_selected)
	dev_row.add_child(_device_option)
	var rescan := Button.new()
	rescan.text = "Rescan"
	rescan.focus_mode = Control.FOCUS_NONE
	rescan.pressed.connect(_refresh_devices)
	dev_row.add_child(rescan)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	vbox.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows_box)

	_build_rows()

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	vbox.add_child(actions)
	var save := Button.new()
	save.text = "SAVE"
	save.custom_minimum_size = Vector2(160, 48)
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(_save)
	actions.add_child(save)
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.custom_minimum_size = Vector2(160, 48)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func() -> void: closed.emit())
	actions.add_child(close_btn)


func _build_rows() -> void:
	var last_group := ""
	for target: Dictionary in AXIS_TARGETS:
		last_group = _maybe_group_header(target["group"], last_group)
		_add_axis_row(target)
	# Throttle sits with translation semantically but is its own binding kind.
	_maybe_group_header("THROTTLE", "")
	_add_throttle_row()
	last_group = ""
	for target: Dictionary in BUTTON_TARGETS:
		last_group = _maybe_group_header(target["group"], last_group)
		_add_button_row(target)


func _maybe_group_header(group: String, last_group: String) -> String:
	if group == last_group:
		return last_group
	var header := Label.new()
	header.text = group
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	_rows_box.add_child(header)
	return group


func _row_container(name_text: String, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_rows_box.add_child(row)
	var name_label := Label.new()
	name_label.text = name_text
	name_label.custom_minimum_size = Vector2(130, 0)
	row.add_child(name_label)
	var value := Label.new()
	value.custom_minimum_size = Vector2(150, 0)
	value.add_theme_color_override("font_color", Color(0.6, 0.95, 0.7))
	row.add_child(value)
	_value_labels[key] = value
	return row


func _add_axis_row(target: Dictionary) -> void:
	var key: String = "%s|%s" % [target["neg"], target["pos"]]
	var row := _row_container(target["label"], key)
	var bind := Button.new()
	bind.text = "BIND"
	bind.focus_mode = Control.FOCUS_NONE
	bind.pressed.connect(_begin_listen.bind({"kind": "axis", "key": key}))
	row.add_child(bind)
	var rev := Button.new()
	rev.text = "REV"
	rev.focus_mode = Control.FOCUS_NONE
	rev.pressed.connect(_toggle_reverse.bind(key))
	row.add_child(rev)
	for source: String in HID_SOURCE_LABELS:
		var hid_btn := Button.new()
		hid_btn.text = HID_SOURCE_LABELS[source]
		hid_btn.focus_mode = Control.FOCUS_NONE
		hid_btn.pressed.connect(_bind_hid.bind(key, source))
		row.add_child(hid_btn)


func _add_button_row(target: Dictionary) -> void:
	var key: String = "btn:%s" % target["action"]
	var row := _row_container(target["label"], key)
	var bind := Button.new()
	bind.text = "BIND"
	bind.focus_mode = Control.FOCUS_NONE
	bind.pressed.connect(_begin_listen.bind({"kind": "button", "key": target["action"]}))
	row.add_child(bind)


func _add_throttle_row() -> void:
	var row := _row_container("Throttle", "throttle")
	var bind := Button.new()
	bind.text = "BIND"
	bind.focus_mode = Control.FOCUS_NONE
	bind.pressed.connect(_begin_listen.bind({"kind": "throttle", "key": "throttle"}))
	row.add_child(bind)
	var inv := Button.new()
	inv.text = "INVERT"
	inv.focus_mode = Control.FOCUS_NONE
	inv.pressed.connect(_toggle_throttle_invert)
	row.add_child(inv)


# --- Device handling -------------------------------------------------------

func _refresh_devices() -> void:
	_device_option.clear()
	var pads := Input.get_connected_joypads()
	for device in pads:
		_device_option.add_item("%d: %s" % [device, Input.get_joy_name(device)], device)
	if pads.is_empty():
		_status.text = "No joystick connected. Plug one in and press Rescan."
		_device = -1
		_guid = ""
		_load_working_from_profile()
		return
	_device = pads[0]
	_device_option.select(0)
	_on_device_selected(0)


func _on_device_selected(index: int) -> void:
	_device = _device_option.get_item_id(index)
	_guid = Input.get_joy_guid(_device)
	_listening = {}
	_status.text = "Editing: %s" % Input.get_joy_name(_device)
	_load_working_from_profile()


## Seed the working binds from this device's current effective profile so the
## screen shows what's already mapped and SAVE preserves untouched controls.
func _load_working_from_profile() -> void:
	_axis_binds.clear()
	_button_binds.clear()
	_throttle.clear()
	var profile := InputRouter.profile_for_guid(_guid) if not _guid.is_empty() else {}
	for spec: Dictionary in profile.get("axes", []):
		var key: String = "%s|%s" % [spec.get("neg", ""), spec.get("pos", "")]
		_axis_binds[key] = {"kind": "joy", "axis": int(spec.get("axis", 0)), "reverse": false}
	for spec: Dictionary in profile.get("hid_axes", []):
		var key: String = "%s|%s" % [spec.get("neg", ""), spec.get("pos", "")]
		_axis_binds[key] = {"kind": "hid", "source": String(spec.get("source", "")), "reverse": false}
	for spec: Dictionary in profile.get("buttons", []):
		_button_binds[String(spec.get("action", ""))] = int(spec.get("button", 0))
	_throttle_orig = {}
	_throttle_rebound = false
	if profile.has("throttle"):
		var t: Dictionary = profile["throttle"]
		_throttle_orig = t.duplicate(true)
		# Legacy idle_deadzone form is idle=+1/full=-1 (not inverted).
		var inv := float(t.get("idle", 1.0)) < float(t.get("full", -1.0))
		_throttle = {"axis": int(t.get("axis", 0)), "invert": inv}
	_refresh_values()


# --- Binding actions -------------------------------------------------------

func _begin_listen(what: Dictionary) -> void:
	if _device == -1:
		_status.text = "Pick a device first."
		return
	_listening = what
	_held_at_start = {}
	if what["kind"] == "button":
		# Sample always-held selector buttons now so we can refuse them.
		for b in MAX_SCAN_BUTTONS:
			if Input.is_joy_button_pressed(_device, b as JoyButton):
				_held_at_start[b] = true
		_status.text = "Press the button for this control…"
	else:
		_status.text = "Move the axis for this control…"


func _toggle_reverse(key: String) -> void:
	if _axis_binds.has(key):
		_axis_binds[key]["reverse"] = not _axis_binds[key].get("reverse", false)
		_refresh_values()


func _bind_hid(key: String, source: String) -> void:
	_axis_binds[key] = {"kind": "hid", "source": source, "reverse": false}
	_listening = {}
	_refresh_values()


func _toggle_throttle_invert() -> void:
	if _throttle.has("axis"):
		_throttle["invert"] = not _throttle.get("invert", false)
		_refresh_values()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()
		return
	if _listening.is_empty():
		return
	if event is InputEventJoypadButton and event.device == _device and event.pressed:
		if _listening["kind"] != "button":
			return
		if _held_at_start.has(event.button_index):
			_status.text = "Button %d is a held selector — pick another." % event.button_index
			return
		_button_binds[_listening["key"]] = int(event.button_index)
		_finish_listen()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion and event.device == _device:
		if _listening["kind"] == "button":
			return
		if absf(event.axis_value) < AXIS_CAPTURE_THRESHOLD:
			return
		var axis := int(event.axis)
		if _listening["kind"] == "throttle":
			_throttle = {"axis": axis, "invert": event.axis_value < 0.0}
			_throttle_rebound = true
		else:
			# Push toward +axis maps to `pos`; if the user pushed negative to
			# reach the threshold, pre-reverse so the felt direction matches.
			_axis_binds[_listening["key"]] = {
				"kind": "joy", "axis": axis, "reverse": event.axis_value < 0.0}
		_finish_listen()
		get_viewport().set_input_as_handled()


func _finish_listen() -> void:
	_listening = {}
	_status.text = "Bound. Continue, or SAVE."
	_refresh_values()


# --- Display + save --------------------------------------------------------

func _refresh_values() -> void:
	for target: Dictionary in AXIS_TARGETS:
		var key: String = "%s|%s" % [target["neg"], target["pos"]]
		_value_labels[key].text = _axis_text(_axis_binds.get(key, {}))
	for target: Dictionary in BUTTON_TARGETS:
		var action: String = target["action"]
		var text := "Button %d" % _button_binds[action] if _button_binds.has(action) else "—"
		_value_labels["btn:%s" % action].text = text
	_value_labels["throttle"].text = _throttle_text()


func _axis_text(bind: Dictionary) -> String:
	if bind.is_empty():
		return "—"
	var suffix := "  (rev)" if bind.get("reverse", false) else ""
	if bind.get("kind", "") == "hid":
		return HID_SOURCE_LABELS.get(bind.get("source", ""), bind.get("source", "")) + suffix
	return "Axis %d%s" % [bind.get("axis", 0), suffix]


func _throttle_text() -> String:
	if not _throttle.has("axis"):
		return "—"
	return "Axis %d%s" % [_throttle["axis"], "  (inv)" if _throttle.get("invert", false) else ""]


## Assemble the working binds into the profile schema and persist. InputConfig
## emits profiles_changed, which InputRouter binds live.
func _save() -> void:
	if _guid.is_empty():
		_status.text = "No device to save."
		return
	var axes: Array = []
	var hid_axes: Array = []
	for key: String in _axis_binds:
		var bind: Dictionary = _axis_binds[key]
		var pair := key.split("|")
		var neg := pair[0]
		var pos := pair[1]
		if bind.get("reverse", false):
			var tmp := neg
			neg = pos
			pos = tmp
		if bind.get("kind", "") == "hid":
			hid_axes.append({"source": bind["source"], "neg": neg, "pos": pos})
		else:
			axes.append({"axis": bind["axis"], "neg": neg, "pos": pos})
	var buttons: Array = []
	for action: String in _button_binds:
		buttons.append({"button": _button_binds[action], "action": action})
	var profile := {
		"name": Input.get_joy_name(_device),
		"guid": _guid,
		"axes": axes,
		"buttons": buttons,
		"hid_axes": hid_axes,
		"reserved_buttons": [],
	}
	if _throttle.has("axis"):
		profile["throttle"] = _throttle_spec_out()
	InputConfig.save_profile(profile)
	_status.text = "Saved profile for %s." % Input.get_joy_name(_device)


## Throttle spec to persist. A freshly re-bound throttle (or a device with no
## prior throttle) only knows axis + direction, so it writes plain ±1 endpoints.
## But if the loaded throttle's axis was left alone we preserve its original
## calibration (idle_deadzone / custom idle-full endpoints / deadzone) verbatim,
## flipping it through _invert_throttle_spec() only when INVERT was toggled.
func _throttle_spec_out() -> Dictionary:
	var axis: int = _throttle["axis"]
	var inv: bool = _throttle.get("invert", false)
	if _throttle_rebound or _throttle_orig.is_empty():
		return {"axis": axis, "idle": -1.0 if inv else 1.0, "full": 1.0 if inv else -1.0}
	var orig_inv := float(_throttle_orig.get("idle", 1.0)) < float(_throttle_orig.get("full", -1.0))
	return _invert_throttle_spec(_throttle_orig) if inv != orig_inv else _throttle_orig.duplicate(true)


## Flip a throttle spec's direction while keeping its calibration. The legacy
## idle_deadzone form (idle=+1/full=-1) has no inverted shorthand, so it expands
## to the general {idle,full,deadzone} form — deadzone (1-d)/2 is the same
## normalized idle band; the general form just swaps its endpoints.
func _invert_throttle_spec(spec: Dictionary) -> Dictionary:
	var out := {"axis": int(spec.get("axis", 0))}
	if spec.has("idle_deadzone"):
		out["idle"] = -1.0
		out["full"] = 1.0
		out["deadzone"] = (1.0 - float(spec["idle_deadzone"])) / 2.0
	else:
		out["idle"] = float(spec.get("full", -1.0))
		out["full"] = float(spec.get("idle", 1.0))
		if spec.has("deadzone"):
			out["deadzone"] = float(spec["deadzone"])
	return out
