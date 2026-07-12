extends Node
## Raw joypad/keyboard input -> GameState intents.
##
## Phase 1: only a global quit key on the main window (secondary windows have
## their own event streams and handle Esc in RoleWindow.gd). HOTAS bindings and
## the raw-HID switch panel arrive in Phase 5 and route through here so
## GameState never cares where an input came from.
##
## Phase 2: the glance camera polls get_glance() each frame. The hat is digital
## (Windows exposes the primary POV hat as JOY_BUTTON_DPAD_* — see plan risk #1),
## which is exactly what a hold-to-glance/release-to-recenter interaction wants.


## Digital glance direction from the POV hat (arrow keys as the desk-free dev
## fallback), +x = right, +y = down. The Input singleton is process-global, so
## this keeps working no matter which of the four windows has OS focus
## (plan risk #6).
func get_glance() -> Vector2:
	return Input.get_vector("glance_left", "glance_right", "glance_up", "glance_down")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
