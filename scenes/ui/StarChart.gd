extends Control
## Schematic system chart for the Chart display. Deliberately an abstract 2D
## plot, not a to-scale 3D scene (plan "World-scale navigation — precision
## guardrail"): orbital radii are sqrt-compressed so the inner system stays
## readable next to the outer dwarfs, and all math is plain float. Mouse
## driven: left-drag pans, wheel zooms about the cursor.
##
## Bodies/names are placeholders matching simpit-world.md's structure (K-dwarf
## primary, gas giants with moon L1 necklaces, an eccentric binary dwarf pair
## with a marked empty focus) until the real nav data model lands.

@export var accent: Color = Color(0.45, 0.7, 1.0)

const STAR_NAME := "HEARTH (K2V)"
const BODIES := [
	{"name": "CINDER", "kind": "rocky", "au": 0.18},
	{"name": "BASTION", "kind": "rocky", "au": 0.34},
	{"name": "VERGE", "kind": "rocky", "au": 0.52},
	{"name": "THALASSA", "kind": "giant", "au": 0.95, "moons": ["KERUL", "HAVEN", "LOWLIGHT"]},
	{"name": "PALINODE", "kind": "giant", "au": 1.60, "moons": ["TARSA", "GREYWATER"]},
]
## Binary dwarf pair on an eccentric orbit; the empty second focus is a real
## frontier nav marker in the world doc.
const DWARF := {"name": "COLDHARBOR A/B", "au": 3.2, "eccentricity": 0.45}

## Where the own-ship marker sits until a nav system exists.
const SHIP_AT := {"giant": "THALASSA", "moon": "HAVEN"}

const UNIT_PX := 220.0
const MOON_ORBIT_BASE := 0.16
const MOON_ORBIT_STEP := 0.09

var _zoom := 1.0
var _pan := Vector2.ZERO
var _dragging := false
var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_about(event.position, 1.15)
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_about(event.position, 1.0 / 1.15)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_pan += event.relative
		accept_event()


func _zoom_about(pointer: Vector2, factor: float) -> void:
	var new_zoom := clampf(_zoom * factor, 0.3, 8.0)
	factor = new_zoom / _zoom
	# Keep the chart point under the cursor fixed while zooming.
	var rel := pointer - size / 2.0
	_pan = rel - (rel - _pan) * factor
	_zoom = new_zoom


## Chart units (sqrt-compressed AU) -> screen pixels.
func _to_screen(p: Vector2) -> Vector2:
	return size / 2.0 + _pan + p * UNIT_PX * _zoom


## Orbit radius in chart units for a body at the given AU.
func _orbit_r(au: float) -> float:
	return sqrt(au)


## Deterministic "snapshot" angle so the layout is stable run to run.
func _body_angle(seed_text: String) -> float:
	return float(hash(seed_text) % 6283) / 1000.0


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var dim := Color(accent, 0.25)
	var mid := Color(accent, 0.6)
	var star_pos := _to_screen(Vector2.ZERO)
	var star_color := Color(1.0, 0.75, 0.5)

	draw_circle(star_pos, 7.0 * _zoom, star_color)
	draw_string(font, star_pos + Vector2(-60, 22 + 7.0 * _zoom), STAR_NAME,
			HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(star_color, 0.85))

	for body: Dictionary in BODIES:
		var orbit_r: float = _orbit_r(body["au"])
		draw_arc(star_pos, orbit_r * UNIT_PX * _zoom, 0.0, TAU, 128, dim, 1.0, true)
		var pos := _to_screen(Vector2.from_angle(_body_angle(body["name"])) * orbit_r)
		var is_giant: bool = body["kind"] == "giant"
		draw_circle(pos, (5.0 if is_giant else 3.0) * _zoom, mid)
		draw_string(font, pos + Vector2(-60, -10.0 - 4.0 * _zoom), body["name"],
				HORIZONTAL_ALIGNMENT_CENTER, 120, 12, accent)
		if is_giant:
			_draw_moons(body, pos, font)

	_draw_dwarf_pair(star_pos, font)

	draw_string(font, Vector2(8, 20), "SYSTEM SCHEMATIC — DRAG PAN · WHEEL ZOOM",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, accent)
	draw_string(font, Vector2(8, size.y - 10),
			"<> L1 NECKLACE NODE    + EMPTY FOCUS    ^ OWN SHIP",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, mid)


func _draw_moons(giant: Dictionary, giant_pos: Vector2, font: Font) -> void:
	var dim := Color(accent, 0.3)
	var moons: Array = giant["moons"]
	var moon_positions: Array[Vector2] = []
	for i in moons.size():
		var orbit_px := (MOON_ORBIT_BASE + MOON_ORBIT_STEP * i) * UNIT_PX * _zoom
		draw_arc(giant_pos, orbit_px, 0.0, TAU, 64, dim, 1.0, true)
		var ang := _body_angle(moons[i]) + TAU * float(i) / moons.size()
		var pos := giant_pos + Vector2.from_angle(ang) * orbit_px
		moon_positions.append(pos)
		draw_circle(pos, 2.5 * _zoom, accent)
		draw_string(font, pos + Vector2(-50, 16), moons[i],
				HORIZONTAL_ALIGNMENT_CENTER, 100, 11, Color(accent, 0.8))
		if giant["name"] == SHIP_AT["giant"] and moons[i] == SHIP_AT["moon"]:
			_draw_ship_marker(pos, font)
	# L1 necklace nodes between adjacent moons of the same giant.
	for i in moon_positions.size() - 1:
		var node := moon_positions[i].lerp(moon_positions[i + 1], 0.5)
		_draw_diamond(node, 5.0, Color(0.5, 1.0, 0.7, 0.9))


func _draw_dwarf_pair(star_pos: Vector2, font: Font) -> void:
	var dim := Color(accent, 0.25)
	var a := _orbit_r(DWARF["au"])
	var e: float = DWARF["eccentricity"]
	# Ellipse with the star at one focus, apsis line along +x.
	var points := PackedVector2Array()
	for i in 129:
		var theta := TAU * float(i) / 128.0
		var r := a * (1.0 - e * e) / (1.0 + e * cos(theta))
		points.append(_to_screen(Vector2.from_angle(theta) * r))
	draw_polyline(points, dim, 1.0, true)
	var body_pos := _to_screen(
			Vector2.from_angle(2.4) * a * (1.0 - e * e) / (1.0 + e * cos(2.4)))
	draw_circle(body_pos, 3.0 * _zoom, Color(accent, 0.7))
	draw_circle(body_pos + Vector2(6, -4) * _zoom, 2.0 * _zoom, Color(accent, 0.7))
	draw_string(font, body_pos + Vector2(-70, 18), DWARF["name"],
			HORIZONTAL_ALIGNMENT_CENTER, 140, 11, Color(accent, 0.7))
	# The geometrically real, massless second focus — frontier route marker.
	var focus := _to_screen(Vector2(-2.0 * a * e, 0.0))
	draw_line(focus - Vector2(6, 0), focus + Vector2(6, 0), Color(0.5, 1.0, 0.7, 0.9), 1.5)
	draw_line(focus - Vector2(0, 6), focus + Vector2(0, 6), Color(0.5, 1.0, 0.7, 0.9), 1.5)
	draw_string(font, focus + Vector2(-60, 20), "EMPTY FOCUS",
			HORIZONTAL_ALIGNMENT_CENTER, 120, 10, Color(0.5, 1.0, 0.7, 0.7))


func _draw_ship_marker(pos: Vector2, font: Font) -> void:
	var pulse := 0.5 + 0.5 * sin(_time * TAU * 0.8)
	var color := Color(1.0, 0.9, 0.4)
	draw_arc(pos, 9.0 + 3.0 * pulse, 0.0, TAU, 32, Color(color, 0.8 - 0.4 * pulse), 1.5, true)
	draw_string(font, pos + Vector2(-50, -14), "OWN SHIP",
			HORIZONTAL_ALIGNMENT_CENTER, 100, 11, color)


func _draw_diamond(pos: Vector2, r: float, color: Color) -> void:
	var pts: PackedVector2Array = [
		pos + Vector2(0, -r), pos + Vector2(r, 0), pos + Vector2(0, r), pos + Vector2(-r, 0)]
	draw_colored_polygon(pts, color)
