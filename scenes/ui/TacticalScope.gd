extends Control
## Radar/sensor scope for the Tactical display: rotating sweep, range rings,
## contact blips plotted around own ship on the XZ plane. This is the
## omnidirectional view the main HUD deliberately does not duplicate (plan
## Phase 2 rule of thumb). Mouse-driven — the Surface Go is treated as
## non-touch — click a blip to lock it.
##
## In STRUCT mode this becomes the wreck's structural map (plan Phase 4):
## once a scan has resolved the graph, members are plotted with their frame
## load, cut state, and predicted risk spike — click one to select it as the
## cut target. Choosing where to cut is a read-the-wreck decision, so the
## information that drives it lives here, not on a numeric meter.

@export var accent: Color = Color(1.0, 0.72, 0.2)

## Scope range (meters) and sweep speed (revolutions/second) per sensor mode.
const RANGE_BY_MODE := {"PASSIVE": 600.0, "ACTIVE": 250.0, "STRUCT": 250.0}
const SWEEP_HZ_BY_MODE := {"PASSIVE": 0.2, "ACTIVE": 0.5, "STRUCT": 0.35}

const CLICK_RADIUS := 24.0
const SWEEP_TRAIL_STEPS := 36

const LOAD_HIGH_COLOR := Color(1.0, 0.42, 0.15)
const CUT_COLOR := Color(0.45, 0.32, 0.1)

var _sweep := 0.0
var _time := 0.0


func _ready() -> void:
	GameState.sensor_mode_changed.connect(func(_mode: String) -> void: queue_redraw())
	GameState.tracked_contact_changed.connect(func(_id: int) -> void: queue_redraw())
	GameState.wreck_scanned.connect(queue_redraw)
	GameState.wreck_member_cut.connect(func(_id: int) -> void: queue_redraw())
	GameState.wreck_members_lost.connect(queue_redraw)
	GameState.selected_member_changed.connect(func(_id: int) -> void: queue_redraw())
	GameState.site_reset.connect(queue_redraw)
	GameState.power_changed.connect(queue_redraw)
	GameState.tick_changed.connect(_on_tick_changed)


## STRUCT mode has no continuous animation of its own (no sweep) — its
## progress arcs and selection pulse only need the shared 10Hz tick, not a
## full 60fps redraw + O(links x members) rebuild every physics frame.
func _on_tick_changed(_tick: int) -> void:
	if GameState.sensor_mode != "STRUCT":
		return
	_time += 1.0 / GameState.TICK_RATE_HZ
	queue_redraw()


func _process(delta: float) -> void:
	if GameState.sensor_mode == "STRUCT":
		return
	_time += delta
	var hz: float = SWEEP_HZ_BY_MODE[GameState.sensor_mode]
	_sweep = fposmod(_sweep + TAU * hz * delta, TAU)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _struct_overlay_active():
		for member: Dictionary in GameState.wreck["members"]:
			if _member_pos(member).distance_to(event.position) <= CLICK_RADIUS:
				SalvageSystem.select_member(member["id"])
				accept_event()
				return
		return
	for blip in _blips():
		if blip["pos"].distance_to(event.position) <= CLICK_RADIUS:
			GameState.set_tracked_contact(blip["contact"]["id"])
			accept_event()
			return


func _struct_overlay_active() -> bool:
	return GameState.sensor_mode == "STRUCT" and GameState.wreck.get("scanned", false)


func _scope_center() -> Vector2:
	return size / 2.0


func _scope_radius() -> float:
	return minf(size.x, size.y) / 2.0 - 22.0


## Contacts within range, mapped to scope pixels in ship-relative XZ: own ship
## stays centered with -Z (forward) up, and the world rotates around it as the
## ship yaws.
func _blips() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var scope_range: float = RANGE_BY_MODE[GameState.sensor_mode]
	var ship_xform: Transform3D = GameState.local_ship()["transform"]
	var c := _scope_center()
	var r := _scope_radius()
	for contact in GameState.contacts:
		var local: Vector3 = ship_xform.affine_inverse() * (contact["position"] as Vector3)
		var planar := Vector2(local.x, local.z)
		if planar.length() > scope_range:
			continue
		out.append({"contact": contact, "pos": c + planar * (r / scope_range)})
	return out


## Structural-map screen position for a member (schematic coords, fore = up).
func _member_pos(member: Dictionary) -> Vector2:
	return _scope_center() + Vector2(member["sx"], member["sy"]) * _scope_radius() * 0.78


func _draw() -> void:
	if GameState.sensor_mode == "STRUCT":
		_draw_struct(ThemeDB.fallback_font)
		return
	_draw_radar(ThemeDB.fallback_font)


func _draw_radar(font: Font) -> void:
	var c := _scope_center()
	var r := _scope_radius()
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


func _draw_struct(font: Font) -> void:
	var c := _scope_center()
	var r := _scope_radius()
	var dim := Color(accent, 0.28)
	var mid := Color(accent, 0.55)
	var wreck: Dictionary = GameState.wreck

	draw_arc(c, r, 0.0, TAU, 96, dim, 1.0, true)
	draw_string(font, Vector2(8, 20),
			"STRUCTURAL MAP — WRECK RNG %d M" % roundi(SalvageSystem.wreck_distance()),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, accent)

	if not wreck.get("scanned", false):
		var progress: float = wreck.get("scan_progress", 0.0)
		var scanning := progress > 0.0
		draw_string(font, Vector2(0, c.y - 12),
				"STRUCTURAL SCAN %d%%" % roundi(progress * 100.0) if scanning
				else "NO STRUCTURAL DATA — HOLD STRUCT MODE TO SCAN",
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, mid)
		if scanning:
			draw_arc(c, r * 0.5, -PI / 2.0, -PI / 2.0 + TAU * progress, 64, accent, 2.0, true)
		if GameState.power("SENSORS") < 0.1:
			draw_string(font, Vector2(0, c.y + 16),
					"SENSORS UNPOWERED — RAISE ALLOCATION ON TABLET",
					HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, LOAD_HIGH_COLOR)
		return

	# Frame links first, so member markers draw over them.
	for member: Dictionary in wreck["members"]:
		for other_id: int in member["links"]:
			if other_id < member["id"]:
				continue
			var other := GameState.get_member(other_id)
			var severed: bool = member["cut"] or member["destroyed"] \
					or other["cut"] or other["destroyed"]
			draw_line(_member_pos(member), _member_pos(other),
					Color(CUT_COLOR, 0.6) if severed else mid, 1.0 if severed else 2.0)

	for member: Dictionary in wreck["members"]:
		_draw_member(member, font)

	var selected := GameState.get_member(GameState.selected_member_id)
	var info := "CLICK A MEMBER TO SELECT CUT POINT"
	if not selected.is_empty():
		var good: GoodDefinition = MarketSystem.good(selected["good"])
		info = "%s — LOAD %s — EST RISK +%d%% — YIELD %.1f %s %s" % [
			selected["name"], SalvageSystem.load_class(selected),
			roundi(SalvageSystem.predicted_spike(selected) * 100.0),
			selected["qty"], good.unit, selected["good"]]
	draw_string(font, Vector2(0, size.y - 8), info,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, accent)


func _draw_member(member: Dictionary, font: Font) -> void:
	var pos := _member_pos(member)
	var gone: bool = member["cut"] or member["destroyed"]
	var load_bearing: float = member["load"]
	var color := CUT_COLOR if gone \
			else Color(accent, 0.55).lerp(LOAD_HIGH_COLOR, clampf(load_bearing, 0.0, 1.0))
	# Marker size scales with frame load: big node = load-bearing spar.
	var marker_r := 5.0 + 7.0 * load_bearing
	draw_circle(pos, marker_r, Color(color, 0.35))
	draw_arc(pos, marker_r, 0.0, TAU, 32, color, 1.5, true)
	if gone:
		draw_line(pos - Vector2(marker_r, marker_r), pos + Vector2(marker_r, marker_r), color, 1.5)
		draw_line(pos + Vector2(-marker_r, marker_r), pos + Vector2(marker_r, -marker_r), color, 1.5)
	if member["id"] == GameState.selected_member_id:
		var pulse := 0.6 + 0.4 * sin(_time * TAU * 1.2)
		draw_arc(pos, marker_r + 6.0, 0.0, TAU, 32, Color(accent, pulse), 2.0, true)
	if member["id"] == GameState.wreck["cutting_id"]:
		var progress: float = GameState.wreck["cut_progress"]
		draw_arc(pos, marker_r + 6.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 32,
				LOAD_HIGH_COLOR, 2.5, true)
	var label: String = member["name"]
	if member["destroyed"]:
		label += " (LOST)"
	elif member["cut"]:
		label += " (CUT)"
	draw_string(font, pos + Vector2(-60, marker_r + 16), label,
			HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color(color, 0.9))
