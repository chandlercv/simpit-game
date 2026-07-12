extends Node
## Spawns the secondary native OS windows at boot and positions every window
## on its configured screen (requires embed_subwindows = off in project.godot).
##
## Loops over whatever roles DisplayConfig knows about — a new display role is
## an entry here plus a scene, with no changes to GameState or existing windows.

const SECONDARY_SCENES: Dictionary = {
	"tactical": "res://scenes/displays/TacticalWindow.tscn",
	"tablet": "res://scenes/displays/TabletWindow.tscn",
	"chart": "res://scenes/displays/StarChartWindow.tscn",
}

## Screens already hosting a full-coverage window. A role that lands on an
## already-claimed screen (dev setup with fewer monitors than roles) falls back
## to a small bordered window so it doesn't bury what's underneath.
var _claimed_screens: Array[int] = []
var _cascade := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Deferred so get_tree().current_scene is set and all autoloads are ready.
	_setup.call_deferred()


func _setup() -> void:
	var current := get_tree().current_scene
	# Dev utilities (ScreenLabeler, InputEcho) run as the current scene and
	# manage their own windows — don't spawn the game's windows under them.
	if current and current.scene_file_path.begins_with("res://tools/"):
		return
	_position_main_window()
	for role in SECONDARY_SCENES:
		_spawn_window(role)


func _position_main_window() -> void:
	var screen: int = DisplayConfig.get_screen_for_role(DisplayConfig.ROLE_MAIN)
	var win := get_window()
	win.current_screen = screen
	win.mode = Window.MODE_FULLSCREEN
	_claimed_screens.append(screen)


func _spawn_window(role: String) -> void:
	var screen: int = DisplayConfig.get_screen_for_role(role)
	var packed: PackedScene = load(SECONDARY_SCENES[role])
	var win: Window = packed.instantiate()
	win.title = "Salvager — %s" % role.capitalize()
	if screen in _claimed_screens:
		# Shared screen (dev fallback): bordered, cascaded, not full-coverage.
		win.borderless = false
		win.size = Vector2i(960, 540)
		win.position = DisplayServer.screen_get_position(screen) \
				+ Vector2i(80, 80) + Vector2i(40, 40) * _cascade
		_cascade += 1
	else:
		win.borderless = true
		win.position = DisplayServer.screen_get_position(screen)
		win.size = DisplayServer.screen_get_size(screen)
		_claimed_screens.append(screen)
	add_child(win)
