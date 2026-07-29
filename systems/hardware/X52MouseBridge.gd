extends Node
## X52 throttle's mouse-stick nub read over raw HID via hid-gd, exposed as the
## bindable virtual axes x52_mouse_x / x52_mouse_y (see InputRouter.HID_SOURCES).
## Godot's joypad layer does NOT surface the nub (confirmed by probe), so raw HID
## is the only way to reach it — like the X55 POV hat in HidGlanceBridge.
##
## (The X52 scroll WHEEL is NOT here: Godot already exposes it as joypad buttons
## 32 (up) / 33 (down), bindable through a profile's normal `buttons`.)
##
## OPT-IN: closed until InputRouter calls set_active(true), which it does only
## when a loaded profile binds an x52_mouse_* source. The X52 has a single HID
## collection (the joystick, usage_page 1 / usage 4) that Godot also reads as a
## joypad; concurrent HID + joypad access is the same pattern HidGlanceBridge
## already proves on the X55. Degrades to ZERO without the extension/device.
##
## Report layout (VID 0x06a3 / PID 0x075c joystick collection, 14 bytes; nub
## confirmed by isolation capture + the documented Saitek/Logitech X52 mapping):
##   byte 13 low nibble  = mouse X (4-bit, 0..15, centered at 8)
##   byte 13 high nibble = mouse Y (4-bit, 0..15, centered at 8)
##   rest = 0x88 (X:8, Y:8). Both nibbles vary together because a nudge in one
##   direction tilts the tiny nub in the other too — normal for this control.

const VID := 0x06a3
const PID := 0x075c
const RETRY_INTERVAL := 3.0
const MAX_READS_PER_FRAME := 32
## Nub report is the last byte of the 14-byte joystick report.
const NUB_BYTE := 13

## Latest decoded nub direction, each axis -1..1 (+x, +y follow the raw nibble;
## flip in a profile's hid_axes neg/pos if a direction feels reversed). ZERO when
## inactive, absent, or degraded.
var axis := Vector2.ZERO

var _active := false
var _hid: Object
var _retry_timer := 0.0
var _announced_missing := false


## 4-bit nub nibble (0..15, center 8) -> -1..1, with a ±1 idle deadzone since the
## nub's rest value wanders a step or two.
static func _nib_norm(nib: int) -> float:
	var d := nib - 8
	if absi(d) <= 1:
		return 0.0
	return clampf(float(d) / 7.0, -1.0, 1.0)


## Pure decode: raw report -> nub direction. X = low nibble, Y = high nibble.
static func parse_report(report: PackedByteArray) -> Vector2:
	if report.size() <= NUB_BYTE:
		return Vector2.ZERO
	var b := report[NUB_BYTE]
	return Vector2(_nib_norm(b & 0x0f), _nib_norm(b >> 4))


func _ready() -> void:
	set_process(false)
	if not ClassDB.class_exists("Hid"):
		push_warning("hid-gd extension missing — X52 nub axes disabled")


## Called by InputRouter when a profile binds (or stops binding) an x52_mouse_*
## source. Opening is deferred to _process's retry loop so a missing device just
## retries quietly rather than blocking here.
func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	if not ClassDB.class_exists("Hid"):
		return
	if active:
		_retry_timer = 0.0
		_announced_missing = false
		set_process(true)
	else:
		_close()
		set_process(false)


func _process(delta: float) -> void:
	if _hid == null:
		_retry_timer -= delta
		if _retry_timer <= 0.0:
			_retry_timer = RETRY_INTERVAL
			_try_open()
		return
	for _i in MAX_READS_PER_FRAME:
		# Untyped return: hid-gd surfaces read errors / closed handles as an int
		# error code instead of a PackedByteArray (same contract as the other
		# bridges) — drop the handle and let the retry loop reopen.
		var report: Variant = _hid.call("read_timeout", 16, 0)
		if typeof(report) != TYPE_PACKED_BYTE_ARRAY:
			_close()
			return
		if report.is_empty():
			break
		axis = parse_report(report)


## Open the X52 joystick collection (usage_page 1 / usage 4) by path.
func _try_open() -> void:
	var probe: Object = ClassDB.instantiate("Hid")
	for info: Dictionary in probe.call("list_devices"):
		if int(info.get("vid", 0)) != VID or int(info.get("pid", 0)) != PID:
			continue
		if int(info.get("usage_page", 0)) != 1 or int(info.get("usage", 0)) != 4:
			continue
		var hid: Object = ClassDB.instantiate("Hid")
		if hid.call("open_path", info["path"]):
			_hid = hid
			print("X52MouseBridge: x52 nub online (%s)" % info["path"])
			return
	if not _announced_missing:
		_announced_missing = true
		print("X52MouseBridge: x52 not found (vid 0x%04x pid 0x%04x), retrying" % [VID, PID])


func _close() -> void:
	if _hid != null and _hid.has_method("close"):
		_hid.call("close")
	_hid = null
	axis = Vector2.ZERO
	_retry_timer = RETRY_INTERVAL
	_announced_missing = false
