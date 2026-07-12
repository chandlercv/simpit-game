extends Window
## Root of a secondary display window (Tactical / Tablet / Chart).
## WindowManager instantiates it at boot and positions it on its configured
## screen. Each native window gets its own input event stream, so quit keys
## are handled here rather than in InputRouter (which only sees the main
## window's events).


func _ready() -> void:
	close_requested.connect(_quit)
	window_input.connect(_on_window_input)


func _on_window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_quit()


func _quit() -> void:
	get_tree().quit()
