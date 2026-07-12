extends Control
## Phase 1 placeholder content for every display window: the window's role
## name, the shared GameState tick counter, and which screen the window is
## actually on. All four windows showing identical, non-drifting ticks proves
## one-process shared state works across native windows.

@export var role_name: String = "ROLE"
@export var accent: Color = Color(0.9, 0.9, 0.9)

@onready var _role_label: Label = %RoleLabel
@onready var _tick_label: Label = %TickLabel
@onready var _info_label: Label = %InfoLabel


func _ready() -> void:
	_role_label.text = role_name.to_upper()
	_role_label.add_theme_color_override("font_color", accent)
	_tick_label.add_theme_color_override("font_color", accent)
	_info_label.add_theme_color_override("font_color", accent.darkened(0.35))
	GameState.tick_changed.connect(_on_tick_changed)
	_on_tick_changed(GameState.tick)


func _on_tick_changed(tick: int) -> void:
	_tick_label.text = "TICK %06d" % tick
	var win := get_window()
	if win:
		_info_label.text = "screen %d — %d × %d" % [win.current_screen, win.size.x, win.size.y]
