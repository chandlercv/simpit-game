extends Node
## Headless load check: instantiates every display window scene (WindowManager
## skips them under the headless DisplayServer) plus the world scene, runs a
## few frames so _ready/_process/_draw paths execute, and quits. Script errors
## surface on stderr:
##
##   godot --headless res://tools/DisplayLoadCheck.tscn

const SCENES := [
	"res://scenes/displays/TacticalWindow.tscn",
	"res://scenes/displays/MfdWindow.tscn",
	"res://scenes/displays/CameraWindow.tscn",
	"res://scenes/boot/Boot.tscn",
]


func _ready() -> void:
	for path: String in SCENES:
		var packed: PackedScene = load(path)
		add_child(packed.instantiate())
		print("loaded: " + path)
	_finish.call_deferred()


func _finish() -> void:
	# A handful of frames so per-frame UI code runs against live GameState.
	for i in 30:
		await get_tree().process_frame
	# Force the states the Tactical/HUD draw paths branch on (scanned graph,
	# selection, live cut) so a windowed run exercises them; _draw is skipped
	# under the headless DisplayServer.
	GameState.set_sensor_mode("STRUCT")
	GameState.wreck["scanned"] = true
	SalvageSystem.select_member(GameState.wreck["members"][0]["id"])
	GameState.wreck["cutting_id"] = GameState.wreck["members"][2]["id"]
	GameState.wreck["cut_progress"] = 0.5
	for i in 30:
		await get_tree().process_frame

	# Exercise the restructured navigation/selection intents so their code paths
	# run (page switching, camera views, cut/contact cycling) — a runtime error in
	# any of them surfaces on stderr here rather than only in a live playtest.
	for unit in get_tree().get_nodes_in_group("mfd_unit"):
		unit.go_home()
		unit.page_step(1)
		unit.page_step(-1)
	for view: String in GameState.EXTERNAL_VIEWS:
		GameState.set_external_view(view)
	GameState.cycle_external_view()
	GameState.cycle_tactical_view()
	GameState.set_tactical_view("SCOPE")
	# Every navigation datum, and the band's own visibility. Each datum is a
	# different resolution path through NavReference, and each one repaints the
	# whole Tactical band — a divide-by-zero on a missing origin surfaces here
	# rather than the first time someone pins a datum in flight.
	for datum: String in GameState.NAV_REFERENCES:
		GameState.set_nav_reference(datum)
	GameState.cycle_nav_reference()
	GameState.toggle_tactical_band()
	GameState.toggle_tactical_band()
	for scale: String in GameState.RATE_SCALES:
		GameState.set_rate_scale(scale)
	GameState.cycle_sensor_mode()
	SalvageSystem.cycle_member(1)
	SalvageSystem.cycle_member(-1)
	GameState.cycle_tracked_contact(1)
	for i in 10:
		await get_tree().process_frame

	print("DISPLAY LOAD CHECK DONE")
	get_tree().quit(0)
