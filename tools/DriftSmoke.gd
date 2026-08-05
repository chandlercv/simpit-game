extends Node
## Headless checks for the post-cut collection mini-game (DriftSystem):
##  - a completed cut detaches a real, drifting piece instead of stowing
##    directly into cargo;
##  - collisions impart velocity to movable bodies (ramming a piece, and one
##    movable body knocking another — the same pass a salvage piece and a
##    debris chunk trade momentum through);
##  - the four collection gates (hatch, range, relative speed, forward cone)
##    are all required together, and holding all four stows the piece;
##  - the cargo hatch interlocks the cutter and departure/jump while open;
##  - the rival runs the same sever-then-retrieve loop, and pieces are
##    free-for-all so the player can beat it to one.
##
##   godot --headless res://tools/DriftSmoke.tscn
##
## Runs with no 3D scene, so members carry no baked center/radius/seam by
## default — checks that need a known position/velocity seed those fields on
## the live member dict directly before spawning a piece, the same shortcut
## AlignSmoke/CollisionSmoke use. InputRouter._process is disabled so it can't
## clobber the ship transform/velocity these checks drive by hand.

var _failures: Array[String] = []


func _ready() -> void:
	Engine.time_scale = 10.0
	InputRouter.set_process(false)
	# InputRouter.set_process(false) only stops InputRouter's OWN _process — its
	# raw-HID children (SwitchPanelBridge etc.) keep polling real connected
	# hardware regardless. On a dev box with a live switch panel, a physical
	# COWL switch left ON would otherwise flip GameState.cargo_hatch_open mid-test
	# out from under these checks, so silence those children too.
	for child in InputRouter.get_children():
		child.set_process(false)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame

	# --- Detach: a completed cut no longer stows directly — it detaches a
	# real, drifting piece instead. ---
	SalvageSystem.reset_site()
	var detach_id := _cuttable_ids()[0]
	_setup_matched(detach_id)
	GameState.set_cargo_hatch(false)
	GameState.wreck["cutting_id"] = detach_id
	GameState.wreck["cut_progress"] = 0.0
	GameState.wreck["align_quality"] = 1.0
	var cut_done := await _wait_until(
			func() -> bool: return GameState.wreck["cutting_id"] == -1, 12.0)
	_check(cut_done, "the forced cut completes")
	_check(GameState.local_ship()["cargo"].is_empty(),
			"a completed cut does not stow anything directly")
	var detached := _find_piece_by_member(detach_id)
	_check(not detached.is_empty(), "the severed member detaches as an adrift piece")
	_check((detached.get("velocity", Vector3.ZERO) as Vector3).length() > 0.01,
			"the detached piece carries nonzero drift velocity")

	# --- Momentum: a moving movable body knocks a stationary one, and ramming
	# a drifting piece with the ship kicks it. ---
	SalvageSystem.reset_site()
	GameState.ship_def.collision_a = Vector3.ZERO
	GameState.ship_def.collision_b = Vector3.ZERO
	GameState.ship_def.collision_radius = 1.5
	GameState.local_ship()["transform"] = Transform3D(Basis.IDENTITY, Vector3(1000, 0, 0))
	GameState.local_ship()["velocity"] = Vector3.ZERO

	# Bodies I register here have no owning system to integrate their position
	# from "vel" each frame (that's DriftSystem's/DebrisField's job for the real
	# thing) — so start them already overlapping rather than relying on motion
	# to close the gap; CollisionSystem's movable-pair pass only needs one frame
	# of overlap to exchange the impulse.
	var a_id := GameState.register_obstacle(
			"BODY A", Vector3(0, 0, -48.5), 1.0, PackedVector3Array(), false, 1.0)
	var b_id := GameState.register_obstacle(
			"BODY B", Vector3(0, 0, -47), 1.0, PackedVector3Array(), false, 1.0)
	GameState.get_obstacle(a_id)["vel"] = Vector3(0, 0, 5)  # A closing on B
	await get_tree().process_frame
	await get_tree().process_frame
	var b_vel: Vector3 = GameState.get_obstacle(b_id)["vel"]
	_check(b_vel.length() > 0.5,
			"a moving movable body knocks a stationary one on contact (b picked up %.2f m/s)"
					% b_vel.length())
	GameState.remove_obstacle(a_id)
	GameState.remove_obstacle(b_id)

	var fake_member := {"id": 999, "name": "TEST PANEL", "good": "HULL ALLOY",
		"node": "PanelA", "center": Vector3(0, 0, -10), "seam": Vector3(0, 0.5, -10),
		"radius": 1.0, "vel": Vector3.ZERO}
	var momentum_piece_id := DriftSystem.spawn_piece(fake_member, 1.0)
	var vel_before: Vector3 = GameState.get_salvage_piece(momentum_piece_id)["velocity"]
	GameState.local_ship()["transform"] = Transform3D(Basis.IDENTITY, Vector3(0, 0, -6))
	GameState.local_ship()["velocity"] = Vector3(0, 0, -8)
	await _wait(0.8)
	var vel_after: Vector3 = GameState.get_salvage_piece(momentum_piece_id)["velocity"]
	_check(vel_after.length() > vel_before.length() + 0.5,
			"ramming a drifting piece imparts velocity to it (%.2f -> %.2f m/s)" % [
				vel_before.length(), vel_after.length()])

	# --- Collection gates: hatch open + in range + speed matched + nose-on are
	# all required together; each alone isn't enough, and holding all four
	# fills the scoop and stows the piece. ---
	SalvageSystem.reset_site()
	var gate_member_id := _cuttable_ids()[0]
	var gate_member: Dictionary = GameState.get_member(gate_member_id)
	gate_member["center"] = Vector3(0, 0, -10)
	gate_member["seam"] = Vector3(0, 0.5, -10)
	gate_member["radius"] = 1.0
	gate_member["vel"] = Vector3.ZERO
	var gate_piece_id := DriftSystem.spawn_piece(gate_member, float(gate_member["qty"]))

	GameState.set_cargo_hatch(false)
	await _hold_on_piece(gate_piece_id, 1.0)
	_check(float(GameState.get_salvage_piece(gate_piece_id).get("scoop", 0.0)) <= 0.05,
			"hatch closed blocks the scoop even when otherwise aligned")

	GameState.set_cargo_hatch(true)
	await _hold_off_axis(gate_piece_id, 1.0)
	_check(float(GameState.get_salvage_piece(gate_piece_id).get("scoop", 0.0)) <= 0.05,
			"a piece outside the forward hatch cone doesn't fill the scoop")

	await _hold_on_piece(gate_piece_id, 6.0)
	_check(GameState.get_salvage_piece(gate_piece_id).is_empty(),
			"holding hatch+range+speed+cone stows the piece and removes it")
	_check(not GameState.local_ship()["cargo"].is_empty(),
			"the collected piece lands in cargo")
	GameState.set_cargo_hatch(false)

	# --- Instrument math: collection_status is the single evaluation the scoop,
	# the MFD SCOOP page and the HUD cue all read, so its aiming numbers have to
	# agree with the cone gate it hands the scoop. ---
	SalvageSystem.reset_site()
	var aim_member := {"id": 998, "name": "AIM TEST", "good": "HULL ALLOY",
		"node": "PanelA", "center": Vector3(0, 0, -20), "seam": Vector3(0, 0, -20),
		"radius": 1.0, "vel": Vector3.ZERO}
	var aim_piece_id := DriftSystem.spawn_piece(aim_member, 1.0)
	var aim_piece := GameState.get_salvage_piece(aim_piece_id)
	# Hold it still so the geometry below is exact rather than a moving target.
	aim_piece["velocity"] = Vector3.ZERO
	GameState.get_obstacle(int(aim_piece["obstacle_id"]))["vel"] = Vector3.ZERO

	# Parked 5 m in front of it, nose straight at it: dead centre of the cone.
	_place_ship_facing(Vector3(0, 0, -15), Vector3(0, 0, -1))
	var nose_on := DriftSystem.collection_status(aim_piece)
	_check(float(nose_on["off_axis"]) < 1.0,
			"nose-on reads ~0° off-axis (got %.1f°)" % nose_on["off_axis"])
	_check(nose_on["in_cone"], "nose-on satisfies the cone gate")

	# Same spot, nose swung 90° to starboard: hard off-axis, cone gate fails.
	_place_ship_facing(Vector3(0, 0, -15), Vector3(1, 0, 0))
	var side_on := DriftSystem.collection_status(aim_piece)
	_check(absf(float(side_on["off_axis"]) - 90.0) < 1.0,
			"nose 90° off the piece reads ~90° off-axis (got %.1f°)" % side_on["off_axis"])
	_check(not side_on["in_cone"], "a 90°-off piece fails the cone gate")
	_check(absf((side_on["aim"] as Vector2).length() - float(side_on["off_axis"])) < 0.01,
			"the aim vector's magnitude IS the off-axis angle (what the SCOOP field plots)")

	# nearest_piece picks the one actually being worked.
	var far_member := {"id": 997, "name": "FAR TEST", "good": "HULL ALLOY",
		"node": "PanelB", "center": Vector3(0, 0, -200), "seam": Vector3(0, 0, -200),
		"radius": 1.0, "vel": Vector3.ZERO}
	DriftSystem.spawn_piece(far_member, 1.0)
	_check(DriftSystem.nearest_piece().get("id", -1) == aim_piece_id,
			"nearest_piece returns the closest adrift piece")

	# --- Interlocks: an open cargo hatch blocks firing the cutter and blocks
	# leaving the site (dock/jump). ---
	SalvageSystem.reset_site()
	var lock_id := _cuttable_ids()[0]
	_setup_matched(lock_id)
	GameState.set_cargo_hatch(true)
	SalvageSystem.request_cut()
	_check(GameState.align_state != "ALIGNING" and GameState.wreck["cutting_id"] == -1,
			"an open cargo hatch blocks firing the cutter")
	var comms_before := GameState.comms.size()
	MarketSystem.request_dock(0)
	await get_tree().process_frame
	_check(GameState.run_phase == "ON_SITE", "an open cargo hatch blocks departure/jump")
	_check(_has_comms_since(comms_before, "HATCH"),
			"the hatch interlock logs why departure was held")
	GameState.set_cargo_hatch(false)

	# --- Rival parity: severing a member via the rival path also detaches a
	# real, collectible piece; collect_for_rival despawns it, and — since
	# pieces are free-for-all — the player can just as well beat the rival to
	# one it cut. ---
	SalvageSystem.reset_site()
	var result := SalvageSystem.rival_strip_member()
	_check(not result.is_empty(), "the rival severs a member")
	var rival_piece_id: int = result.get("piece_id", -1)
	_check(rival_piece_id != -1 and not GameState.get_salvage_piece(rival_piece_id).is_empty(),
			"the rival's cut detaches a real adrift piece, same as ours")
	DriftSystem.collect_for_rival(rival_piece_id)
	_check(GameState.get_salvage_piece(rival_piece_id).is_empty(),
			"collect_for_rival despawns the piece it claims")

	var result2 := SalvageSystem.rival_strip_member()
	var piece2_id: int = result2.get("piece_id", -1)
	_check(piece2_id != -1, "the rival severs a second member")
	GameState.set_cargo_hatch(true)
	await _hold_on_piece(piece2_id, 6.0)
	_check(GameState.get_salvage_piece(piece2_id).is_empty(),
			"pieces are free-for-all — the player can scoop one the rival cut")
	GameState.set_cargo_hatch(false)

	if _failures.is_empty():
		print("DRIFT SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("DRIFT SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


## Scanned + selected + cutter powered + MATCHED on `id` (no 3D scene to fly),
## same shortcut AlignSmoke uses.
func _setup_matched(id: int) -> void:
	GameState.wreck["scanned"] = true
	GameState.local_ship()["power"]["CUTTER"] = 1.0
	GameState.approach_state = "HOLDING"
	GameState.selected_member_id = -1
	SalvageSystem.select_member(id)
	GameState.approach_state = "MATCHED"
	GameState.matched_member_id = id


## Continuously parks the ship a hair off the given piece (nose-on, velocity
## matched) for `duration` game-seconds — the three collection gates besides
## the hatch. Chases the piece's live position every frame so a multi-second
## hold doesn't drift out of range as the piece keeps drifting, and returns
## early if the piece is collected (removed) mid-hold.
func _hold_on_piece(piece_id: int, duration: float) -> void:
	GameState.approach_state = "HOLDING"
	var elapsed := 0.0
	while elapsed < duration:
		var piece := GameState.get_salvage_piece(piece_id)
		if piece.is_empty():
			return
		var piece_pos: Vector3 = (piece["transform"] as Transform3D).origin
		var piece_vel: Vector3 = piece["velocity"]
		var offset := Vector3(0, 0, 1.0)
		GameState.local_ship()["transform"] = Transform3D(
				Basis.looking_at(offset.normalized()), piece_pos - offset)
		GameState.local_ship()["velocity"] = piece_vel
		await get_tree().process_frame
		elapsed += get_process_delta_time()


## Same hold, but nose pointing AWAY from the piece — range and relative speed
## still gate true, isolating the forward-cone gate as the one that fails.
func _hold_off_axis(piece_id: int, duration: float) -> void:
	GameState.approach_state = "HOLDING"
	var elapsed := 0.0
	while elapsed < duration:
		var piece := GameState.get_salvage_piece(piece_id)
		if piece.is_empty():
			return
		var piece_pos: Vector3 = (piece["transform"] as Transform3D).origin
		var piece_vel: Vector3 = piece["velocity"]
		var offset := Vector3(0, 0, 1.0)
		GameState.local_ship()["transform"] = Transform3D(
				Basis.looking_at(-offset.normalized()), piece_pos - offset)
		GameState.local_ship()["velocity"] = piece_vel
		await get_tree().process_frame
		elapsed += get_process_delta_time()


## Park the ship at `pos`, stationary, with its nose pointing along `look_dir`.
func _place_ship_facing(pos: Vector3, look_dir: Vector3) -> void:
	GameState.local_ship()["transform"] = Transform3D(
			Basis.looking_at(look_dir.normalized()), pos)
	GameState.local_ship()["velocity"] = Vector3.ZERO


func _find_piece_by_member(member_id: int) -> Dictionary:
	for piece: Dictionary in GameState.salvage_pieces:
		if piece["member_id"] == member_id:
			return piece
	return {}


func _cuttable_ids() -> Array[int]:
	var out: Array[int] = []
	for member: Dictionary in GameState.wreck.get("members", []):
		if not member["cut"] and not member["destroyed"]:
			out.append(member["id"])
	return out


func _wait(game_seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < game_seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _wait_until(predicate: Callable, timeout_seconds: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if predicate.call():
			return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return predicate.call()


func _has_comms_since(from_index: int, substr: String) -> bool:
	for i in range(from_index, GameState.comms.size()):
		if GameState.comms[i]["text"].contains(substr):
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
