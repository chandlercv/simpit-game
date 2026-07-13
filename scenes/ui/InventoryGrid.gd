extends Control
## Cargo manifest for the tablet — touch-first: tap a tile to select it and
## see its details. Tap-to-select over free-drag per the plan (spacedesk
## ~30fps + latency); tiles answer raw touch and mouse alike since touch
## emulation is off project-wide.

@export var accent: Color = Color(0.3, 0.9, 0.78)

var _selected_id := -1
var _tiles: Array = []

@onready var _header: Label = %Header
@onready var _grid: GridContainer = %Grid
@onready var _detail: Label = %Detail


func _ready() -> void:
	_header.add_theme_font_size_override("font_size", 15)
	_header.add_theme_color_override("font_color", accent)
	_detail.add_theme_color_override("font_color", Color(accent, 0.8))
	GameState.cargo_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for tile in _tiles:
		tile.queue_free()
	_tiles.clear()
	var ship: Dictionary = GameState.ships[GameState.LOCAL_PEER_ID]
	var cargo: Array = ship["cargo"]
	var total_mass := 0.0
	for item: Dictionary in cargo:
		total_mass += item["mass_t"]
		var tile := Tile.new()
		tile.item = item
		tile.accent = accent
		tile.custom_minimum_size = Vector2(0, 84)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.tapped.connect(_select)
		_grid.add_child(tile)
		_tiles.append(tile)
	_header.text = "CARGO MANIFEST — %.1f T / %.0f T" % [total_mass, ship["cargo_mass_limit_t"]]
	_select(_selected_id)


func _select(id: int) -> void:
	_selected_id = id
	var selected: Dictionary = {}
	for tile in _tiles:
		tile.selected = tile.item["id"] == id
		if tile.selected:
			selected = tile.item
	if selected.is_empty():
		_selected_id = -1
		_detail.text = "TAP AN ITEM"
	else:
		_detail.text = "%s — %.1f T — %.1f M³" % [
			selected["name"], selected["mass_t"], selected["vol_m3"]]


class Tile:
	extends Control
	## One cargo tile. Tap (touch or mouse) selects it.

	signal tapped(id: int)

	var item: Dictionary
	var accent: Color
	var selected := false:
		set(v):
			selected = v
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var touch_tap: bool = event is InputEventScreenTouch and event.pressed
		var click: bool = event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT
		if touch_tap or click:
			tapped.emit(item["id"])
			accept_event()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(accent, 0.28 if selected else 0.1))
		draw_rect(rect, accent if selected else Color(accent, 0.45), false,
				2.0 if selected else 1.0)
		draw_string(font, Vector2(12, 30), item["name"],
				HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 15,
				accent if selected else Color(accent, 0.85))
		draw_string(font, Vector2(12, 56), "%.1f T · %.1f M³" % [item["mass_t"], item["vol_m3"]],
				HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 13, Color(accent, 0.6))
