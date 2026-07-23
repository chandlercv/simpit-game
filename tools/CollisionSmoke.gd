extends Node
## Headless checks for CollisionSystem's capsule collision volume:
##  - the volume follows the ship-local capsule, not the transform origin
##    (a body over the offset capsule collides; one at the origin does not);
##  - ramming a solid body damages the hull, logs a COLLISION, and stops the
##    ship at the surface (no tunnelling);
##  - a gentle sub-threshold nudge separates the ship without any damage.
##
## The capsule is set deterministically here so the math is tested independently
## of the baked kestrel.tres values (those are validated by ShipColliderBake and
## in-editor playtest, not this smoke).
##
##   godot --headless res://tools/CollisionSmoke.tscn

const CollisionScript := preload("res://systems/CollisionSystem.gd")

var _failures: Array[String] = []


func _ready() -> void:
	Engine.time_scale = 10.0
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

	# --- Hard ram into the wreck: damage + stop at the surface -----------------
	_reset_ship()
	ship = GameState.local_ship()
	var ram_min_sep := ship_radius + CollisionScript.WRECK_RADIUS
	var bow_before: float = ship["hull_sections"]["BOW"]
	var comms_before := GameState.comms.size()

	Input.action_press("thrust_forward")
	var rammed := await _wait_until(
			func() -> bool: return _has_comms_since(comms_before, "COLLISION"), 12.0)
	Input.action_release("thrust_forward")
	_check(rammed, "ramming the wreck logs a COLLISION event")

	_check(ship["hull_sections"]["BOW"] < bow_before,
			"impact damages the facing (BOW) hull section (%.2f -> %.2f)" % [
				bow_before, ship["hull_sections"]["BOW"]])

	# Let a few frames settle, then confirm the ship sits at the surface rather
	# than punching through to the far side of the wreck.
	await _wait(0.3)
	_check(ship["transform"].origin.z > wreck_pos.z + ram_min_sep - 1.0,
			"ship stopped near the surface, no tunnelling (z %.1f, wreck z %.1f)" % [
				ship["transform"].origin.z, wreck_pos.z])

	if _failures.is_empty():
		print("COLLISION SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("COLLISION SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


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
