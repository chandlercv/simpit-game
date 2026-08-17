extends Node
## Renders the main hull-camera view for a hundred frames and saves a PNG so
## graphics changes can be eyeballed without a full playtest:
##
##   godot --path . res://tools/ScreenshotCheck.tscn ++ <output.png> [close] [title|manual|terminal] [<chapter-id>]
##
## Defaults to user://main_view.png. `close` parks the ship at cutting range;
## `title` puts the launch title card over the view, the way it appears at boot;
## `manual` opens the pilot's handbook over that card and `terminal` opens the
## terminal procedures, which is the only way to eyeball their layout short of
## launching the game. Add a chapter id to shoot a specific page.
## Runs windowed (rendering needs a real DisplayServer); WindowManager leaves
## tools scenes alone, so only the one window flashes up — and, for the same
## reason, the title card here is built directly rather than by the launch flow.

const TitleCardScript := preload("res://scenes/displays/TitleCard.gd")
const ManualContentScript := preload("res://scenes/displays/PilotManualContent.gd")
const TerminalContentScript := preload("res://scenes/displays/TerminalProceduresContent.gd")


func _ready() -> void:
	get_window().size = Vector2i(1720, 720)
	# Main display only. The Camera display can't be shot here: it borrows the Main
	# world through WindowManager, which deliberately leaves tools scenes alone, so
	# its viewport would come out empty. The BELLY landing view is checked by
	# assertion in DockSmoke instead.
	var scene: PackedScene = load("res://scenes/displays/MainViewWindow.tscn")
	add_child(scene.instantiate())
	var args := OS.get_cmdline_user_args()
	# A document is opened BY the card (it owns the layer), so `manual`/`terminal`
	# imply `title` — asking for the page without the screen it hangs off would
	# have to build it a second way, and then it wouldn't be the thing players see.
	if args.has("title") or args.has("manual") or args.has("terminal"):
		var layer := CanvasLayer.new()
		layer.layer = 15
		add_child(layer)
		var card: Control = TitleCardScript.new()
		layer.add_child(card)
		card.start()
		if args.has("manual") or args.has("terminal"):
			var doc := "terminal" if args.has("terminal") else "manual"
			card._open_document(doc)
			# A chapter can be named to shoot it specifically, e.g.
			# `manual checklist-arrival`; otherwise the manual's own first chapter.
			# Matched against the catalog rather than a name pattern, so every
			# chapter is reachable and a typo'd id is reported instead of silently
			# shooting the front page.
			var ids: PackedStringArray = []
			var catalog: Array = (TerminalContentScript.CHAPTERS if doc == "terminal"
					else ManualContentScript.CHAPTERS)
			for chapter: Dictionary in catalog:
				ids.append(String(chapter["id"]))
			for arg in args:
				if ids.has(arg):
					card._manual_ui.show_chapter(arg)
				elif not ["manual", "terminal", "title"].has(arg) and not arg.ends_with(".png"):
					push_warning("no %s chapter '%s'; ids: %s" % [doc, arg, ", ".join(ids)])
	_shoot.call_deferred()


func _shoot() -> void:
	# Freeze the glance rig at forward-center: a held HOTAS button that maps
	# to a DPAD code would otherwise yaw every screenshot.
	var rig := find_child("HullCameraRig", true, false)
	if rig:
		rig.set_process(false)
	# The "close" flag parks the ship at cutting range so the working view can be
	# judged, not just the arrival view.
	if OS.get_cmdline_user_args().has("close"):
		var ship: Dictionary = GameState.local_ship()
		var t: Transform3D = ship["transform"]
		t.origin = Vector3(1.5, 0.5, -29.0)
		ship["transform"] = t
	# The "berth" flag flies out to the station and parks on short final, looking
	# down into the bay — the one view that can't be judged from the claim, and
	# the one where a geometry mistake in the berth actually shows up.
	if OS.get_cmdline_user_args().has("berth"):
		await _park_on_final()
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


## Start a real approach and put the ship on short final over the pad, gear down,
## nose pitched into the descent — what the pilot sees on the way in.
func _park_on_final() -> void:
	# A physical throttle resting off-centre would fly the ship out of the shot
	# during the hundred frames below — the same reason the glance rig is frozen.
	# Silence InputRouter and its raw-HID children for the duration.
	InputRouter.set_process(false)
	for child in InputRouter.get_children():
		child.set_process(false)
	Engine.time_scale = 10.0
	MarketSystem.request_dock(0)
	var waited := 0.0
	while GameState.run_phase != "APPROACH" and waited < 30.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	GameState.set_landing_gear(true)
	while not GameState.gear_locked_down() and waited < 60.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	# Actually fly the pattern to FINAL rather than teleporting to the pad with
	# the approach still reading INBOUND: state drives what the scene shows (gate
	# rings hide once flown), so a shortcut here would photograph a view no pilot
	# ever sees.
	_place(DockingSystem.gate_world(0), 0.0)
	while GameState.docking_state != "CLEARED" and waited < 200.0:
		GameState.local_ship()["velocity"] = Vector3.ZERO
		await get_tree().process_frame
		waited += get_process_delta_time()
	for i in range(1, DockingSystem.GATES.size()):
		_place(DockingSystem.gate_world(i), 0.0)
		await get_tree().process_frame
		await get_tree().process_frame
	Engine.time_scale = 1.0
	var height := 9.0
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("alt="):
			height = String(arg).trim_prefix("alt=").to_float()
	_place(DockingSystem.pad_world(), height)


## Park the ship at `at`, lifted `height` along the pad's up axis, WINGS LEVEL on
## the lane's heading.
##
## Level specifically, and not pitched down at the deck: a landing has to be
## flown within TILT_LIMIT_DEG of level, so a nose-down pose is an attitude no
## pilot could ever touch down in. Posing it that way to get the pad in the
## forward camera photographs a lie — the bow ends up against the deck, which is
## a failed landing, not an approach. Use the BELLY view to see the pad.
func _place(at: Vector3, height: float) -> void:
	var up: Vector3 = DockingSystem.pad_up()
	var ship: Dictionary = GameState.local_ship()
	ship["transform"] = Transform3D(
			Basis.looking_at(DockingSystem.pad_forward(), up), at + up * height)
	ship["velocity"] = Vector3.ZERO
