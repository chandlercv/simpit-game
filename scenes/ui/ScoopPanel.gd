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

@export var accent: Color = Color(0.3, 0.9, 0.78)

## Reserve for the footer button row so the field never overlaps it.
const FOOTER_H := 52.0
## Vertical room for the gate checklist + scoop meter under the field.
const CHECKLIST_H := 116.0
const HEADER_H := 34.0

## Half-angle the cone field spans edge to edge. Wider than the collect cone so
## a piece that's off-target still shows up on the field (and which way to turn)
## instead of pinning to the rim immediately.
const FIELD_SPAN_DEG := 90.0
## Screen pixels per m/s of lateral relative drift on the drift arrow.
const DRIFT_PX_PER_MS := 26.0
const DRIFT_MAX_PX := 46.0

const GOOD := Color(0.45, 1.0, 0.55)
const WARN := Color(1.0, 0.62, 0.25)

var _hatch: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var footer := HBoxContainer.new()
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -(FOOTER_H - 8.0)
	footer.offset_left = 8
	footer.offset_right = -8
	footer.offset_bottom = -8
	footer.add_theme_constant_override("separation", 8)
	add_child(footer)

	_hatch = ButtonTheme.make_button(accent)
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
	var piece := DriftSystem.nearest_piece()
	if piece.is_empty():
		var mid := (size.y - FOOTER_H) / 2.0
		draw_string(font, Vector2(0, mid), "NO SALVAGE ADRIFT",
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(accent, 0.6))
		draw_string(font, Vector2(0, mid + 24), "CUT A MEMBER FREE TO COLLECT IT",
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(accent, 0.4))
		return

	var st := DriftSystem.collection_status(piece)
	draw_string(font, Vector2(8, 22), "SCOOP — %s" % st["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, accent)
	draw_string(font, Vector2(-8, 22), "%d M" % roundi(st["range"]),
			HORIZONTAL_ALIGNMENT_RIGHT, size.x, 16, accent)

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
		_draw_arrowhead(center + dir * field, dir, 11.0, WARN)
	else:
		var mark_col: Color = GOOD if st["gated"] else (
				cone_col if st["in_cone"] else Color(1.0, 0.7, 0.25))
		_draw_diamond(marker, 9.0, mark_col, 2.0)
		# Which way it's sliding relative to us — thrust along this to null it.
		var drift: Vector2 = st["rel_lateral"]
		if drift.length() > 0.05:
			var arrow: Vector2 = drift.normalized() * minf(
					drift.length() * DRIFT_PX_PER_MS, DRIFT_MAX_PX)
			draw_line(marker, marker + arrow, Color(1.0, 0.9, 0.4, 0.9), 1.5)
			_draw_arrowhead(marker + arrow, arrow.normalized(), 6.0, Color(1.0, 0.9, 0.4, 0.9))
		if float(st["scoop"]) > 0.0:
			draw_arc(marker, 15.0, -PI / 2.0, -PI / 2.0 + TAU * float(st["scoop"]),
					36, GOOD, 2.5, true)

	# --- Gate checklist -----------------------------------------------------
	var y := center.y + field + 18.0
	_draw_gate(font, y, "HATCH", "OPEN" if st["hatch"] else "SECURED", st["hatch"])
	_draw_gate(font, y + 18.0, "RANGE", "%.1f / %.1f M" % [
		maxf(float(st["gap"]), 0.0), DriftSystem.SCOOP_RANGE], st["in_range"])
	_draw_gate(font, y + 36.0, "REL SPD", "%.2f / %.2f M/S" % [
		st["rel_speed"], DriftSystem.COLLECT_REL_SPEED], st["speed_ok"])
	_draw_gate(font, y + 54.0, "CONE", "%d° / %d°" % [
		roundi(float(st["off_axis"])), roundi(DriftSystem.COLLECT_CONE_DEG)], st["in_cone"])

	# Closure rate is context, not a gate — it tells you whether the range gate
	# is about to open on you while you fight the other three.
	var closure: float = st["closure"]
	draw_string(font, Vector2(8, y + 74.0), "%s %.2f M/S" % [
		"CLOSING" if closure > 0.0 else "OPENING", absf(closure)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(accent, 0.65))

	_draw_meter(font, Vector2(8, y + 82.0), size.x - 16.0, "SCOOP",
			float(st["scoop"]), GOOD if st["gated"] else Color(accent, 0.6))


## One checklist row: name, live value against its limit, and a pass mark.
func _draw_gate(font: Font, y: float, label: String, value: String, ok: bool) -> void:
	var col := GOOD if ok else WARN
	draw_string(font, Vector2(8, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(accent, 0.75))
	draw_string(font, Vector2(84, y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	draw_string(font, Vector2(-8, y), "OK" if ok else "✗", HORIZONTAL_ALIGNMENT_RIGHT,
			size.x, 12, col)


## A labelled 0..1 bar: label on the left, filled track on the right (matches
## the ALIGN page's meters).
func _draw_meter(font: Font, pos: Vector2, width: float, label: String,
		value: float, color: Color) -> void:
	draw_string(font, pos + Vector2(0, 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
	var track_x := pos.x + 52.0
	var track_w := width - 52.0
	var track := Rect2(track_x, pos.y + 2.0, track_w, 12.0)
	draw_rect(track, Color(color, 0.12), true)
	draw_rect(Rect2(track_x, pos.y + 2.0, track_w * clampf(value, 0.0, 1.0), 12.0), color, true)
	draw_rect(track, Color(color, 0.5), false, 1.0)


func _draw_diamond(c: Vector2, r: float, color: Color, width: float) -> void:
	draw_polyline(PackedVector2Array([
			c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r),
			c + Vector2(-r, 0), c + Vector2(0, -r)]), color, width, true)


func _draw_arrowhead(tip: Vector2, dir: Vector2, r: float, color: Color) -> void:
	var d := dir.normalized()
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([
			tip, tip - d * r * 1.7 + n * r * 0.8, tip - d * r * 1.7 - n * r * 0.8]), color)
