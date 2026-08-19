extends Node
## Headless checks for CollisionSystem's capsule collision volume:
##  - the volume follows the ship-local capsule, not the transform origin
##    (a body over the offset capsule collides; one at the origin does not);
##  - ramming a solid body damages the hull, logs a COLLISION, and stops the
##    ship at the surface (no tunnelling);
##  - a gentle sub-threshold nudge separates the ship without any damage;
##  - the segment-vs-convex-hull GJK distance is correct, a flat hull is hugged
##    tightly, and wreck_surface_distance measures only wreck-tagged hulls.
##
## The capsule is set deterministically here so the math is tested independently
## of the baked kestrel.tres values (those are validated by ShipColliderBake and
## in-editor playtest, not this smoke).
##
##   godot --headless res://tools/CollisionSmoke.tscn

var _failures: Array[String] = []


func _ready() -> void:
	Engine.time_scale = 10.0
	# Keep each physics step at 1/60 s of game time under the accelerated clock
	# (steps per real second scale up; the sim's integration step does not).
	Engine.physics_ticks_per_second = roundi(60.0 * Engine.time_scale)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame

	_check(GameState.run_phase == "ON_SITE", "starts ON_SITE")
	_check(not GameState.wreck.is_empty(), "wreck graph present")
	var wreck_pos: Vector3 = GameState.wreck["position"]

	# --- Offset awareness: the volume follows the capsule, not the origin ------
	# A capsule offset to +X (spine along Z at x=5). A body at the world origin is
	# outside it; a body beside the spine is inside it.
	_set_capsule(Vector3(5, 0, -3), Vector3(5, 0, 3), 1.0)

	_reset_ship()
	var origin_id := GameState.register_obstacle("ORIGIN BUOY", Vector3.ZERO, 0.5)
	await _wait(0.3)
	_check(GameState.local_ship()["transform"].origin.length() < 0.05,
			"body at the origin does not touch the offset capsule (no push)")
	GameState.remove_obstacle(origin_id)

	_reset_ship()
	var spine_id := GameState.register_obstacle("SPINE BUOY", Vector3(5, 1.2, 0), 0.5)
	await _wait(0.3)
	_check(GameState.local_ship()["transform"].origin.length() > 0.1,
			"body against the offset capsule pushes the ship (volume is offset)")
	GameState.remove_obstacle(spine_id)

	# --- Ram + gentle tests use a simple centred fore-aft capsule --------------
	_set_capsule(Vector3(0, 0, -3), Vector3(0, 0, 3), 1.5)
	var ship_radius := 1.5

	# --- Gentle nudge below the speed floor: separate, no damage ---------------
	var buoy_pos := Vector3(50, 0, 0)
	var buoy_r := 3.0
	var buoy_min_sep := ship_radius + buoy_r
	var buoy_id := GameState.register_obstacle("GENTLE BUOY", buoy_pos, buoy_r)
	var hull_before_gentle := _hull_total()
	_reset_ship()
	var ship: Dictionary = GameState.local_ship()
	# Sit just inside the buoy (capsule spine runs along Z at x = origin.x) with a
	# slow inward drift well under the floor.
	ship["transform"] = Transform3D(Basis.IDENTITY,
			buoy_pos + Vector3(buoy_min_sep - 0.2, 0, 0))
	ship["velocity"] = Vector3(-0.5, 0, 0)
	await _wait(0.5)
	_check(not _has_comms("GENTLE BUOY"), "gentle contact logs no collision")
	_check(is_equal_approx_soft(_hull_total(), hull_before_gentle),
			"gentle contact deals no hull damage")
	_check(GameState.local_ship()["transform"].origin.x - buoy_pos.x >= buoy_min_sep - 0.3,
			"gentle contact still separates the ship")
	GameState.remove_obstacle(buoy_id)

	# --- Hard ram into a wreck-core hull: damage + stop at the surface ---------
	# The wreck now collides through per-member hulls (Wreck.gd), so stand one in
	# here as a solid box the ship can ram head-on (−Z).
	_reset_ship()
	ship = GameState.local_ship()
	var core_he := Vector3(4, 4, 4)
	var core_id := GameState.register_obstacle(
			"WRECK CORE", wreck_pos, 7.0, _box_hull(wreck_pos, core_he), true)
	var bow_before: float = ship["hull_sections"]["BOW"]
	var comms_before := GameState.comms.size()

	Input.action_press("thrust_forward")
	var rammed := await _wait_until(
			func() -> bool: return _has_comms_since(comms_before, "COLLISION"), 12.0)
	Input.action_release("thrust_forward")
	_check(rammed, "ramming a wreck hull logs a COLLISION event")

	_check(ship["hull_sections"]["BOW"] < bow_before,
			"impact damages the facing (BOW) hull section (%.2f -> %.2f)" % [
				bow_before, ship["hull_sections"]["BOW"]])

	# Let a few frames settle, then confirm the ship sits in front of the hull
	# rather than punching through to the far side of the wreck centre.
	await _wait(0.3)
	_check(ship["transform"].origin.z > wreck_pos.z,
			"ship stopped in front of the wreck hull, no tunnelling (z %.1f, wreck z %.1f)" % [
				ship["transform"].origin.z, wreck_pos.z])
	GameState.remove_obstacle(core_id)

	# --- GJK distance unit checks (segment vs convex hull) --------------------
	# A unit cube hull centred at the origin; distances are known analytically.
	var cube := _box_hull(Vector3.ZERO, Vector3(1, 1, 1))
	_check(_approx(CollisionSystem.hull_distance(Vector3(3, 0, 0), Vector3(3, 0, 0), cube), 2.0),
			"gjk: point off a face")
	_check(_approx(CollisionSystem.hull_distance(Vector3(2, 2, 0), Vector3(2, 2, 0), cube), sqrt(2.0)),
			"gjk: point off an edge")
	_check(_approx(CollisionSystem.hull_distance(Vector3(2, 2, 2), Vector3(2, 2, 2), cube), sqrt(3.0)),
			"gjk: point off a corner")
	_check(CollisionSystem.hull_distance(Vector3.ZERO, Vector3.ZERO, cube) == 0.0,
			"gjk: point inside the hull -> distance 0")
	_check(_approx(CollisionSystem.hull_distance(Vector3(-3, 2, 0), Vector3(3, 2, 0), cube), 1.0),
			"gjk: segment spanning the hull, parallel over the top face")

	# --- wreck_surface_distance measures only wreck-tagged hulls --------------
	# A wreck box (face at x 101) and a nearer debris box (face x 104): the query
	# must report the wreck's 4.0, ignoring the closer non-wreck body.
	var w_id := GameState.register_obstacle(
			"W", Vector3(100, 0, 0), 2.0, _box_hull(Vector3(100, 0, 0), Vector3(1, 1, 1)), true)
	var d_id := GameState.register_obstacle(
			"D", Vector3(103, 0, 0), 2.0, _box_hull(Vector3(103, 0, 0), Vector3(1, 1, 1)), false)
	var wsd := CollisionSystem.wreck_surface_distance(Vector3(105, 0, 0), Vector3(105, 0, 0))
	_check(_approx(wsd, 4.0),
			"wreck_surface_distance uses the wreck hull, ignores debris (%.2f, want 4.0)" % wsd)
	GameState.remove_obstacle(w_id)
	GameState.remove_obstacle(d_id)

	# --- Tight hull fit: a flat plate stops the ship at its face, not its
	# bounding sphere. Thin in X (half 0.3), broad 2x2 in YZ; the sphere that
	# would enclose it has radius ~2.9, so a sphere body would hold the ship far
	# further out than the hull does.
	_set_capsule(Vector3.ZERO, Vector3.ZERO, 0.5)
	var plate_c := Vector3(60, 0, 0)
	var plate := _box_hull(plate_c, Vector3(0.3, 2.0, 2.0))
	var plate_id := GameState.register_obstacle("TEST PLATE", plate_c, 2.9, plate)
	_reset_ship()
	ship = GameState.local_ship()
	# Start just past the broad +X face so the ship is penetrating by 0.3.
	ship["transform"] = Transform3D(Basis.IDENTITY, plate_c + Vector3(0.5, 0, 0))
	ship["velocity"] = Vector3.ZERO
	await _wait(0.3)
	var plate_x: float = GameState.local_ship()["transform"].origin.x
	var want_x := plate_c.x + 0.3 + 0.5  # face + ship radius
	_check(absf(plate_x - want_x) < 0.1,
			"hull push-out hugs the flat face (x %.2f, want %.2f)" % [plate_x, want_x])
	_check(plate_x < plate_c.x + 2.0,
			"hull fit settles the ship far short of the bounding-sphere standoff")
	GameState.remove_obstacle(plate_id)

	# --- A FLAT hull must not swallow things that are nowhere near it.
	#
	# GJK reduces its simplex through _sub_tetra, which decided "origin inside"
	# whenever no face reported the origin outside it. A squashed tetrahedron has
	# near-zero face normals, so every face abstains and the origin reads as
	# enclosed — at any distance. Support points taken from a thin slab are
	# coplanar exactly like that, so the station's 22 x 2 x 22 m berth floor
	# reported contact with a ship ELEVEN METRES above it, intermittently,
	# depending on which coplanar vertices the supports happened to pick.
	var slab := PackedVector3Array()
	for sx in [-11.0, 11.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-11.0, 11.0]:
				slab.append(Vector3(sx, sy, sz))
	var worst_error := 0.0
	var false_hits := 0
	# Queried with the ship's REAL capsule, not a point: the degenerate simplex
	# only shows up for a segment-vs-slab Minkowski difference, which is exactly
	# what the ship is.
	# Explicit, not read from ship_def: the plate check above zeroes the capsule,
	# and a point query does not produce the degenerate simplex this is about.
	var ca := Vector3(0.0, -0.7, -0.95)
	var cb := Vector3(0.0, -0.7, 0.95)
	for h in [3.0, 5.0, 7.5, 9.0, 11.0, 12.5, 14.0, 15.5, 17.0]:
		var centre := Vector3(0.4, h, -0.3)   # above the slab, near its middle
		var measured: float = CollisionSystem.hull_distance(centre + ca, centre + cb, slab)
		var expected: float = h + minf(ca.y, cb.y) - 1.0   # slab's top face
		worst_error = maxf(worst_error, absf(measured - expected))
		if measured <= 0.0:
			false_hits += 1
	_check(false_hits == 0,
			"a flat slab reports no contact with a ship clear of it (%d false hits)"
					% false_hits)
	_check(worst_error < 0.01,
			"...and measures the true distance to its face (worst error %.3f m)"
					% worst_error)
	# The other half: a point genuinely inside the slab still reads as inside.
	_check(CollisionSystem.hull_distance(Vector3(0.2, 0.0, 0.1),
			Vector3(0.2, 0.0, 0.1), slab) <= 0.0,
			"...while a point actually inside it still registers")

	if _failures.is_empty():
		print("COLLISION SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("COLLISION SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


## Eight corners of an axis-aligned box — a convex hull point cloud for the GJK
## tests, standing in for a baked debris chunk.
func _box_hull(center: Vector3, he: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				pts.append(center + Vector3(he.x * sx, he.y * sy, he.z * sz))
	return pts


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.02


func _set_capsule(a: Vector3, b: Vector3, radius: float) -> void:
	GameState.ship_def.collision_a = a
	GameState.ship_def.collision_b = b
	GameState.ship_def.collision_radius = radius


func _reset_ship() -> void:
	var ship: Dictionary = GameState.local_ship()
	ship["transform"] = Transform3D.IDENTITY
	ship["velocity"] = Vector3.ZERO


func _hull_total() -> float:
	var total := 0.0
	for value: float in GameState.local_ship()["hull_sections"].values():
		total += value
	return total


func _has_comms(substr: String) -> bool:
	return _has_comms_since(0, substr)


func _has_comms_since(from_index: int, substr: String) -> bool:
	for i in range(from_index, GameState.comms.size()):
		if GameState.comms[i]["text"].contains(substr):
			return true
	return false


func is_equal_approx_soft(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _wait(game_seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < game_seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


## Poll a predicate each frame up to a timeout; returns whether it went true.
func _wait_until(predicate: Callable, timeout_seconds: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if predicate.call():
			return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return predicate.call()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
