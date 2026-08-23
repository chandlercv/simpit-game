extends Node
## Renders a display for a hundred frames and saves a PNG so graphics changes can
## be eyeballed without a full playtest:
##
##   godot --path . res://tools/ScreenshotCheck.tscn ++ <output.png> [close|rival] [title|manual|terminal] [<chapter-id>]
##   godot --path . res://tools/ScreenshotCheck.tscn ++ <output.png> mfd [<page>] [<procedure>]
##
## Defaults to user://main_view.png. `close` parks the ship at cutting range;
## `rival` stands ThreatSystem's rival cutter and patrol up in front of the camera
## with the rival's torch firing, which is how their models and the exterior light
## fit get judged without waiting out a spawn window in a real run;
## `title` puts the launch title card over the view, the way it appears at boot;
## `manual` opens the pilot's handbook over that card and `terminal` opens the
## terminal procedures, which is the only way to eyeball their layout short of
## launching the game. Add a chapter id to shoot a specific page.
##
## `mfd` shoots the MFD display instead of the Main view, at its real 1280x800
## canvas — the MENU home by default, or a named page (`mfd DOCK`), and for the
## CHECKLIST page a named procedure (`mfd CHECKLIST cutting`). This is how MFD
## layout and type sizing get judged short of the physical panel.
##
## Runs windowed (rendering needs a real DisplayServer); WindowManager leaves
## tools scenes alone, so only the one window flashes up — and, for the same
## reason, the title card here is built directly rather than by the launch flow.

const TitleCardScript := preload("res://scenes/displays/TitleCard.gd")
const ManualContentScript := preload("res://scenes/displays/PilotManualContent.gd")
const TerminalContentScript := preload("res://scenes/displays/TerminalProceduresContent.gd")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("mfd"):
		_build_mfd(args)
		_shoot.call_deferred()
		return
	get_window().size = Vector2i(1720, 720)
	# Main display only. The Camera display can't be shot here: it borrows the Main
	# world through WindowManager, which deliberately leaves tools scenes alone, so
	# its viewport would come out empty. The BELLY landing view is checked by
	# assertion in DockSmoke instead.
	var scene: PackedScene = load("res://scenes/displays/MainViewWindow.tscn")
	add_child(scene.instantiate())
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


## The MFD display, at the 1280x800 canvas it is authored in, with its Root
## content harvested out of the scene's Window the way WindowManager does — a
## Window instantiated as a child would pop a second OS window and shoot empty.
func _build_mfd(args: PackedStringArray) -> void:
	get_window().size = Vector2i(1280, 800)
	# `berth` flies a real approach (see _park_on_final), which needs the world
	# and the station in it — so the Main view goes in underneath, and the MFD's
	# own opaque background then covers it. It is the only way to shoot the DOCK
	# page with its gate checklist live rather than reading NO APPROACH RUNNING.
	if args.has("berth"):
		var main: Node = (load("res://scenes/displays/MainViewWindow.tscn") as PackedScene).instantiate()
		add_child(main)
		# Its HUD sits on a CanvasLayer, which draws over the MFD regardless of
		# tree order — the world is wanted here, the other display's instruments
		# are not.
		for node in main.find_children("*", "CanvasLayer", true, false):
			(node as CanvasLayer).visible = false
	var window: Window = load("res://scenes/displays/MfdWindow.tscn").instantiate()
	var root: Control = window.get_node("Root")
	window.remove_child(root)
	root.owner = null   # else reparenting warns that MfdWindow's ownership is now inconsistent
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.free()

	# A page name puts both units on it, so the shot shows the page rather than
	# whichever two the units happen to default to. With no page named, both go
	# to the MENU home — the grid is the thing most worth looking at.
	var pages: Array[String] = MfdUnit.PAGES
	var wanted := ""
	for arg in args:
		if pages.has(arg):
			wanted = arg
			break
	for unit in get_tree().get_nodes_in_group("mfd_unit"):
		if wanted == "":
			unit.go_home()
			continue
		unit.show_page(wanted)
		# ...and on CHECKLIST, a procedure name opens that procedure, since its
		# index is a different view from any of its lists.
		if wanted != "CHECKLIST":
			continue
		var panel: Control = unit._pages["CHECKLIST"]
		for i in panel._lists.size():
			if args.has(String(panel._lists[i]["id"])):
				panel._open_list(i)


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
	# The "rival" flag stands ThreatSystem's two ships up in front of the camera —
	# the only way to look at the rival cutter and the patrol short of waiting out
	# their spawn windows in a real run.
	var rival := OS.get_cmdline_user_args().has("rival")
	if rival:
		await _park_on_the_threats()
	for i in 100:
		# Fire the rival's torch partway through, so the flare is standing when the
		# frame is taken rather than having burnt out before it.
		if rival and i == 55:
			var pos: Vector3 = GameState.get_contact(_rival_id)["position"]
			GameState.rival_cut_fired.emit(pos, GameState.wreck["position"])
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var path := "user://main_view.png"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		path = args[0]
	image.save_png(path)
	print("saved: " + path)
	get_tree().quit(0)


## Where the two AI ships are parked for the "rival" shot, and where the Kestrel
## sits to look at them: close enough that a 3 m hull fills usable frame, far
## enough apart that neither hides the other or sits inside the derelict.
const RIVAL_VIEWPOINT := Vector3(0.0, 0.5, -14.0)
const RIVAL_PARK := Vector3(-2.6, 0.7, -20.5)
const PATROL_PARK := Vector3(2.9, -0.5, -21.5)

var _rival_id := -1


## Force ThreatSystem's spawn windows, freeze the two ships where they can be
## seen, and park the Kestrel looking at them. ThreatSystem is stopped rather than
## slowed once they are placed: the ships hold still for the shot while the lights
## keep flashing at their real rate, which is the whole point of the picture.
func _park_on_the_threats() -> void:
	InputRouter.set_process(false)
	for child in InputRouter.get_children():
		child.set_process(false)
	Engine.time_scale = 10.0
	ThreatSystem._rival_timer = 0.0
	ThreatSystem._patrol_timer = 0.0
	var waited := 0.0
	while (ThreatSystem._rival_contact_id == -1
			or ThreatSystem._patrol_contact_id == -1) and waited < 30.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	Engine.time_scale = 1.0
	ThreatSystem.set_physics_process(false)
	_rival_id = ThreatSystem._rival_contact_id
	_pose_contact(_rival_id, RIVAL_PARK, GameState.wreck["position"])
	_pose_contact(ThreatSystem._patrol_contact_id, PATROL_PARK, RIVAL_VIEWPOINT)
	var ship: Dictionary = GameState.local_ship()
	var t: Transform3D = ship["transform"]
	t.origin = RIVAL_VIEWPOINT
	ship["transform"] = t


func _pose_contact(id: int, at: Vector3, facing: Vector3) -> void:
	var contact := GameState.get_contact(id)
	if contact.is_empty():
		push_warning("ScreenshotCheck: contact %d never spawned" % id)
		return
	contact["position"] = at
	contact["heading"] = (facing - at).normalized()


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
