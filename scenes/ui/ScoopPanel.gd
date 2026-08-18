extends Control
## MFD SCOOP page: the post-cut collection instrument — the rendezvous half of
## the salvage loop, as ALIGN is the cutting half.
##
## A severed member drifts free (DriftSystem) and only stows once four gates hold
## at the same time: cargo hatch open, inside scoop range, relative speed nulled,
## and the piece inside the hatch's forward cone. Flying that off the camera feed
## alone is guesswork — nothing there tells you WHICH gate is the one still
## failing — so this page draws the task directly:
##
##   * a CONE FIELD centred on the ship's nose: the piece's marker sits where it
##     actually is off-axis, so pitching/yawing until the marker is inside the
##     tolerance ring *is* the aiming task, with an edge arrow to point the way
##     round when it's outside the field entirely;
##   * a DRIFT ARROW off that marker — which way, and how fast, the piece is
##     sliding relative to you. Thrust that way to null it;
##   * a GATE CHECKLIST with each gate's live value against its limit, so a
##     stalled scoop always names the gate that's holding it up;
##   * the SCOOP meter itself, mirroring the HUD ring.
##
## Read-only view of DriftSystem.collection_status (the same evaluation the scoop
## runs, so these numbers can't disagree with it); the HATCH button calls the
## same GameState intent the keybind and the panel's COWL switch do.

const ButtonTheme := preload("res://scenes/ui/ButtonTheme.gd")
const Instrument := preload("res://scenes/ui/Instrument.gd")

@export var accent: Color = Color(0.3, 0.9, 0.78)

## Reserve for the footer button row so the field never overlaps it.
const FOOTER_H := 76.0
## The four gates, drawn on Instrument.ROW_PITCH.
const GATE_ROWS := 4
## Vertical room for the gate checklist + scoop meter under the field. Derived
## from the row pitch so raising the type scale moves the reserve with it; the
## slack is the closure line and the scoop meter below the gates.
const CHECKLIST_H := GATE_ROWS * Instrument.ROW_PITCH + 60.0
const HEADER_H := 42.0

## Half-angle the cone field spans edge to edge. Wider than the collect cone so
## a piece that's off-target still shows up on the field (and which way to turn)
## instead of pinning to the rim immediately.
const FIELD_SPAN_DEG := 90.0
## Screen pixels per m/s of lateral relative drift on the drift arrow.
const DRIFT_PX_PER_MS := 26.0
const DRIFT_MAX_PX := 46.0

const GOOD := Instrument.GOOD
const WARN := Instrument.WARN

## The gate row labels, for measuring the value column off the widest of them.
const GATE_LABELS: PackedStringArray = ["HATCH", "RANGE", "REL SPD", "CONE"]

var _hatch: Button


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

	_hatch = ButtonTheme.make_touch_button(accent)
	_hatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hatch.pressed.connect(GameState.toggle_cargo_hatch)
	footer.add_child(_hatch)

	GameState.cargo_hatch_changed.connect(func(_open: bool) -> void: _refresh())
	GameState.salvage_pieces_changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	# Everything on this page moves continuously (the piece drifts, the ship
	# turns), so redraw per frame while it's the visible page.
	queue_redraw()


func _refresh() -> void:
	_hatch.text = "SECURE HATCH" if GameState.cargo_hatch_open else "OPEN HATCH"
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	# Off the claim (transit/docked) DriftSystem is paused but any pieces still
	# adrift stay in the world list, so the gate evaluation below would keep
	# reporting range, drift and gates for frozen salvage that can't be flown to.
	# Say what's actually true instead.
	if not DriftSystem.is_collecting():
		var adrift := GameState.salvage_pieces.size()
		var detail := "SCOOP WORKS ON SITE ONLY"
		if adrift > 0:
			detail = "%d PIECE%s LEFT ADRIFT AT THE CLAIM" % [
				adrift, "" if adrift == 1 else "S"]
		Instrument.draw_notice(self, font, "COLLECTION SUSPENDED", detail, accent, FOOTER_H)
		return

	var piece := DriftSystem.nearest_piece()
	if piece.is_empty():
		Instrument.draw_notice(self, font, "NO SALVAGE ADRIFT",
				"CUT A MEMBER FREE TO COLLECT IT", accent, FOOTER_H)
		return

	var st := DriftSystem.collection_status(piece)
	draw_string(font, Vector2(8, 26), "SCOOP — %s" % st["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, Instrument.HEADING, accent)
	draw_string(font, Vector2(-8, 26), "%d M" % roundi(st["range"]),
			HORIZONTAL_ALIGNMENT_RIGHT, size.x, Instrument.HEADING, accent)

	# --- Cone field ---------------------------------------------------------
	var avail := size.y - FOOTER_H - HEADER_H - CHECKLIST_H
	var field: float = maxf(minf(size.x * 0.44, avail * 0.5), 24.0)
	var center := Vector2(size.x / 2.0, HEADER_H + field)
	var px_per_deg := field / FIELD_SPAN_DEG
	var cone_r: float = DriftSystem.COLLECT_CONE_DEG * px_per_deg

	# Field rim, nose crosshair at dead centre, and the cone tolerance ring the
	# marker has to sit inside.
	draw_arc(center, field, 0.0, TAU, 72, Color(accent, 0.25), 1.0, true)
	draw_line(center - Vector2(field, 0), center + Vector2(field, 0), Color(accent, 0.12), 1.0)
	draw_line(center - Vector2(0, field), center + Vector2(0, field), Color(accent, 0.12), 1.0)
	var cone_col := GOOD if st["in_cone"] else Color(accent, 0.7)
	draw_arc(center, cone_r, 0.0, TAU, 48, cone_col, 1.5, true)
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + d * 5.0, center + d * 10.0, Color(accent, 0.8), 1.5)

	# The piece, placed by its true off-nose angle. Past the field edge it clamps
	# to the rim as an arrowhead — "keep turning this way".
	var aim: Vector2 = st["aim"]
	var marker := center + aim * px_per_deg
	var offset := marker - center
	if offset.length() > field:
		var dir := offset.normalized()
		Instrument.draw_arrowhead(self, center + dir * field, dir, 11.0, WARN)
	else:
		var mark_col: Color = GOOD if st["gated"] else (
				cone_col if st["in_cone"] else Color(1.0, 0.7, 0.25))
		Instrument.draw_diamond(self, marker, 9.0, mark_col, 2.0)
		# Which way it's sliding relative to us — thrust along this to null it.
		var drift: Vector2 = st["rel_lateral"]
		if drift.length() > 0.05:
			var arrow: Vector2 = drift.normalized() * minf(
					drift.length() * DRIFT_PX_PER_MS, DRIFT_MAX_PX)
			draw_line(marker, marker + arrow, Color(1.0, 0.9, 0.4, 0.9), 1.5)
			Instrument.draw_arrowhead(self, marker + arrow, arrow.normalized(), 6.0,
					Color(1.0, 0.9, 0.4, 0.9))
		if float(st["scoop"]) > 0.0:
			draw_arc(marker, 15.0, -PI / 2.0, -PI / 2.0 + TAU * float(st["scoop"]),
					36, GOOD, 2.5, true)

	# --- Gate checklist -----------------------------------------------------
	var y := center.y + field + 18.0
	var pitch := Instrument.ROW_PITCH
	var label_w := Instrument.label_column(font, GATE_LABELS)
	Instrument.draw_gate(self, font, y, "HATCH",
			"OPEN" if st["hatch"] else "SECURED", st["hatch"], accent, label_w)
	Instrument.draw_gate(self, font, y + pitch, "RANGE", "%.1f / %.1f M" % [
		maxf(float(st["gap"]), 0.0), DriftSystem.SCOOP_RANGE], st["in_range"],
			accent, label_w)
	Instrument.draw_gate(self, font, y + pitch * 2.0, "REL SPD", "%.2f / %.2f M/S" % [
		st["rel_speed"], DriftSystem.COLLECT_REL_SPEED], st["speed_ok"], accent, label_w)
	Instrument.draw_gate(self, font, y + pitch * 3.0, "CONE", "%d° / %d°" % [
		roundi(float(st["off_axis"])), roundi(DriftSystem.COLLECT_CONE_DEG)],
			st["in_cone"], accent, label_w)

	# Closure rate is context, not a gate — it tells you whether the range gate
	# is about to open on you while you fight the other three.
	var closure: float = st["closure"]
	draw_string(font, Vector2(8, y + pitch * 4.0 + 4.0), "%s %.2f M/S" % [
		"CLOSING" if closure > 0.0 else "OPENING", absf(closure)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, Instrument.ANNOT, Color(accent, 0.65))

	Instrument.draw_meter(self, font, Vector2(8, y + pitch * 4.0 + 14.0),
			size.x - 16.0, "SCOOP", float(st["scoop"]),
			GOOD if st["gated"] else Color(accent, 0.6),
			Instrument.label_column(font, ["SCOOP"]))


