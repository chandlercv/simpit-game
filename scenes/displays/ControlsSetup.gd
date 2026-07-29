extends Control
class_name ControlsSetup
## In-game HOTAS remapper, opened with the configure_controls hotkey (see
## InputRouter._toggle_controls_setup). It writes user profile JSON via
## InputConfig — the same files the file-based loader reads — so binding an
## arbitrary stick needs no code edit and no log-reading.
##
## Flow: press BIND on a control, then move the axis / press the button on ANY
## connected device — capture auto-detects which physical device+axis+button it
## was, so a HOTAS split across a stick and a throttle just works (each device
## saves its own profile). For an axis you can instead pick an X52 nub source.
##
## Capture POLLS the global Input singleton each frame rather than using _input:
## in the multi-window simpit _input/_unhandled_input only fire for the focused
## window's viewport, so joypad events were silently dropped (the "nothing
## happens" bug). Input polling is process-global and focus-independent — the
## same reason InputRouter/WindowManager poll their hotkeys. Held selector
## buttons (X55/X52 mode banks, always down) are sampled at BIND start and
## refused so they can't be captured by accident.

signal closed

## Axis-pair controls: BIND captures a joypad axis (or an X52 nub source) driving
## `neg`..`pos`. `group` only organises the list.
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
## an OPS row with BIND instead. HID picks attach to the X52's profile on SAVE.
const HID_SOURCE_LABELS := {
	"x52_mouse_x": "X52 nub X", "x52_mouse_y": "X52 nub Y",
}
const X52_GUID := "0300ea18a30600005c07000000000000"

## Axis deviation from its BIND-start rest that counts as "the user moved this".
const AXIS_CAPTURE_THRESHOLD := 0.6
const AXIS_SCAN_COUNT := 10
const MAX_SCAN_BUTTONS := 40

## key "neg|pos" -> {"kind":"joy","guid":String,"axis":int,"reverse":bool}
##                | {"kind":"hid","source":String,"reverse":bool}
var _axis_binds: Dictionary = {}
## action -> {"guid":String,"button":int}
var _button_binds: Dictionary = {}
## {} or {"guid":String,"axis":int,"invert":bool}
var _throttle: Dictionary = {}
## The loaded throttle spec, verbatim, so an untouched throttle keeps its
## calibration (idle_deadzone / custom idle-full endpoints / deadzone) on SAVE.
var _throttle_orig: Dictionary = {}
## True once the throttle axis is re-captured: a fresh bind has no calibration,
## so it writes plain ±1 endpoints instead of preserving _throttle_orig.
var _throttle_rebound := false
## guid -> {"name":String, "reserved_buttons":Array} for every connected device,
## so SAVE preserves each device's name + reserved banks.
var _dev_meta: Dictionary = {}
## Set of GUIDs that had a non-empty effective profile at load. SAVE force-writes
## an empty override for any of these left with no binds, so clearing every
## control on a device actually persists instead of leaving its stale file (or
## built-in) to reassert the cleared bindings on reload.
var _loaded_guids: Dictionary = {}
## Bindings shadowed at load: when two connected devices bind the SAME function,
## the working dicts (keyed by function, not device) keep only the last-enumerated
## device's entry. Without these, SAVE would rebuild the losing device's profile
## from that collapsed state and drop its binding for good. Each shadow re-emits
## its device's spec on SAVE — unless the winning entry was since rebound/cleared,
## detected by instance identity against _load_winner_* (capture reassigns the
## entry; REV/INVERT mutate in place, which must NOT evict the other device).
var _shadow_axes: Array = []            # [{"key":String, "value":Dictionary}]
var _shadow_buttons: Array = []         # [{"action":String, "value":Dictionary}]
var _shadow_throttle: Dictionary = {}   # {} or {"guid":String, "spec":Dictionary}
var _load_winner_axis: Dictionary = {}  # shadowed axis key -> load-time winner instance
var _load_winner_button: Dictionary = {}  # shadowed action -> load-time winner instance

## Active BIND capture, or {} when idle.
var _listening: Dictionary = {}       # {"kind":"axis"|"button"|"throttle", "key":..}
var _axis_baseline: Dictionary = {}   # "device:axis" -> float rest sampled at BIND
var _btn_held: Dictionary = {}        # "device:button" -> true, held at BIND start

var _devices_label: Label
var _status: Label
var _rows_box: VBoxContainer
var _value_labels: Dictionary = {}    # row key -> Label


func start() -> void:
	# Parented to a CanvasLayer, not a Control, so anchors alone don't stretch us
	# to the viewport — set offsets too and re-fit on resize, else the backdrop
	# and rows collapse to the top (the game view showed through below them).
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_build_ui()
	_reload()


func _fit_to_viewport() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_viewport().get_visible_rect().size


# --- UI construction -------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.03, 0.05, 0.98)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	hint.text = "Each row is a bindable function. Press a bind button, then work " \
		+ "just that control on any device — it auto-detects which. AXIS binds an " \
		+ "analog axis to a pair; −btn / +btn bind a button to each direction (use " \
		+ "these for a POV hat that reports as buttons, e.g. strafe on the X52 " \
		+ "hat). REV flips an axis; a nub source can be picked instead. A throttle " \
		+ "can rest anywhere; let a spring-loaded stick axis recenter before the " \
		+ "next bind. The X52 wheel is buttons 32/33 — bind it on an OPS row. SAVE " \
		+ "writes a profile per device. Esc or CLOSE exits."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
	vbox.add_child(hint)

	var dev_row := HBoxContainer.new()
	dev_row.add_theme_constant_override("separation", 10)
	vbox.add_child(dev_row)
	_devices_label = Label.new()
	_devices_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dev_row.add_child(_devices_label)
	var rescan := Button.new()
	rescan.text = "Rescan"
	rescan.focus_mode = Control.FOCUS_NONE
	rescan.pressed.connect(_reload)
	dev_row.add_child(rescan)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	vbox.add_child(_status)

	# Rows go straight into the main column: an earlier ScrollContainer here
	# collapsed to zero height and clipped every row invisible. The ~16 rows fit
	# the Main display; re-introduce scrolling only with an explicit height.
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_rows_box)

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
		if target["pos"] == "glance_down":  # last GLANCE row
			_add_note("The X55 POV hat drives glance automatically via raw HID " \
				+ "(off Godot's DPAD to avoid the selector collision) — no binding " \
				+ "needed. Bind Glance here only for other hardware.")
	# Throttle sits with translation semantically but is its own binding kind.
	_maybe_group_header("THROTTLE", "")
	_add_throttle_row()
	last_group = ""
	for target: Dictionary in BUTTON_TARGETS:
		last_group = _maybe_group_header(target["group"], last_group)
		_add_button_row(target)


func _add_note(text: String) -> void:
	var note := Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	_rows_box.add_child(note)


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
	value.custom_minimum_size = Vector2(250, 0)
	value.add_theme_color_override("font_color", Color(0.6, 0.95, 0.7))
	row.add_child(value)
	_value_labels[key] = value
	return row


func _add_axis_row(target: Dictionary) -> void:
	var key: String = "%s|%s" % [target["neg"], target["pos"]]
	var row := _row_container(target["label"], key)
	# A direction pair can be driven by one analog AXIS, or by a BUTTON per
	# direction (a POV hat that reports as buttons — e.g. the X52 throttle hat),
	# or by an X52 nub source. The three are mutually exclusive per pair.
	var bind := Button.new()
	bind.text = "AXIS"
	bind.tooltip_text = "Bind an analog axis to this pair"
	bind.focus_mode = Control.FOCUS_NONE
	bind.pressed.connect(_begin_listen.bind({"kind": "axis", "key": key}))
	row.add_child(bind)
	var neg_btn := Button.new()
	neg_btn.text = "−btn"
	neg_btn.tooltip_text = "Bind a button to %s" % target["neg"]
	neg_btn.focus_mode = Control.FOCUS_NONE
	neg_btn.pressed.connect(_begin_listen.bind({"kind": "button", "key": target["neg"]}))
	row.add_child(neg_btn)
	var pos_btn := Button.new()
	pos_btn.text = "+btn"
	pos_btn.tooltip_text = "Bind a button to %s" % target["pos"]
	pos_btn.focus_mode = Control.FOCUS_NONE
	pos_btn.pressed.connect(_begin_listen.bind({"kind": "button", "key": target["pos"]}))
	row.add_child(pos_btn)
	var rev := Button.new()
	rev.text = "REV"
	rev.focus_mode = Control.FOCUS_NONE
	rev.pressed.connect(_toggle_reverse.bind(key))
	row.add_child(rev)
	var clear := Button.new()
	clear.text = "×"
	clear.focus_mode = Control.FOCUS_NONE
	clear.pressed.connect(_clear_axis.bind(key))
	row.add_child(clear)
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
	var clear := Button.new()
	clear.text = "×"
	clear.focus_mode = Control.FOCUS_NONE
	clear.pressed.connect(_clear_button.bind(target["action"]))
	row.add_child(clear)


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


# --- Load current bindings -------------------------------------------------

func _reload() -> void:
	_listening = {}
	_axis_binds.clear()
	_button_binds.clear()
	_throttle.clear()
	_throttle_orig = {}
	_throttle_rebound = false
	_dev_meta.clear()
	_loaded_guids.clear()
	_shadow_axes.clear()
	_shadow_buttons.clear()
	_shadow_throttle.clear()
	_load_winner_axis.clear()
	_load_winner_button.clear()
	var pads := Input.get_connected_joypads()
	var names: PackedStringArray = []
	for device in pads:
		names.append(Input.get_joy_name(device))
	_devices_label.text = "Connected: " + (", ".join(names) if not names.is_empty()
			else "none — plug in a joystick and press Rescan")
	# Seed the working binds from every connected device's effective profile so
	# the value column shows what is currently mapped and SAVE preserves it.
	for device in pads:
		var guid := Input.get_joy_guid(device)
		var profile := InputRouter.profile_for_guid(guid)
		if not profile.is_empty():
			_loaded_guids[guid] = true
		_dev_meta[guid] = {
			"name": String(profile.get("name", Input.get_joy_name(device))),
			"reserved_buttons": profile.get("reserved_buttons", []),
		}
		for spec: Dictionary in profile.get("axes", []):
			var key: String = "%s|%s" % [spec.get("neg", ""), spec.get("pos", "")]
			_shadow_if_bound(_axis_binds, _shadow_axes, "key", key)
			_axis_binds[key] = {"kind": "joy", "guid": guid, "axis": int(spec.get("axis", 0)), "reverse": false}
		for spec: Dictionary in profile.get("hid_axes", []):
			var key: String = "%s|%s" % [spec.get("neg", ""), spec.get("pos", "")]
			_shadow_if_bound(_axis_binds, _shadow_axes, "key", key)
			_axis_binds[key] = {"kind": "hid", "source": String(spec.get("source", "")), "reverse": false}
		for spec: Dictionary in profile.get("buttons", []):
			var action := String(spec.get("action", ""))
			_shadow_if_bound(_button_binds, _shadow_buttons, "action", action)
			_button_binds[action] = {"guid": guid, "button": int(spec.get("button", 0))}
		if profile.has("throttle"):
			var t: Dictionary = profile["throttle"]
			# A second device's throttle would overwrite the first's below; keep the
			# first as a shadow so SAVE doesn't erase it from that device's file.
			if not _throttle.is_empty():
				_shadow_throttle = {"guid": _throttle["guid"], "spec": _throttle_orig.duplicate(true)}
			_throttle_orig = t.duplicate(true)
			var inv := float(t.get("idle", 1.0)) < float(t.get("full", -1.0))
			_throttle = {"guid": guid, "axis": int(t.get("axis", 0)), "invert": inv}
	# Snapshot each shadowed function's final winner instance, so SAVE can tell an
	# untouched overlap (re-emit the shadow) from a rebound/cleared one (drop it).
	for s: Dictionary in _shadow_axes:
		_load_winner_axis[s["key"]] = _axis_binds.get(s["key"])
	for s: Dictionary in _shadow_buttons:
		_load_winner_button[s["action"]] = _button_binds.get(s["action"])
	if _status:
		_status.text = "Ready — press BIND on a row."
	_refresh_values()


# --- Binding: begin + poll-based capture -----------------------------------

func _begin_listen(what: Dictionary) -> void:
	if Input.get_connected_joypads().is_empty():
		_status.text = "No joystick connected."
		return
	_listening = what
	# Snapshot every device's axis rest values + held buttons so we capture only
	# what MOVES from here (handles axes that rest off-center, like a throttle).
	_axis_baseline.clear()
	_btn_held.clear()
	for device in Input.get_connected_joypads():
		for axis in AXIS_SCAN_COUNT:
			_axis_baseline["%d:%d" % [device, axis]] = Input.get_joy_axis(device, axis as JoyAxis)
		for b in MAX_SCAN_BUTTONS:
			if Input.is_joy_button_pressed(device, b as JoyButton):
				_btn_held["%d:%d" % [device, b]] = true
	_status.text = ("Press the button now…" if what["kind"] == "button"
			else "Move the axis now…")


func _process(_delta: float) -> void:
	if _listening.is_empty():
		return
	if _listening["kind"] == "button":
		_poll_button_capture()
	else:
		_poll_axis_capture()


func _poll_axis_capture() -> void:
	var best_dev := -1
	var best_axis := -1
	var best_delta := 0.0
	for device in Input.get_connected_joypads():
		for axis in AXIS_SCAN_COUNT:
			var v := Input.get_joy_axis(device, axis as JoyAxis)
			var base := float(_axis_baseline.get("%d:%d" % [device, axis], v))
			var delta := v - base
			if absf(delta) > absf(best_delta):
				best_delta = delta
				best_dev = device
				best_axis = axis
	if absf(best_delta) < AXIS_CAPTURE_THRESHOLD:
		return
	var guid := Input.get_joy_guid(best_dev)
	if _listening["kind"] == "throttle":
		# The rest position (baseline) is idle; its sign tells us which endpoint
		# is idle without needing the user to hold full.
		var base := float(_axis_baseline.get("%d:%d" % [best_dev, best_axis], 0.0))
		_throttle = {"guid": guid, "axis": best_axis, "invert": base < 0.0}
		_throttle_rebound = true
	else:
		# Pushing toward +axis maps to `pos`; if the user pushed negative to
		# reach the threshold, pre-reverse so the felt direction matches.
		var key: String = _listening["key"]
		_axis_binds[key] = {
			"kind": "joy", "guid": guid, "axis": best_axis, "reverse": best_delta < 0.0}
		# Axis and per-direction buttons are mutually exclusive for a pair.
		var pair := key.split("|")
		_button_binds.erase(pair[0])
		_button_binds.erase(pair[1])
	_finish_listen()


func _poll_button_capture() -> void:
	for device in Input.get_connected_joypads():
		for b in MAX_SCAN_BUTTONS:
			if not Input.is_joy_button_pressed(device, b as JoyButton):
				continue
			if _btn_held.has("%d:%d" % [device, b]):
				continue  # already down at BIND start (held selector) — ignore
			var action: String = _listening["key"]
			_button_binds[action] = {"guid": Input.get_joy_guid(device), "button": b}
			# If this is one direction of an axis pair, drop the pair's axis bind
			# so the two don't both drive it.
			var pair_key := _pair_key_for_action(action)
			if not pair_key.is_empty():
				_axis_binds.erase(pair_key)
			_finish_listen()
			return


## The "neg|pos" axis-row key whose neg or pos equals `action`, or "" if none
## (i.e. a standalone OPS button like ops_cut).
func _pair_key_for_action(action: String) -> String:
	for target: Dictionary in AXIS_TARGETS:
		if target["neg"] == action or target["pos"] == action:
			return "%s|%s" % [target["neg"], target["pos"]]
	return ""


func _finish_listen() -> void:
	_listening = {}
	_status.text = "Bound. Continue, or SAVE."
	_refresh_values()


func _toggle_reverse(key: String) -> void:
	if _axis_binds.has(key):
		_axis_binds[key]["reverse"] = not _axis_binds[key].get("reverse", false)
		_refresh_values()


func _bind_hid(key: String, source: String) -> void:
	_axis_binds[key] = {"kind": "hid", "source": source, "reverse": false}
	var pair := key.split("|")
	_button_binds.erase(pair[0])
	_button_binds.erase(pair[1])
	_listening = {}
	_status.text = "Bound %s. Continue, or SAVE." % HID_SOURCE_LABELS.get(source, source)
	_refresh_values()


func _clear_axis(key: String) -> void:
	_axis_binds.erase(key)
	var pair := key.split("|")
	_button_binds.erase(pair[0])
	_button_binds.erase(pair[1])
	_refresh_values()


func _clear_button(action: String) -> void:
	_button_binds.erase(action)
	_refresh_values()


func _toggle_throttle_invert() -> void:
	if _throttle.has("axis"):
		_throttle["invert"] = not _throttle.get("invert", false)
		_refresh_values()


func _input(event: InputEvent) -> void:
	# Esc closes the overlay (and is swallowed so it doesn't reach InputRouter's
	# quit-on-Esc). Keyboard reaches the focused window, which is this overlay's.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()


# --- Display + save --------------------------------------------------------

func _dev_short(guid: String) -> String:
	var name := String(_dev_meta.get(guid, {}).get("name", ""))
	if name.is_empty():
		name = guid.substr(0, 6)
	return name.left(14)


func _refresh_values() -> void:
	for target: Dictionary in AXIS_TARGETS:
		var key: String = "%s|%s" % [target["neg"], target["pos"]]
		_value_labels[key].text = _axis_row_text(target["neg"], target["pos"])
	for target: Dictionary in BUTTON_TARGETS:
		var action: String = target["action"]
		var text := "—"
		if _button_binds.has(action):
			var bb: Dictionary = _button_binds[action]
			text = "Button %d · %s" % [bb["button"], _dev_short(bb["guid"])]
		_value_labels["btn:%s" % action].text = text
	_value_labels["throttle"].text = _throttle_text()


## An axis pair shows its analog/nub binding if set, else its per-direction
## button bindings, else —.
func _axis_row_text(neg: String, pos: String) -> String:
	var key := "%s|%s" % [neg, pos]
	if _axis_binds.has(key):
		return _axis_text(_axis_binds[key])
	var parts: PackedStringArray = []
	var guid := ""
	if _button_binds.has(neg):
		parts.append("−Btn%d" % _button_binds[neg]["button"])
		guid = _button_binds[neg]["guid"]
	if _button_binds.has(pos):
		parts.append("+Btn%d" % _button_binds[pos]["button"])
		guid = _button_binds[pos]["guid"]
	if parts.is_empty():
		return "—"
	return "%s · %s" % [" ".join(parts), _dev_short(guid)]


func _axis_text(bind: Dictionary) -> String:
	if bind.is_empty():
		return "—"
	var suffix := "  (rev)" if bind.get("reverse", false) else ""
	if bind.get("kind", "") == "hid":
		return HID_SOURCE_LABELS.get(bind.get("source", ""), bind.get("source", "")) + suffix
	return "Axis %d · %s%s" % [bind.get("axis", 0), _dev_short(bind.get("guid", "")), suffix]


func _throttle_text() -> String:
	if not _throttle.has("axis"):
		return "—"
	return "Axis %d · %s%s" % [
		_throttle["axis"], _dev_short(_throttle.get("guid", "")),
		"  (inv)" if _throttle.get("invert", false) else ""]


## Assemble the working binds into one profile PER device GUID and persist each.
## InputConfig emits profiles_changed, which InputRouter binds live.
func _save() -> void:
	var by_guid: Dictionary = {}
	for key: String in _axis_binds:
		_emit_axis(by_guid, key, _axis_binds[key])
	for action: String in _button_binds:
		_emit_button(by_guid, action, _button_binds[action])
	if _throttle.has("axis"):
		_profile_for(by_guid, _throttle["guid"])["throttle"] = _throttle_spec_out()
	# Re-emit bindings that a same-function bind on another device shadowed at load,
	# so each device keeps its own binding. A shadow is stale — and dropped — if the
	# winning entry was rebound or cleared since (its working instance no longer
	# matches the load-time snapshot); an in-place REV/INVERT keeps both.
	for s: Dictionary in _shadow_axes:
		if is_same(_axis_binds.get(s["key"]), _load_winner_axis.get(s["key"])):
			_emit_axis(by_guid, s["key"], s["value"])
	for s: Dictionary in _shadow_buttons:
		if is_same(_button_binds.get(s["action"]), _load_winner_button.get(s["action"])):
			_emit_button(by_guid, s["action"], s["value"])
	if not _shadow_throttle.is_empty() and not _throttle_rebound:
		_profile_for(by_guid, _shadow_throttle["guid"])["throttle"] = _shadow_throttle["spec"]
	# A device whose every binding was cleared drops out of by_guid above. Force an
	# empty override for each such device so the clear persists — otherwise its old
	# user file (or built-in profile) survives and re-binds the cleared controls.
	for guid: String in _loaded_guids:
		if not by_guid.has(guid):
			_profile_for(by_guid, guid)
	if by_guid.is_empty():
		_status.text = "Nothing bound to save."
		return
	for guid: String in by_guid:
		InputConfig.save_profile(by_guid[guid])
	_status.text = "Saved %d profile(s)." % by_guid.size()


## If `working[key]` is already bound (by an earlier-enumerated device), copy that
## losing entry into `shadows` before the caller overwrites it, so SAVE can keep it
## on its own device. `field` is the shadow key name ("key" for axes, "action").
func _shadow_if_bound(working: Dictionary, shadows: Array, field: String, key: String) -> void:
	if working.has(key):
		shadows.append({field: key, "value": (working[key] as Dictionary).duplicate(true)})


## Append one axis binding (analog or nub) to the right device's working profile,
## swapping neg/pos when reversed. Shared by the main SAVE pass and shadow re-emit.
func _emit_axis(by_guid: Dictionary, key: String, bind: Dictionary) -> void:
	var pair := key.split("|")
	var neg := pair[0]
	var pos := pair[1]
	if bind.get("reverse", false):
		var tmp := neg
		neg = pos
		pos = tmp
	if bind.get("kind", "") == "hid":
		# The nub is read by a global bridge; its binding rides the X52 profile
		# so it activates when the X52 is present.
		_profile_for(by_guid, X52_GUID)["hid_axes"].append({"source": bind["source"], "neg": neg, "pos": pos})
	else:
		_profile_for(by_guid, bind["guid"])["axes"].append({"axis": bind["axis"], "neg": neg, "pos": pos})


## Append one button binding to the right device's working profile.
func _emit_button(by_guid: Dictionary, action: String, bb: Dictionary) -> void:
	_profile_for(by_guid, bb["guid"])["buttons"].append({"button": bb["button"], "action": action})


## Get-or-create the working profile for a device GUID, pre-filled with its name
## and reserved-button bank so SAVE never drops a device's selector protection.
func _profile_for(by_guid: Dictionary, guid: String) -> Dictionary:
	if not by_guid.has(guid):
		var meta: Dictionary = _dev_meta.get(guid, {})
		by_guid[guid] = {
			"name": String(meta.get("name", "HOTAS")),
			"guid": guid,
			"axes": [],
			"buttons": [],
			"hid_axes": [],
			"reserved_buttons": meta.get("reserved_buttons", []),
		}
	return by_guid[guid]


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
