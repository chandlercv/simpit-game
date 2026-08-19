extends Control
## MFD DOCK page: the docking/landing instrument — the arrival and departure
## half of a run, as ALIGN and SCOOP are the two halves of a salvage job.
##
## Flying a station pattern off the camera feed alone is guesswork: nothing out
## there tells you which marker is next, how far off the lane's centreline you
## have drifted, or which of ATC's standing instructions is the one you are
## currently breaking. So this page draws the task directly:
##
##   * the ATC INSTRUCTION banner — the standing clearance, held for as long as
##     it applies (a comms line scrolls away; a clearance doesn't), flashing
##     while it's urgent;
##   * a CONE FIELD centred on the nose, with the next gate placed by its true
##     off-axis angle and the gate's own ring drawn as the tolerance circle, so
##     flying the marker inside the ring *is* the task — plus an edge arrow when
##     it's off the field, and traffic drawn as crosses on the same field;
##   * ON FINAL that field becomes a PAD VIEW — top-down markings, where you
##     actually are across the deck, and a sink-rate tape beside an altitude —
##     because the last 16 m is a different problem from the lane;
##   * a GATE CHECKLIST of every rule ATC is watching (speed, lane, gear, hatch,
##     clearance) against live values, so an imminent go-around always names
##     itself before it happens.
##
## Read-only view of DockingSystem.status() — the same evaluation the rules
## themselves test, so these numbers cannot disagree with what ATC is enforcing.
## The footer buttons call the same intents the keybinds and the switch panel do.

const ButtonTheme := preload("res://scenes/ui/ButtonTheme.gd")
const Instrument := preload("res://scenes/ui/Instrument.gd")

@export var accent: Color = Color(0.3, 0.9, 0.78)

## Reserve for the footer button row so the field never overlaps it.
const FOOTER_H := 76.0
## The five rules ATC is watching, drawn on Instrument.ROW_PITCH.
const GATE_ROWS := 5
## Vertical room for the checklist under the field. Derived from the row pitch so
## raising the type scale moves the reserve with it.
const CHECKLIST_H := GATE_ROWS * Instrument.ROW_PITCH + 20.0
## Room for the two-line ATC banner above the field.
const HEADER_H := 66.0

## Half-angle the cone field spans edge to edge — wide enough that a gate you
## are badly off-line for still shows up (and which way to turn) rather than
## pinning to the rim immediately.
const FIELD_SPAN_DEG := 90.0

## Pad view: screen pixels per metre across the deck.
const PAD_PX_PER_M := 9.0

const GOOD := Instrument.GOOD
const WARN := Instrument.WARN
const BAD := Instrument.BAD

## The gate row labels, for measuring the value column off the widest of them.
const GATE_LABELS: PackedStringArray = ["SPEED", "LANE", "GEAR", "HATCH", "CLEARANCE"]

var _request: Button
var _gear: Button
var _abort: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var footer := HBoxContainer.new()
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -(FOOTER_H - 8.0)
	footer.offset_left = 8
	footer.offset_right = -8
	footer.offset_bottom = -8
	footer.add_theme_constant_override("separation", ButtonTheme.TOUCH_SEP)
	add_child(footer)

	# Touch equivalents of the mapped controls, so the page is flyable on the
	# 13" panel alone.
	_request = ButtonTheme.make_touch_button(accent)
	_request.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_request.pressed.connect(DockingSystem.request_clearance)
	footer.add_child(_request)

	_gear = ButtonTheme.make_touch_button(accent)
	_gear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gear.pressed.connect(GameState.toggle_landing_gear)
	footer.add_child(_gear)

	_abort = ButtonTheme.make_touch_button(Color(1.0, 0.55, 0.45))
	_abort.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_abort.pressed.connect(DockingSystem.abort_approach)
	footer.add_child(_abort)

	GameState.docking_changed.connect(func(_state: String) -> void: _refresh())
	GameState.landing_gear_changed.connect(func(_down: bool) -> void: _refresh())
	_refresh()


func _process(_delta: float) -> void:
	# Everything here moves continuously (the ship flies, traffic works the
	# lane), so redraw per frame while this is the visible page.
	queue_redraw()


func _refresh() -> void:
	var outbound: bool = GameState.docking.get("outbound", false)
	_request.text = "REQUEST DEPARTURE" if GameState.docking_state == "DEPART_HOLD" \
			else ("ACKNOWLEDGE" if DockingSystem.status().get("cleared", false)
					else "REQUEST CLEARANCE")
	_gear.text = "GEAR UP" if GameState.gear_down else "GEAR DOWN"
	# There is no aborting a departure — you are already leaving.
	_abort.disabled = outbound or not DockingSystem.is_active()
	_abort.text = "DEPARTING" if outbound else "ABORT APPROACH"
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var st := DockingSystem.status()
	if st.is_empty():
		Instrument.draw_notice(self, font, "NO APPROACH RUNNING",
				"DOCK FROM THE MARKET PAGE TO FLY A STATION PATTERN", accent, FOOTER_H)
		return

	_draw_atc(font, st)

	var avail := size.y - FOOTER_H - HEADER_H - CHECKLIST_H
	var field: float = maxf(minf(size.x * 0.44, avail * 0.5), 24.0)
	var center := Vector2(size.x / 2.0, HEADER_H + field)
	if st["state"] == "FINAL":
		_draw_pad_view(font, st, center, field)
	else:
		_draw_cone_field(font, st, center, field)
	_draw_checklist(font, st, center.y + field + 16.0)


## The standing instruction, held as long as it applies. Urgent ones pulse — the
## difference between "next marker CHARLIE" and "you are outside the lane" has
## to be readable without stopping to read.
func _draw_atc(font: Font, st: Dictionary) -> void:
	var atc: Dictionary = st.get("atc", {})
	var station: String = st.get("station", "")
	draw_string(font, Vector2(8, 16), station, HORIZONTAL_ALIGNMENT_LEFT, -1,
			Instrument.CORNER, Color(accent, 0.6))
	draw_string(font, Vector2(-8, 16), "BERTH %d" % int(st.get("berth", 0)),
			HORIZONTAL_ALIGNMENT_RIGHT, size.x, Instrument.CORNER, Color(accent, 0.6))
	if atc.is_empty():
		return
	var urgent: bool = atc.get("urgent", false)
	var col := accent
	if urgent:
		# 2 Hz pulse between warn and full — legible at a glance, not a strobe.
		col = WARN.lerp(Color(1, 1, 1), 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0))
	draw_string(font, Vector2(8, 40), String(atc.get("text", "")),
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, Instrument.HEADING, col)
	draw_string(font, Vector2(8, 58), String(atc.get("detail", "")),
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, Instrument.DETAIL,
			Color(accent, 0.55))


## The lane view: the next gate placed by true off-nose angle, its ring as the
## tolerance circle, traffic on the same field.
func _draw_cone_field(font: Font, st: Dictionary, center: Vector2, field: float) -> void:
	var px_per_deg := field / FIELD_SPAN_DEG

	draw_arc(center, field, 0.0, TAU, 72, Color(accent, 0.25), 1.0, true)
	draw_line(center - Vector2(field, 0), center + Vector2(field, 0), Color(accent, 0.12), 1.0)
	draw_line(center - Vector2(0, field), center + Vector2(0, field), Color(accent, 0.12), 1.0)
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + d * 5.0, center + d * 10.0, Color(accent, 0.8), 1.5)

	# The gate's ring drawn at the angle it actually subtends from here, so it
	# grows as you close on it exactly like the real one does.
	var range_m: float = maxf(float(st["range"]), 0.1)
	var gate_r: float = float(st["gate_radius"])
	var subtend := rad_to_deg(atan(gate_r / range_m)) * px_per_deg
	var aim: Vector2 = st["aim"]
	var marker := center + aim * px_per_deg
	var inside: bool = aim.length() <= rad_to_deg(atan(gate_r / range_m))
	draw_arc(marker, maxf(subtend, 4.0), 0.0, TAU, 48,
			GOOD if inside else Color(accent, 0.7), 1.5, true)

	var offset := marker - center
	if offset.length() > field:
		Instrument.draw_arrowhead(self, center + offset.normalized() * field,
				offset.normalized(), 11.0, WARN)
	else:
		Instrument.draw_diamond(self, marker, 7.0, GOOD if inside else WARN, 2.0)
	draw_string(font, marker + Vector2(12, 4), "%s  %d M" % [
		st["gate_name"], roundi(range_m)], HORIZONTAL_ALIGNMENT_LEFT, -1,
			Instrument.ANNOT, Color(accent, 0.9))

	# Traffic on the same field: crosses, red once one is inside the advisory
	# band, so "where is he" is answered on the instrument you're already using.
	for entry: Dictionary in st.get("traffic", []):
		var t_gap: float = entry["gap"]
		if t_gap > 60.0:
			continue
		var t_aim: Vector2 = _bearing_to(entry["range"], entry)
		var at := center + t_aim * px_per_deg
		if (at - center).length() > field:
			continue
		var col := BAD if t_gap <= DockingSystem.TRAFFIC_ADVISORY else Color(accent, 0.75)
		draw_line(at - Vector2(5, 5), at + Vector2(5, 5), col, 1.5)
		draw_line(at - Vector2(5, -5), at + Vector2(5, -5), col, 1.5)
		draw_string(font, at + Vector2(8, -2), "%d M" % roundi(maxf(t_gap, 0.0)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, Instrument.TAG, col)


## Traffic bearings aren't in status() (it reports range and gap, which is what
## the rules use), so they're derived here from the live entry the same way
## status() derives the gate's aim.
func _bearing_to(_range_m: float, entry: Dictionary) -> Vector2:
	for live: Dictionary in GameState.traffic:
		if String(live["name"]) != String(entry["name"]):
			continue
		var ship: Dictionary = GameState.local_ship()
		var xform: Transform3D = ship["transform"]
		var to_them: Vector3 = (live["transform"] as Transform3D).origin - xform.origin
		if to_them.length() < 0.001:
			return Vector2.ZERO
		var local := xform.basis.inverse() * to_them.normalized()
		var off := rad_to_deg(acos(clampf(-local.z, -1.0, 1.0)))
		var lateral := Vector2(local.x, -local.y)
		return lateral.normalized() * off if lateral.length() > 0.0001 else Vector2.ZERO
	return Vector2.ZERO


## On final the problem changes: you are over the pad, and what matters is where
## you are across the deck, how fast you're going down, and how level. So the
## field becomes a top-down view of the markings you're being scored against.
func _draw_pad_view(font: Font, st: Dictionary, center: Vector2, field: float) -> void:
	var pad_r: float = DockingSystem.PAD_RADIUS * PAD_PX_PER_M
	var scale: float = minf(field / maxf(pad_r, 1.0), 1.0)
	pad_r *= scale
	draw_arc(center, pad_r, 0.0, TAU, 64, Color(accent, 0.7), 1.5, true)
	draw_line(center - Vector2(pad_r * 0.9, 0), center + Vector2(pad_r * 0.9, 0),
			Color(accent, 0.25), 1.0)
	draw_line(center - Vector2(0, pad_r * 0.9), center + Vector2(0, pad_r * 0.9),
			Color(accent, 0.25), 1.0)

	# Where the ship actually is across the deck, in the pad's own axes.
	var drift: Vector2 = st["drift"]
	var at := center + drift * PAD_PX_PER_M * scale
	var on_pad: bool = st["on_pad"]
	Instrument.draw_diamond(self, at, 8.0, GOOD if on_pad else BAD, 2.0)
	draw_line(center, at, Color(accent, 0.4), 1.0)

	# Sink-rate tape down the right edge, banded by what the legs will take.
	var descent: float = st["descent"]
	var tape_x := size.x - 22.0
	var tape_top := center.y - field
	var tape_h := field * 2.0
	draw_line(Vector2(tape_x, tape_top), Vector2(tape_x, tape_top + tape_h),
			Color(accent, 0.3), 1.0)
	var frac := clampf(descent / DockingSystem.CRASH_RATE, 0.0, 1.0)
	var rate_col := GOOD
	if descent > DockingSystem.HARD_RATE:
		rate_col = BAD
	elif descent > DockingSystem.FIRM_RATE:
		rate_col = WARN
	draw_line(Vector2(tape_x - 6, tape_top + tape_h * frac),
			Vector2(tape_x + 6, tape_top + tape_h * frac), rate_col, 2.5)
	draw_string(font, Vector2(tape_x - 84, tape_top + tape_h * frac - 4),
			"%.1f M/S" % descent, HORIZONTAL_ALIGNMENT_RIGHT, 80, Instrument.ANNOT,
			rate_col)

	draw_string(font, Vector2(8, center.y + field - 4),
			"ALT %.1f M   OFF %.1f M   TILT %d°" % [
				maxf(float(st["altitude"]), 0.0), float(st["lateral"]),
				roundi(float(st["tilt"]))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, Instrument.ANNOT,
			GOOD if st["level"] and on_pad else WARN)


## Every rule ATC is watching, live. A go-around should never be a surprise —
## the row that is about to cause it is already red.
func _draw_checklist(font: Font, st: Dictionary, y: float) -> void:
	var pitch := Instrument.ROW_PITCH
	var label_w := Instrument.label_column(font, GATE_LABELS)
	var speed_ok: bool = st["speed_ok"]
	Instrument.draw_gate(self, font, y, "SPEED", "%.0f / %.0f M/S" % [
		st["speed"], st["speed_limit"]], speed_ok, accent, label_w)
	var lane_ok: bool = st["lane_ok"]
	Instrument.draw_gate(self, font, y + pitch, "LANE", "%.0f / %.0f M" % [
		st["lane_deviation"], st["lane_limit"]], lane_ok, accent, label_w)
	var gear_ok: bool = st["gear_ok"]
	var gear_text := "DOWN & LOCKED" if gear_ok else (
			"IN TRANSIT %d%%" % roundi(float(st["gear_position"]) * 100.0)
			if float(st["gear_position"]) > 0.0 else "UP")
	Instrument.draw_gate(self, font, y + pitch * 2.0, "GEAR", gear_text, gear_ok,
			accent, label_w)
	Instrument.draw_gate(self, font, y + pitch * 3.0, "HATCH",
			"SECURED" if st["hatch_ok"] else "OPEN", st["hatch_ok"], accent, label_w)
	var cleared: bool = st["cleared"]
	var clearance := "CLEARED"
	if st["hold"]:
		clearance = "HOLDING"
	elif not cleared:
		clearance = "AWAITING"
	Instrument.draw_gate(self, font, y + pitch * 4.0, "CLEARANCE", clearance, cleared,
			accent, label_w)
