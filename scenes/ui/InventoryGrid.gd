extends Control
## Cargo manifest for the MFD CARGO page — touch-first: tap a tile to select it and
## see its details, tap JETTISON to dump it (CargoSystem intent). Tap-to-select
## over free-drag per the plan (spacedesk ~30fps + latency); every widget here
## answers raw touch and mouse alike since touch emulation is off project-wide.

@export var accent: Color = Color(0.3, 0.9, 0.78)

const JETTISON_COLOR := Color(1.0, 0.55, 0.3)

var _selected_id := -1
var _tiles: Array = []
var _jettison: TapButton

@onready var _header: Label = %Header
@onready var _grid: GridContainer = %Grid
@onready var _detail: Label = %Detail


func _ready() -> void:
	_header.add_theme_font_size_override("font_size", 15)
	_header.add_theme_color_override("font_color", accent)
	_detail.add_theme_color_override("font_color", Color(accent, 0.8))
	_jettison = TapButton.new()
	_jettison.accent = JETTISON_COLOR
	_jettison.custom_minimum_size = Vector2(0, 44)
	_jettison.tapped.connect(_on_jettison)
	_detail.get_parent().add_child(_jettison)
	# Mapped cargo controls (InputRouter) reach the grid through this group.
	add_to_group("cargo_grid")
	GameState.cargo_changed.connect(_rebuild)
	_rebuild()


## Step the selection to the next/previous cargo tile (mapped cargo-next/prev).
func select_step(delta: int) -> void:
	if _tiles.is_empty():
		return
	var ids: Array = []
	for tile in _tiles:
		ids.append(tile.item["id"])
	var here := ids.find(_selected_id)
	if here == -1:
		_select(ids[0] if delta >= 0 else ids[ids.size() - 1])
	else:
		var step := 1 if delta >= 0 else -1
		_select(ids[(here + step + ids.size()) % ids.size()])


## Jettison the selected item (mapped cargo-jettison intent).
func jettison_selected() -> void:
	_on_jettison()


func _rebuild() -> void:
	for tile in _tiles:
		tile.queue_free()
	_tiles.clear()
	var ship: Dictionary = GameState.local_ship()
	var cargo: Array = ship["cargo"]
	var total_mass := 0.0
	var total_vol := 0.0
	for item: Dictionary in cargo:
		total_mass += item["mass_t"]
		total_vol += item["vol_m3"]
		var tile := Tile.new()
		tile.item = item
		tile.accent = accent
		tile.custom_minimum_size = Vector2(0, 84)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.tapped.connect(_select)
		_grid.add_child(tile)
		_tiles.append(tile)
	_header.text = "CARGO — %.1f / %.0f T — %.1f / %.0f M³" % [
		total_mass, ship["cargo_mass_limit_t"], total_vol, ship["cargo_vol_limit_m3"]]
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
		_detail.text = "TAP AN ITEM" if not _tiles.is_empty() else "HOLD EMPTY"
		_jettison.label = "JETTISON — SELECT ITEM"
		_jettison.enabled = false
	else:
		_detail.text = "%s — %.1f T — %.1f M³" % [
			selected["name"], selected["mass_t"], selected["vol_m3"]]
		_jettison.label = "JETTISON %s" % selected["name"]
		_jettison.enabled = true


func _on_jettison() -> void:
	if _selected_id != -1:
		CargoSystem.jettison(_selected_id)


class TapButton:
	extends Control
	## Touch/mouse tap button (plain Button ignores raw ScreenTouch, and touch
	## emulation is deliberately off project-wide — plan Phase 3).

	signal tapped

	var accent: Color
	var label := "":
		set(v):
			label = v
			queue_redraw()
	var enabled := false:
		set(v):
			enabled = v
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var touch_tap: bool = event is InputEventScreenTouch and event.pressed
		var click: bool = event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT
		if (touch_tap or click) and enabled:
			tapped.emit()
			accept_event()

	func _draw() -> void:
		var color := accent if enabled else Color(accent, 0.35)
		draw_rect(Rect2(Vector2.ZERO, size), Color(accent, 0.12 if enabled else 0.04))
		draw_rect(Rect2(Vector2.ZERO, size), color, false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(0, size.y / 2.0 + 5), label,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, color)


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
