extends Node
## Headless checks for the flexible-display layout: DisplayConfig per-setup
## persistence + prompt gating; the ScreenLayout planner — that arrangements
## partition their region exactly, that each screen shape puts a panel in a cell
## shaped like its canvas, and which tier each monitor topology lands in; that
## ROLE_CANVAS still matches the scenes; the reparent "harvest" that lifts a
## display window's Root content into a RoleTabHost, and the tab-host show/hide
## logic in both overlay and opaque modes. Backs up and restores user://display_config.cfg
## so it never clobbers a real layout. Script errors (e.g. a %-unique-name that
## didn't survive reparenting) surface on stderr:
##
##   godot --headless res://tools/DisplayLayoutSmoke.tscn

const RoleTabHostScript := preload("res://scenes/displays/RoleTabHost.gd")
const ScreenLayoutScript := preload("res://scenes/displays/ScreenLayout.gd")

## The three secondary roles, in the order WindowManager lays them out.
const ROLES := ["tactical", "mfd", "camera"]

var _failures: Array[String] = []
var _cfg_backup: PackedByteArray = PackedByteArray()
var _had_cfg := false


func _ready() -> void:
	_backup_cfg()
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	_test_defaults_and_prompt()
	_test_persistence()
	_test_partitions()
	_test_arrangements()
	_test_topologies()
	_test_sharing_line()
	_test_canvas_table()
	await _test_harvest_and_host()
	_restore_cfg()

	if _failures.is_empty():
		print("DISPLAY LAYOUT SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("DISPLAY LAYOUT SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


func _test_defaults_and_prompt() -> void:
	_check(InputMap.has_action("redetect_displays"),
			"redetect_displays action registered (F5)")
	_check(InputMap.has_action("open_display_setup"),
			"open_display_setup action registered (F6)")

	_delete_cfg()
	DisplayConfig.reload()
	var count := maxi(DisplayServer.get_screen_count(), 1)

	var main_screen := DisplayConfig.get_screen_for_role(DisplayConfig.ROLE_MAIN)
	_check(main_screen == DisplayServer.get_primary_screen(),
			"default MAIN maps to the primary screen")
	var in_range := true
	for role in DisplayConfig.ALL_ROLES:
		var s := DisplayConfig.get_screen_for_role(role)
		if s < 0 or s >= count:
			in_range = false
	_check(in_range, "every role defaults to a valid screen index")

	if count < DisplayConfig.ALL_ROLES.size():
		_check(DisplayConfig.needs_setup_prompt(),
				"prompts when unconfigured and fewer screens than roles")
	else:
		_check(not DisplayConfig.needs_setup_prompt(),
				"no prompt when every role can get its own screen")


func _test_persistence() -> void:
	_delete_cfg()
	DisplayConfig.reload()
	for role in DisplayConfig.ALL_ROLES:
		DisplayConfig.set_role_screen(role, 0)
	DisplayConfig.commit_all()
	_check(DisplayConfig.has_layout_for_current_setup(),
			"setup counts as configured after commit_all")
	_check(not DisplayConfig.needs_setup_prompt(),
			"no prompt once the setup is configured")

	# Round-trip: a fresh reload must read the saved layout back.
	DisplayConfig.reload()
	_check(DisplayConfig.has_layout_for_current_setup(),
			"saved layout survives reload")
	_check(DisplayConfig.get_screen_for_role(DisplayConfig.ROLE_CAMERA) == 0,
			"reloaded role mapping matches what was saved")


# --- Layout planner (pure geometry, no display server) ---------------------

## Whatever shape a region is cut into, the pieces must cover it exactly: no
## overlap, no seam, nothing falling outside. This is the invariant that breaks
## the moment someone rounds tile *sizes* instead of the cuts between them.
func _test_partitions() -> void:
	var regions := [
		Rect2i(0, 0, 1920, 1032), Rect2i(-1920, 0, 2560, 1440),
		Rect2i(7, 11, 1367, 769), Rect2i(0, 0, 1080, 1920),
	]
	var exact := true
	var disjoint := true
	var positive := true
	for region: Rect2i in regions:
		for n in range(1, 4):
			var roles := ROLES.slice(0, n)
			for tiles: Dictionary in [
					ScreenLayoutScript.tile_strip(region, roles),
					ScreenLayoutScript.tile_screen(region, roles)]:
				var area := 0
				var rects: Array[Rect2i] = []
				for role: String in tiles:
					var rect: Rect2i = tiles[role]
					if rect.size.x <= 0 or rect.size.y <= 0:
						positive = false
					if not region.encloses(rect):
						exact = false
					area += rect.size.x * rect.size.y
					for other in rects:
						if other.intersects(rect):
							disjoint = false
					rects.append(rect)
				if area != region.size.x * region.size.y:
					exact = false
	_check(positive, "no arrangement ever emits a zero-size tile")
	_check(disjoint, "tiles in an arrangement never overlap")
	_check(exact, "tiles cover their region exactly, with no seam or spill")

	# An odd height must not lose a row between the flight view and the strip.
	var split := ScreenLayoutScript.split_main(Rect2i(7, 11, 1921, 1033))
	var main: Rect2i = split["main"]
	var strip: Rect2i = split["strip"]
	_check(main.size.y + strip.size.y == 1033 and strip.position.y == main.end.y
			and main.position == Vector2i(7, 11),
			"an odd screen height splits into main + strip with nothing lost")


## The arrangement tables put each panel in a cell shaped like the canvas it was
## drawn for.
func _test_arrangements() -> void:
	var strip := ScreenLayoutScript.tile_strip(Rect2i(0, 688, 1920, 344), ROLES)
	_check(strip["tactical"] == Rect2i(0, 688, 640, 344)
			and strip["mfd"] == Rect2i(640, 688, 640, 344)
			and strip["camera"] == Rect2i(1280, 688, 640, 344),
			"the Main screen's strip splits into equal columns, left to right")

	var spare := ScreenLayoutScript.tile_screen(Rect2i(1920, 0, 1920, 1032), ROLES)
	_check(spare["mfd"] == Rect2i(1920, 516, 1920, 516),
			"a shared spare screen gives the MFDs the full-width bottom row")
	_check(spare["tactical"] == Rect2i(1920, 0, 960, 516)
			and spare["camera"] == Rect2i(2880, 0, 960, 516),
			"tactical and camera share the row above it")

	var pair := ScreenLayoutScript.tile_screen(Rect2i(0, 0, 1920, 1032), ["mfd", "camera"])
	_check(pair["camera"].size.x == 1920 and pair["mfd"].size.x == 1920
			and pair["mfd"].position.y > pair["camera"].position.y,
			"two roles on a spare screen stack into full-width rows, MFD lowest")

	var lone := ScreenLayoutScript.tile_screen(Rect2i(3840, 0, 1920, 1080), ["camera"])
	_check(lone["camera"] == Rect2i(3840, 0, 1920, 1080),
			"a role alone on a screen still covers it edge to edge")

	_check(ScreenLayoutScript.tile_screen(Rect2i(0, 0, 1920, 1032), ROLES)
			== ScreenLayoutScript.tile_screen(Rect2i(0, 0, 1920, 1032), ROLES),
			"an arrangement is deterministic")


## The tier each monitor topology lands in, which is the whole point of the change.
func _test_topologies() -> void:
	var one := ScreenLayoutScript.plan_screen(
			Rect2i(0, 0, 1920, 1032), true, ROLES, WindowManager.ROLE_CANVAS)
	_check(not one["main_fullscreen"] and one["main"] == Rect2i(0, 0, 1920, 688)
			and not one["tabbed"] and one["tiles"].size() == 3,
			"one 1080p screen flies over three tiled displays in the bottom third")

	var short := ScreenLayoutScript.plan_screen(
			Rect2i(0, 0, 1366, 720), true, ROLES, WindowManager.ROLE_CANVAS)
	_check(short["main_fullscreen"] and short["tabbed"] and short["tab_overlay"]
			and short["tiles"].is_empty(),
			"a screen too short to dock legibly keeps the pre-tiling overlay")

	var spare := ScreenLayoutScript.plan_screen(
			Rect2i(1920, 0, 1920, 1032), false, ROLES, WindowManager.ROLE_CANVAS)
	_check(not spare["tabbed"] and spare["tiles"].size() == 3,
			"two monitors put tactical, MFD and camera up at once")

	var alone := ScreenLayoutScript.plan_screen(
			Rect2i(0, 0, 1920, 1080), true, [], WindowManager.ROLE_CANVAS)
	_check(alone["main_fullscreen"] and alone["tiles"].is_empty() and not alone["tabbed"],
			"MAIN alone on a screen is still fullscreen on it")

	# Whatever tier a topology lands in, every role must come out somewhere.
	var kept := true
	var readable := true
	for w in [1024, 1280, 1366, 1600, 1920, 2560, 3440, 3840]:
		for h in [600, 720, 768, 1080, 1440, 2160]:
			for has_main in [true, false]:
				for n in range(1, 4):
					var roles := ROLES.slice(0, n)
					var plan := ScreenLayoutScript.plan_screen(
							Rect2i(0, 0, w, h), has_main, roles, WindowManager.ROLE_CANVAS)
					var placed: Array = plan["tab_roles"] if plan["tabbed"] \
							else plan["tiles"].keys()
					if placed.size() != n:
						kept = false
					for role: String in placed:
						if not roles.has(role):
							kept = false
					for role: String in plan["tiles"]:
						var scale: float = ScreenLayoutScript.scale_for(
								plan["tiles"][role], WindowManager.ROLE_CANVAS[role])
						if scale < ScreenLayoutScript.MIN_SCALE:
							readable = false
	_check(kept, "no screen shape or role count ever drops a display")
	_check(readable, "a tiled panel is never scaled below MIN_SCALE of its canvas")


## The launch card's one-line summary of what a rig's shared screens will do.
## Built here from hand-made plans because the card can't be shown a second
## monitor headlessly — and because the case that was wrong is precisely a rig
## whose shared screens land in different tiers.
func _test_sharing_line() -> void:
	# A short screen carrying MAIN and one panel: too little room to dock, so
	# that screen tabs. A spare 1080p screen carrying the other two tiles.
	var tabbed_main := ScreenLayoutScript.plan_screen(
			Rect2i(0, 0, 1366, 720), true, ["tactical"], WindowManager.ROLE_CANVAS)
	var tiled_spare := ScreenLayoutScript.plan_screen(
			Rect2i(1920, 0, 1920, 1032), false, ["mfd", "camera"], WindowManager.ROLE_CANVAS)
	var tabbed_spare := ScreenLayoutScript.plan_screen(
			Rect2i(1920, 0, 800, 480), false, ["mfd", "camera"], WindowManager.ROLE_CANVAS)
	var lone_tabbed := ScreenLayoutScript.plan_screen(
			Rect2i(3840, 0, 400, 200), false, ["camera"], WindowManager.ROLE_CANVAS)
	var main_alone := ScreenLayoutScript.plan_screen(
			Rect2i(0, 0, 1920, 1080), true, [], WindowManager.ROLE_CANVAS)
	var all_tiled := ScreenLayoutScript.plan_screen(
			Rect2i(0, 0, 1920, 1032), true, ROLES, WindowManager.ROLE_CANVAS)
	_check(tabbed_main["tabbed"] and tabbed_spare["tabbed"] and lone_tabbed["tabbed"]
			and not tiled_spare["tabbed"] and not all_tiled["tabbed"],
			"the sharing-line fixtures land in the tiers the checks below assume")

	var mixed := ScreenLayoutScript.describe_sharing({0: tabbed_main, 1: tiled_spare}, 0)
	_check(mixed.contains("screen 0") and mixed.contains("tiles the rest"),
			"a rig with one tabbed and one tiled shared screen names the tabbed one")
	_check(not mixed.contains("screens "),
			"one tabbed screen is named in the singular")

	_check(ScreenLayoutScript.describe_sharing({0: tabbed_main, 1: tabbed_spare}, 0)
			== "displays sharing a screen are too tight to tile — LAUNCH tabs them instead",
			"every shared screen tabbing is still reported as one plain outcome")
	_check(ScreenLayoutScript.describe_sharing({0: main_alone, 1: tiled_spare}, 0)
			== "displays sharing a screen are tiled side by side",
			"every shared screen tiling is still reported as one plain outcome")

	# A single role on a screen too small for it tabs, but it shares with nothing
	# — reading the tier off that plan used to call the whole rig tabbed.
	_check(ScreenLayoutScript.describe_sharing(
			{0: main_alone, 1: tiled_spare, 2: lone_tabbed}, 0)
			== "displays sharing a screen are tiled side by side",
			"a lone role tabbing on its own screen is not a sharing outcome")

	# More tabbed shared screens than one only arrives with a fourth panel role,
	# but the sentence they'd be named in is written, so it is checked.
	var two_tabbed := ScreenLayoutScript.describe_sharing(
			{0: tabbed_main, 1: tiled_spare, 2: tabbed_spare}, 0)
	_check(two_tabbed.begins_with("screens 0 and 2 are too tight to tile"),
			"two tabbed shared screens are listed, in screen order")
	# Plan order must not decide the wording: the same rig, iterated the other way.
	_check(ScreenLayoutScript.describe_sharing({1: tiled_spare, 0: tabbed_main}, 0) == mixed,
			"the summary doesn't depend on which screen's plan comes first")

## The planner measures tiles against a table of canvases; a .tscn edit must not
## be able to move the real one out from under it.
func _test_canvas_table() -> void:
	var matched := true
	for role: String in WindowManager.SECONDARY_SCENES:
		var packed: PackedScene = load(WindowManager.SECONDARY_SCENES[role])
		var win: Window = packed.instantiate()
		if win.content_scale_size != WindowManager.ROLE_CANVAS.get(role) \
				or win.content_scale_mode != Window.CONTENT_SCALE_MODE_CANVAS_ITEMS \
				or win.content_scale_aspect != Window.CONTENT_SCALE_ASPECT_EXPAND:
			matched = false
		win.free()
	_check(matched, "ROLE_CANVAS matches the content scale each scene authors")


func _test_harvest_and_host() -> void:
	# Opaque host with all three secondary roles harvested from their windows.
	var host := RoleTabHostScript.new()
	host.configure(true)
	var roles := ["tactical", "mfd", "camera"]
	for role in roles:
		host.add_role(role, WindowManager._harvest_content(role))
	host.finish()
	var w := Window.new()
	w.add_child(host)
	add_child(w)
	# Frames so each reparented content's _ready runs (this is where a broken
	# %-unique-name lookup would error to stderr).
	for i in 20:
		await get_tree().process_frame

	_check(host._panels.size() == 3, "host hosts all three harvested panels")
	_check(host._panels["tactical"].visible and not host._panels["mfd"].visible,
			"opaque host shows the first role on finish()")
	host._select_index(1)
	_check(host._panels["mfd"].visible and not host._panels["tactical"].visible,
			"selecting a tab swaps the visible panel")
	# The reparented content kept its subtree (a %-lookup node resolves).
	var unit: Node = host._panels["mfd"].find_child("MfdUnit*", true, false)
	_check(unit != null, "reparented MFD content kept an MfdUnit subtree")
	w.queue_free()

	# Overlay host starts clean (Main visible), toggles a panel up and back.
	var ov := RoleTabHostScript.new()
	ov.configure(false)
	for role in roles:
		ov.add_role(role, WindowManager._harvest_content(role))
	ov.finish()
	var w2 := Window.new()
	w2.add_child(ov)
	add_child(w2)
	for i in 10:
		await get_tree().process_frame
	_check(ov._active == "" and not ov._holder.visible,
			"overlay host starts on MAIN with no panel shown")
	ov._select_index(0)
	_check(ov._holder.visible and ov._scrim.visible,
			"overlay raises the dimmed panel when a role is selected")
	ov._toggle()
	_check(ov._active == "" and not ov._holder.visible,
			"overlay backtick/MAIN toggle hides the panel again")
	w2.queue_free()


# --- config backup/restore -------------------------------------------------

func _backup_cfg() -> void:
	if FileAccess.file_exists(DisplayConfig.CONFIG_PATH):
		_had_cfg = true
		_cfg_backup = FileAccess.get_file_as_bytes(DisplayConfig.CONFIG_PATH)


func _restore_cfg() -> void:
	if _had_cfg:
		var f := FileAccess.open(DisplayConfig.CONFIG_PATH, FileAccess.WRITE)
		f.store_buffer(_cfg_backup)
		f.close()
	else:
		_delete_cfg()
	DisplayConfig.reload()


func _delete_cfg() -> void:
	if FileAccess.file_exists(DisplayConfig.CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DisplayConfig.CONFIG_PATH))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
