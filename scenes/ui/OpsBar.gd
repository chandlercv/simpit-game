extends HBoxContainer
## Salvage-ops controls for the Tactical display: approach/match-velocity
## toggle and the cutter trigger. Mouse-driven buttons calling SalvageSystem
## intents; button text mirrors GameState each frame so every window stays in
## agreement about what the ship is doing.

@export var accent: Color = Color(1.0, 0.72, 0.2)

var _approach_button: Button
var _cut_button: Button


func _ready() -> void:
	_approach_button = _make_button()
	_approach_button.pressed.connect(SalvageSystem.toggle_approach)
	_cut_button = _make_button()
	_cut_button.pressed.connect(SalvageSystem.request_cut)


func _process(_delta: float) -> void:
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
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(accent, 0.08)
	normal.border_color = Color(accent, 0.5)
	normal.set_border_width_all(1)
	normal.set_content_margin_all(8)
	var hover := normal.duplicate()
	hover.bg_color = Color(accent, 0.16)
	var disabled := normal.duplicate()
	disabled.border_color = Color(accent, 0.2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_hover_color", accent.lightened(0.2))
	button.add_theme_color_override("font_disabled_color", Color(accent, 0.35))
	add_child(button)
	return button
