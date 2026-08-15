extends Node
## The docking/landing mini-game: hand-flying a station's arrival pattern under
## ATC control, then setting the ship down on a berth pad.
##
## Docking used to be a button and a three-second timer (MarketSystem). It is now
## a piloted phase of its own (run_phase APPROACH): MarketSystem still runs the
## abstract burn out to the station, but it hands the ship over here on arrival
## and only books the berth once the gear is actually on the deck.
##
## The task has four interlocking parts, none of which can be flown by autopilot:
##
##   * A LANE of gates — ALPHA (the hold marker), BRAVO, CHARLIE, DELTA — that
##     doglegs through the station's structure and narrows as it goes. Each gate
##     must be flown THROUGH (inside its ring, before its plane) and each leg has
##     a corridor you have to stay inside, so the last stretch is genuinely tight
##     quarters between two habitat drums and down into a walled berth bay.
##   * TRAFFIC working the same volume — a lane tug, a shuttle on the ring
##     circuit, an ore barge on the outer transit. They're solid (CollisionSystem
##     tests them) and they foul the lane on their own schedule, which is what
##     ATC sequences you around.
##   * ATC INSTRUCTIONS you have to comply with: hold at the marker until you're
##     cleared, keep under the speed you were given, hold position again if
##     traffic crosses ahead, gear down before the final gate. Breaking one gets
##     you sent around the pattern again. ACTUAL CONTACT is treated differently —
##     it's billed, not waved off (see _bill_damages), because it has already
##     cost you hull and losing the clearance for it as well would be a
##     punishment out of all proportion to a scrape.
##   * THE LANDING itself: descend into the berth and put it on the pad with the
##     gear down and locked, wings level, inside the pad markings, at a sink rate
##     the legs can take. Quality is scored — a greaser earns standing with the
##     faction, an arrival costs hull.
##
## Geometry lives here as STATION-LOCAL data (the GATES / PAD_LOCAL /
## TRAFFIC_ROUTES constants) and Station.gd places its 3D gate rings and traffic
## meshes FROM that data, so the thing you fly and the thing you see can't drift
## apart. A station node registers its world transform (register_station); with
## no 3D scene at all — a headless smoke run — the default transform keeps every
## rule testable.
##
## Motion has no engine physics behind it, same as the rest of the project: the
## ship is integrated by SalvageSystem's manual flight, traffic is walked along
## parametric routes here, and both are mirrored into GameState.contacts so
## collision and the displays see them.

## Where the station sits when no Station node has registered one (headless).
const DEFAULT_STATION_ORIGIN := Vector3(0, 0, 900)

## The arrival lane, in station-local space (+Y up; ships arrive from +Z and work
## inbound toward -Z). Per gate: the ring you must fly through (`radius`) and the
## corridor radius around the leg that LEADS to it (`lane`) — both tighten as you
## get closer in. Gate 0 is the hold marker: it has no corridor, since getting to
## it is free flight.
const GATES := [
	{"name": "ALPHA", "position": Vector3(0, 0, 190), "radius": 14.0, "lane": 40.0},
	{"name": "BRAVO", "position": Vector3(0, 10, 120), "radius": 12.0, "lane": 22.0},
	{"name": "CHARLIE", "position": Vector3(-30, 10, 66), "radius": 9.0, "lane": 15.0},
	{"name": "DELTA", "position": Vector3(-30, 16, 14), "radius": 6.5, "lane": 10.0},
]
## Index of the hold marker in GATES (where you wait for a clearance, and where a
## wave-off sends you back to).
const HOLD_GATE := 0
## Berth pad centre, station-local. The final leg is the vertical drop from
## DELTA (directly above it) onto this point.
const PAD_LOCAL := Vector3(-30, 0, 14)
## Deck markings you have to be inside to be ON the pad rather than beside it.
const PAD_RADIUS := 7.0
## How far either side of the pad centre still counts as "in the berth" for the
## purposes of hitting the deck — the bay's footprint, a little wider than the
## markings. Outside this, being at deck height is just open space beside the
## station rather than an arrival.
const DECK_REACH := 11.0
## The descent from DELTA onto the pad is a FUNNEL, not a tube.
##
## Between the bay walls (which stand BAY_WALL_HEIGHT above the deck — the
## BAY_HEIGHT that tools/build_station.py builds them to) the corridor is the
## strict FINAL_LANE: the walls sit 9 m out, so this is the "between the walls"
## gate and it has to stay tight.
##
## ABOVE the walls it opens out to FINAL_LANE_TOP, because a constant 6 m tube
## is not flyable and never was:
##   * DELTA's ring is 6.5 m, so crossing the marker legally anywhere but dead
##     centre put you outside the corridor on the very next frame; and
##   * you arrive at DELTA carrying up to SPEED_CLEARED of HORIZONTAL speed and
##     the final leg is a vertical drop, so overshooting the descent axis while
##     you turn the corner is unavoidable, not sloppy flying.
## There is nothing to hit up there, so that is where the room belongs.
const FINAL_LANE := 6.0
const FINAL_LANE_TOP := 10.0
const BAY_WALL_HEIGHT := 8.0
## Where the ship is placed when it arrives from the transit burn: out along the
## lane, short of the hold marker, so the first thing you do is fly to ALPHA.
const ENTRY_LOCAL := Vector3(0, 0, 246)

## Ship-origin altitude above the pad at which the gear is on the deck.
const GEAR_HEIGHT := 2.2

## ATC speed limits (m/s) by state. HOLD_SPEED doubles as the "hold position"
## limit when ATC stops you mid-approach for crossing traffic.
const SPEED_INBOUND := 22.0
const SPEED_CLEARED := 12.0
const SPEED_FINAL := 6.0
const HOLD_SPEED := 3.0
## Seconds over the limit before it stops being a warning and becomes a go-around.
const SPEED_GRACE := 2.5
## Seconds outside the lane corridor before the same.
const LANE_GRACE := 1.2

## Minimum seconds parked at the hold marker before ATC will issue a clearance —
## you are being sequenced behind the traffic already in the pattern, so there is
## always a hold to fly, not just a formality to click through.
const CLEARANCE_MIN_HOLD := 5.0
## A traffic ship this close to the lane ahead of you fouls it: ATC withholds
## clearance, or stops you where you are if you're already inbound.
const LANE_CONFLICT_RANGE := 22.0
## Advisory band — ATC calls the traffic out but nothing is broken yet.
const TRAFFIC_ADVISORY := 8.0
## ...and past that, hull-to-hull margin below which separation is lost and you
## are sent around. A near miss is a procedural failure, so it costs the
## clearance; actually hitting the thing is damage, and gets billed instead.
const SEPARATION_MARGIN := 2.5

## Touchdown limits. Sink rate below FIRM is a greaser; above HARD it costs hull;
## above CRASH (or gear up / off the pad / not level) the legs won't take it and
## you bounce back into the pattern.
const FIRM_RATE := 1.5
const HARD_RATE := 3.0
const CRASH_RATE := 5.0
const TILT_LIMIT_DEG := 20.0
## Lateral speed across the pad that still counts as a landing rather than a
## slide off the markings.
const TOUCHDOWN_DRIFT := 2.0

## Hull integrity lost per m/s of sink rate past HARD_RATE.
const DAMAGE_PER_RATE := 0.06
## Standing with the berth's faction: earned for a clean arrival, lost for a
## bounced one or a repeated go-around.
const REP_PER_LANDING := 0.04
const REP_PER_WAVE_OFF := 0.02
## ...but capped for the whole visit. A pattern you are struggling with should
## cost you a reputation, not erase it, and an uncapped bleed turns a bad run
## into an unrecoverable one: a single visit that racked up hundreds of
## go-arounds took a faction from full standing to zero, which then closes off
## the prices and the goodwill you would need to dig back out.
const REP_WAVE_OFF_CAP := 0.12

## Auto-berth: ATC flies you in on request, so a run can be wrapped up without
## the pattern. Deliberately the worse deal — a flat handling fee and a standing
## hit, against the standing a flown arrival earns — so it's an out, not a
## shortcut past a landing you don't fancy.
const AUTO_BERTH_FEE := 300
const REP_AUTO_BERTH := 0.03

## Departure: a broken rule on the way out is a reprimand rather than a
## go-around (sending a departing ship back to the pad would just trap a bad
## pilot at the station), so it costs standing on a cooldown instead.
const REP_PER_REPRIMAND := 0.015
const REPRIMAND_COOLDOWN := 6.0

## Hitting the station's structure is billed, not waved off. You have already
## paid for it in hull damage, and losing the clearance ten metres off the deck
## for scraping a bay wall is a punishment out of all proportion to the mistake —
## so the station charges you for the damage and thinks less of you, and you
## carry on flying. The bill is a call-out fee plus the repair, scaled by how
## hard you hit (CollisionSystem caps impact damage at 0.6).
## Scaled against a hold that sells for roughly 1000 CR: a scrape at the final
## gate's 6 m/s costs about a quarter of a run, and the worst hit the collision
## model can produce costs about half. Enough to hurt, not enough to end you.
const DAMAGES_CALL_OUT := 100
const DAMAGES_PER_DAMAGE := 800.0
const REP_PER_COLLISION := 0.05
## Seconds before a second impact can be billed again, so one clumsy scrape that
## registers over several frames is one invoice.
const DAMAGES_COOLDOWN := 3.0

## Seconds of amnesty on the SUSTAINED rules (corridor, speed) after touching
## something. CollisionSystem pushes the ship back out of whatever it hit and
## reflects its velocity, which on the final descent throws it clean out of a 6 m
## tube — so without this, "contact is billed, not waved off" was a lie: the bill
## arrived and then the shove you took from the wall waved you off a second
## later, for a deviation the impact caused rather than the pilot. Long enough to
## gather it up and get back on the centreline.
const CONTACT_GRACE := 5.0

## Hull wear per second of flying over the gear's rated speed with it extended.
const GEAR_STRESS_PER_S := 0.02

## Station traffic, in station-local space like the lane. `loop` is "pingpong"
## (out and back along the path) or "cycle" (a closed circuit).
const TRAFFIC_ROUTES := [
	{
		"name": "LANE TUG BOLLARD", "kind": "TUG", "radius": 3.5, "speed": 9.0,
		"loop": "pingpong",
		# Crosses the BRAVO→CHARLIE leg square on: this is the traffic you get
		# sequenced behind at the hold, and the one that can stop you mid-lane.
		"path": [Vector3(-95, 10, 92), Vector3(75, 10, 92)],
	},
	{
		"name": "SHUTTLE MERIDIAN 9", "kind": "SHUTTLE", "radius": 2.5, "speed": 15.0,
		"loop": "cycle",
		"path": [Vector3(62, 24, 44), Vector3(4, 24, 136), Vector3(-72, 24, 62),
				Vector3(-44, 24, -28), Vector3(44, 24, -18)],
	},
	{
		"name": "ORE BARGE THRENODY", "kind": "BARGE", "radius": 6.0, "speed": 5.0,
		"loop": "pingpong",
		# Outer transit across the hold marker's approach — slow, huge, and
		# reason enough for ATC to keep you parked at ALPHA for a while.
		"path": [Vector3(96, -8, 236), Vector3(-96, -8, 172)],
	},
]

var _rng := RandomNumberGenerator.new()

## Where the station actually is. Station.gd registers the real one at scene
## setup; the default keeps every rule below exercisable headless.
var _station_xform := Transform3D(Basis.IDENTITY, DEFAULT_STATION_ORIGIN)

## Pattern timers. `_pattern_time` drives the traffic routes and keeps running
## for the whole visit so ships don't jump when a wave-off resets the rest.
var _pattern_time := 0.0
var _hold_time := 0.0
var _over_speed := 0.0
var _off_lane := 0.0
var _next_traffic_id := 0
## Fix the current leg is flown FROM: the last gate passed (or the hold marker).
## Kept as a world point so a wave-off can rebuild the corridor without replaying
## the route.
var _leg_from := Vector3.ZERO
## Traffic already called out as advisory this pass, so "TRAFFIC — TRAFFIC" is a
## call and not a siren.
var _advised: Dictionary = {}
## Seconds left before another outbound reprimand can cost standing again.
var _reprimand_cool := 0.0
## ...and the same for damage invoices.
var _damages_cool := 0.0
## Seconds of post-contact amnesty left on the sustained rules.
var _contact_grace := 0.0


## Fix the traffic phasing so a run is reproducible. Traffic spawns with a random
## phase per visit (so the pattern is never the same rehearsal twice), which also
## means ATC's sequencing hold is random — fine to fly, impossible to test
## against. DockSmoke pins this; nothing in the game calls it.
func set_traffic_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func _ready() -> void:
	_rng.randomize()
	# Running into anything at all while flying a pattern is a go-around: the
	# damage is CollisionSystem's business, the clearance is ours.
	GameState.hull_impact.connect(_on_hull_impact)
	# Every contact, including the gentle ones that never reach hull_impact.
	GameState.ship_contact.connect(_on_ship_contact)


## --- Scene registration (Station.gd) ---------------------------------------


## Station.tscn reports its real placement at scene setup. The lane, the pad and
## the traffic routes are all authored station-locally, so this one transform is
## the only thing the 3D scene and the rules have to agree on.
func register_station(xform: Transform3D) -> void:
	_station_xform = xform
	if is_active():
		_publish_gates()


func station_transform() -> Transform3D:
	return _station_xform


## Station-local → world. Station.gd builds its gate rings and pad from the same
## constants through this, so the geometry you see is the geometry you're flying.
func to_world(local: Vector3) -> Vector3:
	return _station_xform * local


## World position of gate `index`, or the pad for an index past the last gate.
func gate_world(index: int) -> Vector3:
	if index < 0 or index >= GATES.size():
		return to_world(PAD_LOCAL)
	return to_world(GATES[index]["position"])


## The pad's frame: centre, the up axis a landing is measured against, and the
## heading a berthed ship parks on (the lane's inbound direction).
func pad_world() -> Vector3:
	return to_world(PAD_LOCAL)


func pad_up() -> Vector3:
	return _station_xform.basis.y.normalized()


func pad_forward() -> Vector3:
	return -_station_xform.basis.z.normalized()


## --- Queries (read-only, safe for displays) --------------------------------


func is_active() -> bool:
	return GameState.docking_state != "INACTIVE"


## Flying the pattern OUTBOUND (undocking) rather than inbound. The lane, the
## corridors and the speed rules are the same either way — what differs is the
## gate order and what a broken rule costs.
func _outbound() -> bool:
	return GameState.docking_state == "DEPART_HOLD" \
			or GameState.docking_state == "DEPARTING"


## True while the ship is still climbing out of the berth bay (the pad→DELTA
## leg), which is where the gear has to stay down and the tight limits apply.
func _in_berth_bay() -> bool:
	return GameState.docking_state == "DEPARTING" \
			and int(GameState.docking.get("gate", 0)) >= GATES.size() - 1


## Speed ATC is holding you to right now. A hold instruction overrides the
## per-state limit — "hold position" means stop, wherever you happen to be.
func speed_limit() -> float:
	if GameState.docking.get("hold", false) or GameState.docking_state == "HOLD" \
			or GameState.docking_state == "DEPART_HOLD":
		return HOLD_SPEED
	match GameState.docking_state:
		"CLEARED":
			return SPEED_CLEARED
		"FINAL":
			return SPEED_FINAL
		"DEPARTING":
			# Same tight limit on the way up out of the bay as on the way down.
			return SPEED_FINAL if _in_berth_bay() else SPEED_CLEARED
	return SPEED_INBOUND


## Full evaluation of the approach in one place — the same numbers the rules
## below test, so the DOCK page and the HUD can't disagree with what ATC is
## actually watching. {} when no approach is running.
##
## Directions use the reticle convention the rest of the UI shares (+x
## screen-right, +y screen-down), relative to the ship's nose:
##   aim   — where the next gate sits off the nose; the vector's MAGNITUDE is
##           the off-axis angle in degrees, so it drops straight onto a cone field
##   drift — on final, the ship's offset across the pad in the pad's own axes
func status() -> Dictionary:
	if not is_active():
		return {}
	var ship: Dictionary = GameState.local_ship()
	var xform: Transform3D = ship["transform"]
	var velocity: Vector3 = ship.get("velocity", Vector3.ZERO)
	var index: int = GameState.docking.get("gate", HOLD_GATE)
	var final_leg: bool = GameState.docking_state == "FINAL"
	var target: Vector3 = pad_world() if final_leg else gate_world(index)
	var to_target: Vector3 = target - xform.origin
	var dist := to_target.length()
	var los := to_target / dist if dist > 0.0001 else -xform.basis.z
	var inv := xform.basis.inverse()
	var local := inv * los
	var off_axis := rad_to_deg(acos(clampf(-local.z, -1.0, 1.0)))
	var lateral := Vector2(local.x, -local.y)
	var aim := (lateral.normalized() * off_axis) if lateral.length() > 0.0001 else Vector2.ZERO
	var limit := speed_limit()
	var speed := velocity.length()
	var up := pad_up()
	var pad := pad_world()
	var from_pad: Vector3 = xform.origin - pad
	var altitude := from_pad.dot(up)
	var pad_offset: Vector3 = from_pad - up * altitude
	var out := {
		"state": GameState.docking_state,
		"station": GameState.docking.get("station", ""),
		"berth": GameState.docking.get("berth", 0),
		"atc": GameState.docking.get("atc", {}),
		"gate": index,
		"gate_name": "PAD" if final_leg else String(GATES[index]["name"]),
		"gate_position": target,
		"gate_radius": PAD_RADIUS if final_leg else float(GATES[index]["radius"]),
		"range": dist,
		"aim": aim,
		"off_axis": off_axis,
		"lane_deviation": _lane_deviation(xform.origin),
		"lane_limit": _lane_limit(xform.origin),
		"speed": speed,
		"speed_limit": limit,
		"speed_ok": speed <= limit,
		"hold": GameState.docking.get("hold", false) or GameState.docking_state == "HOLD"
				or GameState.docking_state == "DEPART_HOLD",
		"cleared": GameState.docking_state == "CLEARED" or final_leg
				or GameState.docking_state == "DEPARTING",
		"outbound": _outbound(),
		"gear_ok": GameState.gear_locked_down(),
		"gear_position": GameState.gear_position,
		"hatch_ok": not GameState.cargo_hatch_open,
		"altitude": altitude - GEAR_HEIGHT,
		"descent": -velocity.dot(up),
		"lateral": pad_offset.length(),
		"drift": Vector2(pad_offset.dot(_station_xform.basis.x),
				-pad_offset.dot(pad_forward())),
		"tilt": rad_to_deg(xform.basis.y.normalized().angle_to(up)),
		"wave_offs": int(GameState.docking.get("wave_offs", 0)),
		"quality": float(GameState.docking.get("quality", 0.0)),
		"traffic": _traffic_report(xform.origin, velocity),
	}
	out["on_pad"] = out["lateral"] <= PAD_RADIUS
	out["level"] = out["tilt"] <= TILT_LIMIT_DEG
	out["lane_ok"] = out["lane_deviation"] <= out["lane_limit"]
	return out


## Nearest-first traffic summary: how far each ship is hull-to-hull, whether it's
## closing, and whether it's the one fouling the lane ATC is sequencing you
## around.
func _traffic_report(origin: Vector3, velocity: Vector3) -> Array:
	var out: Array = []
	for entry: Dictionary in GameState.traffic:
		var pos: Vector3 = (entry["transform"] as Transform3D).origin
		var to_them: Vector3 = pos - origin
		var dist := to_them.length()
		var los := to_them / dist if dist > 0.0001 else Vector3.FORWARD
		out.append({
			"name": entry["name"],
			"kind": entry["kind"],
			"range": dist,
			"gap": dist - float(entry["radius"]) - CollisionSystem.ship_reach(),
			"closing": -velocity.dot(los) * -1.0,
			"conflict": bool(entry.get("conflict", false)),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["gap"]) < float(b["gap"]))
	return out


## --- Intents (MarketSystem / MFD DOCK page / mapped controls) --------------


## MarketSystem, when the transit burn arrives: place the ship on the station's
## outer approach and start the pattern. The berth is only booked once the ship
## is actually on the pad (see _touchdown).
func begin_approach(faction_index: int) -> void:
	if faction_index < 0 or faction_index >= GameState.market_factions.size():
		return
	var faction: String = GameState.market_factions[faction_index]
	_pattern_time = 0.0
	_hold_time = 0.0
	_over_speed = 0.0
	_off_lane = 0.0
	_advised.clear()
	_damages_cool = 0.0
	_contact_grace = 0.0
	GameState.docking = {
		"faction": faction_index,
		"station": "%s CONTROL" % faction,
		"berth": _rng.randi_range(1, 9),
		"gate": HOLD_GATE,
		"gates": [],
		"pad": pad_world(),
		"hold": false,
		"atc": {},
		"wave_offs": 0,
		"quality": 0.0,
	}
	_publish_gates()
	_spawn_traffic()
	_place_ship_at_entry()
	_leg_from = gate_world(HOLD_GATE)
	_set_state("INBOUND")
	_atc("PROCEED TO MARKER ALPHA AND HOLD",
			"%s, %s. SEQUENCING YOU INTO THE PATTERN FOR BERTH %d." % [
				GameState.ship_def.display_name, GameState.docking["station"],
				GameState.docking["berth"]])


## MarketSystem, on undocking: lift the ship off the berth into the departure
## pattern. The jump home doesn't happen until the lane has been flown outbound
## and ATC releases the ship (see _release_outbound).
func begin_departure(faction_index: int) -> void:
	if faction_index < 0 or faction_index >= GameState.market_factions.size():
		return
	var faction: String = GameState.market_factions[faction_index]
	_pattern_time = 0.0
	_hold_time = 0.0
	_over_speed = 0.0
	_off_lane = 0.0
	_reprimand_cool = 0.0
	_advised.clear()
	_damages_cool = 0.0
	_contact_grace = 0.0
	GameState.docking = {
		"faction": faction_index,
		"station": "%s CONTROL" % faction,
		"berth": _rng.randi_range(1, 9),
		# Outbound the lane is flown backwards, so the first marker to make is the
		# last one of an arrival.
		"gate": GATES.size() - 1,
		"gates": [],
		"pad": pad_world(),
		"hold": false,
		"atc": {},
		"wave_offs": 0,
		"quality": 0.0,
		"outbound": true,
	}
	_publish_gates()
	_spawn_traffic()
	_place_ship_on_pad()
	_leg_from = pad_world()
	_set_state("DEPART_HOLD")
	_atc("HOLD ON THE PAD — REQUEST DEPARTURE WHEN READY",
			"%s, %s. GEAR STAYS DOWN UNTIL YOU ARE CLEAR OF MARKER %s." % [
				GameState.ship_def.display_name, GameState.docking["station"],
				GATES[GATES.size() - 1]["name"]])


## Mapped/touch intent: ask ATC for the clearance to run the lane. Refused while
## you're still moving at the marker or while traffic fouls the lane — the
## refusal names which, so a held clearance is never a mystery.
func request_clearance() -> void:
	if not is_active():
		return
	if GameState.docking_state == "CLEARED" or GameState.docking_state == "FINAL" \
			or GameState.docking_state == "DEPARTING":
		# Already cleared: the same control reads back the standing instruction,
		# which is what an acknowledge button is for.
		_repeat_instruction()
		return
	if GameState.docking_state == "DEPART_HOLD":
		_request_departure()
		return
	if GameState.docking_state != "HOLD":
		GameState.post_comms("ATC", "%s — CONTINUE TO MARKER ALPHA AND HOLD"
				% GameState.ship_def.display_name)
		return
	var speed: float = (GameState.local_ship().get("velocity", Vector3.ZERO) as Vector3).length()
	if speed > HOLD_SPEED:
		_atc("HOLD AT ALPHA — YOU ARE STILL MOVING",
				"STOP AT THE MARKER (UNDER %.0f M/S) BEFORE REQUESTING." % HOLD_SPEED, true)
		return
	var blocker := _lane_conflict()
	if not blocker.is_empty():
		_atc("HOLD — TRAFFIC IN THE LANE",
				"%s IS CROSSING AHEAD OF YOU. STAND BY." % blocker["name"], true)
		return
	if _hold_time < CLEARANCE_MIN_HOLD:
		_atc("STAND BY — SEQUENCING",
				"HOLD AT ALPHA. WE WILL CALL YOUR CLEARANCE.")
		return
	_clear_inbound()


## Mapped/touch intent: have ATC fly you in instead. Costs a handling fee and a
## slice of standing — the way out when you don't want the pattern, never a way
## to dodge a landing you've already committed to.
func request_auto_berth() -> void:
	if not is_active() or _outbound():
		return
	if GameState.docking_state == "FINAL":
		_atc("AUTO-BERTH REFUSED — YOU ARE ON FINAL",
				"TOO LATE TO HAND IT OVER. LAND IT OR GO AROUND.", true)
		return
	if GameState.credits < AUTO_BERTH_FEE:
		_atc("AUTO-BERTH REFUSED — INSUFFICIENT FUNDS",
				"HANDLING IS %d CR AND YOU ARE SHORT. FLY IT IN." % AUTO_BERTH_FEE, true)
		return
	var faction: int = GameState.docking["faction"]
	var berth: int = GameState.docking["berth"]
	GameState.credits -= AUTO_BERTH_FEE
	GameState.credits_changed.emit(GameState.credits)
	_adjust_reputation(-REP_AUTO_BERTH)
	GameState.post_comms("ATC", "AUTO-BERTH ACCEPTED — HANDS OFF, BERTH %d. %d CR HANDLING." % [
		berth, AUTO_BERTH_FEE])
	# Booked through the same door a touchdown uses, with nothing scored: there is
	# exactly one way into DOCKED.
	_set_state("LANDED")
	end_approach()
	MarketSystem.complete_dock(faction)


## Mapped/touch intent (and the MARKET depart control while on approach): give up
## on the berth and go back to the claim.
func abort_approach() -> void:
	if not is_active() or _outbound():
		return
	GameState.post_comms("ATC", "%s CANCELLING THE APPROACH — LEAVING THE PATTERN"
			% GameState.ship_def.display_name)
	end_approach()
	MarketSystem.abort_dock()


## MarketSystem: tear the pattern down (landed, aborted, or the run reset).
func end_approach() -> void:
	_despawn_traffic()
	GameState.docking = {}
	_set_state("INACTIVE")


## --- Per-frame simulation ---------------------------------------------------


func _process(delta: float) -> void:
	# The gear is ship equipment, so its speed rating bites wherever you're
	# flying — including hauling salvage around the claim with it hanging out.
	if not GameState.flight_active():
		return
	_update_gear_stress(delta)
	if not is_active():
		return
	_pattern_time += delta
	_reprimand_cool = maxf(_reprimand_cool - delta, 0.0)
	_damages_cool = maxf(_damages_cool - delta, 0.0)
	_contact_grace = maxf(_contact_grace - delta, 0.0)
	_update_traffic()
	_update_separation()
	if not is_active():
		return  # a separation bust may already have sent us around
	_update_atc_hold()
	_update_speed(delta)
	if not is_active():
		return
	# Before the per-state work: the deck stops the ship no matter which state it
	# is in, including the states a go-around just put it in.
	_check_deck()
	if not is_active():
		return
	match GameState.docking_state:
		"INBOUND":
			_update_inbound(delta)
		"HOLD":
			_update_hold(delta)
		"CLEARED":
			_update_cleared(delta)
		"FINAL":
			_update_final(delta)
		"DEPART_HOLD":
			_update_depart_hold(delta)
		"DEPARTING":
			_update_departing(delta)


## Flying faster than the gear is rated for, with it off the stops, wears the
## legs. It's the cost that keeps the gear a decision rather than something you
## drop once and forget — and the reason the cutter is interlocked while it's out.
func _update_gear_stress(delta: float) -> void:
	if GameState.gear_stowed():
		return
	var speed: float = (GameState.local_ship().get("velocity", Vector3.ZERO) as Vector3).length()
	if speed <= GameState.GEAR_LIMIT_SPEED:
		return
	_damage_hull("DRIVE", GEAR_STRESS_PER_S * delta)
	if fmod(_pattern_time, 2.0) < delta:
		GameState.post_comms("OPS", "GEAR OVERSPEED — %.0f / %.0f M/S, LEGS TAKING LOAD" % [
			speed, GameState.GEAR_LIMIT_SPEED])


## Walk each traffic ship along its route and keep its contact glued to it, then
## re-evaluate which of them is fouling the lane ahead.
func _update_traffic() -> void:
	var blocker_ids := _lane_conflict_ids()
	for entry: Dictionary in GameState.traffic:
		var route: Dictionary = entry["route"]
		var pose := _route_pose(route, _pattern_time + float(entry["phase"]))
		entry["transform"] = pose
		entry["conflict"] = blocker_ids.has(int(entry["id"]))
		var contact := GameState.get_contact(int(entry["contact_id"]))
		if not contact.is_empty():
			contact["position"] = pose.origin


## Traffic separation: an advisory call as one closes, and a go-around if it gets
## inside the hull-to-hull margin. Actual contact is caught by _on_hull_impact.
func _update_separation() -> void:
	var origin: Vector3 = (GameState.local_ship()["transform"] as Transform3D).origin
	var reach := CollisionSystem.ship_reach()
	for entry: Dictionary in GameState.traffic:
		var gap: float = origin.distance_to((entry["transform"] as Transform3D).origin) \
				- float(entry["radius"]) - reach
		var id: int = entry["id"]
		if gap > TRAFFIC_ADVISORY:
			_advised.erase(id)
			continue
		if gap <= SEPARATION_MARGIN:
			_violation("LOSS OF SEPARATION WITH %s" % entry["name"])
			return
		if not _advised.has(id):
			_advised[id] = true
			_atc("TRAFFIC — %s" % entry["name"],
					"%.0f M OFF YOUR HULL. MAINTAIN SEPARATION." % gap, true)


## ATC stops you where you are when traffic fouls the lane ahead mid-approach,
## and releases you once it's clear. Only bites once you're actually running the
## lane — at the marker you're holding anyway.
func _update_atc_hold() -> void:
	if GameState.docking_state != "CLEARED" and GameState.docking_state != "FINAL" \
			and GameState.docking_state != "DEPARTING":
		return
	var blocker := _lane_conflict()
	var holding: bool = GameState.docking.get("hold", false)
	if not blocker.is_empty() and not holding:
		GameState.docking["hold"] = true
		_atc("HOLD POSITION — TRAFFIC CROSSING",
				"%s IS IN THE LANE AHEAD. HOLD UNDER %.0f M/S." % [
					blocker["name"], HOLD_SPEED], true)
	elif blocker.is_empty() and holding:
		GameState.docking["hold"] = false
		_atc("CONTINUE APPROACH", "LANE IS CLEAR. RESUME %.0f M/S." % speed_limit())


## The speed you were given is an instruction like any other: a warning while
## you're over it, a go-around if you stay over it.
func _update_speed(delta: float) -> void:
	var speed: float = (GameState.local_ship().get("velocity", Vector3.ZERO) as Vector3).length()
	var limit := speed_limit()
	if speed <= limit:
		_over_speed = 0.0
		return
	# A contact reflects velocity as well as displacing the ship, so the same
	# amnesty covers the overspeed it can hand you.
	if _contact_grace > 0.0:
		_over_speed = 0.0
		return
	if _over_speed == 0.0:
		_atc("REDUCE SPEED — %.0f M/S" % limit,
				"YOU ARE %.0f M/S OVER THE PATTERN LIMIT." % (speed - limit), true)
	_over_speed += delta
	if _over_speed >= SPEED_GRACE:
		# Outbound this is a telling-off rather than a go-around, so the timer
		# restarts instead of latching — stay fast and you'll hear about it again.
		_over_speed = 0.0
		_violation("EXCESSIVE SPEED IN THE PATTERN")


## Free flight out to the hold marker — no corridor, just get to ALPHA and stop.
func _update_inbound(_delta: float) -> void:
	var origin: Vector3 = (GameState.local_ship()["transform"] as Transform3D).origin
	if origin.distance_to(gate_world(HOLD_GATE)) > float(GATES[HOLD_GATE]["radius"]):
		return
	_hold_time = 0.0
	_set_state("HOLD")
	_atc("HOLD AT ALPHA — REQUEST CLEARANCE WHEN STOPPED",
			"MARKER ALPHA REACHED. STOP UNDER %.0f M/S AND CALL FOR THE LANE."
					% HOLD_SPEED)


## Parked at the marker. Time only counts toward the clearance while you're
## actually holding — inside the ring and slow — and drifting out of it puts you
## back on the inbound leg.
func _update_hold(delta: float) -> void:
	var ship: Dictionary = GameState.local_ship()
	var origin: Vector3 = (ship["transform"] as Transform3D).origin
	if origin.distance_to(gate_world(HOLD_GATE)) > float(GATES[HOLD_GATE]["radius"]):
		_hold_time = 0.0
		_set_state("INBOUND")
		_atc("RETURN TO MARKER ALPHA", "YOU HAVE DRIFTED OUT OF THE HOLD.", true)
		return
	if (ship.get("velocity", Vector3.ZERO) as Vector3).length() > HOLD_SPEED:
		_hold_time = 0.0
		return
	_hold_time += delta
	# Once you've served the sequencing delay and the lane is clear, ATC calls the
	# clearance itself rather than making you keep asking. Tested every frame, not
	# just on the frame the delay runs out: traffic is usually working the lane at
	# that exact moment, and an edge-triggered call would leave the ship holding
	# for a slot that never gets offered again.
	if _hold_time >= CLEARANCE_MIN_HOLD and _lane_conflict().is_empty():
		_clear_inbound()


## Running the lane: stay in the corridor, fly through each ring in order, and
## have the gear down by the last one.
func _update_cleared(delta: float) -> void:
	var origin: Vector3 = (GameState.local_ship()["transform"] as Transform3D).origin
	if not _check_corridor(origin, delta):
		return
	var index: int = GameState.docking["gate"]
	var gate: Dictionary = GATES[index]
	var target: Vector3 = gate_world(index)
	var leg: Vector3 = target - _leg_from
	var ahead: float = (origin - target).dot(leg.normalized()) if leg.length() > 0.001 else 0.0
	if origin.distance_to(target) <= float(gate["radius"]):
		_pass_gate(index, target)
		return
	# Past the gate's plane without having been inside its ring: the marker was
	# missed, which is a go-around whether or not you're still in the corridor.
	if ahead > 0.0:
		_wave_off("MARKER %s MISSED" % gate["name"])


## A ring flown through. The last one is the gate to the berth itself, so it also
## carries the gear check — the one instruction you have to have acted on early.
func _pass_gate(index: int, target: Vector3) -> void:
	_leg_from = target
	if index < GATES.size() - 1:
		GameState.docking["gate"] = index + 1
		var next: Dictionary = GATES[index + 1]
		_atc("%s PASSED — NEXT MARKER %s" % [GATES[index]["name"], next["name"]],
				"CORRIDOR %.0f M. %s" % [float(next["lane"]),
					"GEAR DOWN BEFORE THE FINAL GATE." if index + 1 == GATES.size() - 1
					else "MAINTAIN %.0f M/S." % SPEED_CLEARED])
		return
	if not GameState.gear_locked_down():
		_wave_off("GEAR NOT DOWN AND LOCKED AT THE FINAL GATE")
		return
	if GameState.cargo_hatch_open:
		_wave_off("CARGO HATCH OPEN ON FINAL")
		return
	GameState.docking["gate"] = GATES.size()
	_set_state("FINAL")
	_atc("CLEARED TO LAND — BERTH %d" % int(GameState.docking["berth"]),
			"DESCEND ONTO THE PAD. SINK RATE UNDER %.1f M/S, WINGS LEVEL." % FIRM_RATE)


## The descent onto the pad. The gear/hatch instructions stay live all the way
## down — raise either and you're going around — and contact is evaluated the
## moment the legs reach deck height.
func _update_final(delta: float) -> void:
	var ship: Dictionary = GameState.local_ship()
	var xform: Transform3D = ship["transform"]
	if not GameState.gear_locked_down():
		_wave_off("GEAR RAISED ON FINAL")
		return
	if GameState.cargo_hatch_open:
		_wave_off("CARGO HATCH OPENED ON FINAL")
		return
	# The deck itself is handled by _check_deck, every frame and in every state —
	# see there for why it can't live in here.
	_check_corridor(xform.origin, delta)


## Sat on the pad after undocking, waiting for a slot. Same sequencing as an
## arrival: serve the delay, and don't go anywhere while traffic is working the
## lane you're about to fly up.
func _update_depart_hold(delta: float) -> void:
	var was_ready := _hold_time >= CLEARANCE_MIN_HOLD
	_hold_time += delta
	if not was_ready and _hold_time >= CLEARANCE_MIN_HOLD and _lane_conflict().is_empty():
		_clear_outbound()


## The pilot asking for the departure slot rather than waiting to be called.
func _request_departure() -> void:
	var blocker := _lane_conflict()
	if not blocker.is_empty():
		_atc("HOLD ON THE PAD — TRAFFIC IN THE LANE",
				"%s IS WORKING THE LANE ABOVE YOU. STAND BY." % blocker["name"], true)
		return
	if _hold_time < CLEARANCE_MIN_HOLD:
		_atc("STAND BY — SEQUENCING", "WE WILL CALL YOUR DEPARTURE.")
		return
	_clear_outbound()


## Grant the departure slot.
func _clear_outbound() -> void:
	GameState.docking["hold"] = false
	_leg_from = pad_world()
	_over_speed = 0.0
	_off_lane = 0.0
	_set_state("DEPARTING")
	_atc("CLEARED FOR DEPARTURE — MARKER %s FIRST" % GATES[GATES.size() - 1]["name"],
			"LIFT OFF THE PAD AND RUN THE LANE OUTBOUND: %s. UNDER %.0f M/S IN THE BAY."
					% [_gate_names_outbound(), SPEED_FINAL])


## Flying the lane the other way. Same corridor and speed discipline, gates in
## reverse, and two rules of its own: the gear stays down until the berth bay is
## behind you, and it has to be stowed before ATC will release you for the jump.
func _update_departing(delta: float) -> void:
	var origin: Vector3 = (GameState.local_ship()["transform"] as Transform3D).origin
	# A leg is still inside the bay's walls until DELTA is behind you, so stowing
	# early is a real mistake rather than a formality.
	if _in_berth_bay() and not GameState.gear_locked_down():
		_violation("GEAR RAISED INSIDE THE BERTH BAY")
	if not _check_corridor(origin, delta):
		return
	# Already past the last marker and only the gear is holding the release: keep
	# asking every frame. The final leg is zero-length by then, so the gate logic
	# below would never fire again and the ship would be stuck outside the pattern.
	if bool(GameState.docking.get("release_held", false)):
		_release_outbound()
		return
	var index: int = GameState.docking["gate"]
	var target: Vector3 = gate_world(index)
	var leg: Vector3 = target - _leg_from
	var ahead: float = (origin - target).dot(leg.normalized()) if leg.length() > 0.001 else 0.0
	var through := origin.distance_to(target) <= float(GATES[index]["radius"])
	if not through and ahead <= 0.0:
		return
	if not through:
		# Outbound a missed marker is still a miss, but you're leaving — it costs
		# standing rather than turning you round.
		_reprimand("MARKER %s MISSED ON DEPARTURE" % GATES[index]["name"])
	_leg_from = target
	if index > HOLD_GATE:
		GameState.docking["gate"] = index - 1
		var next: Dictionary = GATES[index - 1]
		# Clearing the last gate is also clearing the bay's walls, which is the
		# moment the gear stops being required and starts being drag.
		var detail := "MAINTAIN %.0f M/S." % SPEED_CLEARED
		if index == GATES.size() - 1:
			detail = "CLEAR OF THE BAY — STOW YOUR GEAR AND MAINTAIN %.0f M/S." % SPEED_CLEARED
		_atc("%s PASSED — NEXT MARKER %s" % [GATES[index]["name"], next["name"]], detail)
		return
	_release_outbound()


## Past the hold marker and out of the pattern — provided the gear is actually
## stowed. Holding the release on the gear is what makes the pilot cycle it on
## the way out instead of dragging it home.
func _release_outbound() -> void:
	if not GameState.gear_stowed():
		# Latch it so the check keeps running, and only call it once — this is a
		# standing instruction, not a klaxon.
		if not bool(GameState.docking.get("release_held", false)):
			GameState.docking["release_held"] = true
			_atc("STOW YOUR GEAR BEFORE THE JUMP",
					"YOU ARE CLEAR OF THE PATTERN BUT STILL HANGING LEGS.", true)
		return
	GameState.docking["release_held"] = false
	GameState.post_comms("ATC", "%s CLEAR OF THE PATTERN — GOOD HUNTING."
			% GameState.ship_def.display_name)
	end_approach()
	MarketSystem.complete_undock()


## The deck is solid whatever ATC currently thinks of you.
##
## Evaluated every frame a pattern is live, NOT only on FINAL. A ship that lost
## its clearance on the way down — an overspeed bust, a missed marker, a
## go-around called while it was already in the berth — is still a ship
## descending into a real bay. With this check living inside _update_final, that
## ship simply sank past deck height with nothing to catch it and ground to a
## halt against the bay floor's collision hull: "CONTACT — STATION BAYFLOOR",
## repeatedly, with no landing ever evaluated.
##
## Arriving without a clearance is a bounce rather than a berth — you can't have
## a landing you weren't cleared for — but it's a bounce, which puts the ship
## back in the air where it can be flown, instead of a grind.
func _check_deck() -> void:
	var ship: Dictionary = GameState.local_ship()
	var xform: Transform3D = ship["transform"]
	var up := pad_up()
	var from_pad: Vector3 = xform.origin - pad_world()
	var altitude := from_pad.dot(up)
	if altitude > GEAR_HEIGHT:
		return
	var offset: Vector3 = from_pad - up * altitude
	# Only inside the berth. Elsewhere "below deck height" is just open space
	# alongside the station, which the pilot is entitled to fly through.
	if offset.length() > DECK_REACH:
		return
	if GameState.docking_state != "FINAL":
		_bounce(ship, xform, up, "TOUCHED DOWN WITHOUT A LANDING CLEARANCE", 0.0)
		return
	_touchdown(ship, xform, offset, up)


## Contact. Everything the legs care about is judged in this one moment: gear,
## sink rate, where on the deck you put it, how level, and how much sideways you
## carried into it. Anything the legs can't take bounces the ship back into the
## pattern; anything they can becomes a berth, scored.
func _touchdown(ship: Dictionary, xform: Transform3D, offset: Vector3, up: Vector3) -> void:
	var velocity: Vector3 = ship.get("velocity", Vector3.ZERO)
	var rate: float = -velocity.dot(up)
	var lateral := offset.length()
	var drift: float = (velocity - up * velocity.dot(up)).length()
	var tilt := rad_to_deg(xform.basis.y.normalized().angle_to(up))
	if lateral > PAD_RADIUS:
		_bounce(ship, xform, up, "OFF THE PAD MARKINGS — %.0f M WIDE" % lateral, 0.0)
		return
	if tilt > TILT_LIMIT_DEG:
		_bounce(ship, xform, up, "NOT LEVEL AT CONTACT — %d°" % roundi(tilt), 0.05)
		return
	if drift > TOUCHDOWN_DRIFT:
		_bounce(ship, xform, up, "SIDEWAYS AT CONTACT — %.1f M/S" % drift, 0.08)
		return
	if rate > CRASH_RATE:
		_bounce(ship, xform, up, "SINK RATE %.1f M/S — LEGS WOULD NOT TAKE IT" % rate,
				DAMAGE_PER_RATE * (rate - HARD_RATE))
		return
	# Down. Score it, park the ship exactly on the pad, and hand the berth back
	# to MarketSystem.
	var quality := clampf(
			(1.0 - clampf(rate / HARD_RATE, 0.0, 1.0)) * 0.5
			+ (1.0 - clampf(lateral / PAD_RADIUS, 0.0, 1.0)) * 0.3
			+ (1.0 - clampf(tilt / TILT_LIMIT_DEG, 0.0, 1.0)) * 0.2, 0.0, 1.0)
	GameState.docking["quality"] = quality
	var parked := xform
	parked.origin = pad_world() + up * GEAR_HEIGHT
	ship["transform"] = parked
	ship["velocity"] = Vector3.ZERO
	_set_state("LANDED")
	var grade := "GREASED" if rate <= FIRM_RATE else ("FIRM" if rate <= HARD_RATE else "HARD")
	GameState.post_comms("ATC", "TOUCHDOWN — %s ARRIVAL, %.1f M/S SINK, %d%% ON THE MARKS" % [
		grade, rate, roundi(quality * 100.0)])
	if rate > HARD_RATE:
		_damage_hull("DRIVE", DAMAGE_PER_RATE * (rate - HARD_RATE))
		_adjust_reputation(-REP_PER_LANDING * 0.5)
	else:
		_adjust_reputation(REP_PER_LANDING * quality)
	var faction: int = GameState.docking["faction"]
	end_approach()
	MarketSystem.complete_dock(faction)


## The legs refused it: kick the ship back up off the deck, hurt it by `damage`,
## and put it round the pattern again.
func _bounce(ship: Dictionary, xform: Transform3D, up: Vector3, reason: String,
		damage: float) -> void:
	var velocity: Vector3 = ship.get("velocity", Vector3.ZERO)
	# Reflect the downward component and bleed the rest, then lift clear of the
	# deck so the next frame isn't another contact.
	var down: float = -velocity.dot(up)
	if down > 0.0:
		velocity += up * down * 1.4
	ship["velocity"] = velocity * 0.5
	var lifted := xform
	lifted.origin += up * (GEAR_HEIGHT + 1.0 - (xform.origin - pad_world()).dot(up))
	ship["transform"] = lifted
	if damage > 0.0:
		_damage_hull("DRIVE", damage)
		_damage_hull("CORE", damage * 0.5)
	_wave_off(reason)


## --- ATC plumbing -----------------------------------------------------------


## Grant the lane. Shared by the pilot's request and ATC's own call once the
## sequencing delay is served.
func _clear_inbound() -> void:
	GameState.docking["gate"] = HOLD_GATE + 1
	GameState.docking["hold"] = false
	_leg_from = gate_world(HOLD_GATE)
	_over_speed = 0.0
	_off_lane = 0.0
	_set_state("CLEARED")
	_atc("CLEARED TO BERTH %d VIA THE LANE" % int(GameState.docking["berth"]),
			"MARKERS %s IN ORDER. SPEED UNDER %.0f M/S. GEAR DOWN BEFORE %s." % [
				_gate_names(), SPEED_CLEARED, GATES[GATES.size() - 1]["name"]])


## A pattern rule was broken. Which consequence that carries depends on the
## direction: inbound you get sent around, outbound you get told off. Every
## shared PROCEDURAL rule (speed, corridor, separation) reports through here so
## the two directions can't drift apart. Contact is not one of them — it goes to
## _bill_damages, which never touches the clearance.
func _violation(reason: String) -> void:
	if _outbound():
		_reprimand(reason)
	else:
		_wave_off(reason)


## Outbound consequence: an urgent call and, at most once per cooldown, a bite
## out of your standing with the station's faction. No forced return — you are
## leaving, and stranding a clumsy pilot on the pad isn't a game.
func _reprimand(reason: String) -> void:
	_atc("%s — CORRECT IT" % reason,
			"%s IS LOGGING THIS DEPARTURE." % GameState.docking.get("station", "CONTROL"),
			true)
	if _reprimand_cool > 0.0:
		return
	_reprimand_cool = REPRIMAND_COOLDOWN
	_adjust_reputation(-REP_PER_REPRIMAND)


## Sent around: back to the inbound leg and the hold, with the clearance
## withdrawn. Repeat offenders lose a little standing with the berth's faction —
## a go-around is free once, expensive as a habit.
func _wave_off(reason: String) -> void:
	if not is_active() or GameState.docking_state == "LANDED":
		return
	var count: int = int(GameState.docking.get("wave_offs", 0)) + 1
	GameState.docking["wave_offs"] = count
	GameState.docking["gate"] = HOLD_GATE
	GameState.docking["hold"] = false
	_hold_time = 0.0
	_over_speed = 0.0
	_off_lane = 0.0
	_advised.clear()
	_damages_cool = 0.0
	_contact_grace = 0.0
	_leg_from = gate_world(HOLD_GATE)
	_set_state("INBOUND")
	_atc("GO AROUND — %s" % reason,
			"CLEARANCE CANCELLED. RETURN TO MARKER ALPHA AND HOLD. (GO-AROUND %d)"
					% count, true)
	# A go-around is free once, expensive as a habit, and never ruinous.
	if count > 1:
		var bled: float = float(GameState.docking.get("rep_bled", 0.0))
		var bite: float = minf(REP_PER_WAVE_OFF, maxf(REP_WAVE_OFF_CAP - bled, 0.0))
		if bite > 0.0:
			GameState.docking["rep_bled"] = bled + bite
			_adjust_reputation(-bite)


## Anything the pattern hit is a go-around — CollisionSystem has already taken
## the hull out of it, this takes the clearance.
## Anything the pattern hit. CollisionSystem has already taken it out of the
## hull; this takes it out of your wallet and your standing — but NOT your
## clearance. Contact is damage, not a procedural failure, and the go-around is
## reserved for the instructions you were actually given (speed, corridor,
## markers, gear).
func _on_hull_impact(section: String, amount: float) -> void:
	if not is_active() or GameState.run_phase != "APPROACH":
		return
	_bill_damages(section, amount)


## Touching anything at all — the gentle grazes included, which never reach
## hull_impact and so were previously silent even though the push-out moved the
## ship. Opens the amnesty window, and says so, because being knocked off the
## centreline and then told you departed the lane with nothing in between is the
## game blaming the pilot for its own shove.
func _on_ship_contact(body_name: String, closing: float) -> void:
	if not is_active() or GameState.run_phase != "APPROACH":
		return
	var fresh := _contact_grace <= 0.0
	_contact_grace = CONTACT_GRACE
	# Reset what's already accumulated: the deviation that put the ship here is
	# the impact's doing, not the pilot's.
	_off_lane = 0.0
	_over_speed = 0.0
	if fresh and closing < CollisionSystem.IMPACT_SPEED_FLOOR:
		# Too soft to damage or bill, so nothing else would ever mention it.
		# Only claim the clearance stands when there IS one — saying it to a ship
		# that was waved off ten seconds ago is worse than saying nothing.
		var standing := "STEADY UP AND CONTINUE — YOUR CLEARANCE STANDS."
		if not bool(status().get("cleared", false)):
			standing = "STEADY UP. YOU ARE NOT CLEARED — RETURN TO MARKER %s." \
					% GATES[HOLD_GATE]["name"]
		_atc("CONTACT — %s" % body_name, standing, true)


## Invoice for hitting the station. Charged against credits, with anything the
## pilot can't cover taken out of their standing instead — a station that can't
## bill you writes you off rather than letting you scrape its structure for free.
func _bill_damages(section: String, amount: float) -> void:
	if _damages_cool > 0.0:
		return
	_damages_cool = DAMAGES_COOLDOWN
	var bill := DAMAGES_CALL_OUT + roundi(maxf(amount, 0.0) * DAMAGES_PER_DAMAGE)
	var paid: int = mini(bill, maxi(GameState.credits, 0))
	if paid > 0:
		GameState.credits -= paid
		GameState.credits_changed.emit(GameState.credits)
	var standing := REP_PER_COLLISION
	if paid < bill:
		# Couldn't pay: the shortfall lands on your reputation instead, in
		# proportion to how much of the bill went unmet.
		standing += REP_PER_COLLISION * (float(bill - paid) / float(bill))
	_adjust_reputation(-standing)
	_atc("CONTACT — %s SECTION" % section,
			"YOU HAVE STRUCK STATION STRUCTURE. DAMAGES %d CR%s." % [
				bill, "" if paid >= bill else " (UNPAID — LOGGED AGAINST YOU)"], true)


## Publish a standing instruction: one line of what to do, one of why, held in
## GameState.docking so an instrument can show it as long as it applies (a comms
## line scrolls away; a clearance doesn't).
func _atc(text: String, detail := "", urgent := false) -> void:
	var instruction := {
		"text": text, "detail": detail, "urgent": urgent, "tick": GameState.tick,
	}
	GameState.docking["atc"] = instruction
	GameState.post_comms("ATC", text if detail.is_empty() else "%s — %s" % [text, detail])
	GameState.atc_instruction.emit(instruction)


## "Say again": re-post the standing instruction without changing it.
func _repeat_instruction() -> void:
	var instruction: Dictionary = GameState.docking.get("atc", {})
	if instruction.is_empty():
		return
	GameState.post_comms("ATC", "%s (READBACK)" % instruction["text"])
	GameState.atc_instruction.emit(instruction)


func _set_state(state: String) -> void:
	if GameState.docking_state == state:
		return
	GameState.docking_state = state
	GameState.docking_changed.emit(state)


func _gate_names() -> String:
	var names: Array[String] = []
	for i in range(HOLD_GATE + 1, GATES.size()):
		names.append(String(GATES[i]["name"]))
	return " ".join(names)


func _gate_names_outbound() -> String:
	var names: Array[String] = []
	for i in range(GATES.size() - 1, HOLD_GATE - 1, -1):
		names.append(String(GATES[i]["name"]))
	return " ".join(names)


## --- Lane geometry ----------------------------------------------------------


## Cache the lane in world space on GameState so instruments and the 3D scene
## read one list rather than each re-transforming the constants.
func _publish_gates() -> void:
	var gates: Array[Dictionary] = []
	for gate: Dictionary in GATES:
		gates.append({
			"name": gate["name"],
			"position": to_world(gate["position"]),
			"radius": gate["radius"],
			"lane": gate["lane"],
		})
	GameState.docking["gates"] = gates
	GameState.docking["pad"] = pad_world()


## Corridor radius for the leg being flown right now.
func _lane_limit(origin: Vector3) -> float:
	if GameState.docking_state == "FINAL":
		return _final_lane_at(origin)
	var index: int = GameState.docking.get("gate", HOLD_GATE)
	if GameState.docking_state == "DEPARTING":
		# Outbound legs are the inbound ones flown backwards, so the corridor is
		# the one belonging to the gate BEHIND you — and the climb out of the bay
		# is the descent onto the pad in reverse.
		if index >= GATES.size() - 1:
			return _final_lane_at(origin)
		return float(GATES[index + 1]["lane"])
	if index <= HOLD_GATE or index >= GATES.size():
		return float(GATES[HOLD_GATE]["lane"])
	return float(GATES[index]["lane"])


## Corridor radius on the final leg at a given point: the strict tube while
## you're down between the bay walls, opening out linearly above them to give
## the turn off the CHARLIE-DELTA leg somewhere to happen.
func _final_lane_at(origin: Vector3) -> float:
	var height: float = (origin - pad_world()).dot(pad_up())
	var delta_height: float = float(GATES[GATES.size() - 1]["position"].y) - PAD_LOCAL.y
	if height <= BAY_WALL_HEIGHT or delta_height <= BAY_WALL_HEIGHT:
		return FINAL_LANE
	var t: float = clampf((height - BAY_WALL_HEIGHT)
			/ (delta_height - BAY_WALL_HEIGHT), 0.0, 1.0)
	return lerpf(FINAL_LANE, FINAL_LANE_TOP, t)


## How far the ship is off the centreline of the leg it's on. Free flight (the
## inbound leg and the hold) has no centreline, so it reads 0.
func _lane_deviation(origin: Vector3) -> float:
	if GameState.docking_state == "FINAL":
		return _distance_to_segment(origin, gate_world(GATES.size() - 1), pad_world())
	if GameState.docking_state != "CLEARED" and GameState.docking_state != "DEPARTING":
		return 0.0
	# Both directions fly _leg_from → the gate they're making, so this measures
	# either without caring which way round the lane is being run.
	var index: int = GameState.docking.get("gate", HOLD_GATE)
	return _distance_to_segment(origin, _leg_from, gate_world(index))


## Corridor discipline, with a moment's grace so a gust of overcorrection isn't
## instantly fatal. Returns false once it has sent the ship around.
func _check_corridor(origin: Vector3, delta: float) -> bool:
	var deviation := _lane_deviation(origin)
	var limit := _lane_limit(origin)
	if deviation <= limit:
		_off_lane = 0.0
		return true
	# Just been shoved by something solid: the deviation is the impact's, so it
	# doesn't count against the pilot until they've had a moment to recover.
	if _contact_grace > 0.0:
		_off_lane = 0.0
		return true
	if _off_lane == 0.0:
		_atc("YOU ARE OUTSIDE THE LANE", "%.0f M OFF THE CENTRELINE — CORRECT NOW."
				% deviation, true)
	_off_lane += delta
	if _off_lane < LANE_GRACE:
		return true
	_off_lane = 0.0
	_violation("DEPARTED THE LANE CORRIDOR")
	# A wave-off has torn the approach down and the caller must stop; a reprimand
	# hasn't, so an outbound ship carries on being told off until it corrects.
	return _outbound()


## Traffic fouling the lane ahead of the ship: measured against the remaining
## legs only, so a tug behind you isn't a reason to hold.
func _lane_conflict() -> Dictionary:
	var ids := _lane_conflict_ids()
	for entry: Dictionary in GameState.traffic:
		if ids.has(int(entry["id"])):
			return entry
	return {}


func _lane_conflict_ids() -> Dictionary:
	var out: Dictionary = {}
	var legs := _conflict_legs()
	for entry: Dictionary in GameState.traffic:
		var pos: Vector3 = (entry["transform"] as Transform3D).origin
		for leg: Array in legs:
			if _distance_to_segment(pos, leg[0], leg[1]) \
					<= LANE_CONFLICT_RANGE + float(entry["radius"]):
				out[int(entry["id"])] = true
				break
	return out


## The leg traffic is judged against: the one being flown right now, or — at a
## hold — the one the ship is about to be cleared onto.
##
## Deliberately ONE leg rather than the whole route ahead. Judging every
## remaining leg means the entire 200 m lane has to be simultaneously clear of
## three ships that are always working it, and that window barely exists: ATC
## would hold a pilot at the marker more or less indefinitely. "Traffic in the
## lane ahead of you" is the leg you are on, which is also the only stretch a
## hold actually protects.
func _conflict_legs() -> Array:
	var index: int = GameState.docking.get("gate", HOLD_GATE)
	match GameState.docking_state:
		"FINAL":
			return [[gate_world(GATES.size() - 1), pad_world()]]
		"DEPART_HOLD":
			return [[pad_world(), gate_world(GATES.size() - 1)]]
		"CLEARED", "DEPARTING":
			return [[_leg_from, gate_world(index)]]
	# INBOUND / HOLD: the first leg of the lane, the one a clearance grants.
	return [[gate_world(HOLD_GATE), gate_world(HOLD_GATE + 1)]]


func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


## --- Traffic ----------------------------------------------------------------


func _spawn_traffic() -> void:
	_despawn_traffic()
	for route: Dictionary in TRAFFIC_ROUTES:
		var id := _next_traffic_id
		_next_traffic_id += 1
		# A random phase per visit so the pattern isn't the same rehearsal twice.
		var phase := _rng.randf_range(0.0, 120.0)
		var entry := {
			"id": id,
			"name": route["name"],
			"kind": route["kind"],
			"radius": route["radius"],
			"route": route,
			"phase": phase,
			"transform": _route_pose(route, phase),
			"contact_id": -1,
			"conflict": false,
		}
		entry["contact_id"] = GameState.register_contact(
				route["name"], (entry["transform"] as Transform3D).origin, false,
				float(route["radius"]))
		GameState.add_traffic(entry)


func _despawn_traffic() -> void:
	for entry: Dictionary in GameState.traffic.duplicate():
		if int(entry.get("contact_id", -1)) != -1:
			GameState.remove_contact(int(entry["contact_id"]))
		GameState.remove_traffic(int(entry["id"]))


## Pose of a route's ship at time `t`: a point along its polyline plus a basis
## facing the way it's travelling, all lifted into world space.
func _route_pose(route: Dictionary, t: float) -> Transform3D:
	var here := _route_point(route, t)
	var ahead := _route_point(route, t + 0.35)
	var dir: Vector3 = ahead - here
	var up := pad_up()
	var basis := _station_xform.basis
	if dir.length() > 0.001:
		var forward := dir.normalized()
		# A route running straight up/down the station's own up axis would make
		# looking_at degenerate; nothing here does, but fall back rather than
		# risk an error basis if a route is ever re-authored that way.
		if absf(forward.dot(up)) < 0.99:
			basis = Basis.looking_at(forward, up)
	return Transform3D(basis, here)


## Distance-parameterised point on a route's path (world space). "pingpong"
## reverses at each end, "cycle" closes the polyline into a circuit.
func _route_point(route: Dictionary, t: float) -> Vector3:
	var path: Array = route["path"]
	var closed: bool = String(route.get("loop", "pingpong")) == "cycle"
	var points: Array = path.duplicate()
	if closed:
		points.append(path[0])
	var spans: Array[float] = []
	var total := 0.0
	for i in range(points.size() - 1):
		var span: float = (points[i + 1] as Vector3).distance_to(points[i] as Vector3)
		spans.append(span)
		total += span
	if total <= 0.0:
		return to_world(path[0])
	var travelled: float = float(route["speed"]) * t
	if closed:
		travelled = fposmod(travelled, total)
	else:
		travelled = fposmod(travelled, total * 2.0)
		if travelled > total:
			travelled = total * 2.0 - travelled
	for i in spans.size():
		if travelled <= spans[i] or i == spans.size() - 1:
			var f: float = clampf(travelled / maxf(spans[i], 0.0001), 0.0, 1.0)
			return to_world((points[i] as Vector3).lerp(points[i + 1] as Vector3, f))
		travelled -= spans[i]
	return to_world(path[0])


## --- Consequences -----------------------------------------------------------


## Put the ship on the outer approach, pointed at the hold marker and stopped —
## the transit burn's arrival, not a teleport into the middle of the pattern.
func _place_ship_at_entry() -> void:
	var ship: Dictionary = GameState.local_ship()
	var origin := to_world(ENTRY_LOCAL)
	var facing: Vector3 = gate_world(HOLD_GATE) - origin
	var basis := _station_xform.basis
	if facing.length() > 0.001:
		basis = Basis.looking_at(facing.normalized(), pad_up())
	ship["transform"] = Transform3D(basis, origin)
	ship["velocity"] = Vector3.ZERO


## Undocking: the ship is standing on the pad on its legs, parked on the lane's
## heading, with the gear already down and locked (it has been holding the ship
## up all the while it was berthed).
func _place_ship_on_pad() -> void:
	var ship: Dictionary = GameState.local_ship()
	var up := pad_up()
	ship["transform"] = Transform3D(Basis.looking_at(-pad_forward(), up),
			pad_world() + up * GEAR_HEIGHT)
	ship["velocity"] = Vector3.ZERO
	GameState.gear_down = true
	GameState.gear_position = 1.0
	GameState.landing_gear_changed.emit(true)


func _damage_hull(section: String, amount: float) -> void:
	var sections: Dictionary = GameState.local_ship()["hull_sections"]
	if not sections.has(section) or amount <= 0.0:
		return
	sections[section] = maxf(float(sections[section]) - amount, 0.05)
	GameState.hull_sections_changed.emit()


func _adjust_reputation(delta: float) -> void:
	var index: int = int(GameState.docking.get("faction", -1))
	if index < 0 or index >= GameState.market_factions.size():
		return
	var faction: String = GameState.market_factions[index]
	if not GameState.reputation.has(faction):
		return
	GameState.reputation[faction] = clampf(
			float(GameState.reputation[faction]) + delta, 0.0, 1.0)
	GameState.reputation_changed.emit()
