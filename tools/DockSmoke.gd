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

	# --- The corner into the descent has to be flyable. DELTA's ring is wider
	# than the tube below it, and you arrive there carrying horizontal speed you
	# cannot shed instantly, so a legal crossing near the ring's edge must not be
	# an instant lane bust. ---
	await _fly_to_cleared()
	GameState.set_landing_gear(true)
	await _wait_until(GameState.gear_locked_down, 8.0)
	await _run_gates_to_last()
	var last: int = DockingSystem.GATES.size() - 1
	# Just inside the ring: a crossing ATC accepts as flying the marker.
	var edge: float = float(DockingSystem.GATES[last]["radius"]) - 0.2
	var sideways: Vector3 = DockingSystem.station_transform().basis.x.normalized()
	_teleport(DockingSystem.gate_world(last) + sideways * edge)
	await _wait(0.3)
	_check(GameState.docking_state == "FINAL",
			"crossing DELTA near the edge of its ring still starts the descent")
	var corner_waves: int = GameState.docking.get("wave_offs", 0)
	# Hold that legal-but-offset position for longer than the corridor grace.
	var held_offset := await _hold(
			DockingSystem.gate_world(last) + sideways * edge, Vector3.ZERO,
			func() -> bool: return int(GameState.docking.get("wave_offs", 0)) > corner_waves,
			DockingSystem.LANE_GRACE * 4.0)
	_check(not held_offset,
			"...and is not immediately outside the final corridor (%.1f m off, ring is %.1f)"
					% [edge, float(DockingSystem.GATES[last]["radius"])])
	# The other half: down between the walls it is still the strict tube. The
	# funnel opens where there is nothing to hit, and nowhere else.
	var deep_waves: int = GameState.docking.get("wave_offs", 0)
	var low: Vector3 = DockingSystem.pad_world() \
			+ DockingSystem.pad_up() * (DockingSystem.BAY_WALL_HEIGHT * 0.5) \
			+ sideways * (DockingSystem.FINAL_LANE + 1.5)
	var deep := await _hold(low, Vector3.ZERO,
			func() -> bool: return int(GameState.docking.get("wave_offs", 0)) > deep_waves,
			DockingSystem.LANE_GRACE * 6.0)
	_check(deep, "...but down between the bay walls the corridor is still the tight tube")

	# --- Contact is billed, not waved off. You have already paid in hull, and
	# losing a clearance ten metres off the deck for a scrape is out of all
	# proportion — so the station invoices you and you keep flying. ---
	await _fly_to_cleared()
	var hit_waves: int = GameState.docking["wave_offs"]
	var hit_credits: int = GameState.credits
	var hit_rep: float = GameState.reputation[GameState.market_factions[0]]
	var hit_state: String = GameState.docking_state
	GameState.hull_impact.emit("BOW", 0.2)
	await _wait(0.2)
	_check(GameState.docking_state == hit_state and int(
			GameState.docking["wave_offs"]) == hit_waves,
			"striking the station does not cost the clearance")
	_check(GameState.credits < hit_credits,
			"...it bills you for the damage (%d CR)" % (hit_credits - GameState.credits))
	_check(GameState.reputation[GameState.market_factions[0]] < hit_rep,
			"...and costs standing with the station")
	# One scrape registering over several frames is one invoice.
	var second_bill: int = GameState.credits
	GameState.hull_impact.emit("BOW", 0.2)
	await _wait(0.2)
	_check(GameState.credits == second_bill,
			"a second contact inside the cooldown is not billed twice")

	# --- The deck catches the ship in EVERY state, not just FINAL. Lose the
	# clearance on the way down and you are still descending into a real berth;
	# with the deck check living inside the FINAL handler, such a ship sank past
	# deck height with nothing to catch it and ground against the bay floor's
	# collision hull instead of ever being evaluated as a landing. ---
	await _fly_to_cleared()
	_check(GameState.docking_state == "CLEARED", "set up above the berth, not cleared to land")
	var deck_comms := GameState.comms.size()
	_park_at(_just_above_deck(), Vector3(0, -1.0, 0))
	await _wait(0.4)
	var height: float = (_ship_pos() - DockingSystem.pad_world()).dot(DockingSystem.pad_up())
	_check(height > DockingSystem.GEAR_HEIGHT,
			"arriving at the deck without a clearance bounces the ship clear (%.1f m)" % height)
	_check(_has_comms_since(deck_comms, "WITHOUT A LANDING CLEARANCE"),
			"...and says why, rather than grinding on the bay floor")
	_check(GameState.run_phase == "APPROACH", "...and does not book the berth")

	# --- Being knocked must not cost the approach either. CollisionSystem pushes
	# the ship out of whatever it touched and reflects its velocity, so without an
	# amnesty the shove itself throws you out of the corridor and the go-around
	# arrives anyway — billing you and then waving you off for its own push. ---
	await _fly_to_cleared()
	var knock_waves: int = GameState.docking["wave_offs"]
	var knock_comms := GameState.comms.size()
	# Gentler than IMPACT_SPEED_FLOOR: too soft to damage or bill, and previously
	# too soft to even be mentioned — while still moving the ship.
	GameState.ship_contact.emit("STATION BAYWALL-1+0",
			CollisionSystem.IMPACT_SPEED_FLOOR * 0.5)
	_check(_has_comms_since(knock_comms, "CONTACT"),
			"even a graze too gentle to bill is called out")
	var knocked := await _hold(_leg_point(0.5) + Vector3(0, 60, 0), Vector3.ZERO,
			func() -> bool: return int(GameState.docking["wave_offs"]) > knock_waves,
			DockingSystem.LANE_GRACE * 2.0)
	_check(not knocked, "a knock buys amnesty on the corridor rule")
	var recovered := await _hold(_leg_point(0.5) + Vector3(0, 60, 0), Vector3.ZERO,
			func() -> bool: return int(GameState.docking["wave_offs"]) > knock_waves,
			DockingSystem.CONTACT_GRACE + DockingSystem.LANE_GRACE * 6.0)
	_check(recovered, "...and the rule resumes once the amnesty runs out")

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
	# The damages bill above left the account short, which is the other half of
	# the auto-berth rule: it is a purchase, and you have to be able to afford it.
	_check(GameState.credits < DockingSystem.AUTO_BERTH_FEE,
			"the damages bill left too little for an auto-berth (%d CR)"
					% GameState.credits)
	DockingSystem.request_auto_berth()
	await _wait(0.2)
	_check(GameState.run_phase == "APPROACH", "auto-berth is refused when short of funds")
	GameState.credits = 1000
	GameState.credits_changed.emit(GameState.credits)
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

	# The berth has to be FLYABLE, not just correctly placed. Convex hulls are
	# baked per mesh, so any part modelled as one open shape (a bay is three
	# walls and a floor) comes back as a solid block with the pad inside it —
	# and then the descent is a collision, not a landing. Checked against the
	# real registered hulls rather than the art.
	# The station only registers its hulls while a pattern is live, so an
	# approach has to be running or this measures an empty list and passes
	# for the wrong reason.
	MarketSystem.request_dock(0)
	await _wait_until(func() -> bool: return GameState.run_phase == "APPROACH", 20.0)
	await get_tree().process_frame
	var deck: Vector3 = DockingSystem.pad_world() \
			+ DockingSystem.pad_up() * DockingSystem.GEAR_HEIGHT
	var station_bodies := 0
	var blocking: Array[String] = []
	for obstacle: Dictionary in GameState.obstacles:
		if not String(obstacle["name"]).begins_with("STATION"):
			continue
		station_bodies += 1
		if CollisionSystem.hull_distance(deck, deck, obstacle.get("hull",
				PackedVector3Array())) <= 0.0:
			blocking.append(String(obstacle["name"]))
	_check(station_bodies > 0,
			"the station registers collision hulls while a pattern is live (%d)"
					% station_bodies)
	_check(blocking.is_empty(),
			"the berth is open down to the pad (blocked by: %s)" % (
				", ".join(blocking) if not blocking.is_empty() else "nothing"))
	# The pad itself must never be solid — you land on it, you don't bounce off it.
	var pad_solid := false
	for obstacle: Dictionary in GameState.obstacles:
		var body_name := String(obstacle["name"])
		pad_solid = pad_solid or body_name.contains("PADDECK") \
				or body_name.contains("PADMARKINGS")
	_check(not pad_solid, "the pad deck and its markings are not collision bodies")

	# ...and the whole point of the above: a landing has to actually complete
	# with the station's collision geometry in the world. Every touchdown check
	# further up runs headless, with no station to hit — which is exactly how a
	# bay whose convex hull swallowed its own pad got through them.
	await _fly_to_final()
	var contact_comms := GameState.comms.size()
	_park_at(_just_above_deck(), Vector3(0, -1.0, 0))
	var landed_for_real := await _wait_until(
			func() -> bool: return GameState.run_phase == "DOCKED", 8.0)
	_check(landed_for_real, "a landing completes with the station's hulls in the world")
	_check(not _has_comms_since(contact_comms, "CONTACT"),
			"...without the descent registering a hull contact")
	var worst := 0.0
	for i in DockingSystem.GATES.size():
		var ring: Node3D = rings.get_child(i)
		worst = maxf(worst, ring.global_position.distance_to(DockingSystem.gate_world(i)))
	_check(worst < 0.01,
			"every ring renders exactly on the gate it represents (%.3f m worst)" % worst)

	# --- The BELLY camera: the landing view. A berth pad sits directly under a
	# ship that must stay level to touch down, and the hull camera looks forward
	# while the glance rig only reaches 45° down — so without a downward vantage
	# the pad is the one thing you cannot see, and the instinct that provokes
	# (pitching the nose at it) is exactly what fails the landing. ---
	_check(GameState.EXTERNAL_VIEWS.has("BELLY"), "BELLY is in the external view cycle")
	var rig: Node3D = load("res://scenes/world/ExternalCameraRig.gd").new()
	add_child(rig)
	GameState.set_external_view("BELLY")
	_place_level(DockingSystem.pad_world() + DockingSystem.pad_up() * 8.0)
	for _i in 4:
		await get_tree().process_frame
	var cam: Camera3D = rig.get_child(0)
	var ship_xform: Transform3D = GameState.local_ship()["transform"]
	var below: float = (cam.global_position - ship_xform.origin).dot(ship_xform.basis.y)
	_check(below < 0.0, "the belly camera sits under the hull (%.1f m)" % below)
	var looking: float = (-cam.global_transform.basis.z).dot(DockingSystem.pad_up())
	_check(looking < -0.9, "...and looks straight down at the pad (%.2f)" % looking)
	rig.queue_free()

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


## Wings level on the lane's heading — the only attitude a landing can be flown
## in, so the only one worth measuring the landing view against.
func _place_level(at: Vector3) -> void:
	var ship: Dictionary = GameState.local_ship()
	ship["transform"] = Transform3D(
			Basis.looking_at(DockingSystem.pad_forward(), DockingSystem.pad_up()), at)
	ship["velocity"] = Vector3.ZERO


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


## Every gate except the last, so a check can control exactly how the final one
## is crossed.
func _run_gates_to_last() -> void:
	for i in range(int(GameState.docking.get("gate", 1)), DockingSystem.GATES.size() - 1):
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
