extends Control
## MFD ALIGN page: the pre-cut alignment mini-game's dedicated precision
## instrument. A large 2-axis crosshair — steer the reticle (aimed with the flight
## pitch/yaw axes while ALIGNING) onto the drifting seam target and hold it inside
## the tolerance ring to fill the lock; the captured quality drives the cut's
## speed, structural-risk spike, and yield. Touch COMMIT banks the current lock;
## CANCEL bails. Read-only view of GameState.align — the buttons call the same
## SalvageSystem intents the cutter trigger does (see SalvageSystem.request_cut /
## cancel_align).

const ButtonTheme := preload("res://scenes/ui/ButtonTheme.gd")
const Instrument := preload("res://scenes/ui/Instrument.gd")

@export var accent: Color = Color(0.3, 0.9, 0.78)

## Reserve for the footer button row so the crosshair field never overlaps it.
const FOOTER_H := 76.0
## Reserve above the field for the page header.
const HEADER_H := 52.0
## Meter labels, for measuring the track inset off the widest of them.
const METER_LABELS: PackedStringArray = ["LOCK", "SLIP"]

var _commit: Button
var _cancel: Button
var _time := 0.0


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

	_commit = ButtonTheme.make_touch_button(accent)
	_commit.text = "COMMIT"
	_commit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commit.pressed.connect(SalvageSystem.request_cut)
	footer.add_child(_commit)

	_cancel = ButtonTheme.make_touch_button(Color(1.0, 0.5, 0.3))
	_cancel.text = "CANCEL"
	_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel.pressed.connect(SalvageSystem.cancel_align)
	footer.add_child(_cancel)

	GameState.align_changed.connect(func(_s: String) -> void: _refresh())
	GameState.tick_changed.connect(func(_t: int) -> void: _refresh())
	_refresh()


func _process(delta: float) -> void:
	# The crosshair drifts every frame, so animate only while the game is live.
	if GameState.align_state == "ALIGNING":
		_time += delta
		queue_redraw()


func _refresh() -> void:
	var aligning := GameState.align_state == "ALIGNING"
	_commit.disabled = not aligning
	_cancel.disabled = not aligning
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var mid_y := (size.y - FOOTER_H) / 2.0
	if GameState.align_state != "ALIGNING" or GameState.align.is_empty():
		Instrument.draw_notice(self, font, "NO ALIGNMENT ACTIVE",
				"FIRE THE CUTTER FROM A MATCHED TARGET", accent, FOOTER_H)
		return

	var align: Dictionary = GameState.align
	var lock := float(align["lock"])
	var slip := float(align["slip"])
	var quality := float(align["quality"])
	var member := GameState.get_member(GameState.selected_member_id)

	# Header.
	draw_string(font, Vector2(8, 26), "ALIGN — %s" % member.get("name", "TARGET"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, Instrument.HEADING, accent)

	var center := Vector2(size.x / 2.0, mid_y)
	var field: float = maxf(minf(size.x, size.y - FOOTER_H - HEADER_H) * 0.42, 24.0)
	var tol: float = SalvageSystem.ALIGN_LOCK_RADIUS * field
	var target := center + Vector2(align["target"]) * field
	var reticle := center + Vector2(align["reticle"]) * field
	var err: float = Vector2(align["reticle"]).distance_to(align["target"])
	var on: bool = err <= SalvageSystem.ALIGN_LOCK_RADIUS

	# Field boundary + crosshair guides + lock-progress ring.
	draw_arc(center, field, 0.0, TAU, 72, Color(accent, 0.28), 1.0, true)
	draw_line(center - Vector2(field, 0), center + Vector2(field, 0), Color(accent, 0.15), 1.0)
	draw_line(center - Vector2(0, field), center + Vector2(0, field), Color(accent, 0.15), 1.0)
	if lock > 0.0:
		draw_arc(center, field, -PI / 2.0, -PI / 2.0 + TAU * lock, 72,
				Color(accent, 0.95), 3.0, true)

	# Seam target ⊕ + tolerance ring (greens up while the reticle is inside).
	var tgt_col := Color(0.45, 1.0, 0.55, 0.9) if on else Color(accent, 0.85)
	draw_arc(target, tol, 0.0, TAU, 40, tgt_col, 1.5, true)
	draw_line(target - Vector2(11, 0), target + Vector2(11, 0), tgt_col, 1.5)
	draw_line(target - Vector2(0, 11), target + Vector2(0, 11), tgt_col, 1.5)

	# Pilot reticle ✛ (rotated cross).
	var rc := Color(1.0, 0.9, 0.4, 0.95)
	for d: Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(reticle - d * 10.0, reticle + d * 10.0, rc, 2.0)

	# Meters + quality readout under the field.
	var bar_y := center.y + field + 16.0
	var pitch := Instrument.METER_PITCH
	var label_w := Instrument.label_column(font, METER_LABELS)
	Instrument.draw_meter(self, font, Vector2(8, bar_y), size.x - 16.0, "LOCK",
			lock, accent, label_w)
	var slip_col := Color(1.0, 0.4, 0.25) if slip > 0.35 else Color(accent, 0.7)
	Instrument.draw_meter(self, font, Vector2(8, bar_y + pitch), size.x - 16.0,
			"SLIP", slip, slip_col, label_w)
	draw_string(font, Vector2(8, bar_y + pitch * 2.0 + 4.0),
			"QUALITY %d%%" % roundi(quality * 100.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, Instrument.ROW, accent)
