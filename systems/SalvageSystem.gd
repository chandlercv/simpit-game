extends Node
## Owns the wreck's structural graph, the scan that reveals it, the
## approach/match-velocity flight profile, cutting, and structural risk.
##
## Risk has a physical basis (plan Phase 4): the graph marks which members
## carry the wreck's residual frame stress. Severing a load-bearing spar
## spikes risk sharply and ratchets the resting baseline up; a cosmetic panel
## barely moves it. Which member to cut is a read-the-wreck decision made on
## the Tactical display's structural overlay, not a countdown timer.

## Cutting head reach; approach must be MATCHED inside this to cut.
const CUT_RANGE := 14.0
## Structural scan only resolves the graph inside this range.
const SCAN_RANGE := 300.0
## Seconds for a full structural scan at 100% SENSORS allocation.
const SCAN_TIME := 5.0
const MIN_CUTTER_POWER := 0.2
const MIN_SENSOR_POWER := 0.1

## Throttle interlock band for the approach autopilot. The throttle folds into
## thrust.z and doesn't self-center, so the lever may rest anywhere up to this
## much forward travel and still read as "idle" to the autopilot: you can arm
## within the band, and a throttle parked inside it won't disengage. Easing the
## lever PAST the band is a real bid for manual control.
const APPROACH_ARM_THROTTLE_MAX := 0.4
## Stick/rotation deflection (and forward travel beyond the band above) that
## counts as the pilot grabbing control from the autopilot.
const MANUAL_OVERRIDE_DELTA := 0.2

## Risk relaxes toward the ratcheting baseline at this exponential rate.
const RISK_EASE := 0.25
## Members below this load fraction are cosmetic (panels, masts).
const COSMETIC_LOAD := 0.2

const DEFAULT_WRECK_POS := Vector3(0, 0, -40)

## Member catalog for the current wreck kit: node names match Wreck.tscn
## children, sx/sy are schematic coords (-1..1, fore = -y) for the Tactical
## overlay, load is the base load-bearing fraction (jittered per run), yield
## is a good display_name + qty range in that good's unit.
## Rules and data are mixed here deliberately — the trigger to split them is
## a second wreck kit (plan: Modding & simpit-building friendliness).
const MEMBER_TABLE := [
	{"node": "Spine", "name": "SPINE TRUSS", "sx": 0.0, "sy": 0.1, "load": 0.9,
		"good": "HULL ALLOY", "qty_min": 2.0, "qty_max": 3.5},
	{"node": "HullFore", "name": "FORE HULL", "sx": 0.0, "sy": -0.62, "load": 0.55,
		"good": "INTACT NAV CORES", "qty_min": 1.0, "qty_max": 1.0},
	{"node": "HullAft", "name": "AFT HULL", "sx": 0.1, "sy": 0.52, "load": 0.62,
		"good": "VOLATILES", "qty_min": 1.5, "qty_max": 3.0},
	{"node": "EngineBell", "name": "ENGINE BELL", "sx": 0.14, "sy": 0.88, "load": 0.34,
		"good": "RARE ISOTOPES", "qty_min": 60.0, "qty_max": 180.0},
	{"node": "PanelA", "name": "RADIATOR PANEL A", "sx": 0.62, "sy": -0.28, "load": 0.08,
		"good": "HULL ALLOY", "qty_min": 0.4, "qty_max": 0.9},
	{"node": "PanelB", "name": "RADIATOR PANEL B", "sx": -0.56, "sy": 0.3, "load": 0.08,
		"good": "HULL ALLOY", "qty_min": 0.4, "qty_max": 0.9},
	{"node": "Antenna", "name": "SENSOR MAST", "sx": -0.34, "sy": -0.85, "load": 0.06,
		"good": "FUSED OPTICS", "qty_min": 6.0, "qty_max": 18.0},
]
## Structural adjacency (indices into MEMBER_TABLE): what hangs off what.
const MEMBER_LINKS := [[0, 1], [0, 2], [2, 3], [1, 4], [2, 5], [1, 6]]

var _rng := RandomNumberGenerator.new()
## Resting risk level; each structural cut ratchets it up.
var _risk_base := 0.15

## Manual flight input for this frame, fed by InputRouter (Phase 5).
## thrust is local (x right, y up, z forward), rot is (pitch, yaw, roll),
## all components -1..1.
var _manual_thrust := Vector3.ZERO
var _manual_rot := Vector3.ZERO


func _ready() -> void:
	_rng.randomize()
	reset_site()
	GameState.post_comms("HARBOR",
			"TRAFFIC ADVISORY: SALVAGE CLAIM 7741-C ACTIVE IN THIS VOLUME")


## --- Intents (called by displays / InputRouter) ---------------------------


func select_member(id: int) -> void:
	if GameState.run_phase != "ON_SITE" or not GameState.wreck["scanned"]:
		return
	var member := GameState.get_member(id)
	if member.is_empty() or member["cut"] or member["destroyed"]:
		return
	GameState.selected_member_id = id
	GameState.selected_member_changed.emit(id)


## InputRouter, every frame: current HOTAS/keyboard flight input. Any real
## input while the approach autopilot is flying disengages it — the stick
## always wins.
func set_manual_flight(thrust: Vector3, rot: Vector3) -> void:
	_manual_thrust = thrust
	_manual_rot = rot
	# Forward travel within the interlock band is a resting throttle, not a grab
	# for control; only the excess past the band (plus any lateral/vertical or
	# rotation input) disengages, so arming with the lever open stays stable.
	var forward_over := maxf(absf(thrust.z) - APPROACH_ARM_THROTTLE_MAX, 0.0)
	var moved := Vector3(thrust.x, thrust.y, forward_over).length() > MANUAL_OVERRIDE_DELTA \
			or rot.length() > MANUAL_OVERRIDE_DELTA
	if GameState.approach_state != "HOLDING" and moved:
		_abort_cut("MANUAL CONTROL")
		_set_approach("HOLDING")
		GameState.post_comms("OPS", "AUTOPILOT DISENGAGED — MANUAL CONTROL")


func toggle_approach() -> void:
	if GameState.run_phase != "ON_SITE":
		return
	if GameState.approach_state == "HOLDING":
		if _manual_thrust.z > APPROACH_ARM_THROTTLE_MAX:
			GameState.post_comms("OPS",
					"APPROACH INHIBITED — THROTTLE PAST %d%%, EASE BACK TO ARM"
					% int(APPROACH_ARM_THROTTLE_MAX * 100.0))
			return
		_set_approach("APPROACHING")
		GameState.post_comms("OPS", "APPROACH BURN — MATCHING VELOCITY WITH WRECK")
	else:
		_abort_cut("APPROACH BROKEN")
		_set_approach("HOLDING")
		GameState.post_comms("OPS", "STATION-KEEPING RELEASED — HOLDING")


func request_cut() -> void:
	if GameState.run_phase != "ON_SITE" or GameState.wreck["cutting_id"] != -1:
		return
	var member := GameState.get_member(GameState.selected_member_id)
	if member.is_empty() or member["cut"] or member["destroyed"]:
		GameState.post_comms("OPS", "CUT ABORT — NO VALID MEMBER SELECTED")
		return
	if GameState.approach_state != "MATCHED":
		GameState.post_comms("OPS", "CUT ABORT — NOT IN CUTTING RANGE (MATCH VELOCITY FIRST)")
		return
	if GameState.power("CUTTER") < MIN_CUTTER_POWER:
		GameState.post_comms("OPS", "CUT ABORT — CUTTER UNPOWERED (RAISE CUTTER ALLOCATION)")
		return
	GameState.wreck["cutting_id"] = member["id"]
	GameState.wreck["cut_progress"] = 0.0
	GameState.post_comms("SALVAGE", "CUTTING %s — LOAD %s" % [
		member["name"], load_class(member)])


## --- Queries (read-only, safe for displays) -------------------------------


## Risk spike a cut of this member would cause — shown on the Tactical
## overlay so choosing a cut point is an informed decision.
func predicted_spike(member: Dictionary) -> float:
	return pow(member["load"], 1.5) * 0.3 + 0.02


func load_class(member: Dictionary) -> String:
	var member_load: float = member["load"]
	if member_load >= 0.5:
		return "HIGH"
	if member_load >= COSMETIC_LOAD:
		return "MED"
	return "LOW"


func wreck_distance() -> float:
	var ship_pos: Vector3 = GameState.local_ship()["transform"].origin
	return ship_pos.distance_to(GameState.wreck["position"])


## --- System-to-system entry points ----------------------------------------


## Wreck.tscn reports its real placement at scene setup (headless smoke tests
## run without the 3D scene, so the graph defaults to DEFAULT_WRECK_POS).
func register_wreck_position(position: Vector3) -> void:
	GameState.wreck["position"] = position


## ThreatSystem: rival salvager severs a member and keeps the yield. Same
## physics as our own cut — the frame doesn't care whose torch it was.
func rival_strip_member() -> Dictionary:
	var candidates: Array[Dictionary] = []
	for member: Dictionary in GameState.wreck["members"]:
		if not member["cut"] and not member["destroyed"] \
				and member["id"] != GameState.wreck["cutting_id"]:
			candidates.append(member)
	if candidates.is_empty():
		return {}
	var member: Dictionary = candidates[_rng.randi_range(0, candidates.size() - 1)]
	member["cut"] = true
	_apply_cut_stress(member)
	GameState.wreck_member_cut.emit(member["id"])
	if GameState.selected_member_id == member["id"]:
		GameState.selected_member_id = -1
		GameState.selected_member_changed.emit(-1)
	return member


## ThreatSystem: the frame lets go. Uncut members are destroyed with it.
func trigger_collapse() -> void:
	_abort_cut("STRUCTURAL COLLAPSE")
	for member: Dictionary in GameState.wreck["members"]:
		if not member["cut"]:
			member["destroyed"] = true
	GameState.selected_member_id = -1
	GameState.selected_member_changed.emit(-1)
	GameState.wreck_members_lost.emit()
	_risk_base = 0.97
	_set_risk(0.97)
	GameState.post_comms("SALVAGE", "WRECK FRAME COLLAPSED — REMAINING SALVAGE LOST")


## CollisionSystem: the approach autopilot drove the ship into a solid body on
## the path. The kinematic controller recomputes velocity toward the standoff
## every frame, discarding the collision bounce, so it would grind indefinitely.
## Break to manual — _update_manual_flight integrates velocity, so the bounce
## carries the ship clear and damps out.
func abort_approach_on_collision() -> void:
	if GameState.approach_state == "HOLDING":
		return
	_abort_cut("PATH OBSTRUCTED")
	_set_approach("HOLDING")
	GameState.post_comms("OPS", "AUTOPILOT DISENGAGED — OBSTRUCTION ON APPROACH")


## MarketSystem: called on leaving the site (docking) — approach state has no
## meaning away from the wreck and shouldn't leak "MATCHED" into the station
## visit or trip a spurious autopilot-disengage when the stick moves.
func reset_approach() -> void:
	_set_approach("HOLDING")


## MarketSystem (on jump back to the claim) and boot: fresh wreck graph.
func reset_site() -> void:
	var members: Array[Dictionary] = []
	for i in MEMBER_TABLE.size():
		var t: Dictionary = MEMBER_TABLE[i]
		members.append({
			"id": i,
			"name": t["name"],
			"node": t["node"],
			"sx": t["sx"],
			"sy": t["sy"],
			"load": clampf(t["load"] + _rng.randf_range(-0.12, 0.12), 0.03, 0.98),
			"links": _links_for(i),
			"cut": false,
			"destroyed": false,
			"good": t["good"],
			"qty": snappedf(_rng.randf_range(t["qty_min"], t["qty_max"]), 0.1),
		})
	var position: Vector3 = GameState.wreck.get("position", DEFAULT_WRECK_POS)
	GameState.wreck = {
		"scanned": false,
		"scan_progress": 0.0,
		"position": position,
		"members": members,
		"cutting_id": -1,
		"cut_progress": 0.0,
	}
	GameState.selected_member_id = -1
	_risk_base = 0.1 + _rng.randf_range(0.0, 0.08)
	_set_risk(_risk_base)
	_set_approach("HOLDING")
	GameState.site_reset.emit()


## --- Per-frame simulation --------------------------------------------------


func _process(delta: float) -> void:
	if GameState.run_phase != "ON_SITE":
		return
	_update_scan(delta)
	_update_approach(delta)
	_update_cut(delta)
	# Risk relaxes toward the ratcheted baseline (residual stress settling).
	var relaxed: float = lerpf(GameState.structural_risk, _risk_base,
			1.0 - exp(-RISK_EASE * delta))
	if absf(relaxed - GameState.structural_risk) > 0.0004:
		_set_risk(relaxed)


func _update_scan(delta: float) -> void:
	var wreck: Dictionary = GameState.wreck
	if wreck["scanned"] or GameState.sensor_mode != "STRUCT":
		return
	if wreck_distance() > SCAN_RANGE or GameState.power("SENSORS") < MIN_SENSOR_POWER:
		return
	wreck["scan_progress"] = minf(
			wreck["scan_progress"] + delta * GameState.power("SENSORS") / SCAN_TIME, 1.0)
	if wreck["scan_progress"] >= 1.0:
		wreck["scanned"] = true
		GameState.wreck_scanned.emit()
		var load_bearing := 0
		for member: Dictionary in wreck["members"]:
			if member["load"] >= COSMETIC_LOAD:
				load_bearing += 1
		GameState.post_comms("SENSORS",
				"STRUCTURAL SCAN COMPLETE — %d MEMBERS RESOLVED, %d CARRYING FRAME STRESS" % [
					wreck["members"].size(), load_bearing])


func _update_approach(delta: float) -> void:
	var ship: Dictionary = GameState.local_ship()
	var transform: Transform3D = ship["transform"]
	if GameState.approach_state == "HOLDING":
		_update_manual_flight(delta)
		return
	var wreck_pos: Vector3 = GameState.wreck["position"]
	var offset: Vector3 = transform.origin - wreck_pos
	# Station-keeping point just inside cutting range, on our approach axis.
	var standoff: Vector3 = wreck_pos + offset.normalized() * (CUT_RANGE - 4.0)
	var to_target: Vector3 = standoff - transform.origin
	var dist := to_target.length()
	# Closing speed profile: proportional braking, capped by ship performance
	# scaled by THRUST allocation (starve the channel and the burn crawls).
	var speed: float = clampf(dist * 0.4, 0.0,
			GameState.ship_def.approach_speed * maxf(GameState.power("THRUST"), 0.05))
	var velocity: Vector3 = to_target.normalized() * speed if dist > 0.01 else Vector3.ZERO
	transform.origin += velocity * delta
	ship["transform"] = transform
	ship["velocity"] = velocity
	if GameState.approach_state == "APPROACHING" \
			and wreck_distance() <= CUT_RANGE and speed < 0.6:
		_set_approach("MATCHED")
		GameState.post_comms("OPS", "VELOCITY MATCHED — INSIDE CUTTING RANGE")


## Newtonian-lite manual flight (Phase 5): rate-controlled attitude, thruster
## acceleration gated by THRUST power, mild flight-assist damping and a speed
## ceiling so the pit stays flyable without a full sim.
func _update_manual_flight(delta: float) -> void:
	var ship: Dictionary = GameState.local_ship()
	var transform: Transform3D = ship["transform"]
	var velocity: Vector3 = ship["velocity"]
	if _manual_rot.length_squared() > 0.001:
		var rate := deg_to_rad(GameState.ship_def.rotation_rate_deg)
		transform.basis = (transform.basis
				* Basis.from_euler(_manual_rot * rate * delta)).orthonormalized()
	if _manual_thrust.length_squared() > 0.001:
		var accel: float = GameState.ship_def.manual_accel \
				* maxf(GameState.power("THRUST"), 0.0)
		var local := Vector3(_manual_thrust.x, _manual_thrust.y, -_manual_thrust.z)
		velocity += transform.basis * local * accel * delta
	else:
		# Flight assist: bleed residual drift so station-keeping is feasible.
		velocity *= exp(-0.35 * delta)
	velocity = velocity.limit_length(GameState.ship_def.max_speed)
	transform.origin += velocity * delta
	ship["transform"] = transform
	ship["velocity"] = velocity


func _update_cut(delta: float) -> void:
	var wreck: Dictionary = GameState.wreck
	if wreck["cutting_id"] == -1:
		return
	if GameState.approach_state != "MATCHED":
		_abort_cut("RANGE OPEN")
		return
	if GameState.power("CUTTER") < MIN_CUTTER_POWER:
		_abort_cut("CUTTER POWER LOST")
		return
	wreck["cut_progress"] = minf(wreck["cut_progress"]
			+ delta * GameState.ship_def.cut_rate * GameState.power("CUTTER"), 1.0)
	if wreck["cut_progress"] >= 1.0:
		_complete_cut(GameState.get_member(wreck["cutting_id"]))


func _complete_cut(member: Dictionary) -> void:
	GameState.wreck["cutting_id"] = -1
	GameState.wreck["cut_progress"] = 0.0
	member["cut"] = true
	var spike := _apply_cut_stress(member)
	GameState.wreck_member_cut.emit(member["id"])
	if GameState.selected_member_id == member["id"]:
		GameState.selected_member_id = -1
		GameState.selected_member_changed.emit(-1)
	GameState.post_comms("SALVAGE", "%s SEVERED — FRAME STRESS %s" % [
		member["name"],
		"SPIKING" if spike > 0.12 else ("SHIFTING" if spike > 0.05 else "STEADY")])
	CargoSystem.stow_salvage(member["name"], member["good"], member["qty"])


## Severing consequences shared by our cuts and the rival's: risk spikes by
## the member's predicted amount and the resting baseline ratchets up.
func _apply_cut_stress(member: Dictionary) -> float:
	var spike := predicted_spike(member)
	_risk_base = minf(_risk_base + member["load"] * 0.09, 0.9)
	_set_risk(minf(GameState.structural_risk + spike, 1.0))
	return spike


func _abort_cut(reason: String) -> void:
	if GameState.wreck["cutting_id"] == -1:
		return
	GameState.wreck["cutting_id"] = -1
	GameState.wreck["cut_progress"] = 0.0
	GameState.post_comms("SALVAGE", "CUT ABORTED — %s" % reason)


func _set_risk(risk: float) -> void:
	GameState.structural_risk = clampf(risk, 0.0, 1.0)
	GameState.structural_risk_changed.emit(GameState.structural_risk)


func _set_approach(state: String) -> void:
	if GameState.approach_state == state:
		return
	GameState.approach_state = state
	GameState.approach_changed.emit(state)


func _links_for(index: int) -> Array:
	var links: Array = []
	for pair: Array in MEMBER_LINKS:
		if pair[0] == index:
			links.append(pair[1])
		elif pair[1] == index:
			links.append(pair[0])
	return links
