extends Control
## Hull integrity heatmap for the tablet: top-down ship silhouette split into
## sections colored by integrity (green → amber → red). Tap a section (touch
## or mouse) for its readout. Values are GameState placeholders until Phase 4
## damage events drive them.

@export var accent: Color = Color(0.3, 0.9, 0.78)

## Unit-space section rects inside a square silhouette area, bow at the top.
const SECTION_LAYOUT := {
	"BOW": Rect2(0.35, 0.02, 0.30, 0.16),
	"PORT": Rect2(0.13, 0.20, 0.20, 0.34),
	"CORE": Rect2(0.35, 0.20, 0.30, 0.34),
	"STBD": Rect2(0.67, 0.20, 0.20, 0.34),
	"AFT": Rect2(0.35, 0.56, 0.30, 0.20),
	"DRIVE": Rect2(0.30, 0.78, 0.40, 0.16),
}

const HEADER_H := 26.0
const FOOTER_H := 26.0

var _selected := ""


func _ready() -> void:
	GameState.hull_sections_changed.connect(queue_redraw)


func _gui_input(event: InputEvent) -> void:
	var touch_tap: bool = event is InputEventScreenTouch and event.pressed
	var click: bool = event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT
	if not (touch_tap or click):
		return
	for section: String in SECTION_LAYOUT:
		if _section_rect(section).has_point(event.position):
			_selected = section
			queue_redraw()
			accept_event()
			return


## Maps a unit-space layout rect into the square silhouette area between the
## header and footer text lines.
func _section_rect(section: String) -> Rect2:
	var area_h := maxf(size.y - HEADER_H - FOOTER_H, 10.0)
	var side := minf(size.x, area_h)
	var origin := Vector2((size.x - side) / 2.0, HEADER_H + (area_h - side) / 2.0)
	var unit: Rect2 = SECTION_LAYOUT[section]
	return Rect2(origin + unit.position * side, unit.size * side)


func _heat(integrity: float) -> Color:
	if integrity < 0.5:
		return Color(0.9, 0.2, 0.15).lerp(Color(1.0, 0.72, 0.2), integrity * 2.0)
	return Color(1.0, 0.72, 0.2).lerp(Color(0.25, 0.85, 0.45), (integrity - 0.5) * 2.0)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var sections: Dictionary = GameState.local_ship()["hull_sections"]
	draw_string(font, Vector2(0, 18), "HULL INTEGRITY",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, accent)
	for section: String in SECTION_LAYOUT:
		var rect := _section_rect(section)
		var integrity: float = sections[section]
		var heat := _heat(integrity)
		var is_selected := section == _selected
		draw_rect(rect, Color(heat, 0.5))
		draw_rect(rect, accent if is_selected else Color(accent, 0.4), false,
				2.0 if is_selected else 1.0)
		draw_string(font, Vector2(rect.position.x, rect.get_center().y - 2),
				section, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 12, Color(1, 1, 1, 0.9))
		draw_string(font, Vector2(rect.position.x, rect.get_center().y + 14),
				"%d%%" % roundi(integrity * 100.0),
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 12, Color(1, 1, 1, 0.7))
	var detail := "TAP A SECTION"
	if _selected != "":
		detail = "%s — INTEGRITY %d%%" % [_selected, roundi(sections[_selected] * 100.0)]
	draw_string(font, Vector2(0, size.y - 8), detail,
			HORIZONTAL_ALIGNMENT_LEFT, size.x, 13, Color(accent, 0.8))
