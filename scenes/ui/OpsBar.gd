extends HBoxContainer
## Salvage-ops controls for the Tactical display: approach/match-velocity
## toggle and the cutter trigger. Mouse-driven buttons calling SalvageSystem
## intents; button text mirrors GameState each frame so every window stays in
## agreement about what the ship is doing.

const ButtonTheme := preload("res://scenes/ui/ButtonTheme.gd")

@export var accent: Color = Color(1.0, 0.72, 0.2)

var _approach_button: Button
var _cut_button: Button


func _ready() -> void:
	_approach_button = _make_button()
	_approach_button.pressed.connect(SalvageSystem.toggle_approach)
	_cut_button = _make_button()
	_cut_button.pressed.connect(SalvageSystem.request_cut)
	GameState.run_phase_changed.connect(func(_p: String) -> void: _update())
	GameState.approach_changed.connect(func(_s: String) -> void: _update())
	GameState.selected_member_changed.connect(func(_id: int) -> void: _update())
	GameState.site_reset.connect(_update)
	# Cut progress ticks up continuously with no dedicated signal, so the
	# shared 10Hz tick is what keeps the "CUTTING NN%" text live.
	GameState.tick_changed.connect(func(_t: int) -> void: _update())
	_update()


func _update() -> void:
	var on_site := GameState.run_phase == "ON_SITE"
	_approach_button.disabled = not on_site
	if not on_site:
		_approach_button.text = "IN TRANSIT" if GameState.run_phase == "TRANSIT" else "DOCKED"
		_cut_button.text = "—"
		_cut_button.disabled = true
		return
	match GameState.approach_state:
		"HOLDING":
			_approach_button.text = "APPROACH WRECK"
		"APPROACHING":
			_approach_button.text = "APPROACHING — ABORT"
		"MATCHED":
			_approach_button.text = "MATCHED — RELEASE"
	var cutting_id: int = GameState.wreck["cutting_id"]
	if cutting_id != -1:
		_cut_button.text = "CUTTING %d%%" % roundi(GameState.wreck["cut_progress"] * 100.0)
		_cut_button.disabled = true
		return
	var selected := GameState.get_member(GameState.selected_member_id)
	if selected.is_empty():
		_cut_button.text = "CUT — SELECT MEMBER"
		_cut_button.disabled = true
	else:
		_cut_button.text = "CUT %s" % selected["name"]
		# Enabled even when range/power would refuse: the refusal comms line
		# tells the player what to fix, which beats a silently dead button.
		_cut_button.disabled = false


func _make_button() -> Button:
	var button := ButtonTheme.make_button(accent)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(button)
	return button
