extends Control
## Market price table for the Chart display. Reads the placeholder table in
## GameState until systems/MarketSystem.gd (Phase 4) owns faction pricing and
## reputation. Static read-only panel — repricing happens on dock.

@export var accent: Color = Color(0.45, 0.7, 1.0)

@onready var _title: Label = %Title
@onready var _grid: GridContainer = %Grid
@onready var _footer: Label = %Footer


func _ready() -> void:
	_title.text = "MARKET FEED"
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", accent)
	_footer.text = "CACHED FEED — REPRICES ON DOCK"
	_footer.add_theme_font_size_override("font_size", 11)
	_footer.add_theme_color_override("font_color", Color(accent, 0.5))
	_grid.columns = GameState.market_factions.size() + 1
	_add_cell("COMMODITY", accent, true)
	for faction in GameState.market_factions:
		_add_cell(faction, accent, true)
	for good: Dictionary in GameState.market_goods:
		_add_cell("%s (%s)" % [good["name"], good["unit"]], Color(accent, 0.85))
		for price: int in good["prices"]:
			_add_cell("%d" % price, Color(accent, 0.65))


func _add_cell(text: String, color: Color, header := false) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13 if header else 12)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(label)
