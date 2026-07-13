extends Control
## Radar/sensor scope for the Tactical display: rotating sweep, range rings,
## contact blips plotted around own ship on the XZ plane. This is the
## omnidirectional view the main HUD deliberately does not duplicate (plan
## Phase 2 rule of thumb). Mouse-driven — the Surface Go is treated as
## non-touch — click a blip to lock it.

@export var accent: Color = Color(1.0, 0.72, 0.2)

## Scope range (meters) and sweep speed (revolutions/second) per sensor mode.
const RANGE_BY_MODE := {"PASSIVE": 600.0, "ACTIVE": 250.0, "STRUCT": 250.0}
const SWEEP_HZ_BY_MODE := {"PASSIVE": 0.2, "ACTIVE": 0.5, "STRUCT": 0.35}

const CLICK_RADIUS := 24.0
const SWEEP_TRAIL_STEPS := 36

var _sweep := 0.0
var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	var hz: float = SWEEP_HZ_BY_MODE[GameState.sensor_mode]
	_sweep = fposmod(_sweep + TAU * hz * delta, TAU)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		for blip in _blips():
			if blip["pos"].distance_to(event.position) <= CLICK_RADIUS:
				GameState.set_tracked_contact(blip["contact"]["id"])
				accept_event()
				return


func _scope_center() -> Vector2:
	return size / 2.0


func _scope_radius() -> float:
	return minf(size.x, size.y) / 2.0 - 22.0


## Contacts within range, mapped to scope pixels. XZ plane, -Z (ship forward)
## is up, matching the HUD's heading convention.
func _blips() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var scope_range: float = RANGE_BY_MODE[GameState.sensor_mode]
	var ship_pos: Vector3 = GameState.ships[GameState.LOCAL_PEER_ID]["transform"].origin
	var c := _scope_center()
	var r := _scope_radius()
	for contact in GameState.contacts:
		var rel: Vector3 = contact["position"] - ship_pos
		var planar := Vector2(rel.x, rel.z)
		if planar.length() > scope_range:
			continue
		out.append({"contact": contact, "pos": c + planar * (r / scope_range)})
	return out


func _draw() -> void:
	var c := _scope_center()
	var r := _scope_radius()
	var font := ThemeDB.fallback_font
	var dim := Color(accent, 0.28)
	var mid := Color(accent, 0.55)

	for i in 3:
		draw_arc(c, r * float(i + 1) / 3.0, 0.0, TAU, 96, dim, 1.0, true)
	for deg in range(0, 360, 30):
		var dir := Vector2.from_angle(deg_to_rad(deg) - PI / 2.0)
		var major := deg % 90 == 0
		draw_line(c + dir * (r - (10.0 if major else 6.0)), c + dir * r, mid, 1.0)
		if major:
			var label := "%03d" % deg
			draw_string(font, c + dir * (r - 26.0) + Vector2(-11, 5), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, mid)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), dim, 1.0)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), dim, 1.0)

	# Sweep with fading trail.
	for i in SWEEP_TRAIL_STEPS:
		var fade := 1.0 - float(i) / SWEEP_TRAIL_STEPS
		var ang := _sweep - float(i) * 0.022
		draw_line(c, c + Vector2.from_angle(ang) * r,
				Color(accent, 0.30 * fade * fade), 2.0 if i == 0 else 1.5)

	# Own ship: chevron at scope center, apex pointing forward (-Z = up).
	var chev: PackedVector2Array = [
		c + Vector2(0, -7), c + Vector2(5, 6), c + Vector2(0, 2), c + Vector2(-5, 6)]
	draw_colored_polygon(chev, accent)

	for blip in _blips():
		var contact: Dictionary = blip["contact"]
		var pos: Vector2 = blip["pos"]
		var is_tracked: bool = contact["id"] == GameState.tracked_contact_id
		var is_threat: bool = contact["threat"]
		var color := accent
		if is_threat:
			color = Color(1.0, 0.42, 0.15, 0.6 + 0.4 * sin(_time * TAU * 1.5))
		if is_threat:
			var tri: PackedVector2Array = [
				pos + Vector2(0, -6), pos + Vector2(5.5, 4.5), pos + Vector2(-5.5, 4.5)]
			draw_colored_polygon(tri, color)
		else:
			draw_rect(Rect2(pos - Vector2(4, 4), Vector2(8, 8)), color)
		if is_tracked:
			draw_arc(pos, 12.0, 0.0, TAU, 32, color, 1.5, true)
		draw_string(font, pos + Vector2(-40, 20), contact["name"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(color, 0.85))

	draw_string(font, Vector2(8, 20),
			"RNG %d M — %s" % [int(RANGE_BY_MODE[GameState.sensor_mode]), GameState.sensor_mode],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, accent)

	if GameState.sensor_mode == "STRUCT":
		# Structural graph overlay arrives with Phase 4's SalvageSystem.
		draw_string(font, Vector2(0, c.y + r * 0.55),
				"STRUCTURAL SCAN — NO WRECK GRAPH IN SCAN RANGE",
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, mid)
