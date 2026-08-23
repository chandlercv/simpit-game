extends Node
## Headless checks for the 3D bodies ThreatSystem's ships wear, and for the
## exterior light fit every hull in the game shares:
##
##  - a contact tagged RIVAL or PATROL stands a hull up under ThreatShips, and
##    removing the contact takes it away again
##  - the hull follows the contact's position and points along its heading
##  - a contact with no kind gets NO hull, which is what keeps this node off the
##    derelict, the debris and the station's traffic — all of which are contacts
##    too, and all of which are drawn somewhere else
##  - both models fit inside ThreatSystem.SHIP_CONTACT_RADIUS. tools/build_ships.py
##    asserts the same thing at export; this is the half that catches a .glb
##    re-exported from something else, or the constant moving underneath it
##  - the light fit is measured off the hull it is bolted to, carries every group,
##    and its groups can be switched
##  - the Kestrel wears the same fit, follows the bus with it, and keeps her own
##    lamps off the hull camera — a two-file contract (ShipLights' layer and
##    HullCameraRig's cull_mask) that does nothing unless both halves agree
##
##   godot --headless res://tools/ThreatShipsSmoke.tscn

const WORLD_SCENE := "res://scenes/world/DebrisField.tscn"

var _failures: Array[String] = []
var _world: Node3D
var _ships: Node3D


func _ready() -> void:
	Engine.time_scale = 10.0
	Engine.physics_ticks_per_second = roundi(60.0 * Engine.time_scale)
	InputRouter.set_process(false)
	for child in InputRouter.get_children():  # silence raw-HID children — a real
		child.set_process(false)              # switch panel would drive the test
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame

	# ThreatSystem is stopped for the duration: its own spawn windows would put a
	# second rival in the volume mid-test and move the one being measured.
	ThreatSystem.set_physics_process(false)
	ThreatSystem.reset_run()

	_world = load(WORLD_SCENE).instantiate()
	add_child(_world)
	for _i in 6:
		await get_tree().physics_frame
	_ships = _world.get_node_or_null("ThreatShips")
	_check(_ships != null, "the world scene carries a ThreatShips node")
	if _ships == null:
		_finish()
		return

	await _test_spawning()
	await _test_pose()
	_test_model_fits()
	await _test_lights()
	await _test_own_ship_fit()
	_finish()


# --- One hull per threat contact --------------------------------------------

func _test_spawning() -> void:
	_check(_hulls() == 0, "no hulls before anything is registered")

	var rival := GameState.register_contact("RIVAL CUTTER", Vector3(0, 0, -60),
			true, ThreatSystem.SHIP_CONTACT_RADIUS, "RIVAL")
	await get_tree().process_frame
	_check(_hulls() == 1, "a RIVAL contact stands one hull up")

	var patrol := GameState.register_contact("FREEHOLD PATROL", Vector3(20, 0, -60),
			true, ThreatSystem.SHIP_CONTACT_RADIUS, "PATROL")
	await get_tree().process_frame
	_check(_hulls() == 2, "a PATROL contact stands up a second")

	# The guard that matters: everything else in `contacts` is drawn elsewhere, so
	# a kind this node does not know must produce nothing rather than a warning and
	# a duplicate. The derelict and the debris chunks register exactly like this.
	var blip := GameState.register_contact("DERELICT FRIGATE", Vector3(0, 0, -40))
	var tug := GameState.register_contact("LANE TUG", Vector3(0, 0, -50), false, 3.5)
	await get_tree().process_frame
	_check(_hulls() == 2, "a contact with no kind gets no hull of its own")

	GameState.remove_contact(blip)
	GameState.remove_contact(tug)
	GameState.remove_contact(patrol)
	await get_tree().process_frame
	# queue_free lands at the end of the frame, so give it one to take effect.
	await get_tree().process_frame
	_check(_hulls() == 1, "removing a contact frees its hull")

	GameState.remove_contact(rival)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_hulls() == 0, "...and the last one leaves nothing behind")


# --- The hull follows the contact -------------------------------------------

func _test_pose() -> void:
	var at := Vector3(12.0, -3.0, -70.0)
	var heading := Vector3(-1.0, 0.0, -1.0).normalized()
	var id := GameState.register_contact("RIVAL CUTTER", at, true,
			ThreatSystem.SHIP_CONTACT_RADIUS, "RIVAL")
	var contact := GameState.get_contact(id)
	contact["heading"] = heading
	await get_tree().process_frame
	await get_tree().process_frame

	var hull := _first_hull()
	_check(hull != null, "the posed contact has a hull")
	if hull != null:
		_check(hull.global_position.distance_to(at) < 0.01,
				"the hull sits where the rules put the contact")
		# Models are authored nose along -z, so that is what must line up with the
		# heading the system published.
		var nose := -hull.global_basis.z
		_check(nose.dot(heading) > 0.999, "...and its nose points along the heading")
		_check(absf(hull.global_basis.x.y) < 0.001, "...with the wings level")

	# A contact that has not moved yet carries a zero heading, which cannot orient
	# anything. It must leave the attitude alone rather than throwing.
	var before := hull.global_basis if hull != null else Basis()
	contact["heading"] = Vector3.ZERO
	await get_tree().process_frame
	if hull != null:
		_check(hull.global_basis.is_equal_approx(before),
				"a contact with no heading yet keeps the attitude it had")

	GameState.remove_contact(id)
	await get_tree().process_frame
	await get_tree().process_frame


# --- The models fit the sphere they collide as ------------------------------

func _test_model_fits() -> void:
	for kind: String in ThreatShipsScript.MESHES:
		var path: String = ThreatShipsScript.SHIP_DIR + ThreatShipsScript.MESHES[kind]
		var packed: PackedScene = load(path)
		_check(packed != null, "%s is present (run tools/build_ships.py)" % kind)
		if packed == null:
			continue
		var root: Node3D = packed.instantiate()
		add_child(root)
		var worst := 0.0
		var meshes := 0
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = node
			if mi.mesh == null:
				continue
			meshes += 1
			var to_root := root.global_transform.affine_inverse() * mi.global_transform
			for v: Vector3 in mi.mesh.get_faces():
				worst = maxf(worst, (to_root * v).length())
		_check(meshes > 0, "%s has geometry in it" % kind)
		_check(worst <= ThreatSystem.SHIP_CONTACT_RADIUS,
				"%s fits its collision sphere (%.2f / %.2f m)" % [
					kind, worst, ThreatSystem.SHIP_CONTACT_RADIUS])
		# ...and is not so small the sphere is mostly empty space, which would let
		# the player bounce off nothing.
		_check(worst > ThreatSystem.SHIP_CONTACT_RADIUS * 0.5,
				"%s actually fills its sphere (%.2f m)" % [kind, worst])
		root.queue_free()


# --- The light fit ----------------------------------------------------------

func _test_lights() -> void:
	# Measured off a stand-in hull rather than a real model, so the test states
	# what the fit does with a box rather than restating one .glb's dimensions.
	var host := Node3D.new()
	add_child(host)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 1.0, 6.0)
	mi.mesh = box
	host.add_child(mi)
	await get_tree().process_frame

	var rig := ShipLights.attach(host, host)
	await get_tree().process_frame
	var groups: Dictionary = {}
	for lamp: Dictionary in rig._lamps:
		groups[lamp["group"]] = int(groups.get(lamp["group"], 0)) + 1
	_check(groups.get("NAV", 0) == 3, "three position lights: port, starboard, tail")
	_check(groups.get("STROBE", 0) == 3, "three strobes: both wingtips and the tail")
	_check(groups.get("BEACON", 0) == 2, "two beacons: above and below")

	# The mounts are MEASURED, so they have to land on the box's real extremes
	# rather than on numbers copied out of a model.
	var xs: Array[float] = []
	for lamp: Dictionary in rig._lamps:
		if lamp["group"] == "NAV":
			xs.append((lamp["quad"] as Node3D).position.x)
	xs.sort()
	_check(is_equal_approx(xs[0], -2.0) and is_equal_approx(xs[2], 2.0),
			"the position lights sit on the hull's real wingtips")

	# NAV is steady, so it is the group whose visibility is purely the switch.
	rig.set_group("NAV", false)
	await get_tree().process_frame
	_check(not _any_visible(rig, "NAV"), "switching a group off puts its lamps out")
	rig.set_group("NAV", true)
	await get_tree().process_frame
	_check(_any_visible(rig, "NAV"), "...and switching it back on lights them")

	host.queue_free()


## The Kestrel's own fit, and the two-file contract that keeps it out of her
## pilot's eyes. The wingtip lamps sit less than a metre either side of the hull
## camera, so an additive blooming quad on the default layer is a sheet of white
## across the windscreen. ShipLights puts own-ship lamps on their own layer and
## HullCameraRig.tscn drops that layer from its cull_mask; either one alone does
## nothing, so both are asserted here.
func _test_own_ship_fit() -> void:
	var ship: Node3D = _world.get_node_or_null("Ship")
	_check(ship != null, "the world scene carries the Kestrel")
	if ship == null:
		return
	var rig: ShipLights = ship.get_node_or_null("ShipLights")
	_check(rig != null, "the Kestrel wears the same fit as the AI ships")
	if rig == null:
		return
	_check(rig._lamps.size() == 8, "...all eight lamps of it")
	var layered := 0
	for lamp: Dictionary in rig._lamps:
		if (lamp["quad"] as VisualInstance3D).layers == ShipLights.OWN_SHIP_LAMP_LAYER:
			layered += 1
	_check(layered == rig._lamps.size(),
			"every own-ship lamp is on the layer the hull camera excludes")

	var cam: Camera3D = ship.find_child("Camera3D", true, false)
	_check(cam != null, "the hull camera is where it was")
	if cam != null:
		_check(cam.cull_mask & ShipLights.OWN_SHIP_LAMP_LAYER == 0,
				"...and it does not render that layer")
		_check(cam.cull_mask & 1 != 0,
				"...while still rendering everything else")

	# Own ship follows the bus: a dark ship is dark outside too.
	GameState.set_master_alt(false)
	GameState.set_master_battery(false)
	await get_tree().process_frame
	_check(not _any_visible(rig, "NAV"), "pulling both masters puts her lights out")
	GameState.set_master_alt(true)
	GameState.set_master_battery(true)
	await get_tree().process_frame
	_check(_any_visible(rig, "NAV"), "...and restoring the bus lights them again")


func _any_visible(rig: ShipLights, group: String) -> bool:
	for lamp: Dictionary in rig._lamps:
		if lamp["group"] == group and (lamp["quad"] as Node3D).visible:
			return true
	return false


# --- Helpers ----------------------------------------------------------------

const ThreatShipsScript := preload("res://scenes/world/ThreatShips.gd")


## Hulls only: the RivalTorch is a permanent child of ThreatShips and is not one.
func _hulls() -> int:
	var count := 0
	for child in _ships.get_children():
		if not child.is_queued_for_deletion() and child.name != "RivalTorch":
			count += 1
	return count


func _first_hull() -> Node3D:
	for child in _ships.get_children():
		if not child.is_queued_for_deletion() and child.name != "RivalTorch":
			return child
	return null


func _finish() -> void:
	if _failures.is_empty():
		print("THREAT SHIPS SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("THREAT SHIPS SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
