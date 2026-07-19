extends Node
## X55 stick POV hat read over raw HID via hid-gd, bypassing Godot's joypad
## layer entirely. Godot collapses the hat into JOY_BUTTON_DPAD_* events,
## where DPAD_RIGHT (14) collides with the stick's always-held selector-
## position button 15 (1-based) — the launch-glance bug. In the raw report
## the hat and that button are separate fields, so reading here needs no
## timing heuristics. See InputRouter.gd for the full story.
##
## Report layout (tools/InputEcho.tscn capture, 2026-07-19, 9 bytes):
##   [0-1] X 16-bit LE     [2-3] Y 16-bit LE     [4 + low nibble of 5] twist
##   [5 high nibble] POV: 0 = centered, 1..8 = N NE E SE S SW W NW clockwise
##   [6-8] buttons (byte 7 bit 6 = the always-held selector button)
##
## Runs degraded-gracefully like SwitchPanelBridge: without the extension or
## the stick connected, `glance` just stays ZERO (keyboard arrows still work)
## and the open is retried in the background.

const VID := 0x0738
const PID := 0x2215
const RETRY_INTERVAL := 3.0
## Reports stream at device rate (axis jitter alone emits constantly), so a
## few can queue between frames; drain to the freshest each frame, bounded in
## case a flood ever outpaces us.
const MAX_READS_PER_FRAME := 32

## +x = right, +y = down (Input.get_vector convention); diagonals normalized
## to match get_vector's circular clamp. Indexed by POV value - 1.
const POV_DIRS: Array[Vector2] = [
	Vector2(0, -1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1),
	Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1),
]

## Latest decoded hat direction; ZERO when centered, absent, or degraded.
var glance := Vector2.ZERO

var _hid: Object
var _retry_timer := 0.0
var _announced_missing := false


## Pure decode: raw report -> hat direction vector.
static func parse_pov(report: PackedByteArray) -> Vector2:
	if report.size() < 6:
		return Vector2.ZERO
	var pov := report[5] >> 4
	if pov < 1 or pov > POV_DIRS.size():
		return Vector2.ZERO
	return POV_DIRS[pov - 1].normalized()


func _ready() -> void:
	if not ClassDB.class_exists("Hid"):
		push_warning("hid-gd extension missing — POV glance disabled (arrows still work)")
		set_process(false)


func _process(delta: float) -> void:
	if _hid == null:
		_retry_timer -= delta
		if _retry_timer <= 0.0:
			_retry_timer = RETRY_INTERVAL
			_try_open()
		return
	for _i in MAX_READS_PER_FRAME:
		# Untyped return: hid-gd surfaces read errors / closed handles as an
		# int error code instead of a PackedByteArray (same contract as
		# SwitchPanelBridge) — drop the handle and let the retry loop reopen.
		var report: Variant = _hid.call("read_timeout", 16, 0)
		if typeof(report) != TYPE_PACKED_BYTE_ARRAY:
			_close()
			return
		if report.is_empty():
			break
		glance = parse_pov(report)


## The stick exposes several HID collections under one vid/pid; open the
## joystick collection (usage_page 1 / usage 4) by path so open(vid, pid)
## can't land on the wrong one.
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
			print("HidGlanceBridge: x55 pov online")
		elif not _announced_missing:
			_announced_missing = true
			print("HidGlanceBridge: open_path failed for %s, retrying" % info["path"])
		return
	if not _announced_missing:
		# One quiet note, then silent background retries: an unplugged stick
		# is a normal desk state, not an error loop.
		_announced_missing = true
		print("HidGlanceBridge: x55 stick not found (vid 0x%04x pid 0x%04x), retrying" % [VID, PID])


## Release the handle and re-arm the retry loop so a mid-session unplug or
## read error recovers once the stick is back.
func _close() -> void:
	if _hid != null and _hid.has_method("close"):
		_hid.call("close")
	_hid = null
	glance = Vector2.ZERO
	_retry_timer = RETRY_INTERVAL
	_announced_missing = false
