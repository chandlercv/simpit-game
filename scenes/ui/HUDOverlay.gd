extends Control
## Thin HUD overlaid on the hull-camera feed — reads as markings on a camera
## feed, not dashboard chrome. Rule of thumb (plan Phase 2): if it's tied to
## what's currently in the camera's view it can live here; omnidirectional or
## historical readouts (full radar sweep, complete contact list, risk-over-time)
## belong on the Tactical window.
##
## Draws: nose reticle (marks where the hull points, slides off-centre while
## glancing), velocity-vector brackets (direction of travel), velocity/heading
## readout, lock brackets + distance on the tracked contact when it's in frame,
## pulsing threat brackets + proximity warning for threat contacts in frame.
## Contacts behind the camera or outside the frame draw nothing — that's
## Tactical's job.

## Set by MainViewWindow.gd at runtime (a .tscn NodePath can't reach inside the
## instanced world scene). Unprojected coordinates match this Control 1:1
## because the SubViewportContainer stretches the SubViewport to window size.
var camera: Camera3D

const HUD_COLOR := Color(0.75, 0.88, 0.95, 0.85)
const THREAT_COLOR := Color(1.0, 0.35, 0.25, 0.9)

## Threat contacts closer than this (meters) get the proximity warning.
const PROXIMITY_RANGE := 25.0

## Keeps the nose reticle / velocity marker off the very edge when clamped.
const EDGE_MARGIN := 24.0

## At/below this speed the ship is effectively stationary; hide the resting marker.
const VEL_EPSILON := 0.05

## Drift-marker sensitivity: screen offset per (m/s) of lateral velocity, as a
## fraction of viewport height. At 0.04, ~10 m/s of drift pushes the brackets
## ~40% of the way to the screen edge before the margin clamp catches them.
const VEL_MARKER_SCALE := 0.04

var _time := 0.0

@onready var _vel_label: Label = %VelLabel
@onready var _hdg_label: Label = %HdgLabel
@onready var _tgt_label: Label = %TargetLabel


func _ready() -> void:
	for label in [_vel_label, _hdg_label, _tgt_label]:
		label.add_theme_color_override("font_color", HUD_COLOR)
	GameState.tick_changed.connect(_on_tick_changed)
	_update_readouts()


## The readout labels only need shared-tick resolution; the brackets drawn in
## _draw() need every frame since their screen position tracks the camera,
## which keeps moving between ticks.
func _on_tick_changed(_tick: int) -> void:
	_update_readouts()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _update_readouts() -> void:
	var ship: Dictionary = GameState.local_ship()
	var velocity: Vector3 = ship.get("velocity", Vector3.ZERO)
	var vel_text := "VEL %5.1f M/S" % velocity.length()
	if GameState.approach_state != "HOLDING":
		vel_text += "  — %s" % GameState.approach_state
	_vel_label.text = vel_text
	if camera == null:
		return
	var fwd := -camera.global_transform.basis.z
	var azimuth := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	var elevation := rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
	_hdg_label.text = "HDG %03d  EL %+03d" % [roundi(azimuth), roundi(elevation)]
	var tracked := GameState.get_contact(GameState.tracked_contact_id)
	if tracked.is_empty():
		_tgt_label.text = ""
	else:
		var dist := camera.global_position.distance_to(tracked["position"])
		_tgt_label.text = "TGT %s — %d M" % [tracked["name"], roundi(dist)]


func _draw() -> void:
	_draw_reticle()
	_draw_velocity_vector()
	_draw_ops_state()
	if camera == null:
		return
	var frame := Rect2(Vector2.ZERO, size)
	var font := ThemeDB.fallback_font
	for contact in GameState.contacts:
		var pos: Vector3 = contact["position"]
		# Contextual only: nothing is drawn for contacts out of frame.
		if camera.is_position_behind(pos):
			continue
		var screen_pos := camera.unproject_position(pos)
		if not frame.has_point(screen_pos):
			continue
		var is_tracked: bool = contact["id"] == GameState.tracked_contact_id
		var is_threat: bool = contact["threat"]
		var color := THREAT_COLOR if is_threat else HUD_COLOR
		if is_threat:
			color.a = 0.55 + 0.45 * sin(_time * TAU * 1.5)
		var radius := 28.0 if is_tracked else 18.0
		var width := 2.0 if is_tracked else 1.2
		_draw_corner_brackets(screen_pos, radius, color, width)
		var dist := camera.global_position.distance_to(pos)
		var label: String = contact["name"]
		if is_tracked:
			label += "  %d M" % roundi(dist)
		draw_string(font, screen_pos + Vector2(-radius, radius + 18), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		if is_threat and dist < PROXIMITY_RANGE:
			draw_string(font, screen_pos + Vector2(-radius, -radius - 10),
					"PROXIMITY", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)


## Camera-feed-tied ops readouts: cutter progress while the torch is live,
## and a phase banner when the feed isn't showing the claim at all.
func _draw_ops_state() -> void:
	var font := ThemeDB.fallback_font
	var c := size / 2.0
	if GameState.run_phase != "ON_SITE":
		var banner := "IN TRANSIT" if GameState.run_phase == "TRANSIT" \
				else "DOCKED — %s" % GameState.market_factions[GameState.docked_faction]
		draw_string(font, Vector2(0, c.y + 70), banner,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, HUD_COLOR)
		return
	var cutting_id: int = GameState.wreck.get("cutting_id", -1)
	if cutting_id != -1:
		var member := GameState.get_member(cutting_id)
		draw_string(font, Vector2(0, c.y + 70),
				"CUTTING %s — %d%%" % [member["name"],
					roundi(GameState.wreck["cut_progress"] * 100.0)],
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, THREAT_COLOR)


## Screen point for a world-space direction from the camera eyepoint, clamped
## into the frame (minus a margin) so out-of-fov directions pin to the nearest
## edge. Returns null when the direction is behind the camera.
func _project_direction(dir: Vector3) -> Variant:
	var world_point := camera.global_position + dir.normalized() * 1000.0
	if camera.is_position_behind(world_point):
		return null
	var p := camera.unproject_position(world_point)
	return p.clamp(Vector2(EDGE_MARGIN, EDGE_MARGIN), size - Vector2(EDGE_MARGIN, EDGE_MARGIN))


## The nose reticle, and the drift marker's anchor, both live here: the ship's
## *nose* projected to screen (glance rotates only the camera gimbal, so the nose
## slides off-centre as you look around). Falls back to screen centre when the
## nose is behind the camera or the camera isn't wired up yet.
func _nose_center() -> Vector2:
	if camera == null:
		return size / 2.0
	var xform: Transform3D = GameState.local_ship()["transform"]
	var p = _project_direction(-xform.basis.z)
	return p if p != null else size / 2.0


## The reticle marks the ship's *nose*, not the view centre: glance rotates only
## the camera gimbal, so the nose slides off-centre as you look around. At rest
## (no glance) the nose projects to screen centre, matching the old fixed glyph.
func _draw_reticle() -> void:
	var c := _nose_center()
	draw_arc(c, 14.0, 0.0, TAU, 48, HUD_COLOR, 1.5, true)
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + dir * 22.0, c + dir * 34.0, HUD_COLOR, 1.5)


## Drift marker: a pair of vertical brackets [ ] offset from the nose reticle by
## the ship's *lateral* velocity — the component perpendicular to the nose;
## forward speed shows in the VEL readout, not here. The offset scales with drift
## *magnitude* (not just direction), so the brackets rest on the reticle when you
## fly straight and slide smoothly back onto it as you counter-thrust to null,
## instead of pinning to the screen edge the moment travel goes off-axis.
func _draw_velocity_vector() -> void:
	if camera == null:
		return
	var vel: Vector3 = GameState.local_ship().get("velocity", Vector3.ZERO)
	if vel.length() < VEL_EPSILON:
		return
	var nose := -(GameState.local_ship()["transform"] as Transform3D).basis.z
	var drift := vel - nose * vel.dot(nose)
	var cam_basis := camera.global_transform.basis
	var px_per_ms := size.y * VEL_MARKER_SCALE
	var offset := Vector2(drift.dot(cam_basis.x), -drift.dot(cam_basis.y)) * px_per_ms
	var center := (_nose_center() + offset).clamp(
			Vector2(EDGE_MARGIN, EDGE_MARGIN), size - Vector2(EDGE_MARGIN, EDGE_MARGIN))
	_draw_flanking_brackets(center, 18.0, HUD_COLOR, 1.5)


func _draw_flanking_brackets(center: Vector2, r: float, color: Color, width: float) -> void:
	var arm := r * 0.5
	for s: float in [-1.0, 1.0]:
		var x := center.x + s * r
		var top := Vector2(x, center.y - r)
		var bot := Vector2(x, center.y + r)
		draw_line(top, bot, color, width)  # spine
		draw_line(top, top + Vector2(-s * arm, 0), color, width)  # top serif (toward center)
		draw_line(bot, bot + Vector2(-s * arm, 0), color, width)  # bottom serif


func _draw_corner_brackets(center: Vector2, r: float, color: Color, width: float) -> void:
	var arm := r * 0.45
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var p := center + corner * r
		draw_line(p, p + Vector2(-corner.x * arm, 0), color, width)
		draw_line(p, p + Vector2(0, -corner.y * arm), color, width)
