extends Node
## Saitek Pro Flight Switch Panel (VID 0x06a3 / PID 0x0d67) read natively
## in-engine via the hid-gd GDExtension — no external process (plan Phase 5).
## The panel never enumerates as a joystick, so Godot's Input singleton can't
## see it; hid-gd opens the raw HID interface and this node polls reports.
##
## The report decode is an isolated pure function (raw bytes -> named switch
## states), ported from the already-proven flightbridge/devices/flight_panel.py
## — per the plan's modding guidance, the trigger to generalize this into a
## declarative device-profile schema is a SECOND raw-HID device, not now.
## Runs degraded-gracefully: without the extension or the panel connected it
## just retries in the background.

const VID := 0x06a3
const PID := 0x0d67
const RETRY_INTERVAL := 3.0

## Bit order matches the panel's 3-byte report (flight_panel.py unpacks the
## same order as generic switch indices 0..19).
const SWITCH_NAMES: Array[String] = [
	"MASTER_BAT", "MASTER_ALT", "AVIONICS", "FUEL_PUMP",
	"DE_ICE", "PITOT_HEAT", "COWL", "PANEL_LIGHTS",
	"BEACON", "NAV", "STROBE", "TAXI",
	"LANDING", "ENGINE_OFF", "ENGINE_R", "ENGINE_L",
	"ENGINE_BOTH", "ENGINE_START", "GEAR_UP", "GEAR_DOWN",
]

var _hid: Object
var _retry_timer := 0.0
var _announced_missing := false


## Pure decode: raw HID report -> { switch_name: bool }. A leading zero
## report-ID byte is skipped (flight_panel.py's proven parsing) — but only
## when the report is longer than the panel's 3 payload bytes, since byte 0
## of a bare payload is legitimately zero with all bank-1 switches off.
static func parse_report(report: PackedByteArray) -> Dictionary:
	var out: Dictionary = {}
	if report.size() < 3:
		return out
	var bytes := report
	if bytes.size() > 3 and bytes[0] == 0:
		bytes = bytes.slice(1)
	for i in SWITCH_NAMES.size():
		var byte_index := i / 8
		if byte_index >= bytes.size():
			break
		out[SWITCH_NAMES[i]] = bool((bytes[byte_index] >> (i % 8)) & 1)
	return out


func _ready() -> void:
	if not ClassDB.class_exists("Hid"):
		push_warning("hid-gd extension missing — switch panel disabled")
		set_process(false)


func _process(delta: float) -> void:
	if _hid == null:
		_retry_timer -= delta
		if _retry_timer <= 0.0:
			_retry_timer = RETRY_INTERVAL
			_try_open()
		return
	# read_timeout returns a PackedByteArray on success (possibly empty when no
	# new report is pending), but hid-gd surfaces a read error / closed handle
	# as an int error code. Keep the return untyped so that error path doesn't
	# throw on the typed assignment; on error, drop the handle and let the
	# retry loop above reopen it — otherwise a mid-session unplug is permanent.
	var report: Variant = _hid.call("read_timeout", 8, 0)
	if typeof(report) != TYPE_PACKED_BYTE_ARRAY:
		_close("SWITCH PANEL OFFLINE")
		return
	if not report.is_empty():
		_apply(parse_report(report))


func _try_open() -> void:
	var hid: Object = ClassDB.instantiate("Hid")
	# hid-gd's open() returns a success bool, not an Error code.
	if hid.call("open", VID, PID):
		_hid = hid
		GameState.post_comms("SYSTEM", "SWITCH PANEL ONLINE")
	elif not _announced_missing:
		# One quiet note, then silent background retries: an unplugged panel
		# is a normal desk state, not an error loop.
		_announced_missing = true
		print("SwitchPanelBridge: panel not found (vid 0x%04x pid 0x%04x), retrying" % [VID, PID])


## Release the handle and re-arm the retry loop so the panel can recover from a
## mid-session unplug or read error. Re-arming _announced_missing keeps the
## silent-retry contract: the "not found" note only prints on the first miss.
func _close(reason: String) -> void:
	if _hid != null and _hid.has_method("close"):
		_hid.call("close")
	_hid = null
	_retry_timer = RETRY_INTERVAL
	_announced_missing = false
	GameState.post_comms("SYSTEM", reason)


func _apply(switches: Dictionary) -> void:
	for switch_name: String in switches:
		var on: bool = switches[switch_name]
		if GameState.panel_switches.get(switch_name) == on:
			continue
		GameState.panel_switches[switch_name] = on
		GameState.panel_switch_changed.emit(switch_name, on)
		GameState.post_comms("PANEL", "%s %s" % [switch_name, "ON" if on else "OFF"])
		_route_intent(switch_name, on)


## Switch -> gameplay intent mapping. Most switches just publish state (views
## like Ship.gd read panel_switches directly); the ones with systemic effects
## route through the same intents the touch UI uses.
func _route_intent(switch_name: String, on: bool) -> void:
	match switch_name:
		"MASTER_BAT":
			GameState.set_master_battery(on)
		"MASTER_ALT":
			GameState.set_master_alt(on)
		"AVIONICS", "FUEL_PUMP", "DE_ICE", "PITOT_HEAT":
			GameState.set_power_switch(switch_name, on)
		"COWL":
			GameState.set_cargo_hatch(on)
		# The panel's gear lever is a two-position switch decoded as a pair, so
		# only the edge that is going ON carries the intent.
		"GEAR_DOWN":
			if on:
				GameState.set_landing_gear(true)
		"GEAR_UP":
			if on:
				GameState.set_landing_gear(false)
