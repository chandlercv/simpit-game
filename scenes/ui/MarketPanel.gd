extends Control
## Market panel for the Chart display, fed by MarketSystem (Phase 4): live
## faction price table with reputation standing, plus the dock → sell hold →
## depart flow. Mouse-driven, matching the 13" physical monitor's input.

@export var accent: Color = Color(0.45, 0.7, 1.0)

const SELL_COLOR := Color(0.5, 1.0, 0.7)

@onready var _title: Label = %Title
@onready var _grid: GridContainer = %Grid
@onready var _footer: Label = %Footer


func _ready() -> void:
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", accent)
	_footer.add_theme_font_size_override("font_size", 11)
	_footer.add_theme_color_override("font_color", Color(accent, 0.5))
	GameState.market_changed.connect(_rebuild)
	GameState.credits_changed.connect(func(_credits: int) -> void: _rebuild())
	GameState.reputation_changed.connect(_rebuild)
	GameState.run_phase_changed.connect(func(_phase: String) -> void: _rebuild())
	GameState.cargo_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	_title.text = "MARKET FEED — %d CR" % GameState.credits
	for child in _grid.get_children():
		child.queue_free()
	var factions := GameState.market_factions
	_grid.columns = factions.size() + 1

	_add_cell("COMMODITY", accent, true)
	for fi in factions.size():
		_add_cell(factions[fi],
				SELL_COLOR if fi == GameState.docked_faction else accent, true)

	_add_cell("STANDING", Color(accent, 0.6))
	for faction in factions:
		_add_cell("%d%%" % roundi(GameState.reputation[faction] * 100.0),
				Color(accent, 0.6))

	for good: Dictionary in GameState.market_goods:
		_add_cell("%s (%s)" % [good["name"], good["unit"]], Color(accent, 0.85))
		for price: int in good["prices"]:
			_add_cell("%d" % price, Color(accent, 0.65))

	_add_cell("", accent)
	for fi in factions.size():
		_grid.add_child(_faction_actions(fi))

	match GameState.run_phase:
		"ON_SITE":
			_footer.text = "CACHED FEED — DOCK TO TRADE (LEAVES THE CLAIM)"
		"TRANSIT":
			_footer.text = "IN TRANSIT — STAND BY"
		"DOCKED":
			_footer.text = "DOCKED AT %s — HOLD SELLS HERE FOR %d CR" % [
				GameState.market_factions[GameState.docked_faction],
				MarketSystem.hold_value(GameState.docked_faction)]


## Action cell under a faction column: DOCK from the claim; SELL/DEPART while
## docked there.
func _faction_actions(faction_index: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	if GameState.run_phase == "DOCKED" and faction_index == GameState.docked_faction:
		var value := MarketSystem.hold_value(faction_index)
		var sell := _make_button("SELL HOLD (%d CR)" % value, SELL_COLOR)
		sell.disabled = value == 0
		sell.pressed.connect(MarketSystem.sell_hold)
		box.add_child(sell)
		var depart := _make_button("DEPART FOR CLAIM", accent)
		depart.pressed.connect(MarketSystem.request_undock)
		box.add_child(depart)
	else:
		var dock := _make_button("DOCK", accent)
		dock.disabled = GameState.run_phase != "ON_SITE"
		dock.pressed.connect(MarketSystem.request_dock.bind(faction_index))
		box.add_child(dock)
	return box


func _add_cell(text: String, color: Color, header := false) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13 if header else 12)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(label)


func _make_button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 12)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(color, 0.08)
	normal.border_color = Color(color, 0.5)
	normal.set_border_width_all(1)
	normal.set_content_margin_all(6)
	var hover := normal.duplicate()
	hover.bg_color = Color(color, 0.18)
	var disabled := normal.duplicate()
	disabled.border_color = Color(color, 0.2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", color.lightened(0.2))
	button.add_theme_color_override("font_disabled_color", Color(color, 0.35))
	return button
