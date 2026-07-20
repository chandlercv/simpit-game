extends Node
## Owns the display layout: shows the setup chooser when needed, then spawns the
## secondary native OS windows and positions every window on its configured
## screen (requires embed_subwindows = off in project.godot).
##
## Placement is data-driven from DisplayConfig.get_roles_for_screen():
##  - MAIN → the primary window, fullscreen on its screen.
##  - one role alone on a non-Main screen → its own full-coverage borderless window.
##  - two+ roles sharing a spare screen → a RoleTabHost filling a window on it.
##  - any role(s) landing on the Main screen → a dimmed RoleTabHost overlay in a
##    CanvasLayer over the Main view.
## Adding a new display role is an entry in SECONDARY_SCENES plus a DisplayConfig
## role — no other changes.

const SECONDARY_SCENES: Dictionary = {
	"tactical": "res://scenes/displays/TacticalWindow.tscn",
	"tablet": "res://scenes/displays/TabletWindow.tscn",
	"chart": "res://scenes/displays/StarChartWindow.tscn",
}

const RoleTabHostScript := preload("res://scenes/displays/RoleTabHost.gd")
const DisplaySetupScript := preload("res://scenes/displays/DisplaySetup.gd")

var _windows: Array[Window] = []
var _hosts: Array = []
var _overlay_layer: CanvasLayer = null
var _setup_ui: Node = null


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
	if DisplayConfig.needs_setup_prompt():
		_show_setup()
	else:
		_place_all()


# --- Setup chooser ---------------------------------------------------------

func _show_setup() -> void:
	_teardown()
	var layer := _ensure_overlay_layer()
	_setup_ui = DisplaySetupScript.new()
	_setup_ui.confirmed.connect(_on_setup_confirmed)
	layer.add_child(_setup_ui)
	_setup_ui.start()


func _on_setup_confirmed() -> void:
	if is_instance_valid(_setup_ui):
		_setup_ui.queue_free()
	_setup_ui = null
	_place_all()


# --- Layout ----------------------------------------------------------------

func _place_all() -> void:
	_teardown()
	_position_main_window()
	var main_screen: int = DisplayConfig.get_screen_for_role(DisplayConfig.ROLE_MAIN)

	var by_screen: Dictionary = {}
	for role in SECONDARY_SCENES:
		var screen: int = DisplayConfig.get_screen_for_role(role)
		if not by_screen.has(screen):
			by_screen[screen] = []
		by_screen[screen].append(role)

	for screen in by_screen:
		var roles: Array = by_screen[screen]
		if screen == main_screen:
			_make_overlay_host(roles)
		elif roles.size() == 1:
			_spawn_window(roles[0], screen)
		else:
			_spawn_packed_window(roles, screen)


func _position_main_window() -> void:
	var screen: int = DisplayConfig.get_screen_for_role(DisplayConfig.ROLE_MAIN)
	var win := get_window()
	win.current_screen = screen
	win.mode = Window.MODE_FULLSCREEN


func _spawn_window(role: String, screen: int) -> void:
	var packed: PackedScene = load(SECONDARY_SCENES[role])
	var win: Window = packed.instantiate()
	win.title = "Salvager — %s" % role.capitalize()
	win.borderless = true
	win.position = DisplayServer.screen_get_position(screen)
	win.size = DisplayServer.screen_get_size(screen)
	add_child(win)
	_windows.append(win)


func _spawn_packed_window(roles: Array, screen: int) -> void:
	var win := Window.new()
	win.title = "Salvager — " + _roles_title(roles)
	win.borderless = true
	win.position = DisplayServer.screen_get_position(screen)
	win.size = DisplayServer.screen_get_size(screen)
	var host := RoleTabHostScript.new()
	host.configure(true)
	for role in roles:
		host.add_role(role, _harvest_content(role))
	host.finish()
	win.add_child(host)
	add_child(win)
	_windows.append(win)


func _make_overlay_host(roles: Array) -> void:
	var layer := _ensure_overlay_layer()
	var host := RoleTabHostScript.new()
	host.configure(false)
	for role in roles:
		host.add_role(role, _harvest_content(role))
	host.finish()
	layer.add_child(host)
	_hosts.append(host)


## Instantiate a display window scene and lift out its reusable Root content,
## leaving standalone-window scenes untouched. Owners authored under the window
## are cleared so the detached subtree carries no dangling owner (unique-name
## lookups inside instanced sub-scenes keep their own owner scope and survive).
func _harvest_content(role: String) -> Control:
	var packed: PackedScene = load(SECONDARY_SCENES[role])
	var win: Window = packed.instantiate()
	var content: Control = win.get_node("Root")
	win.remove_child(content)
	_orphan_owner(content, win)
	win.free()
	return content


func _orphan_owner(node: Node, old_owner: Node) -> void:
	if node.owner == old_owner:
		node.owner = null
	for child in node.get_children():
		_orphan_owner(child, old_owner)


func _roles_title(roles: Array) -> String:
	var parts: PackedStringArray = []
	for role in roles:
		parts.append(String(role).capitalize())
	return " / ".join(parts)


func _ensure_overlay_layer() -> CanvasLayer:
	if _overlay_layer and is_instance_valid(_overlay_layer):
		return _overlay_layer
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 20
	get_window().add_child(_overlay_layer)
	return _overlay_layer


func _teardown() -> void:
	for w in _windows:
		if is_instance_valid(w):
			w.queue_free()
	_windows.clear()
	for h in _hosts:
		if is_instance_valid(h):
			h.queue_free()
	_hosts.clear()
	if is_instance_valid(_setup_ui):
		_setup_ui.queue_free()
	_setup_ui = null
	if _overlay_layer and is_instance_valid(_overlay_layer):
		_overlay_layer.queue_free()
	_overlay_layer = null


# --- Hot-plug / re-open ----------------------------------------------------

## Polled rather than handled via _unhandled_input: the Input singleton is
## process-global, so F5/F6 fire no matter which window has OS focus, whereas an
## autoload's _unhandled_input only sees the main window's viewport (see the
## InputRouter header on the same cross-window focus issue).
func _process(_delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if Input.is_action_just_pressed("redetect_displays"):
		_redetect()
	elif Input.is_action_just_pressed("open_display_setup"):
		_show_setup()


## Re-read the monitor topology and rebuild. A setup seen before applies its
## saved layout; an unknown one re-opens the chooser.
func _redetect() -> void:
	DisplayConfig.reload()
	_setup()
