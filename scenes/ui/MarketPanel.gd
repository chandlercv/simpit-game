extends Control
## Market panel for the Chart display, fed by MarketSystem (Phase 4): live
## faction price table with reputation standing, plus the dock → sell hold →
## depart flow. Mouse-driven, matching the 13" physical monitor's input.

const ButtonTheme := preload("res://scenes/ui/ButtonTheme.gd")

@export var accent: Color = Color(0.45, 0.7, 1.0)

const SELL_COLOR := Color(0.5, 1.0, 0.7)

@onready var _title: Label = %Title
@onready var _grid: GridContainer = %Grid
@onready var _footer: Label = %Footer

## Last seen state of hatch_open_locked(), watched in _process.
var _hatch_ready := false


func _ready() -> void:
	_title.add_theme_font_size_override("font_size", 17)
	_title.add_theme_color_override("font_color", accent)
	_footer.add_theme_font_size_override("font_size", 13)
	_footer.add_theme_color_override("font_color", Color(accent, 0.5))
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameState.market_changed.connect(_rebuild)
	GameState.credits_changed.connect(func(_credits: int) -> void: _rebuild())
	GameState.reputation_changed.connect(_rebuild)
	GameState.run_phase_changed.connect(func(_phase: String) -> void: _rebuild())
	# The approach's own states matter here too: reaching FINAL withdraws the
	# auto-berth offer, and the footer tracks inbound vs. outbound.
	GameState.docking_changed.connect(func(_state: String) -> void: _rebuild())
	GameState.cargo_changed.connect(_rebuild)
	# The SELL control names the hatch and the propellant controls quote a live
	# tank level, so both have to follow those two pieces of state.
	GameState.cargo_hatch_changed.connect(func(_open: bool) -> void: _rebuild())
	GameState.propellant_changed.connect(_rebuild)
	_rebuild()


## The SELL control turns on when the door reaches its stop, which is a couple of
## seconds AFTER the lever moved — so the lever signal alone would leave the
## button reading "OPEN HATCH TO SELL" over an open hold forever. Watch the
## derived state and rebuild only when it actually flips; a rebuild per frame
## would tear down the very button being pressed.
func _process(_delta: float) -> void:
	var ready := GameState.hatch_open_locked()
	if ready != _hatch_ready:
		_hatch_ready = ready
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
		"APPROACH":
			var docking: Dictionary = DockingSystem.status()
			if docking.get("outbound", false):
				_footer.text = "DEPARTING %s — FLY THE LANE OUT" % docking.get("station", "")
			else:
				_footer.text = "ON APPROACH TO %s — FLY IT IN, OR BUY AN AUTO-BERTH" \
						% docking.get("station", "")
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
		# The hold discharges through the hatch, so say so on the control rather
		# than letting the pilot press a live-looking button and be refused.
		var open := GameState.hatch_open_locked()
		var sell := _make_button("SELL HOLD (%d CR)" % value
				if open else "OPEN HATCH TO SELL", SELL_COLOR)
		sell.disabled = value == 0 or not open
		sell.pressed.connect(MarketSystem.sell_hold)
		box.add_child(sell)
		# Propellant is the other thing a berth sells. Each button quotes the cost
		# of filling that tank from where it stands and goes inert once it is full.
		for kind: String in MarketSystem.PROPELLANT_NAMES:
			var quote := MarketSystem.propellant_quote(kind)
			var fuel := _make_button("%s FULL" % kind if quote <= 0
					else "%s TO FULL (%d CR)" % [kind, quote], accent)
			fuel.disabled = quote <= 0 or GameState.credits < quote
			fuel.pressed.connect(MarketSystem.buy_propellant.bind(kind))
			box.add_child(fuel)
		var depart := _make_button("DEPART FOR CLAIM", accent)
		depart.pressed.connect(MarketSystem.request_undock)
		box.add_child(depart)
	elif GameState.run_phase == "APPROACH" \
			and faction_index == int(GameState.docking.get("faction", -1)):
		# Mid-approach the column becomes the two ways out of the pattern that
		# aren't flying it: pay ATC to park it, or give up on the berth. Neither
		# applies on the way out, where you're already leaving.
		if DockingSystem.status().get("outbound", false):
			var leaving := _make_button("DEPARTING — FLY THE LANE", accent)
			leaving.disabled = true
			box.add_child(leaving)
		else:
			var auto := _make_button("AUTO-BERTH (%d CR)" % DockingSystem.AUTO_BERTH_FEE,
					accent)
			auto.disabled = GameState.credits < DockingSystem.AUTO_BERTH_FEE \
					or GameState.docking_state == "FINAL"
			auto.pressed.connect(DockingSystem.request_auto_berth)
			box.add_child(auto)
			var abort := _make_button("ABORT APPROACH", SELL_COLOR)
			abort.pressed.connect(DockingSystem.abort_approach)
			box.add_child(abort)
	else:
		var dock := _make_button("DOCK", accent)
		dock.disabled = GameState.run_phase != "ON_SITE"
		dock.pressed.connect(MarketSystem.request_dock.bind(faction_index))
		box.add_child(dock)
	return box


func _add_cell(text: String, color: Color, header := false) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15 if header else 14)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(label)


## Full-height touch targets in a column only a quarter of the panel wide, so the
## label wraps inside the button rather than being clipped or forcing the type
## back down — height is what a fingertip needs, and the column already gives the
## button its width.
func _make_button(text: String, color: Color) -> Button:
	var button := ButtonTheme.make_button(color, 8)
	button.text = text
	button.custom_minimum_size = Vector2(0, ButtonTheme.TOUCH_MIN_H)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 14)
	return button
