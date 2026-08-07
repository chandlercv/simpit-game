extends Node
## Headless checks for the launch flow: the scenario catalog + its intents, and
## the title card itself — that it builds, reports the live display/controls
## state, and that LAUNCH commits the scenario exactly once. Backs up and
## restores user://display_config.cfg so it never clobbers a real layout.
##
##   godot --headless res://tools/TitleCardSmoke.tscn
##
## WindowManager's own launch sequencing (card → chooser → windows, and the pause
## it holds meanwhile) is display-server work and can't run headless; this covers
## the state machine underneath it.

const TitleCardScript := preload("res://scenes/displays/TitleCard.gd")

var _failures: Array[String] = []
var _cfg_backup: PackedByteArray = PackedByteArray()
var _had_cfg := false
## Signal probes. Members, not lambda-captured locals: a GDScript lambda captures
## by VALUE, so a counter local to the test would never see the increment.
var _changed_to := ""
var _launch_count := 0


func _ready() -> void:
	_backup_cfg()
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	_test_catalog()
	_test_selection()
	await _test_card()
	_test_launch()
	_restore_cfg()

	if _failures.is_empty():
		print("TITLE CARD SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("TITLE CARD SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


func _test_catalog() -> void:
	_check(not GameState.SCENARIOS.is_empty(), "at least one scenario is offered")
	var well_formed := true
	for entry: Dictionary in GameState.SCENARIOS:
		for field in ["id", "name", "subtitle", "blurb"]:
			if String(entry.get(field, "")).is_empty():
				well_formed = false
	_check(well_formed, "every scenario carries id/name/subtitle/blurb")
	_check(GameState.scenario_def(GameState.scenario).has("name"),
			"the default selection resolves to a scenario")
	_check(GameState.scenario_def("nope").is_empty(),
			"an unknown id resolves to no scenario")
	_check(not GameState.scenario_started,
			"a scenario is not started before LAUNCH")


func _test_selection() -> void:
	# Selecting the (only) shipped scenario is a no-op; an unknown id must not
	# leave the card pointing at nothing.
	var before := GameState.scenario
	GameState.scenario_changed.connect(_on_scenario_changed)
	GameState.set_scenario("definitely-not-a-scenario")
	_check(GameState.scenario == before, "an unknown id leaves the selection alone")
	_check(_changed_to.is_empty(), "an unknown id emits no selection change")
	GameState.set_scenario(before)
	_check(_changed_to.is_empty(), "re-picking the current scenario emits nothing")
	GameState.scenario_changed.disconnect(_on_scenario_changed)


func _on_scenario_changed(id: String) -> void:
	_changed_to = id


func _test_card() -> void:
	var card: Control = TitleCardScript.new()
	add_child(card)
	card.start()
	await get_tree().process_frame

	_check(card._scenario_buttons.size() == GameState.SCENARIOS.size(),
			"one scenario button per catalog entry")
	_check(card._blurb.text == String(GameState.scenario_def(GameState.scenario)["blurb"]),
			"the blurb tracks the selected scenario")
	var mapping_shown := true
	for role in DisplayConfig.ALL_ROLES:
		if not card._display_status.text.contains(role.to_upper()):
			mapping_shown = false
	_check(mapping_shown, "the DISPLAYS row names every display role")
	_check(card._display_status.text.contains("screen"),
			"the DISPLAYS row reports the screen count")
	_check(not card._controls_status.text.is_empty(),
			"the CONTROLS row reports the input situation")

	# A layout change while the card is up is reflected without a rebuild.
	DisplayConfig.set_role_screen(DisplayConfig.ROLE_CAMERA, 0)
	_check(card._display_status.text.contains("CAMERA→0"),
			"reassigning a display refreshes the DISPLAYS row")

	# Stepping out to the display chooser and back keeps the same card.
	card.suspend()
	_check(not card.visible, "the card hides while a setup step is up")
	card.resume()
	_check(card.visible and card._launch_button.has_focus(),
			"the card comes back focused when the step confirms")
	card.queue_free()


func _test_launch() -> void:
	GameState.scenario_launched.connect(_on_scenario_launched)
	GameState.launch_scenario()
	_check(GameState.scenario_started, "LAUNCH starts the scenario")
	_check(_launch_count == 1, "LAUNCH announces the run once")
	GameState.launch_scenario()
	_check(_launch_count == 1, "a second LAUNCH can't restart the run")
	GameState.scenario_launched.disconnect(_on_scenario_launched)


func _on_scenario_launched(_id: String) -> void:
	_launch_count += 1


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
	elif FileAccess.file_exists(DisplayConfig.CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DisplayConfig.CONFIG_PATH))
	DisplayConfig.reload()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
