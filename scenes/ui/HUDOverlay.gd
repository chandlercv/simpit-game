extends Control
## Thin HUD overlaid on the hull-camera feed — reads as markings on a camera
## feed, not dashboard chrome. Rule of thumb (plan Phase 2): if it's tied to
## what's currently in the camera's view it can live here; omnidirectional or
## historical readouts (full radar sweep, complete contact list, risk-over-time)
## belong on the Tactical window.
##
## Draws: center reticle, velocity/heading readout, lock brackets + distance on
## the tracked contact when it's in frame, pulsing threat brackets + proximity
## warning for threat contacts in frame. Contacts behind the camera or outside
## the frame draw nothing — that's Tactical's job.

## Set by MainViewWindow.gd at runtime (a .tscn NodePath can't reach inside the
## instanced world scene). Unprojected coordinates match this Control 1:1
## because the SubViewportContainer stretches the SubViewport to window size.
var camera: Camera3D

const HUD_COLOR := Color(0.75, 0.88, 0.95, 0.85)
const THREAT_COLOR := Color(1.0, 0.35, 0.25, 0.9)

## Threat contacts closer than this (meters) get the proximity warning.
const PROXIMITY_RANGE := 25.0

var _time := 0.0

@onready var _vel_label: Label = %VelLabel
@onready var _hdg_label: Label = %HdgLabel
@onready var _tgt_label: Label = %TargetLabel


func _ready() -> void:
	for label in [_vel_label, _hdg_label, _tgt_label]:
		label.add_theme_color_override("font_color", HUD_COLOR)


func _process(delta: float) -> void:
	_time += delta
	_update_readouts()
	queue_redraw()


func _update_readouts() -> void:
	var ship: Dictionary = GameState.ships[GameState.LOCAL_PEER_ID]
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


func _draw_reticle() -> void:
	var c := size / 2.0
	draw_arc(c, 14.0, 0.0, TAU, 48, HUD_COLOR, 1.5, true)
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + dir * 22.0, c + dir * 34.0, HUD_COLOR, 1.5)


func _draw_corner_brackets(center: Vector2, r: float, color: Color, width: float) -> void:
	var arm := r * 0.45
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var p := center + corner * r
		draw_line(p, p + Vector2(-corner.x * arm, 0), color, width)
		draw_line(p, p + Vector2(0, -corner.y * arm), color, width)
