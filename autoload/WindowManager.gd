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
## Placement is planned by ScreenLayout from DisplayConfig.get_roles_for_screen()
## and applied here:
##  - MAIN alone on its screen → the primary window, fullscreen on it.
##  - MAIN sharing its screen → the primary window drops to a borderless
##    MODE_WINDOWED rect over the top two thirds; the roles tile the bottom third.
##  - roles sharing a spare screen → tiled, one borderless window each.
##  - a role alone on a spare screen → its own full-coverage borderless window.
##  - a region whose tiles would be too small to read → a RoleTabHost spanning it
##    instead: a window on a spare screen, or the dimmed overlay in a CanvasLayer
##    over a fullscreen Main view.
## Every tile is the display's own scene Window, so it keeps its content scale
## and RoleWindow's Esc/close handling. Adding a new display role is an entry in
## SECONDARY_SCENES + ROLE_CANVAS plus a DisplayConfig role — no other changes.

const SECONDARY_SCENES: Dictionary = {
	"tactical": "res://scenes/displays/TacticalWindow.tscn",
	"mfd": "res://scenes/displays/MfdWindow.tscn",
	"camera": "res://scenes/displays/CameraWindow.tscn",
}

## Each secondary scene's authored content_scale_size — the canvas ScreenLayout
## measures a tile against to decide whether a panel still reads at that size.
## DisplayLayoutSmoke asserts this table against the scenes themselves, so a
## .tscn edit can't silently desync it.
const ROLE_CANVAS: Dictionary = {
	"tactical": Vector2i(1280, 720),
	"mfd": Vector2i(1280, 800),
	"camera": Vector2i(1280, 720),
}

const RoleTabHostScript := preload("res://scenes/displays/RoleTabHost.gd")
const RoleWindowScript := preload("res://scenes/displays/RoleWindow.gd")
const DisplaySetupScript := preload("res://scenes/displays/DisplaySetup.gd")
const TitleCardScript := preload("res://scenes/displays/TitleCard.gd")
const ScreenLayoutScript := preload("res://scenes/displays/ScreenLayout.gd")

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
## True while the Main window has been shrunk to share its screen with a panel
## strip. Only then does anything need giving back before the chooser is drawn.
var _main_shares_screen := false
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
	_restore_main_window()
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
	var main_screen: int = DisplayConfig.get_screen_for_role(DisplayConfig.ROLE_MAIN)
	var by_screen := _roles_by_screen()
	# MAIN alone on its screen has no by_screen entry, but its window still has to
	# be placed — without this a four-monitor rig never leaves its boot size.
	if not by_screen.has(main_screen):
		by_screen[main_screen] = []

	for screen: int in by_screen:
		var roles: Array = by_screen[screen]
		var has_main := screen == main_screen
		var exclusive := not has_main and roles.size() <= 1
		var plan: Dictionary = ScreenLayoutScript.plan_screen(
				_screen_region(screen, exclusive), has_main, roles, ROLE_CANVAS)
		_apply_plan(plan, screen, has_main)


## Secondary roles per screen, in SECONDARY_SCENES order (tactical, MFD, camera —
## Dictionary iteration is insertion order). Not DisplayConfig.get_roles_for_screen,
## which includes MAIN and would need filtering back out.
func _roles_by_screen() -> Dictionary:
	var by_screen: Dictionary = {}
	for role: String in SECONDARY_SCENES:
		var screen: int = DisplayConfig.get_screen_for_role(role)
		if not by_screen.has(screen):
			by_screen[screen] = []
		by_screen[screen].append(role)
	return by_screen


## The rect a screen's layout is planned inside. A window covering a whole screen
## is what makes the Windows shell hide the taskbar over it, so the one-window
## cases keep the full screen rect exactly as they always have. A screen we split
## loses that, and the taskbar is topmost — so plan those inside the usable rect
## or it eats the bottom row.
func _screen_region(screen: int, exclusive: bool) -> Rect2i:
	if exclusive:
		return Rect2i(DisplayServer.screen_get_position(screen),
				DisplayServer.screen_get_size(screen))
	return DisplayServer.screen_get_usable_rect(screen)


func _apply_plan(plan: Dictionary, screen: int, has_main: bool) -> void:
	if has_main:
		_position_main_window(plan["main"], plan["main_fullscreen"], screen)
	if plan["tabbed"]:
		if plan["tab_overlay"]:
			_make_overlay_host(plan["tab_roles"])
		else:
			_spawn_packed_window(plan["tab_roles"], plan["tab_region"])
		return
	var tiles: Dictionary = plan["tiles"]
	for role: String in tiles:
		_spawn_window(role, tiles[role])


func _position_main_window(rect: Rect2i, fullscreen: bool, screen: int) -> void:
	var win := get_window()
	if fullscreen:
		_main_shares_screen = false
		win.current_screen = screen
		win.mode = Window.MODE_FULLSCREEN
		return
	# Sharing the screen with the panel strip. Leave fullscreen first — geometry
	# written to a fullscreen window is ignored — and set borderless before the
	# rect, because while it's false `position` means the client origin and the
	# window lands a title bar too low.
	_main_shares_screen = true
	win.mode = Window.MODE_WINDOWED
	win.borderless = true
	win.size = rect.size
	win.position = rect.position


## Give the whole Main screen back before the chooser is drawn over it:
## _teardown() has already closed the strip's windows, so a Main window still
## sitting at two thirds height would leave the bottom third showing the desktop.
## A no-op unless the window was actually shrunk, so the launch card and a
## four-monitor rig keep the size they always had. Deliberately not inside
## _teardown() itself — _place_all() calls that too, and would flash fullscreen
## on every F5 rebuild.
func _restore_main_window() -> void:
	if not _main_shares_screen or DisplayServer.get_name() == "headless":
		return
	_main_shares_screen = false
	var win := get_window()
	win.current_screen = DisplayConfig.get_screen_for_role(DisplayConfig.ROLE_MAIN)
	win.mode = Window.MODE_FULLSCREEN


func _spawn_window(role: String, rect: Rect2i) -> void:
	var packed: PackedScene = load(SECONDARY_SCENES[role])
	var win: Window = packed.instantiate()
	win.title = "Salvager — %s" % role.capitalize()
	win.borderless = true
	# Tiles are placed, not dragged: Aero Snap on a focused borderless window
	# would otherwise let a stray Win+Arrow pull one out of its rect.
	win.unresizable = true
	win.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	win.position = rect.position
	win.size = rect.size
	add_child(win)
	_windows.append(win)


func _spawn_packed_window(roles: Array, rect: Rect2i) -> void:
	var win := Window.new()
	win.title = "Salvager — " + _roles_title(roles)
	win.borderless = true
	win.unresizable = true
	win.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	# _harvest_content throws away each scene's own Window, and with it the
	# content scale that keeps a panel's layout intact at a size other than the
	# one it was drawn at. Put it back on the host, sized to the largest canvas
	# among the roles it carries.
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = _shared_canvas(roles)
	# The same script the tiled windows get from their scenes, so a packed host
	# answers Esc and the window close button like every other display.
	win.set_script(RoleWindowScript)
	win.position = rect.position
	win.size = rect.size
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


## The canvas one host window has to serve for every panel it carries: the
## componentwise largest, so no role is laid out in less room than it asks for.
func _shared_canvas(roles: Array) -> Vector2i:
	var canvas := ScreenLayoutScript.DEFAULT_CANVAS
	for role: String in roles:
		var role_canvas: Vector2i = ROLE_CANVAS.get(role, ScreenLayoutScript.DEFAULT_CANVAS)
		canvas = Vector2i(maxi(canvas.x, role_canvas.x), maxi(canvas.y, role_canvas.y))
	return canvas


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
