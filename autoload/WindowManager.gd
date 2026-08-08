extends Node
## Owns the launch flow and the display layout: shows the title card, then the
## setup chooser when needed, then spawns the secondary native OS windows and
## positions every window on its configured screen (requires embed_subwindows =
## off in project.godot).
##
## Launch order at boot: title card (scenario + displays + controls, tree paused)
## → display chooser if this monitor setup has never been assigned → windows
## placed and the tree unpaused. The chooser is also a step you can take *from*
## the card and come back from, so the card is hidden rather than freed while
## it runs.
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
	"mfd": "res://scenes/displays/MfdWindow.tscn",
	"camera": "res://scenes/displays/CameraWindow.tscn",
}

const RoleTabHostScript := preload("res://scenes/displays/RoleTabHost.gd")
const DisplaySetupScript := preload("res://scenes/displays/DisplaySetup.gd")
const TitleCardScript := preload("res://scenes/displays/TitleCard.gd")

## What the chooser's confirm button is called, per what confirming actually does
## from where it was opened. One label for all three read as a lie in two of them:
## coming back from the card's DISPLAYS step starts nothing, and neither does an
## F6 re-assign mid-run.
const CONFIRM_BACK := "BACK TO TITLE"
const CONFIRM_LAUNCH := "LAUNCH"
const CONFIRM_APPLY := "APPLY"

var _windows: Array[Window] = []
var _hosts: Array = []
var _overlay_layer: CanvasLayer = null
var _setup_ui: Node = null
## The launch screen, alive (possibly hidden) until LAUNCH. Kept on its own layer
## so _teardown() — which rebuilds the display layout — can't free it mid-launch.
var _title_ui: Control = null
var _title_layer: CanvasLayer = null


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# The title card pauses the tree, and a paused node neither processes nor
	# receives input — so the manager that has to un-pause it (and its F5/F6
	# polling) must keep running.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Deferred so get_tree().current_scene is set and all autoloads are ready.
	_setup.call_deferred()


## The 3D World3D that the Main hull-cam SubViewport renders. The CameraWindow
## assigns this to its own SubViewport so its external cameras render the SAME
## world (rather than a private copy). Returns null before the Main view exists.
func main_world_3d() -> World3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var vp := _find_subviewport(scene)
	# find_world_3d(), not world_3d: the Main SubViewport uses own_world_3d, whose
	# auto-created World3D is returned by find_world_3d() — the `world_3d` property
	# is only the (here empty) explicit override, so reading it hands back null.
	return vp.find_world_3d() if vp else null


func _find_subviewport(node: Node) -> SubViewport:
	if node is SubViewport:
		return node
	for child in node.get_children():
		var found := _find_subviewport(child)
		if found:
			return found
	return null


func _setup() -> void:
	var current := get_tree().current_scene
	# Dev utilities (ScreenLabeler, InputEcho) run as the current scene and
	# manage their own windows — don't spawn the game's windows under them.
	if current and current.scene_file_path.begins_with("res://tools/"):
		return
	if not GameState.scenario_started:
		_show_title()
	elif DisplayConfig.needs_setup_prompt():
		_show_setup()
	else:
		_place_all()


# --- Title card ------------------------------------------------------------

func _show_title() -> void:
	_teardown()
	_close_title()
	# Nothing in the scenario runs until LAUNCH: a paused tree freezes the world
	# (and the systems driving it) while leaving it rendered behind the card.
	get_tree().paused = true
	_title_layer = CanvasLayer.new()
	# Below the setup chooser (20) and the remapper (25), both of which the card
	# opens and both of which cover it while they're up.
	_title_layer.layer = 15
	_title_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().add_child(_title_layer)
	_title_ui = TitleCardScript.new()
	_title_ui.launched.connect(_on_title_launched)
	_title_ui.display_setup_requested.connect(_show_setup)
	_title_layer.add_child(_title_ui)
	_title_ui.start()


func _on_title_launched() -> void:
	_close_title()
	# An unconfigured monitor setup still gets the chooser, exactly as it did
	# before the card existed — the card's DISPLAYS row warns that it will. This
	# is the one path where confirming really does start the run.
	if DisplayConfig.needs_setup_prompt():
		_show_setup(CONFIRM_LAUNCH)
	else:
		_place_all()


func _close_title() -> void:
	if is_instance_valid(_title_ui):
		_title_ui.queue_free()
	_title_ui = null
	if is_instance_valid(_title_layer):
		_title_layer.queue_free()
	_title_layer = null


# --- Setup chooser ---------------------------------------------------------

## `confirm_label` defaults to the mid-run F6 case; _on_title_launched passes the
## launching one. The title card's own DISPLAYS step arrives here through the
## zero-arg signal, and is caught by the check below rather than by the caller.
func _show_setup(confirm_label := CONFIRM_APPLY) -> void:
	_teardown()
	# Opened from the card (its DISPLAYS row, or F6 before launch): the card waits
	# hidden underneath and comes back with the new assignment when the chooser
	# confirms — so confirming here returns, it doesn't start anything.
	if is_instance_valid(_title_ui):
		confirm_label = CONFIRM_BACK
		_title_ui.suspend()
	var layer := _ensure_overlay_layer()
	_setup_ui = DisplaySetupScript.new()
	_setup_ui.confirm_label = confirm_label
	_setup_ui.confirmed.connect(_on_setup_confirmed)
	layer.add_child(_setup_ui)
	_setup_ui.start()


func _on_setup_confirmed() -> void:
	if is_instance_valid(_setup_ui):
		_setup_ui.queue_free()
	_setup_ui = null
	if is_instance_valid(_title_ui):
		_title_ui.resume()
		return
	_place_all()


# --- Layout ----------------------------------------------------------------

func _place_all() -> void:
	_teardown()
	# The world runs once its displays are up: the title card and the chooser both
	# hold the pause until here (a no-op on the mid-game F5 rebuild path).
	get_tree().paused = false
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
	# ALWAYS so the setup chooser still takes clicks while the title card holds
	# the tree paused (a paused Control receives no input at all).
	_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
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
