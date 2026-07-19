extends HBoxContainer
## Sensor mode selector for the Tactical display (PASSIVE / ACTIVE / STRUCT).
## Mouse-driven buttons; state lives in GameState so the scope, comms log,
## and any future display all react to the same mode.

const ButtonTheme := preload("res://scenes/ui/ButtonTheme.gd")

@export var accent: Color = Color(1.0, 0.72, 0.2)

var _buttons: Dictionary = {}


func _ready() -> void:
	for mode in GameState.SENSOR_MODES:
		var button := Button.new()
		button.text = mode
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_stylebox_override("normal", ButtonTheme.make_toggle_stylebox(accent, false))
		button.add_theme_stylebox_override("hover", ButtonTheme.make_toggle_stylebox(accent, false, true))
		button.add_theme_stylebox_override("pressed", ButtonTheme.make_toggle_stylebox(accent, true))
		button.add_theme_stylebox_override("hover_pressed", ButtonTheme.make_toggle_stylebox(accent, true))
		button.add_theme_color_override("font_color", accent.darkened(0.2))
		button.add_theme_color_override("font_hover_color", accent)
		button.add_theme_color_override("font_pressed_color", Color(0.08, 0.05, 0.0))
		button.add_theme_color_override("font_hover_pressed_color", Color(0.08, 0.05, 0.0))
		button.pressed.connect(_on_pressed.bind(mode))
		add_child(button)
		_buttons[mode] = button
	GameState.sensor_mode_changed.connect(_sync)
	_sync(GameState.sensor_mode)


func _on_pressed(mode: String) -> void:
	GameState.set_sensor_mode(mode)
	# Re-sync so clicking the already-active button can't visually untoggle it.
	_sync(GameState.sensor_mode)


func _sync(mode: String) -> void:
	for m: String in _buttons:
		_buttons[m].button_pressed = m == mode
