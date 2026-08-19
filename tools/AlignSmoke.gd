extends Node
## Headless checks for the per-member approach + pre-cut alignment mini-game:
## approach needs a target and re-selecting forces a reposition; the cutter
## trigger opens alignment (not a cut); on-target aim builds the lock and commits
## at high quality; a sustained slip aborts (hard-fail) and nudges risk; and the
## banked quality binds the stakes — a clean cut is faster and preserves more yield.
##
##   godot --headless res://tools/AlignSmoke.tscn
##
## Runs with no 3D scene, so members carry no baked center/radius and MATCHED is
## forced directly rather than flown. InputRouter._process is disabled so it can't
## clobber the align input we feed by hand each frame.

var _failures: Array[String] = []


func _ready() -> void:
	Engine.time_scale = 10.0
	# Keep each physics step at 1/60 s of game time under the accelerated clock
	# (steps per real second scale up; the sim's integration step does not).
	Engine.physics_ticks_per_second = roundi(60.0 * Engine.time_scale)
	InputRouter.set_process(false)
	# InputRouter.set_process(false) only stops InputRouter's OWN _process — its
	# raw-HID children (SwitchPanelBridge etc.) keep polling real connected
	# hardware regardless. On a dev box with a live switch panel, a physical
	# COWL switch left ON would otherwise flip GameState.cargo_hatch_open mid-test
	# and abort a forced cut/alignment out from under these checks.
	for child in InputRouter.get_children():
		child.set_process(false)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame

	# --- Per-member approach ---
	SalvageSystem.reset_site()
	GameState.wreck["scanned"] = true
	GameState.approach_state = "HOLDING"
	GameState.selected_member_id = -1
	SalvageSystem.toggle_approach()
	_check(GameState.approach_state == "HOLDING", "approach refuses to arm with no target selected")

	var ids := _cuttable_ids()
	_check(ids.size() >= 2, "at least two cuttable members available")
	# Select A, fake a match to A, then select B: the match must drop for a reposition.
	SalvageSystem.select_member(ids[0])
	GameState.approach_state = "MATCHED"
	GameState.matched_member_id = ids[0]
	SalvageSystem.select_member(ids[1])
	_check(GameState.approach_state == "HOLDING", "selecting a new target drops out of MATCHED")
	_check(GameState.matched_member_id == -1, "matched member cleared on reselect")

	# --- Alignment begins on the cutter trigger ---
	SalvageSystem.reset_site()
	var target_id := _cuttable_ids()[0]
	_setup_matched(target_id)
	SalvageSystem.request_cut()
	_check(GameState.align_state == "ALIGNING", "request_cut opens alignment, not a cut")
	_check(GameState.wreck["cutting_id"] == -1, "no cut starts until alignment commits")

	# On-target aim builds the lock to auto-commit at high quality.
	var committed := await _drive_align(true, 4.0)
	_check(committed, "on-target aim builds lock and auto-commits")
	var q_high: float = float(GameState.wreck.get("align_quality", 0.0))
	_check(q_high > 0.7, "clean alignment banks high quality (%.2f)" % q_high)
	_check(GameState.wreck["cutting_id"] != -1, "commit starts the cut")
	await _wait_cut_done(8.0)

	# --- Slip aborts (hard-fail) and nudges risk ---
	SalvageSystem.reset_site()
	_setup_matched(_cuttable_ids()[0])
	SalvageSystem.request_cut()
	var risk_before: float = GameState.structural_risk
	var aborted := await _drive_align(false, 5.0)
	_check(aborted, "sustained off-target slip aborts the alignment")
	_check(GameState.align_state == "IDLE", "a slipped alignment returns to IDLE")
	_check(GameState.wreck["cutting_id"] == -1, "a slipped alignment starts no cut")
	_check(GameState.structural_risk > risk_before, "a botched alignment nudges structural risk")

	# --- Stakes bind: clean vs sloppy cut (same power, quality is the only difference) ---
	SalvageSystem.reset_site()
	GameState.wreck["scanned"] = true
	var rich := _richest_ids(2)
	var hi := await _timed_cut(rich[0], 1.0)
	var lo := await _timed_cut(rich[1], 0.0)
	_check(hi["time"] < lo["time"],
			"clean cut completes faster (%.2fs vs %.2fs)" % [hi["time"], lo["time"]])
	_check(hi["ratio"] > lo["ratio"] + 0.2,
			"clean cut preserves more yield (%.2f vs %.2f of base)" % [hi["ratio"], lo["ratio"]])

	if _failures.is_empty():
		print("ALIGN SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("ALIGN SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


## Scanned + selected + cutter powered + MATCHED on `id` (no 3D scene to fly).
func _setup_matched(id: int) -> void:
	GameState.wreck["scanned"] = true
	GameState.local_ship()["power"]["CUTTER"] = 1.0
	GameState.approach_state = "HOLDING"
	GameState.selected_member_id = -1
	SalvageSystem.select_member(id)
	GameState.approach_state = "MATCHED"
	GameState.matched_member_id = id


## Feed align input toward (on_target) or away from (else) the drifting seam until
## the mini-game leaves ALIGNING (commit or abort). Returns true if it resolved.
func _drive_align(on_target: bool, timeout: float) -> bool:
	var elapsed := 0.0
	while GameState.align_state == "ALIGNING" and elapsed < timeout:
		var align: Dictionary = GameState.align
		var reticle := Vector2(align["reticle"])
		var target := Vector2(align["target"])
		var aim: Vector2
		if on_target:
			# Command exactly the move that lands the reticle on the seam this
			# physics step (no overshoot), so it tracks the drift dead-centre for
			# high quality. The mini-game integrates on the physics tick, so the
			# aim must be recomputed at that cadence with that step.
			var rate: float = SalvageSystem.ALIGN_RETICLE_RATE * maxf(get_physics_process_delta_time(), 0.0001)
			aim = ((target - reticle) / rate).clampf(-1.0, 1.0)
		else:
			# Drive to the far corner from the seam to hold well past the slip radius.
			aim = (reticle - target).sign()
			if aim == Vector2.ZERO:
				aim = Vector2.ONE
		SalvageSystem.set_align_input(aim)
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	SalvageSystem.set_align_input(Vector2.ZERO)
	return GameState.align_state != "ALIGNING"


## Drive a cut of `id` to completion at a forced alignment `quality`, exercising
## the real _update_cut/_complete_cut scaling. Returns {time, ratio} where ratio
## is the severed piece's (DriftSystem) quality-scaled qty / the member's base qty.
func _timed_cut(id: int, quality: float) -> Dictionary:
	_setup_matched(id)
	var base: float = float(GameState.get_member(id)["qty"])
	var member_name: String = GameState.get_member(id)["name"]
	GameState.wreck["cutting_id"] = id
	GameState.wreck["cut_progress"] = 0.0
	GameState.wreck["align_quality"] = quality
	var elapsed := 0.0
	while GameState.wreck["cutting_id"] != -1 and elapsed < 12.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	var yield_qty := _piece_qty(member_name)
	return {"time": elapsed, "ratio": (yield_qty / base) if base > 0.0 else 0.0}


func _wait_cut_done(timeout: float) -> void:
	var elapsed := 0.0
	while GameState.wreck["cutting_id"] != -1 and elapsed < timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _cuttable_ids() -> Array[int]:
	var out: Array[int] = []
	for member: Dictionary in GameState.wreck.get("members", []):
		if not member["cut"] and not member["destroyed"]:
			out.append(member["id"])
	return out


## The n members with the largest base qty (least distorted by 0.1 snapping in the
## yield ratio check).
func _richest_ids(n: int) -> Array[int]:
	var members: Array = GameState.wreck.get("members", []).duplicate()
	members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["qty"]) > float(b["qty"]))
	var out: Array[int] = []
	for member: Dictionary in members:
		if out.size() >= n:
			break
		out.append(member["id"])
	return out


## The severed member now detaches as a drifting piece (DriftSystem) instead of
## stowing straight into the hold — read its already quality-scaled qty off
## that piece rather than the cargo list.
func _piece_qty(member_name: String) -> float:
	for piece: Dictionary in GameState.salvage_pieces:
		if piece["name"] == member_name:
			return float(piece["qty"])
	return 0.0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
