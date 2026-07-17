extends Node
## Renders the main hull-camera view for a hundred frames and saves a PNG so
## graphics changes can be eyeballed without a full playtest:
##
##   godot --path . res://tools/ScreenshotCheck.tscn ++ <output.png>
##
## Defaults to user://main_view.png. Runs windowed (rendering needs a real
## DisplayServer); WindowManager leaves tools scenes alone, so only the one
## window flashes up.


func _ready() -> void:
	get_window().size = Vector2i(1720, 720)
	var scene: PackedScene = load("res://scenes/displays/MainViewWindow.tscn")
	add_child(scene.instantiate())
	_shoot.call_deferred()


func _shoot() -> void:
	# Freeze the glance rig at forward-center: a held HOTAS button that maps
	# to a DPAD code would otherwise yaw every screenshot.
	var rig := find_child("HullCameraRig", true, false)
	if rig:
		rig.set_process(false)
	# Second user arg "close" parks the ship at cutting range so the working
	# view can be judged, not just the arrival view.
	if OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "close":
		var ship: Dictionary = GameState.local_ship()
		var t: Transform3D = ship["transform"]
		t.origin = Vector3(1.5, 0.5, -29.0)
		ship["transform"] = t
	for i in 100:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var path := "user://main_view.png"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		path = args[0]
	image.save_png(path)
	print("saved: " + path)
	get_tree().quit(0)
