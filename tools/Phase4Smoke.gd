extends Node
## Headless end-to-end check of the Phase 4 gameplay loop (plan "Done when"):
## jump in, scan (structural graph), approach, cut and collect 3 items (each
## a real drifting piece scooped through the cargo hatch — see DriftSystem)
## with visibly different risk impact by load, manage cargo (jettison), dock,
## sell, jump back to a fresh site.
##
##   godot --headless res://tools/Phase4Smoke.tscn
##
## Exits 0 on success, 1 with FAIL lines otherwise. Runs the real systems at
## Engine.time_scale, no mocks.

var _failures: Array[String] = []
## member id -> structural_risk at the instant the cut landed (signal-captured
## so the post-spike relaxation can't blur the comparison).
var _risk_at_cut := {}


func _ready() -> void:
	Engine.time_scale = 20.0
	# Keep each physics step at 1/60 s of game time under the accelerated clock
	# (steps per real second scale up; the sim's integration step does not).
	Engine.physics_ticks_per_second = roundi(60.0 * Engine.time_scale)
	InputRouter.set_process(false)
	# InputRouter.set_process(false) only stops InputRouter's OWN _process — its
	# raw-HID children (SwitchPanelBridge etc.) keep polling real connected
	# hardware regardless. On a dev box with a live switch panel, a physical
	# COWL switch left ON would otherwise flip GameState.cargo_hatch_open mid-test
	# and abort a cut out from under _collect_piece.
	for child in InputRouter.get_children():
		child.set_process(false)
	GameState.wreck_member_cut.connect(
			func(id: int) -> void: _risk_at_cut[id] = GameState.structural_risk)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame

	# Market data loaded from .tres definitions.
	_check(GameState.market_factions.size() == 3, "3 factions loaded from data/")
	_check(GameState.market_goods.size() == 5, "5 goods loaded from data/")
	_check(MarketSystem.claim_faction() == "FREEHOLD", "FREEHOLD holds the claim")
	_check(GameState.local_ship()["cargo_mass_limit_t"] > 0.0,
			"ship limits come from ShipDefinition")

	# 1. Scan: STRUCT mode + powered sensors reveal the structural graph.
	_check(not GameState.wreck["scanned"], "site starts unscanned")
	GameState.set_sensor_mode("STRUCT")
	_check(await _wait_until(func() -> bool: return GameState.wreck["scanned"], 20.0),
			"structural scan completes in STRUCT mode")

	# 2. Extract 3 members: cosmetic first, most load-bearing second — the
	# risk impact must differ visibly by load (the plan's core mechanic). The
	# approach now flies to the *selected* member and the cut is alignment-gated,
	# so _cut() picks the target, re-arms the approach, and commits the alignment.
	GameState.set_power("CUTTER", 1.0)
	var low := _pick_member(false)
	var risk_before_low: float = GameState.structural_risk
	var low_id: int = await _cut(low)
	var high := _pick_member(true)
	var risk_before_high: float = GameState.structural_risk
	var high_id: int = await _cut(high)
	var third := _pick_member(false)
	await _cut(third)
	var spike_low: float = _risk_at_cut.get(low_id, 1.0) - risk_before_low
	var spike_high: float = _risk_at_cut.get(high_id, 0.0) - risk_before_high
	_check(spike_high > spike_low + 0.05,
			"load-bearing cut spikes risk visibly more (+%.0f%% vs +%.0f%%)" % [
				spike_high * 100.0, spike_low * 100.0])
	var cargo: Array = GameState.local_ship()["cargo"]
	_check(cargo.size() == 3, "3 salvage items stowed (got %d)" % cargo.size())

	# 4. Manage cargo: jettison one item.
	if not cargo.is_empty():
		CargoSystem.jettison(cargo[0]["id"])
	_check(GameState.local_ship()["cargo"].size() == 2, "jettison removes an item")

	# 5. Dock and sell. The berth is flown for now (DockingSystem), which DockSmoke
	# covers; this test is about the market, so it buys an auto-berth to get in.
	var buyer: String = GameState.market_factions[0]
	MarketSystem.request_dock(0)
	_check(await _wait_until(
			func() -> bool: return GameState.run_phase == "APPROACH", 20.0),
			"transit ends on the station's approach")
	DockingSystem.request_auto_berth()
	_check(await _wait_until(
			func() -> bool: return GameState.run_phase == "DOCKED", 20.0),
			"auto-berth books the berth")
	# After the handling fee, so the sale is measured against what's actually in
	# the account.
	var credits_before: int = GameState.credits
	var rep_before: float = GameState.reputation[buyer]
	var quote: int = MarketSystem.hold_value(0)
	# The hold is discharged through the cargo hatch, so a buttoned-up ship has
	# nothing to hand over — that refusal is what makes opening up the first item
	# of the arrival procedure rather than a courtesy.
	GameState.set_cargo_hatch(false)
	MarketSystem.sell_hold()
	_check(GameState.credits == credits_before,
			"a sale is refused with the cargo hatch secured")
	GameState.set_cargo_hatch(true)
	MarketSystem.sell_hold()
	_check(GameState.credits == credits_before + quote and quote > 0,
			"hold sold for the quoted %d CR" % quote)
	_check(GameState.local_ship()["cargo"].is_empty(), "hold empty after sale")
	_check(GameState.reputation[buyer] > rep_before,
			"reputation rises with the buyer (%s)" % buyer)

	# 6. Jump back: fresh site. Undocking now lifts into a piloted departure
	# (DockSmoke flies it); this asserts the handover and then takes the release
	# ATC would give a ship that had flown the lane out.
	# Open to sell, secure to leave: the hatch that had to be open for the
	# discharge has to be shut again before the ship will be let off the pad.
	MarketSystem.request_undock()
	_check(GameState.run_phase == "DOCKED",
			"departure is refused while the hatch is still open for the discharge")
	GameState.set_cargo_hatch(false)
	MarketSystem.request_undock()
	_check(await _wait_until(
			func() -> bool: return GameState.docking_state == "DEPART_HOLD", 20.0),
			"undocking lifts into the departure pattern")
	DockingSystem.end_approach()
	MarketSystem.complete_undock()
	_check(await _wait_until(
			func() -> bool: return GameState.run_phase == "ON_SITE", 20.0),
			"jump returns to the claim")
	_check(not GameState.wreck["scanned"], "new site needs a fresh scan")
	var any_cut := false
	for member: Dictionary in GameState.wreck["members"]:
		any_cut = any_cut or member["cut"] or member["destroyed"]
	_check(not any_cut, "new wreck graph is intact")

	if _failures.is_empty():
		print("PHASE4 SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("PHASE4 SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


## Uncut member with the highest/lowest frame load (picked live, in case the
## rival got to one first).
func _pick_member(load_bearing: bool) -> Dictionary:
	var best: Dictionary = {}
	for member: Dictionary in GameState.wreck["members"]:
		if member["cut"] or member["destroyed"]:
			continue
		if best.is_empty() \
				or (load_bearing and member["load"] > best["load"]) \
				or (not load_bearing and member["load"] < best["load"]):
			best = member
	return best


func _cut(member: Dictionary) -> int:
	if member.is_empty():
		_check(false, "member available to cut (none left uncut)")
		return -1
	# Per-member approach: pick the target, then fly to it and match. Selecting a
	# new target drops any prior match, so this re-arms the approach each time.
	SalvageSystem.select_member(member["id"])
	SalvageSystem.toggle_approach()
	var matched := await _wait_until(
			func() -> bool: return GameState.approach_state == "MATCHED", 60.0)
	_check(matched, "approach matches on %s" % member["name"])
	_check(SalvageSystem.wreck_distance() <= SalvageSystem.CUT_RANGE,
			"matched inside CUT_RANGE")
	# The cut is alignment-gated: the first trigger opens the mini-game, the second
	# commits it (here at whatever quality has built — the smoke isn't testing aim).
	SalvageSystem.request_cut()
	SalvageSystem.request_cut()
	var done := await _wait_until(
			func() -> bool: return member["cut"], 30.0)
	_check(done, "cut of %s completes" % member["name"])
	# The severed yield is now a drifting piece (DriftSystem), not an instant
	# stow — fly alongside it and scoop it through the cargo hatch.
	var collected := await _collect_piece(member["name"], 8.0)
	_check(collected, "%s collected through the cargo hatch" % member["name"])
	return member["id"]


## Simulates flying the piece down: opens the hatch and, every frame, parks the
## ship a hair off the piece (nose-on, velocity matched) — the three DriftSystem
## collection gates besides range — until its scoop meter fills and it's stowed,
## or this times out.
func _collect_piece(member_name: String, timeout: float) -> bool:
	# Hand control back from the (now-stale, member-cut) approach autopilot to
	# manual flight so it doesn't fight this positioning every frame.
	GameState.approach_state = "HOLDING"
	GameState.set_cargo_hatch(true)
	var elapsed := 0.0
	while elapsed < timeout:
		var piece := _find_piece(member_name)
		if piece.is_empty():
			break
		var piece_pos: Vector3 = (piece["transform"] as Transform3D).origin
		var piece_vel: Vector3 = piece["velocity"]
		var ship: Dictionary = GameState.local_ship()
		var offset := Vector3(0, 0, 1.0)
		ship["transform"] = Transform3D(Basis.looking_at(offset.normalized()), piece_pos - offset)
		ship["velocity"] = piece_vel
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	GameState.set_cargo_hatch(false)
	return _find_piece(member_name).is_empty()


func _find_piece(member_name: String) -> Dictionary:
	for piece: Dictionary in GameState.salvage_pieces:
		if piece["name"] == member_name:
			return piece
	return {}


func _wait_until(predicate: Callable, timeout_game_s: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_game_s:
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
