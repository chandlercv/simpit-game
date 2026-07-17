extends Node
## Headless load check: instantiates every display window scene (WindowManager
## skips them under the headless DisplayServer) plus the world scene, runs a
## few frames so _ready/_process/_draw paths execute, and quits. Script errors
## surface on stderr:
##
##   godot --headless res://tools/DisplayLoadCheck.tscn

const SCENES := [
	"res://scenes/displays/TacticalWindow.tscn",
	"res://scenes/displays/TabletWindow.tscn",
	"res://scenes/displays/StarChartWindow.tscn",
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
	print("DISPLAY LOAD CHECK DONE")
	get_tree().quit(0)
