extends Control
## HOTAS/raw-input discovery tool (plan Phase 5): logs every joypad
## connection, button, axis, and hat event with device id + index so real
## bindings are written from observed indices, not documentation (X52/X55
## community SDL mappings are known to be incomplete).
##
##   godot --path . res://tools/InputEcho.tscn
##
## Everything shown on screen is also appended to user://input_echo.log and
## stdout — run it, work every axis/button/switch once, then share the log.
## If the hid-gd extension is present, raw HID devices (e.g. the Saitek
## switch panel, which never enumerates as a joypad) are listed too, and the
## panel's raw reports are echoed when it's connected. Esc quits.

const LOG_PATH := "user://input_echo.log"
const MAX_LINES := 34
const PANEL_VID := 0x06a3
const PANEL_PID := 0x0d67
## X55 Rhino stick — raw joystick collection (usage_page 1, usage 4 picks the
## MI_00 interface among the stick's several HID collections). Dumped to find
## the POV hat's byte offset/encoding for the planned HID glance bridge.
const X55_VID := 0x0738
const X55_PID := 0x2215

var _lines: PackedStringArray = []
var _log_file: FileAccess
var _panel: Object
var _x55: Object
## Axis values last shown per "device:axis" key, to only log meaningful moves.
var _axis_shown: Dictionary = {}
var _last_panel_report := PackedByteArray()
var _last_x55_report := PackedByteArray()

@onready var _label: RichTextLabel = %Log


func _ready() -> void:
	get_window().title = "Salvager — Input Echo"
	get_window().size = Vector2i(1100, 720)
	_log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	_emit("INPUT ECHO — work every axis/button/hat/switch once, Esc quits")
	_emit("log file: %s" % ProjectSettings.globalize_path(LOG_PATH))
	Input.joy_connection_changed.connect(_on_joy_changed)
	_list_joypads()
	_list_hid_devices()
	_open_panel()
	_open_x55()


func _list_joypads() -> void:
	var pads := Input.get_connected_joypads()
	_emit("connected joypads: %d" % pads.size())
	for device in pads:
		_emit("  device %d: \"%s\"  guid=%s" % [
			device, Input.get_joy_name(device), Input.get_joy_guid(device)])


func _list_hid_devices() -> void:
	if not ClassDB.class_exists("Hid"):
		_emit("hid-gd extension not loaded — raw HID listing unavailable")
		return
	var devices: Array = ClassDB.instantiate("Hid").call("list_devices")
	_emit("raw HID devices (hid-gd): %d" % devices.size())
	for info in devices:
		_emit("  %s" % str(info))


func _open_panel() -> void:
	if not ClassDB.class_exists("Hid"):
		return
	_panel = ClassDB.instantiate("Hid")
	# hid-gd's open() returns a success bool, not an Error code.
	if _panel.call("open", PANEL_VID, PANEL_PID):
		_emit("saitek switch panel open (vid 0x%04x pid 0x%04x) — flip switches" % [
			PANEL_VID, PANEL_PID])
	else:
		_emit("saitek switch panel not found (vid 0x%04x pid 0x%04x)" % [
			PANEL_VID, PANEL_PID])
		_panel = null


## Open the X55 stick's joystick HID collection by path so we grab MI_00
## (usage_page 1 / usage 4) and not one of the stick's other collections —
## open(vid, pid) could land on any of them.
func _open_x55() -> void:
	if not ClassDB.class_exists("Hid"):
		return
	var probe: Object = ClassDB.instantiate("Hid")
	for info: Dictionary in probe.call("list_devices"):
		if int(info.get("vid", 0)) != X55_VID or int(info.get("pid", 0)) != X55_PID:
			continue
		if int(info.get("usage_page", 0)) != 1 or int(info.get("usage", 0)) != 4:
			continue
		var hid: Object = ClassDB.instantiate("Hid")
		if hid.call("open_path", info["path"]):
			_x55 = hid
			_emit("x55 stick hid open — work the POV hat, watch for changing bytes")
			_emit("  path: %s" % info["path"])
		else:
			_emit("x55 stick hid open_path FAILED: %s" % info["path"])
		return
	_emit("x55 stick joystick collection not found (vid 0x%04x pid 0x%04x usage 1/4)" % [
			X55_VID, X55_PID])


func _on_joy_changed(device: int, connected: bool) -> void:
	_emit("joy_connection_changed: device %d %s" % [
		device, "CONNECTED" if connected else "DISCONNECTED"])
	_list_joypads()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
	elif event is InputEventJoypadButton:
		_emit("device %d  BUTTON %2d  %s" % [
			event.device, event.button_index,
			"pressed " if event.pressed else "released"])
	elif event is InputEventJoypadMotion:
		# Only log fresh moves past 0.08 steps so idle jitter doesn't flood.
		var key := "%d:%d" % [event.device, event.axis]
		if absf(event.axis_value - float(_axis_shown.get(key, 9.0))) > 0.08:
			_axis_shown[key] = event.axis_value
			_emit("device %d  AXIS %2d  %+.2f" % [
				event.device, event.axis, event.axis_value])


func _process(_delta: float) -> void:
	if _panel != null:
		var report: PackedByteArray = _panel.call("read_timeout", 8, 0)
		if not report.is_empty() and report != _last_panel_report:
			_last_panel_report = report
			_emit("panel report: %s" % _hex(report))
	if _x55 != null:
		# 64 bytes is comfortably past any HOTAS report length; the read
		# returns whatever one report actually contains.
		var report: Variant = _x55.call("read_timeout", 64, 0)
		if typeof(report) == TYPE_PACKED_BYTE_ARRAY and not report.is_empty() \
				and report != _last_x55_report:
			# ^ marks each byte that changed vs the previous report, so the POV
			# field stands out while the hat is worked.
			var marks := ""
			for i in report.size():
				var changed: bool = i >= _last_x55_report.size() \
						or report[i] != _last_x55_report[i]
				marks += "^^ " if changed else "   "
			_emit("x55 report: %s" % _hex(report))
			if not _last_x55_report.is_empty():
				_emit("            %s" % marks.strip_edges(false, true))
			_last_x55_report = report


static func _hex(bytes: PackedByteArray) -> String:
	var hex := ""
	for b in bytes:
		hex += "%02x " % b
	return hex.strip_edges()


func _emit(line: String) -> void:
	print(line)
	if _log_file:
		_log_file.store_line(line)
		_log_file.flush()
	_lines.append(line)
	while _lines.size() > MAX_LINES:
		_lines.remove_at(0)
	_label.text = "\n".join(_lines)
