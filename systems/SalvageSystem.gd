extends Node
## Owns the wreck's structural graph, the scan that reveals it, the
## approach/match-velocity flight profile, cutting, and structural risk.
##
## Risk has a physical basis (plan Phase 4): the graph marks which members
## carry the wreck's residual frame stress. Severing a load-bearing spar
## spikes risk sharply and ratchets the resting baseline up; a cosmetic panel
## barely moves it. Which member to cut is a read-the-wreck decision made on
## the Tactical display's structural overlay, not a countdown timer.

## Cutting head reach; approach must be MATCHED inside this to cut. Also the
## centre-based standoff used when no wreck surface is available (headless).
const CUT_RANGE := 14.0
## Gap held between the ship hull and the wreck's surface when the approach
## autopilot parks (surface-relative; see _update_approach). Small enough that
## the cutting head reaches, large enough to clear the frame from any angle.
const STANDOFF_GAP := 2.0
## Remaining travel (m) to the park point that still counts as matched.
const MATCH_SLACK := 1.0
## Structural scan only resolves the graph inside this range.
const SCAN_RANGE := 300.0
## Seconds for a full structural scan at 100% SENSORS allocation.
const SCAN_TIME := 5.0
const MIN_CUTTER_POWER := 0.2
const MIN_SENSOR_POWER := 0.1
## Minimum FBW authority to open (or keep) the pre-cut alignment. While
## ALIGNING the router routes pitch/yaw to the torch, so the pilot has no
## authority to cancel residual spin by hand — with the stabilisation degraded
## the seam sweeps the reticle at a rate nothing can null, which makes the
## mini-game unwinnable rather than hard. The interlock refuses it up front.
const MIN_ALIGN_AUTHORITY := 0.5

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

## Per-site derelict tumble: reset_site() rolls a random spin axis + rate (rad/s)
## into wreck["tumble_omega"], so no two claims tumble alike and the alignment
## challenge can't be memorised. Rate is capped low so it reads as adrift (not
## spinning) and the approach feed-forward can still hold station — v = ω × r stays
## small enough that MATCHED is reachable. A minority of wrecks come in barely
## turning, for variety. Wreck.gd (view/physics) reads the published omega.
const TUMBLE_RATE_MIN := 0.07
const TUMBLE_RATE_MAX := 0.20
const TUMBLE_STABLE_CHANCE := 0.2
const TUMBLE_STABLE_MIN := 0.02
const TUMBLE_STABLE_MAX := 0.05

## --- Pre-cut alignment mini-game ------------------------------------------
## Once MATCHED on a member, firing the cutter opens a 2-axis crosshair: the
## player steers a reticle (align.reticle, -1..1) onto a drifting seam point
## (align.target) and holds it inside LOCK_RADIUS to build align.lock to 1.0
## (auto-commit). Straying past SLIP_RADIUS grows align.slip; a full slip aborts
## the cut (the hard-fail). The captured align.quality (0..1) then scales the
## cut's speed, risk spike, and yield — a clean cut is faster, safer, richer.
## Reticle aim comes from the flight pitch/yaw axes (InputRouter routes them here
## while ALIGNING so they don't disengage the match).
const ALIGN_LOCK_RADIUS := 0.18
const ALIGN_SLIP_RADIUS := 0.55
const ALIGN_LOCK_RATE := 0.7
const ALIGN_LOCK_BLEED := 0.9
const ALIGN_SLIP_RATE := 0.6
const ALIGN_SLIP_RECOVER := 0.4
const ALIGN_RETICLE_RATE := 1.4
## The seam is a real point on the member (Wreck.gd bakes it), so it "drifts"
## because the derelict tumbles — no synthetic wander. This maps the seam's offset
## from the member centroid (up to its radius) into the -1..1 align field: larger
## members sweep a wider arc, so a big spar is harder to hold than a small panel.
const ALIGN_SEAM_SPAN := 1.6
## Quality (0..1) -> outcome. Cut-rate multiplier floor, risk-spike multiplier
## band (poor alignment spikes harder), yield multiplier floor, and the risk
## nudge a botched (slipped-out) alignment leaves behind.
const ALIGN_RATE_MIN := 0.45
const ALIGN_RISK_MIN := 0.6
const ALIGN_RISK_MAX := 1.6
const ALIGN_YIELD_MIN := 0.55
const ALIGN_BOTCH_RISK := 0.05

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

## Alignment aim for this frame, fed by InputRouter from the flight pitch/yaw axes
## while ALIGNING, already oriented to the reticle field (x = screen-right,
## y = screen-down), each -1..1. Consumed by _update_align.
var _align_input := Vector2.ZERO


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
	if id == GameState.selected_member_id:
		return
	# A new cut target means a new approach destination: the current match (and any
	# cut/alignment on it) no longer applies, so drop to HOLDING and make the pilot
	# re-arm the approach to reposition onto the new member.
	if GameState.approach_state != "HOLDING":
		_abort_align("TARGET CHANGED")
		_abort_cut("TARGET CHANGED")
		_set_approach("HOLDING")
		GameState.post_comms("OPS",
				"REPOSITION REQUIRED — RE-ARM APPROACH FOR %s" % member["name"])
	GameState.selected_member_id = id
	GameState.selected_member_changed.emit(id)


## Step the cut-target selection to the next still-cuttable member (mapped
## salvage-next/prev intent). Wraps; picks the first cuttable when nothing is
## selected. No-op until the wreck is scanned.
func cycle_member(delta: int) -> void:
	if GameState.run_phase != "ON_SITE" or not GameState.wreck.get("scanned", false):
		return
	var members: Array = GameState.wreck.get("members", [])
	var cuttable: Array[int] = []
	for member: Dictionary in members:
		if not member["cut"] and not member["destroyed"]:
			cuttable.append(member["id"])
	if cuttable.is_empty():
		return
	var here := cuttable.find(GameState.selected_member_id)
	if here == -1:
		select_member(cuttable[0] if delta >= 0 else cuttable[cuttable.size() - 1])
	else:
		var step := 1 if delta >= 0 else -1
		select_member(cuttable[(here + step + cuttable.size()) % cuttable.size()])


## InputRouter, every frame: current HOTAS/keyboard flight input. Any real
## input while the approach autopilot is flying disengages it — the stick
## always wins.
func set_manual_flight(thrust: Vector3, rot: Vector3) -> void:
	ShipMotion.set_command(thrust, rot)
	# Forward travel within the interlock band is a resting throttle, not a grab
	# for control; only the excess past the band (plus any lateral/vertical or
	# rotation input) disengages, so arming with the lever open stays stable.
	var forward_over := maxf(absf(thrust.z) - APPROACH_ARM_THROTTLE_MAX, 0.0)
	var moved := Vector3(thrust.x, thrust.y, forward_over).length() > MANUAL_OVERRIDE_DELTA \
			or rot.length() > MANUAL_OVERRIDE_DELTA
	if GameState.approach_state != "HOLDING" and moved:
		_abort_align("MANUAL CONTROL")
		_abort_cut("MANUAL CONTROL")
		_set_approach("HOLDING")
		GameState.post_comms("OPS", "AUTOPILOT DISENGAGED — MANUAL CONTROL")


func toggle_approach() -> void:
	if GameState.run_phase != "ON_SITE":
		return
	if GameState.approach_state == "HOLDING":
		# The approach now flies to a specific member, so it needs a destination.
		if GameState.get_member(GameState.selected_member_id).is_empty():
			GameState.post_comms("OPS", "APPROACH INHIBITED — SELECT A CUT TARGET FIRST")
			return
		if ShipMotion.throttle_command() > APPROACH_ARM_THROTTLE_MAX:
			GameState.post_comms("OPS",
					"APPROACH INHIBITED — THROTTLE PAST %d%%, EASE BACK TO ARM"
					% int(APPROACH_ARM_THROTTLE_MAX * 100.0))
			return
		# The autopilot only translates, and it translates on the drive. With the
		# selector off a running position — or on the thermal stage alone with a dry
		# hydrogen tank — it would command a burn nothing can deliver and sit there
		# reporting APPROACHING forever, so refuse it up front.
		if GameState.thrust_fraction() <= 0.0:
			GameState.post_comms("OPS",
					"APPROACH INHIBITED — DRIVE NOT MAKING THRUST (CHECK THE SELECTOR)")
			return
		_set_approach("APPROACHING")
		GameState.post_comms("OPS", "APPROACH BURN — MATCHING VELOCITY WITH %s"
				% GameState.get_member(GameState.selected_member_id)["name"])
	else:
		_abort_align("APPROACH BROKEN")
		_abort_cut("APPROACH BROKEN")
		_set_approach("HOLDING")
		GameState.post_comms("OPS", "STATION-KEEPING RELEASED — HOLDING")


## Bindable (throttle_cmd_toggle): forwards to the motion pipeline, which owns
## the throttle command law. See ShipMotion.ThrottleCmdMode.
func toggle_throttle_cmd_mode() -> void:
	ShipMotion.toggle_throttle_cmd_mode()


## The cutter trigger (ops_cut / CUT button) is context-sensitive: from a matched
## member it opens the pre-cut alignment mini-game; pressed again while ALIGNING it
## commits the lock at its current quality (an early-out speed/cleanliness trade).
func request_cut() -> void:
	if GameState.run_phase != "ON_SITE":
		return
	if GameState.cargo_hatch_open:
		GameState.post_comms("OPS", "CUT ABORT — SECURE CARGO HATCH FIRST")
		return
	# An extended leg sits in the torch's arc, so the gear interlocks the cutter
	# the same way the hatch does — which is what gives the gear a cost at the
	# claim as well as at the station.
	if not GameState.gear_stowed():
		GameState.post_comms("OPS", "CUT ABORT — STOW THE LANDING GEAR FIRST")
		return
	if GameState.align_state == "ALIGNING":
		_commit_align()
		return
	if GameState.wreck["cutting_id"] != -1:
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
	if ShipMotion.authority() < MIN_ALIGN_AUTHORITY:
		GameState.post_comms("OPS",
				"CUT ABORT — STABILISATION DEGRADED (CHECK FLIGHT ASSIST AND THRUST ALLOCATION)")
		return
	_begin_align(member)


## InputRouter, every frame while ALIGNING: the pilot's aim from the flight
## pitch/yaw axes, oriented so the reticle tracks the nose (x = screen-right,
## y = screen-down), each -1..1.
func set_align_input(aim: Vector2) -> void:
	_align_input = aim


## MFD/touch intent: bail out of the alignment mini-game without cutting.
func cancel_align() -> void:
	_abort_align("CANCELLED")


## Open the alignment mini-game on the matched member. The reticle starts centred;
## the seam target starts wherever the member's baked seam currently projects (and
## keeps moving with the tumble) so there's a real, moving alignment to hold.
func _begin_align(member: Dictionary) -> void:
	_align_input = Vector2.ZERO
	GameState.align = {
		"reticle": Vector2.ZERO,
		"target": _seam_offset(member),
		"lock": 0.0,
		"slip": 0.0,
		"quality": 0.0,
	}
	GameState.align_state = "ALIGNING"
	GameState.align_changed.emit("ALIGNING")
	GameState.post_comms("SALVAGE", "ALIGN CUTTING HEAD — %s (LOAD %s)" % [
		member["name"], load_class(member)])


## Bank the current alignment quality and hand off to the real cut.
func _commit_align() -> void:
	var member := GameState.get_member(GameState.selected_member_id)
	if member.is_empty():
		_abort_align("NO TARGET")
		return
	var quality: float = clampf(GameState.align.get("quality", 0.0), 0.0, 1.0)
	GameState.align_state = "IDLE"
	GameState.align = {}
	GameState.align_changed.emit("IDLE")
	_begin_cut(member, quality)


func _begin_cut(member: Dictionary, quality: float) -> void:
	GameState.wreck["cutting_id"] = member["id"]
	GameState.wreck["cut_progress"] = 0.0
	GameState.wreck["align_quality"] = quality
	GameState.post_comms("SALVAGE", "CUTTING %s — ALIGN %d%% — LOAD %s" % [
		member["name"], roundi(quality * 100.0), load_class(member)])


func _abort_align(reason: String) -> void:
	if GameState.align_state != "ALIGNING":
		return
	GameState.align_state = "IDLE"
	GameState.align = {}
	GameState.align_changed.emit("IDLE")
	GameState.post_comms("SALVAGE", "ALIGNMENT LOST — %s" % reason)


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


## The current forward throttle command, 0..1 — the value toggle_approach() tests
## against APPROACH_ARM_THROTTLE_MAX before it will arm. Read-only, for the
## instruments: the MFD CHECKLIST page shows this item against its limit so a
## refused approach names the reason before you press for it.
func throttle_command() -> float:
	return ShipMotion.throttle_command()


## Ship collision radius, or a fallback for an unbaked capsule — mirrors
## CollisionSystem so the surface standoff and the actual collision agree.
func _ship_radius() -> float:
	var r: float = GameState.ship_def.collision_radius
	return r if r > 0.0 else 2.5


## --- System-to-system entry points ----------------------------------------


## Wreck.tscn reports its real placement at scene setup (headless smoke tests
## run without the 3D scene, so the graph defaults to DEFAULT_WRECK_POS).
func register_wreck_position(position: Vector3) -> void:
	GameState.wreck["position"] = position


## ThreatSystem: rival salvager severs a member. Same physics as our own cut —
## the frame doesn't care whose torch it was — and full yield (the rival skips
## the alignment mini-game entirely). Detaches a drifting piece just like a
## player cut; ThreatSystem then has to physically close on it and hold long
## enough to claim it (DriftSystem.collect_for_rival) — the same two-phase
## sever-then-retrieve loop the player runs, and because pieces are
## free-for-all either side can beat the other to one. Returns {} if nothing
## is left to strip, else {name, id, piece_id} for ThreatSystem's comms line
## and chase target.
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
	var piece_id: int = DriftSystem.spawn_piece(member, member["qty"])
	return {"name": member["name"], "id": member["id"], "piece_id": piece_id}


## ThreatSystem: the frame lets go. Uncut members are destroyed with it.
func trigger_collapse() -> void:
	_abort_align("STRUCTURAL COLLAPSE")
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
## Break to manual — ShipMotion.step integrates velocity, so the bounce
## carries the ship clear and damps out.
func abort_approach_on_collision() -> void:
	if GameState.approach_state == "HOLDING":
		return
	_abort_align("PATH OBSTRUCTED")
	_abort_cut("PATH OBSTRUCTED")
	_set_approach("HOLDING")
	GameState.post_comms("OPS", "AUTOPILOT DISENGAGED — OBSTRUCTION ON APPROACH")


## MarketSystem: called on leaving the site (docking) — approach state has no
## meaning away from the wreck and shouldn't leak "MATCHED" into the station
## visit or trip a spurious autopilot-disengage when the stick moves.
func reset_approach() -> void:
	_abort_align("APPROACH BROKEN")
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
		"align_quality": 1.0,
		"tumble_omega": _random_tumble(),
	}
	GameState.selected_member_id = -1
	GameState.align_state = "IDLE"
	GameState.align = {}
	_risk_base = 0.1 + _rng.randf_range(0.0, 0.08)
	_set_risk(_risk_base)
	_set_approach("HOLDING")
	GameState.site_reset.emit()


## Roll this site's derelict tumble: a random spin axis and a rate (rad/s), mostly
## in the normal band but occasionally barely-turning. Returns ω = axis * rate;
## Wreck.gd spins the frame about it and feed-forwards v = ω × r per member.
func _random_tumble() -> Vector3:
	var axis := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0))
	axis = axis.normalized() if axis.length() > 0.01 else Vector3.UP
	var rate: float
	if _rng.randf() < TUMBLE_STABLE_CHANCE:
		rate = _rng.randf_range(TUMBLE_STABLE_MIN, TUMBLE_STABLE_MAX)
	else:
		rate = _rng.randf_range(TUMBLE_RATE_MIN, TUMBLE_RATE_MAX)
	return axis * rate


## --- Per-frame simulation --------------------------------------------------


func _physics_process(delta: float) -> void:
	# The station's docking pattern is hand-flown on the same stick, so manual
	# flight has to integrate there too — but nothing else in this system means
	# anything away from the claim: there is no wreck to scan, align on or cut.
	if GameState.run_phase == "APPROACH":
		ShipMotion.step(delta)
		return
	if GameState.run_phase != "ON_SITE":
		return
	_update_scan(delta)
	_update_approach(delta)
	_update_align(delta)
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
		ShipMotion.step(delta)
		return
	# The autopilot flies on the drive, and the selector moves under it: OFF or
	# START after toggle_approach()'s gate has already passed. The seize below is
	# kinematic and never consults the drive, so without this the ship would keep
	# closing — and then hold station, and be cut from — on a drive making no
	# thrust at all. Hand control back the way a collision does.
	if GameState.thrust_fraction() <= 0.0:
		_abort_align("DRIVE THRUST LOST")
		_abort_cut("DRIVE THRUST LOST")
		_set_approach("HOLDING")
		GameState.post_comms("OPS", "AUTOPILOT DISENGAGED — DRIVE NOT MAKING THRUST")
		ShipMotion.step(delta)
		return
	# Fly to the *selected* member: its baked world centroid (published into the
	# graph by Wreck.gd) is the park target, so the ship stations off that member
	# specifically. Fall back to the wreck centre when the member carries no baked
	# geometry (headless with no 3D scene).
	var member := GameState.get_member(GameState.selected_member_id)
	var target_pos: Vector3 = member.get("center", GameState.wreck["position"])
	var origin: Vector3 = transform.origin
	var to_center: Vector3 = target_pos - origin
	var center_dist := to_center.length()
	var approach_dir := to_center / center_dist if center_dist > 0.001 else -transform.basis.z
	# Park a fixed clearance off the member: its radius, the ship's reach, and the
	# standoff gap. member.radius is 0 when unbaked, leaving a centre-based standoff.
	var member_radius: float = member.get("radius", 0.0)
	var remaining: float = center_dist - (member_radius + _ship_radius() + STANDOFF_GAP)
	# Closing speed profile: proportional braking, capped by ship performance
	# scaled by THRUST allocation (starve the channel and the burn crawls).
	var speed: float = clampf(remaining * 0.4, 0.0,
			GameState.ship_def.approach_speed * maxf(GameState.power("THRUST"), 0.05))
	# The member orbits the wreck centre as the frame tumbles; feed-forward its
	# orbital velocity so the ship holds station on it (without this the pure-closing
	# controller lags a moving standoff and never settles inside MATCH_SLACK). The
	# closing term still shrinks to zero at the park point, so the MATCHED gate trips.
	var member_vel: Vector3 = member.get("vel", Vector3.ZERO)
	var closing: Vector3 = approach_dir * speed if remaining > 0.01 else Vector3.ZERO
	var velocity: Vector3 = member_vel + closing
	transform.origin += velocity * delta
	ShipMotion.seize(transform, velocity)
	if GameState.approach_state == "APPROACHING" \
			and remaining <= MATCH_SLACK and speed < 0.6:
		_set_approach("MATCHED")
		GameState.post_comms("OPS", "VELOCITY MATCHED — STANDOFF ON %s" % member["name"])


## The 2-axis crosshair mini-game (see the ALIGN_* consts). Drifts the seam target,
## steers the reticle from the pilot's aim, and accumulates lock/slip. Same
## interlocks as an active cut — lose the match or cutter power and it's off.
func _update_align(delta: float) -> void:
	if GameState.align_state != "ALIGNING":
		return
	if GameState.approach_state != "MATCHED":
		_abort_align("RANGE OPEN")
		return
	if GameState.power("CUTTER") < MIN_CUTTER_POWER:
		_abort_align("CUTTER POWER LOST")
		return
	if ShipMotion.authority() < MIN_ALIGN_AUTHORITY:
		_abort_align("STABILISATION DEGRADED")
		return
	if GameState.cargo_hatch_open:
		_abort_align("CARGO HATCH OPEN")
		return
	var align: Dictionary = GameState.align
	var member := GameState.get_member(GameState.selected_member_id)
	# The seam is a fixed point on the member; it moves in view only because the
	# derelict tumbles, so the drift you fight has a visible cause on the hull.
	align["target"] = _seam_offset(member)
	# Steer the reticle from the pilot's aim.
	align["reticle"] = (Vector2(align["reticle"])
			+ _align_input * ALIGN_RETICLE_RATE * delta).clampf(-1.0, 1.0)
	var err: float = Vector2(align["reticle"]).distance_to(align["target"])
	if err <= ALIGN_LOCK_RADIUS:
		align["lock"] = minf(float(align["lock"]) + ALIGN_LOCK_RATE * delta, 1.0)
		# Weight quality by how centred the hold is (1 at the bullseye, 0 at the edge).
		var closeness := 1.0 - err / ALIGN_LOCK_RADIUS
		align["quality"] = maxf(float(align["quality"]), float(align["lock"]) * closeness)
		align["slip"] = maxf(float(align["slip"]) - ALIGN_SLIP_RECOVER * delta, 0.0)
	else:
		align["lock"] = maxf(float(align["lock"]) - ALIGN_LOCK_BLEED * delta, 0.0)
		if err >= ALIGN_SLIP_RADIUS:
			align["slip"] = minf(float(align["slip"]) + ALIGN_SLIP_RATE * delta, 1.0)
		else:
			align["slip"] = maxf(float(align["slip"]) - ALIGN_SLIP_RECOVER * delta, 0.0)
	if float(align["slip"]) >= 1.0:
		_abort_align("TORCH SLIPPED")
		_set_risk(minf(GameState.structural_risk + ALIGN_BOTCH_RISK, 1.0))
		return
	if float(align["lock"]) >= 1.0:
		_commit_align()


## The member's cut seam as a point in the -1..1 align field: the seam's offset
## from the member centroid (both baked world points that ride the tumble),
## projected onto the ship's right/up axes and normalized by the member's reach.
## As the derelict rotates this offset swings, so the target tracks the visible
## spin. Zero when the member carries no baked geometry (headless): a static seam.
func _seam_offset(member: Dictionary) -> Vector2:
	if not (member.has("seam") and member.has("center")):
		return Vector2.ZERO
	var offset: Vector3 = member["seam"] - member["center"]
	var basis: Basis = (GameState.local_ship()["transform"] as Transform3D).basis
	var span: float = maxf(float(member.get("radius", 1.0)), 0.5) * ALIGN_SEAM_SPAN
	# +x is screen-right, +y is screen-down, matching the reticle's convention.
	return Vector2(offset.dot(basis.x), -offset.dot(basis.y)) / span


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
	if GameState.cargo_hatch_open:
		_abort_cut("CARGO HATCH OPEN")
		return
	# Alignment quality throttles the cut: a clean lock cuts near full rate, a sloppy
	# one crawls at ALIGN_RATE_MIN.
	var quality: float = clampf(float(wreck.get("align_quality", 1.0)), 0.0, 1.0)
	wreck["cut_progress"] = minf(wreck["cut_progress"]
			+ delta * GameState.ship_def.cut_rate * GameState.power("CUTTER")
			* lerpf(ALIGN_RATE_MIN, 1.0, quality), 1.0)
	if wreck["cut_progress"] >= 1.0:
		_complete_cut(GameState.get_member(wreck["cutting_id"]))


func _complete_cut(member: Dictionary) -> void:
	# Alignment quality (banked at commit) softens the risk spike and preserves
	# yield; a ragged cut spikes harder and loses salvage. Reset to 1.0 after so a
	# later non-aligned sever (rival/collapse) doesn't inherit this cut's score.
	var quality: float = clampf(float(GameState.wreck.get("align_quality", 1.0)), 0.0, 1.0)
	GameState.wreck["cutting_id"] = -1
	GameState.wreck["cut_progress"] = 0.0
	GameState.wreck["align_quality"] = 1.0
	member["cut"] = true
	var spike := _apply_cut_stress(member, lerpf(ALIGN_RISK_MAX, ALIGN_RISK_MIN, quality))
	GameState.wreck_member_cut.emit(member["id"])
	if GameState.selected_member_id == member["id"]:
		GameState.selected_member_id = -1
		GameState.selected_member_changed.emit(-1)
	GameState.post_comms("SALVAGE", "%s SEVERED — FRAME STRESS %s" % [
		member["name"],
		"SPIKING" if spike > 0.12 else ("SHIFTING" if spike > 0.05 else "STEADY")])
	# The yield no longer teleports into the hold: it's now a physical, drifting
	# piece (DriftSystem) the pilot has to fly down and scoop through the cargo
	# hatch — CargoSystem.stow_salvage only fires on that collection.
	var yield_qty: float = snappedf(member["qty"] * lerpf(ALIGN_YIELD_MIN, 1.0, quality), 0.1)
	DriftSystem.spawn_piece(member, yield_qty)


## Severing consequences shared by our cuts and the rival's: risk spikes by the
## member's predicted amount (scaled by `risk_mult` — alignment quality for our
## cuts, 1.0 for the rival's) and the resting baseline ratchets up.
func _apply_cut_stress(member: Dictionary, risk_mult := 1.0) -> float:
	var spike := predicted_spike(member) * risk_mult
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
	# A match belongs to the member we approached; anything else clears it.
	GameState.matched_member_id = GameState.selected_member_id if state == "MATCHED" else -1
	GameState.approach_changed.emit(state)


func _links_for(index: int) -> Array:
	var links: Array = []
	for pair: Array in MEMBER_LINKS:
		if pair[0] == index:
			links.append(pair[1])
		elif pair[1] == index:
			links.append(pair[0])
	return links
