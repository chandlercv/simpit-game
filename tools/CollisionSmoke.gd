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

	# --- Sub-stepping: a body thinner than one tick's travel still stops the ---
	# --- ship rather than being flown straight through.                      ---
	#
	# This is the case DIRECT law makes reachable and the discrete overlap test
	# cannot see on its own: at 400 m/s a 60 Hz tick carries the ship 6.7 m, so a
	# 1 m body sits entirely between two consecutive tested positions. Without
	# ShipMotion sub-stepping the collision pass with it, the ship arrives on the
	# far side having never touched anything.
	_set_capsule(Vector3(0, 0, -0.95), Vector3(0, 0, 0.95), 0.35)
	_reset_ship()
	ship = GameState.local_ship()
	GameState.set_fbw_law("DIRECT")
	var wall_z := -300.0
	var plate_he := Vector3(6, 6, 0.5)
	# Registered with the hull's TRUE bounding radius, which is what Station.gd
	# and Wreck.gd both do. It matters: the bounding radius of a broad thin plate
	# is nothing like its thickness, and a test that quietly passed a small radius
	# would never exercise the gap between the two.
	var thin_id := GameState.register_obstacle(
			"THIN PLATE", Vector3(0, 0, wall_z), plate_he.length(),
			_box_hull(Vector3(0, 0, wall_z), plate_he), true)
	comms_before = GameState.comms.size()
	ship["velocity"] = Vector3(0, 0, -400.0)
	var caught := await _wait_until(
			func() -> bool: return _has_comms_since(comms_before, "COLLISION"), 4.0)
	_check(caught, "a plate thinner than one tick's travel is still hit at 400 m/s")
	_check(ship["transform"].origin.z > wall_z,
			"...and the ship is stopped in front of it, not tunnelled through (z %.1f, plate z %.1f)"
					% [ship["transform"].origin.z, wall_z])
	GameState.remove_obstacle(thin_id)

	# The same case in the orientation that actually bounds it, and at a speed
	# nothing in the game can produce — because the point is that SPEED IS NOT
	# WHAT BOUNDS IT.
	#
	# Flown NOSE-ON the capsule's own 2.6 m length is swept through the body and
	# the window is generous; flown BROADSIDE only its 0.7 m diameter is, and that
	# is the figure the sampler has to be calibrated against. Gating on the
	# generous orientation is how a ship tunnels while flying sideways.
	#
	# 20 km/s is 333 m in a tick, five hundred times the body's own diameter. It
	# is struck anyway, because the sampler spends its sub-steps on the stretch of
	# path where contact is possible rather than spreading them over the whole
	# tick — and how long the ship is alongside a 0.35 m body does not depend on
	# how fast it got there. Every alignment between the sampling grid and the
	# body is tried.
	var side := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3.ZERO)
	var tunnelled := 0
	var worst_steps := 0
	for i in 8:
		var at := Vector3(0, 0, -6000.0 - float(i) * 41.7)
		var pebble := GameState.register_obstacle(
				"PEBBLE", at, 0.35, PackedVector3Array(), true)
		var probe := at + Vector3(0, 0, 167.0)
		for hazard: Dictionary in CollisionSystem.path_hazard(
				probe, probe + Vector3(0, 0, -333.3)):
			worst_steps = maxi(worst_steps, ceili(
					(float(hazard["hi"]) - float(hazard["lo"])) * 333.3
					/ maxf(0.5 * float(hazard["window"]), 0.01)))
		ShipMotion.seize(side, Vector3(0, 0, -20000.0))
		comms_before = GameState.comms.size()
		var struck := await _wait_until(
				func() -> bool: return _has_comms_since(comms_before, "COLLISION"), 3.0)
		if not struck:
			tunnelled += 1
		GameState.remove_obstacle(pebble)
	_check(tunnelled == 0,
			"a 0.35 m body is struck BROADSIDE at 20 km/s, at any alignment (%d/8 missed)"
					% tunnelled)
	# ...and it is not brute force doing it. A stretch's interval and window come
	# from the same geometry, so an isolated body's demand is a bounded handful
	# whatever the speed. If this ever climbs past that, the sampler has gone
	# back to dividing distance instead of hazard and the speed ceiling is back
	# with it, whatever the check above happens to say.
	_check(worst_steps > 0 and worst_steps <= 8,
			"...on %d sub-steps — the cost is set by the body, not the speed"
					% worst_steps)

	# --- A BROAD, THIN hull is sized by its thickness, not its bounding sphere ---
	#
	# A station bay wall is 18 m by 16 m and 1.6 m thick: a 12 m bounding radius
	# around 1.6 m of substance. Gate the sub-stepping on the radius and the ship
	# is told it has 24 m of window where it really has 2.3 m, and steps clean over
	# the wall — which is not an exotic-speed problem, it starts in the hundreds.
	# The window has to be the hull's shadow on the direction of travel.
	var wall_he := Vector3(9.0, 8.0, 0.8)
	tunnelled = 0
	for i in 8:
		var wz := -600.0 - float(i) * 0.8
		var wall := GameState.register_obstacle("BAY WALL", Vector3(0, 0, wz),
				wall_he.length(), _box_hull(Vector3(0, 0, wz), wall_he), true)
		ShipMotion.seize(Transform3D.IDENTITY, Vector3(0, 0, -900.0))
		comms_before = GameState.comms.size()
		var struck := await _wait_until(
				func() -> bool: return _has_comms_since(comms_before, "COLLISION"), 3.0)
		if not struck:
			tunnelled += 1
		GameState.remove_obstacle(wall)
	_check(tunnelled == 0,
			"a 1.6 m wall inside a 12 m bounding sphere is struck at 900 m/s (%d/8 missed)"
					% tunnelled)

	# --- SEPARATE bodies must stay SEPARATE sampling stretches -----------------
	#
	# Folding every hazard on the path into one [min lo, max hi] span sampled at
	# the tightest window reintroduces the speed ceiling by the back door: two of
	# these walls 150 m apart on one 200 m tick merged into a ~170 m interval
	# divided at one wall's 2.3 m window — a demand of 150-odd sub-steps against
	# a budget of 32, most of it spent finely sampling the EMPTY GAP between the
	# walls while both went under-sampled. Flown live before the split, the ship
	# crossed both walls clean at 12 km/s with the sampler reporting the path
	# covered. Disjoint stretches cost their own handful of steps each and the
	# gap between them costs one coarse step, whatever its length.
	_set_capsule(Vector3(0, -0.7, -0.95), Vector3(0, -0.7, 0.95), 0.35)
	var pair_probe := Vector3(0, 0, -560.0)
	var wall_a := GameState.register_obstacle("WALL A", Vector3(0, 0, -600.0),
			wall_he.length(), _box_hull(Vector3(0, 0, -600.0), wall_he), true)
	var wall_b := GameState.register_obstacle("WALL B", Vector3(0, 0, -750.0),
			wall_he.length(), _box_hull(Vector3(0, 0, -750.0), wall_he), true)
	var stretches := CollisionSystem.path_hazard(
			pair_probe, pair_probe + Vector3(0, 0, -200.0))
	_check(stretches.size() == 2,
			"two walls 150 m apart are two disjoint stretches, not one merged span (%d)"
					% stretches.size())
	var stretch_demand := 0
	for stretch: Dictionary in stretches:
		stretch_demand = maxi(stretch_demand, ceili(
				(float(stretch["hi"]) - float(stretch["lo"])) * 200.0
				/ maxf(0.5 * float(stretch["window"]), 0.01)))
	_check(stretch_demand > 0 and stretch_demand <= 8,
			"...each wanting its own handful of steps (worst %d), none spent on the gap"
					% stretch_demand)
	GameState.remove_obstacle(wall_a)
	GameState.remove_obstacle(wall_b)

	tunnelled = 0
	for i in 8:
		var oz := -float(i) * 25.0
		var wa := GameState.register_obstacle("WALL A", Vector3(0, 0, -600.0 + oz),
				wall_he.length(), _box_hull(Vector3(0, 0, -600.0 + oz), wall_he), true)
		var wb := GameState.register_obstacle("WALL B", Vector3(0, 0, -750.0 + oz),
				wall_he.length(), _box_hull(Vector3(0, 0, -750.0 + oz), wall_he), true)
		ShipMotion.seize(Transform3D.IDENTITY, Vector3(0, 0, -12000.0))
		comms_before = GameState.comms.size()
		var pair_struck := await _wait_until(
				func() -> bool: return _has_comms_since(comms_before, "COLLISION"), 2.0)
		if not pair_struck:
			tunnelled += 1
		GameState.remove_obstacle(wa)
		GameState.remove_obstacle(wb)
		_reset_ship()
	_check(tunnelled == 0,
			"one of two separated walls registers on every 12 km/s pass (%d/8 crossed clean)"
					% tunnelled)

	# --- Near-misses must not starve the hit -----------------------------------
	#
	# Seven pebbles sit 1.2 m off the flight path: close enough that their
	# broadphase envelopes intersect it — each earns its own sampling stretch —
	# and too far to ever touch the ship. Beyond them, ON the path, a wall.
	# Under a shared sub-step budget the seven bystanders spent five steps each
	# before the ship ever reached the wall, the wall's own stretch was clamped
	# to a single unresolved step, and the ship crossed 1.6 m of structure at
	# 12 km/s without a mark on it. What a stretch costs must be set by ITS
	# body — never by how many other bodies the path merely passed on the way.
	var bystanders: Array[int] = []
	for k in 7:
		bystanders.append(GameState.register_obstacle(
				"BYSTANDER", Vector3(1.2, 0, -420.0 - 15.0 * float(k)), 0.35,
				PackedVector3Array(), true))
	var far_wall := GameState.register_obstacle("FAR WALL", Vector3(0, 0, -560.0),
			wall_he.length(), _box_hull(Vector3(0, 0, -560.0), wall_he), true)
	ShipMotion.seize(Transform3D.IDENTITY, Vector3(0, 0, -12000.0))
	comms_before = GameState.comms.size()
	var wall_struck := await _wait_until(
			func() -> bool: return _has_comms_since(comms_before, "FAR WALL"), 2.0)
	_check(wall_struck,
			"a wall past seven near-miss bodies is still struck — bystanders starve nothing")
	for id: int in bystanders:
		GameState.remove_obstacle(id)
	GameState.remove_obstacle(far_wall)
	_reset_ship()
	_set_capsule(Vector3(0, 0, -0.95), Vector3(0, 0, 0.95), 0.35)

	InputRouter.set_process(true)
	_reset_ship()
	GameState.set_fbw_law("NORMAL")

	# --- The bounce splits by mass, so WHAT you hit matters ---------------------
	# The ship used to reflect identically off everything, which is why ramming a
	# pebble and ramming a boulder felt the same. Same closing speed into a light
	# body and a heavy one must now leave the ship going at different speeds.
	var light := await _ram_body(CollisionSystem.body_mass(0.8))
	var heavy := await _ram_body(GameState.ship_mass() * 20.0)
	_check(heavy > light + 0.5,
			"a heavy body throws the ship back harder than a light one (%.2f vs %.2f m/s)"
					% [heavy, light])

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


## Drive the ship into a movable sphere of `mass` kg at a fixed closing speed and
## report its velocity ON THE TICK THE CONTACT LANDS. The only variable is the
## body's mass, so what comes back is the mass split and nothing else.
##
## Read on the contact tick, not after the ship settles: under NORMAL law the
## translation null bleeds whatever the bounce left within a second or so, and
## both cases converge on nearly stopped. DIRECT law is selected for the same
## reason — nothing must tidy the number away before it is read.
func _ram_body(mass: float) -> float:
	_reset_ship()
	SalvageSystem.set_manual_flight(Vector3.ZERO, Vector3.ZERO)
	GameState.set_fbw_law("DIRECT")
	var ship: Dictionary = GameState.local_ship()
	var id := GameState.register_obstacle(
			"RAM TARGET", Vector3(0, 0, -12.0), 2.0, PackedVector3Array(), false, mass)
	ship["velocity"] = Vector3(0, 0, -8.0)
	await _wait_until(
			func() -> bool:
				return absf((GameState.local_ship()["velocity"] as Vector3).z + 8.0) > 0.01,
			4.0)
	var rebound: float = (ship["velocity"] as Vector3).z
	GameState.remove_obstacle(id)
	GameState.set_fbw_law("NORMAL")
	_reset_ship()
	return rebound


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
