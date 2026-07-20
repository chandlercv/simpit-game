extends Node
## Headless checks for the flexible-display layout: DisplayConfig per-setup
## persistence + prompt gating, the reparent "harvest" that lifts a display
## window's Root content into a RoleTabHost, and the tab-host show/hide logic in
## both overlay and opaque modes. Backs up and restores user://display_config.cfg
## so it never clobbers a real layout. Script errors (e.g. a %-unique-name that
## didn't survive reparenting) surface on stderr:
##
##   godot --headless res://tools/DisplayLayoutSmoke.tscn

const RoleTabHostScript := preload("res://scenes/displays/RoleTabHost.gd")

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
	_check(DisplayConfig.get_screen_for_role(DisplayConfig.ROLE_CHART) == 0,
			"reloaded role mapping matches what was saved")


func _test_harvest_and_host() -> void:
	# Opaque host with all three secondary roles harvested from their windows.
	var host := RoleTabHostScript.new()
	host.configure(true)
	var roles := ["tactical", "tablet", "chart"]
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
	_check(host._panels["tactical"].visible and not host._panels["tablet"].visible,
			"opaque host shows the first role on finish()")
	host._select_index(1)
	_check(host._panels["tablet"].visible and not host._panels["tactical"].visible,
			"selecting a tab swaps the visible panel")
	# The reparented content kept its subtree (a %-lookup node resolves).
	var inv: Node = host._panels["tablet"].find_child("InventoryGrid", true, false)
	_check(inv != null, "reparented Tablet content kept its InventoryGrid subtree")
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
