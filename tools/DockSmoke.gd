extends Node
## Headless checks for the docking/landing mini-game (DockingSystem):
##  - the transit burn hands over to a flown approach instead of berthing;
##  - the hold gates the clearance on being stopped AND on the lane being clear
##    of traffic, and ATC calls it itself once both hold;
##  - the lane's markers must be flown through in order, and missing one,
##    leaving the corridor, or sitting over the speed limit sends you around;
##  - the gear travels in real time, is required at the final gate, and
##    interlocks the cutter while it's extended;
##  - a hot touchdown bounces and a clean one books the berth, scored;
##  - auto-berth is a paid alternative inbound and refused on final;
##  - the departure is flown too: gear down until clear of the bay, stowed
##    before ATC releases the ship, and rules broken outbound cost standing
##    rather than turning the ship round;
##  - the 3D station agrees with the lane data it's built from.
##
##   godot --headless res://tools/DockSmoke.tscn
##
## Mostly runs with no 3D scene — DockingSystem's geometry defaults to
## DEFAULT_STATION_ORIGIN so every rule is exercisable headless, the same
## shortcut AlignSmoke/DriftSmoke use. The last section loads the real world
## scene to check Station.gd places its rings and pad from the same constants.
## InputRouter._process (and its raw-HID children) are disabled so a physically
## connected panel can't drive the ship out from under these checks.

## Generous: a clearance waits on the sequencing delay AND on traffic clearing
## the lane, and the ore barge works a slow 190 m transit across the hold.
const CLEARANCE_TIMEOUT := 120.0

var _failures: Array[String] = []


func _ready() -> void:
	Engine.time_scale = 10.0
	InputRouter.set_process(false)
	for child in InputRouter.get_children():
		child.set_process(false)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	# Traffic phases are random per visit, which makes ATC's sequencing hold
	# random too — pinned here so a failure is reproducible.
	DockingSystem.set_traffic_seed(20260809)

	# --- The gear interlocks the cutter (a leg sits in the torch's arc), which
	# is what gives it a cost back at the claim and not just at the station.
	# Checked here, on site, because that is the only phase the cutter runs in. ---
	GameState.set_landing_gear(true)
	await _wait_until(GameState.gear_locked_down, 8.0)
	var cut_comms := GameState.comms.size()
	SalvageSystem.request_cut()
	_check(_has_comms_since(cut_comms, "STOW THE LANDING GEAR"),
			"extended gear interlocks the cutter at the claim")
	GameState.set_landing_gear(false)
	await _wait_until(GameState.gear_stowed, 8.0)

	# --- Handover: docking is flown now, so the burn ends on the approach. ---
	MarketSystem.request_dock(0)
	var handed := await _wait_until(
			func() -> bool: return GameState.run_phase == "APPROACH", 20.0)
	_check(handed, "the transit burn hands over to a flown approach")
	_check(GameState.docking_state == "INBOUND", "the pattern starts INBOUND")
	_check(GameState.traffic.size() == DockingSystem.TRAFFIC_ROUTES.size(),
			"the station's traffic is in the pattern (%d ships)" % GameState.traffic.size())
	var entry_range: float = _ship_pos().distance_to(DockingSystem.gate_world(0))
	_check(entry_range > 40.0,
			"the ship arrives out on the approach, not on top of the marker (%.0f m)"
					% entry_range)

	# --- Gear travel is real time, and it interlocks the cutter. ---
	GameState.set_landing_gear(true)
	_check(not GameState.gear_locked_down(), "selecting gear down does not lock it instantly")
	await _wait(GameState.GEAR_TRAVEL_TIME * 0.5)
	_check(GameState.gear_position > 0.2 and GameState.gear_position < 0.9,
			"the gear is mid-travel a moment later (%.2f)" % GameState.gear_position)
	var locked := await _wait_until(GameState.gear_locked_down, 6.0)
	_check(locked, "the gear reaches down-and-locked on its own")
	GameState.set_landing_gear(false)
	var stowed := await _wait_until(GameState.gear_stowed, 6.0)
	_check(stowed, "...and stows again")

	# --- The hold: a clearance has to be earned. ---
	_park_at(DockingSystem.gate_world(0), Vector3(0, 0, -20))
	var held := await _wait_until(
			func() -> bool: return GameState.docking_state == "HOLD", 15.0)
	_check(held, "reaching marker ALPHA puts the ship in the hold")
	DockingSystem.request_clearance()
	_check(GameState.docking_state == "HOLD",
			"a clearance is refused while the ship is still moving")
	_stop_ship()
	DockingSystem.request_clearance()
	_check(GameState.docking_state == "HOLD",
			"...and still refused before the sequencing delay is served")
	var cleared := await _wait_until(
			func() -> bool: return GameState.docking_state == "CLEARED",
			CLEARANCE_TIMEOUT)
	_check(cleared, "ATC calls the clearance itself once the delay is served")
	_check(int(GameState.docking["gate"]) == 1, "the first marker to make is BRAVO")

	# --- Markers must be flown through, in order. ---
	var wave_offs: int = GameState.docking["wave_offs"]
	_teleport(DockingSystem.gate_world(1))
	await _wait(0.2)
	_check(int(GameState.docking["gate"]) == 2, "flying through BRAVO advances to CHARLIE")
	# Skipping straight past CHARLIE's plane, outside its ring, is a miss.
	_teleport(DockingSystem.gate_world(2)
			+ (DockingSystem.gate_world(3) - DockingSystem.gate_world(2)).normalized() * 12.0
			+ Vector3(0, 30, 0))
	var missed := await _wait_until(
			func() -> bool: return int(GameState.docking["wave_offs"]) > wave_offs, 4.0)
	_check(missed, "crossing a marker's plane outside its ring is a go-around")
	_check(GameState.docking_state == "INBOUND", "a go-around puts the ship back inbound")

	# --- Overspeed and the corridor. ---
	await _fly_to_cleared()
	var before_speed: int = GameState.docking["wave_offs"]
	# Pinned every frame: flight assist bleeds residual velocity (and in SPEED
	# mode drives the forward component to the throttle, which is zero here), so
	# a one-shot injection decays out of the overspeed band before SPEED_GRACE is
	# up. Holding position too keeps the corridor rule out of what's under test.
	var sped := await _hold(_leg_point(0.5),
			Vector3(0, 0, -DockingSystem.SPEED_CLEARED * 3.0),
			func() -> bool: return int(GameState.docking["wave_offs"]) > before_speed,
			DockingSystem.SPEED_GRACE * 4.0)
	_check(sped, "sitting over the pattern speed limit sends the ship around")

	await _fly_to_cleared()
	var before_lane: int = GameState.docking["wave_offs"]
	# Well outside the corridor for the leg being flown, but stationary, so only
	# the lane rule can be what trips.
	_park_at(_leg_point(0.5) + Vector3(0, 60, 0), Vector3.ZERO)
	var strayed := await _wait_until(
			func() -> bool: return int(GameState.docking["wave_offs"]) > before_lane,
			DockingSystem.LANE_GRACE * 6.0)
	_check(strayed, "leaving the lane corridor sends the ship around")

	# --- The gear is required at the final gate. ---
	await _fly_to_cleared()
	GameState.set_landing_gear(false)
	await _wait_until(GameState.gear_stowed, 6.0)
	var before_gear: int = GameState.docking["wave_offs"]
	await _run_gates()
	await _wait(0.3)
	_check(int(GameState.docking["wave_offs"]) > before_gear,
			"reaching the final gate with the gear up is a go-around")

	# --- A hot touchdown bounces; a clean one books the berth. ---
	await _fly_to_final()
	var bounces: int = GameState.docking["wave_offs"]
	# Placed a hair BELOW gear height so contact is judged on the next tick with
	# the sink rate intact — dropped from above, flight assist would bleed the
	# rate away before the ship ever reached the deck.
	_park_at(_just_above_deck(), Vector3(0, -(DockingSystem.CRASH_RATE + 4.0), 0))
	var bounced := await _wait_until(
			func() -> bool: return int(GameState.docking["wave_offs"]) > bounces, 4.0)
	_check(bounced, "arriving faster than the legs can take bounces the ship")
	_check(GameState.run_phase == "APPROACH", "...and does not book the berth")

	await _fly_to_final()
	_park_at(_just_above_deck(), Vector3(0, -1.0, 0))
	var down := await _wait_until(
			func() -> bool: return GameState.run_phase == "DOCKED", 8.0)
	_check(down, "a gentle touchdown on the markings books the berth")
	_check(_has_comms("TOUCHDOWN"), "the arrival is graded on the comms log")

	# --- Departure is flown too. ---
	MarketSystem.request_undock()
	var lifted := await _wait_until(
			func() -> bool: return GameState.docking_state == "DEPART_HOLD", 10.0)
	_check(lifted, "undocking lifts into the departure pattern rather than jumping")
	_check(GameState.gear_locked_down(), "the ship starts the departure on its legs")
	_check(_ship_pos().distance_to(DockingSystem.pad_world())
			< DockingSystem.GEAR_HEIGHT + 0.5, "...standing on the pad")
	var out_cleared := await _wait_until(
			func() -> bool: return GameState.docking_state == "DEPARTING",
			CLEARANCE_TIMEOUT)
	_check(out_cleared, "ATC calls the departure once the delay is served")
	_check(int(GameState.docking["gate"]) == DockingSystem.GATES.size() - 1,
			"the outbound lane starts at the marker an arrival ends on")

	# Stowing the gear inside the bay is a reprimand, not a go-around: it costs
	# standing and leaves the ship flying.
	var rep_before: float = GameState.reputation[GameState.market_factions[0]]
	GameState.set_landing_gear(false)
	await _wait_until(GameState.gear_stowed, 6.0)
	await _wait(0.4)
	_check(GameState.docking_state == "DEPARTING",
			"a rule broken outbound does not turn the ship round")
	_check(GameState.reputation[GameState.market_factions[0]] < rep_before,
			"...it costs standing with the station instead")

	# Fly the lane out. The release is held until the gear is actually stowed.
	GameState.set_landing_gear(true)
	await _wait_until(GameState.gear_locked_down, 6.0)
	_run_gates_outbound()
	await _wait(0.4)
	_check(GameState.run_phase == "APPROACH",
			"ATC holds the release while the ship is still hanging legs")
	_check(_has_comms("STOW YOUR GEAR"), "...and says so")
	GameState.set_landing_gear(false)
	await _wait_until(GameState.gear_stowed, 6.0)
	var released := await _wait_until(
			func() -> bool: return GameState.run_phase != "APPROACH", 6.0)
	_check(released, "stowing the gear releases the ship from the pattern")
	var home := await _wait_until(
			func() -> bool: return GameState.run_phase == "ON_SITE", 20.0)
	_check(home, "the jump completes back at the claim")

	# --- Auto-berth: the paid way out of the pattern. ---
	MarketSystem.request_dock(0)
	await _wait_until(func() -> bool: return GameState.run_phase == "APPROACH", 20.0)
	var credits_before: int = GameState.credits
	DockingSystem.request_auto_berth()
	var bought := await _wait_until(
			func() -> bool: return GameState.run_phase == "DOCKED", 10.0)
	_check(bought, "auto-berth books the berth without flying the pattern")
	_check(GameState.credits == credits_before - DockingSystem.AUTO_BERTH_FEE,
			"...for the handling fee (%d CR)" % DockingSystem.AUTO_BERTH_FEE)

	# It is an alternative to flying it, not an escape from a landing gone wrong.
	MarketSystem.request_undock()
	await _wait_until(func() -> bool: return GameState.docking_state == "DEPART_HOLD", 10.0)
	DockingSystem.end_approach()
	MarketSystem.complete_undock()
	await _wait_until(func() -> bool: return GameState.run_phase == "ON_SITE", 20.0)
	MarketSystem.request_dock(0)
	await _wait_until(func() -> bool: return GameState.run_phase == "APPROACH", 20.0)
	await _fly_to_final()
	DockingSystem.request_auto_berth()
	await _wait(0.2)
	_check(GameState.run_phase == "APPROACH", "auto-berth is refused on final")

	# --- The DOCK page renders in both of its modes. Its draw code only runs
	# when the page is visible, so nothing else here would catch a bad index or
	# a missing status key in it. ---
	var page: Control = load("res://scenes/ui/DockPanel.gd").new()
	page.size = Vector2(420, 640)
	add_child(page)
	# The previous check left the ship on final, so take the pad view first and
	# then get waved off (gear up on final) back onto the lane.
	page.queue_redraw()
	await get_tree().process_frame
	_check(DockingSystem.status()["state"] == "FINAL",
			"the DOCK page draws the pad view on final")
	GameState.set_landing_gear(false)
	await _wait_until(func() -> bool: return GameState.docking_state == "INBOUND", 10.0)
	await _fly_to_cleared()
	page.queue_redraw()
	await get_tree().process_frame
	_check(DockingSystem.status()["state"] == "CLEARED",
			"...and the lane view on a cleared approach")
	DockingSystem.abort_approach()
	page.queue_redraw()
	await get_tree().process_frame
	_check(DockingSystem.status().is_empty(),
			"...and the idle notice with no approach running")
	page.queue_free()
	await _wait_until(func() -> bool: return GameState.run_phase == "ON_SITE", 20.0)

	# --- The 3D station is built from the same constants the rules use. ---
	var world: Node3D = load("res://scenes/world/DebrisField.tscn").instantiate()
	add_child(world)
	for _i in 6:
		await get_tree().process_frame
	var station: Node3D = world.get_node("Station")
	_check(DockingSystem.station_transform().origin.distance_to(station.global_position) < 0.01,
			"Station.gd registers its own placement with the rules")
	var rings: Node3D = station.get_node("Gates")
	_check(rings.get_child_count() == DockingSystem.GATES.size(),
			"a gate ring exists per lane gate (%d)" % rings.get_child_count())
	var worst := 0.0
	for i in DockingSystem.GATES.size():
		var ring: Node3D = rings.get_child(i)
		worst = maxf(worst, ring.global_position.distance_to(DockingSystem.gate_world(i)))
	_check(worst < 0.01,
			"every ring renders exactly on the gate it represents (%.3f m worst)" % worst)

	if _failures.is_empty():
		print("DOCK SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("DOCK SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


## --- Helpers ----------------------------------------------------------------


func _ship_pos() -> Vector3:
	return (GameState.local_ship()["transform"] as Transform3D).origin


## Put the ship somewhere with a velocity, keeping its basis — there is no 3D
## scene to fly in, so every positional check drives the transform by hand the
## way AlignSmoke does.
func _park_at(position: Vector3, velocity: Vector3) -> void:
	var ship: Dictionary = GameState.local_ship()
	var xform: Transform3D = ship["transform"]
	xform.origin = position
	ship["transform"] = xform
	ship["velocity"] = velocity


## Ship origin a hair below the height at which the legs are on the deck, so the
## very next DockingSystem tick judges the contact.
func _just_above_deck() -> Vector3:
	return DockingSystem.pad_world() \
			+ DockingSystem.pad_up() * (DockingSystem.GEAR_HEIGHT - 0.05)


func _teleport(position: Vector3) -> void:
	_park_at(position, Vector3.ZERO)


func _stop_ship() -> void:
	GameState.local_ship()["velocity"] = Vector3.ZERO


## A point along the leg currently being flown, `t` of the way down it.
func _leg_point(t: float) -> Vector3:
	var index: int = GameState.docking.get("gate", 1)
	var from: Vector3 = DockingSystem.gate_world(maxi(index - 1, 0))
	return from.lerp(DockingSystem.gate_world(index), t)


## Get back to a fresh clearance after a go-around: park on the marker, stop,
## and wait for ATC to call it.
func _fly_to_cleared() -> void:
	if GameState.docking_state != "INBOUND" and GameState.docking_state != "HOLD":
		return
	_park_at(DockingSystem.gate_world(0), Vector3.ZERO)
	await _wait_until(func() -> bool: return GameState.docking_state == "HOLD", 10.0)
	_stop_ship()
	await _wait_until(func() -> bool: return GameState.docking_state == "CLEARED",
			CLEARANCE_TIMEOUT)


## Hop the ship through every remaining ring in order.
func _run_gates() -> void:
	for i in range(int(GameState.docking.get("gate", 1)), DockingSystem.GATES.size()):
		_teleport(DockingSystem.gate_world(i))
		await get_tree().process_frame


func _run_gates_outbound() -> void:
	for i in range(int(GameState.docking.get("gate", 0)), -1, -1):
		_teleport(DockingSystem.gate_world(i))
		await get_tree().process_frame


## Cleared, gear down, and through every gate — parked on final over the pad.
func _fly_to_final() -> void:
	await _fly_to_cleared()
	GameState.set_landing_gear(true)
	await _wait_until(GameState.gear_locked_down, 8.0)
	await _run_gates()
	await _wait_until(func() -> bool: return GameState.docking_state == "FINAL", 4.0)


func _wait(game_seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < game_seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


## Wait for `predicate`, re-pinning the ship's pose and velocity every frame.
## Manual flight integrates and bleeds velocity each tick, so any rule that needs
## a condition SUSTAINED (overspeed, corridor) has to be held rather than poked
## once. Pinning position as well keeps one rule under test at a time.
func _hold(position: Vector3, velocity: Vector3, predicate: Callable,
		timeout_seconds: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		_park_at(position, velocity)
		if predicate.call():
			return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return predicate.call()


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
		if String(GameState.comms[i]["text"]).contains(substr):
			return true
	return false


func _has_comms(substr: String) -> bool:
	for entry: Dictionary in GameState.comms:
		if String(entry["text"]).contains(substr):
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
