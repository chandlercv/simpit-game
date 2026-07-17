extends Node
## Raw joypad/keyboard input -> GameState intents. GameState never cares
## where an input came from: HOTAS axes, keyboard fallbacks, and the raw-HID
## switch panel all land here first.
##
## Phase 2: the glance camera polls get_glance() each frame. The hat is
## digital (Windows exposes the primary POV hat as JOY_BUTTON_DPAD_* — plan
## risk #1), which is exactly what hold-to-glance/release-to-recenter wants.
##
## Phase 5: named flight actions (thrust_*/strafe_*/pitch_*/yaw_*/roll_*)
## are polled here and fed to SalvageSystem as the manual-flight intent.
## They carry keyboard fallbacks now; HOTAS InputEventJoypadMotion bindings
## are added to the same actions once tools/InputEcho.tscn has reported the
## real X52/X55 axis indices — no code changes, Input Map only. The Saitek
## switch panel (never a joypad) is read by SwitchPanelBridge, spawned here.

const SwitchPanelBridgeScene := preload("res://systems/hardware/SwitchPanelBridge.gd")


func _ready() -> void:
	add_child(SwitchPanelBridgeScene.new())


func _process(_delta: float) -> void:
	var thrust := Vector3(
		Input.get_axis("strafe_left", "strafe_right"),
		Input.get_axis("thrust_down", "thrust_up"),
		Input.get_axis("thrust_back", "thrust_forward"))
	var rot := Vector3(
		Input.get_axis("pitch_down", "pitch_up"),
		Input.get_axis("yaw_right", "yaw_left"),
		Input.get_axis("roll_right", "roll_left"))
	SalvageSystem.set_manual_flight(thrust, rot)


## Digital glance direction from the POV hat (arrow keys as the desk-free dev
## fallback), +x = right, +y = down. The Input singleton is process-global, so
## this keeps working no matter which of the four windows has OS focus
## (plan risk #6).
func get_glance() -> Vector2:
	return Input.get_vector("glance_left", "glance_right", "glance_up", "glance_down")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
