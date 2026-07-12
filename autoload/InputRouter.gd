extends Node
## Raw joypad/keyboard input -> GameState intents.
##
## Phase 1: only a global quit key on the main window (secondary windows have
## their own event streams and handle Esc in RoleWindow.gd). HOTAS bindings and
## the raw-HID switch panel arrive in Phase 5 and route through here so
## GameState never cares where an input came from.


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
