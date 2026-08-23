extends Node
## Rival salvagers, the claim-holder's patrol timer, and collapse events
## (feeds the Tactical window's contacts and risk). All timers pause off-site
## and reset when MarketSystem jumps back in for a fresh run.

## Rival cutter: spawn window after jump-in, closing speed, strip cadence.
const RIVAL_SPAWN_MIN := 45.0
const RIVAL_SPAWN_MAX := 90.0
const RIVAL_SPEED := 6.0
const RIVAL_SPAWN_RANGE := 180.0
const RIVAL_WORK_RANGE := 20.0
const RIVAL_STRIP_INTERVAL := 25.0
## Runs the same sever-then-retrieve loop the player does (skipping only the
## alignment mini-game): how close it needs to close on its own severed piece,
## and how long it holds there, to claim it (DriftSystem.collect_for_rival).
## Pieces are free-for-all, so a slow rival can lose one to the player.
const RIVAL_COLLECT_RANGE := 6.0
const RIVAL_COLLECT_TIME := 2.0
## Collision radius for the rival/patrol ships (they're solid to ram into).
## This is the sphere the hulls in tools/build_ships.py are built to fit inside —
## that script refuses to export a vertex outside it — so the model can never
## outgrow what the player actually collides with. Move one, move both.
const SHIP_CONTACT_RADIUS := 2.0

## Patrol: how long the claim window stays open, enforcement bite.
const PATROL_WINDOW_MIN := 240.0
const PATROL_WINDOW_MAX := 360.0
const PATROL_SPEED := 15.0
const PATROL_SPAWN_RANGE := 400.0
const PATROL_ENFORCE_RANGE := 60.0
const PATROL_FINE := 200
const PATROL_REP_HIT := 0.12

## Collapse: above this risk the frame can let go at any moment; chance per
## second scales with how far past it risk has climbed.
const COLLAPSE_RISK_FLOOR := 0.55
const COLLAPSE_CHANCE_SCALE := 0.06
const COLLAPSE_DAMAGE_RANGE := 25.0

var _rng := RandomNumberGenerator.new()

## The rival's own APPROACH -> CUT -> COLLECT loop (back to CUT until the frame
## is stripped) -> DEPART, mirroring the player's approach/align/cut/scoop loop
## minus the alignment mini-game.
enum RivalState { APPROACH, CUT, COLLECT, DEPART }

var _rival_timer := 0.0
var _rival_contact_id := -1
var _rival_state: RivalState = RivalState.APPROACH
var _strip_timer := 0.0
## The piece the rival just cut and is closing on, -1 when not in COLLECT.
var _rival_piece_id := -1
var _rival_collect_timer := 0.0

var _patrol_timer := 0.0
var _patrol_contact_id := -1
var _patrol_enforced := false
var _warned_2min := false
var _warned_30s := false

var _collapsed := false


func _ready() -> void:
	_rng.randomize()
	reset_run()


## MarketSystem, on jumping back to the claim: fresh timers, clear spawns.
func reset_run() -> void:
	if _rival_contact_id != -1:
		GameState.remove_contact(_rival_contact_id)
	if _patrol_contact_id != -1:
		GameState.remove_contact(_patrol_contact_id)
	_rival_contact_id = -1
	_patrol_contact_id = -1
	_rival_state = RivalState.APPROACH
	_rival_piece_id = -1
	_rival_collect_timer = 0.0
	_rival_timer = _rng.randf_range(RIVAL_SPAWN_MIN, RIVAL_SPAWN_MAX)
	_strip_timer = RIVAL_STRIP_INTERVAL
	_patrol_timer = _rng.randf_range(PATROL_WINDOW_MIN, PATROL_WINDOW_MAX)
	_patrol_enforced = false
	_warned_2min = false
	_warned_30s = false
	_collapsed = false


func _physics_process(delta: float) -> void:
	if GameState.run_phase != "ON_SITE":
		return
	_update_rival(delta)
	_update_patrol(delta)
	_update_collapse(delta)


func _update_rival(delta: float) -> void:
	var wreck_pos: Vector3 = GameState.wreck["position"]
	if _rival_contact_id == -1:
		_rival_timer -= delta
		if _rival_timer <= 0.0:
			var bearing := _rng.randf_range(0.0, TAU)
			var spawn := wreck_pos + Vector3(cos(bearing), _rng.randf_range(-0.2, 0.2),
					sin(bearing)) * RIVAL_SPAWN_RANGE
			_rival_contact_id = GameState.register_contact(
					"RIVAL CUTTER", spawn, true, SHIP_CONTACT_RADIUS, "RIVAL")
			_rival_state = RivalState.APPROACH
			GameState.post_comms("SENSORS",
					"NEW CONTACT — RIVAL CUTTER CLOSING ON THE WRECK")
		return
	var contact := GameState.get_contact(_rival_contact_id)
	if contact.is_empty():
		_rival_contact_id = -1
		return
	match _rival_state:
		RivalState.APPROACH:
			_update_rival_approach(contact, wreck_pos, delta)
		RivalState.CUT:
			_update_rival_cut(contact, wreck_pos, delta)
		RivalState.COLLECT:
			_update_rival_collect(contact, delta)
		RivalState.DEPART:
			_update_rival_depart(contact, wreck_pos, delta)


## Close on the wreck; once in reach, start the cutting cadence.
func _update_rival_approach(contact: Dictionary, wreck_pos: Vector3, delta: float) -> void:
	var to_wreck: Vector3 = wreck_pos - contact["position"]
	contact["heading"] = to_wreck.normalized()
	if to_wreck.length() > RIVAL_WORK_RANGE:
		contact["position"] += to_wreck.normalized() * RIVAL_SPEED * delta
		return
	_strip_timer = RIVAL_STRIP_INTERVAL
	_rival_state = RivalState.CUT


## Station-keep on the wreck; every RIVAL_STRIP_INTERVAL it severs a member —
## same physics/yield SalvageSystem gives our own cuts, no crosshair for the
## rival — then has to go physically retrieve that piece (COLLECT) before it
## can start the next one. Nothing left to strip: burn for home.
func _update_rival_cut(contact: Dictionary, wreck_pos: Vector3, delta: float) -> void:
	var to_wreck: Vector3 = wreck_pos - contact["position"]
	# Station-keeping, but nose on the work: the torch points at what it is cutting.
	contact["heading"] = to_wreck.normalized()
	if to_wreck.length() > RIVAL_WORK_RANGE:
		_rival_state = RivalState.APPROACH
		return
	_strip_timer -= delta
	if _strip_timer > 0.0:
		return
	var result := SalvageSystem.rival_strip_member()
	if result.is_empty():
		_rival_state = RivalState.DEPART
		GameState.post_comms("SENSORS", "RIVAL CUTTER BURNING OUT OF THE VOLUME")
		return
	GameState.post_comms("SALVAGE",
			"RIVAL CUTTER FLARE — %s STRIPPED BY RIVAL" % result["name"])
	# The flare that comms line names, for anything drawing the volume: the rival's
	# hull, and the piece it has just taken off. A cue, not a cause — the cut is
	# already resolved above, and nothing here waits on it being seen.
	var flare := GameState.get_salvage_piece(int(result["piece_id"]))
	if not flare.is_empty():
		GameState.rival_cut_fired.emit(contact["position"],
				(flare["transform"] as Transform3D).origin)
	_rival_piece_id = result["piece_id"]
	_rival_collect_timer = 0.0
	_rival_state = RivalState.COLLECT


## Close on the piece it just cut and hold within RIVAL_COLLECT_RANGE for
## RIVAL_COLLECT_TIME to claim it. Pieces are free-for-all — if the player
## scoops it first, the piece vanishes out from under the rival and it just
## resumes cutting the next member instead.
func _update_rival_collect(contact: Dictionary, delta: float) -> void:
	var piece := GameState.get_salvage_piece(_rival_piece_id)
	if piece.is_empty():
		_rival_piece_id = -1
		_strip_timer = RIVAL_STRIP_INTERVAL
		_rival_state = RivalState.CUT
		return
	var pos: Vector3 = (piece["transform"] as Transform3D).origin
	var to_piece: Vector3 = pos - contact["position"]
	var dist := to_piece.length()
	contact["heading"] = to_piece.normalized()
	if dist > RIVAL_COLLECT_RANGE:
		contact["position"] += to_piece.normalized() * RIVAL_SPEED * delta
		_rival_collect_timer = 0.0
		return
	_rival_collect_timer += delta
	if _rival_collect_timer < RIVAL_COLLECT_TIME:
		return
	DriftSystem.collect_for_rival(_rival_piece_id)
	GameState.post_comms("SALVAGE", "RIVAL CUTTER RECOVERED ITS SALVAGE")
	_rival_piece_id = -1
	_strip_timer = RIVAL_STRIP_INTERVAL
	_rival_state = RivalState.CUT


## Burn away from the wreck; drop off the scope once clear and re-arm the spawn
## window for a future rival.
func _update_rival_depart(contact: Dictionary, wreck_pos: Vector3, delta: float) -> void:
	var away: Vector3 = (contact["position"] - wreck_pos).normalized()
	contact["heading"] = away
	contact["position"] += away * RIVAL_SPEED * 2.0 * delta
	if contact["position"].distance_to(wreck_pos) > PATROL_SPAWN_RANGE:
		GameState.remove_contact(_rival_contact_id)
		_rival_contact_id = -1
		_rival_state = RivalState.APPROACH
		_rival_timer = _rng.randf_range(RIVAL_SPAWN_MIN, RIVAL_SPAWN_MAX)


func _update_patrol(delta: float) -> void:
	if _patrol_contact_id == -1:
		_patrol_timer -= delta
		if _patrol_timer <= 120.0 and not _warned_2min:
			_warned_2min = true
			GameState.post_comms("HARBOR",
					"%s PATROL WINDOW CLOSING — 2 MINUTES" % MarketSystem.claim_faction())
		if _patrol_timer <= 30.0 and not _warned_30s:
			_warned_30s = true
			GameState.post_comms("HARBOR", "PATROL INBOUND — CLEAR THE CLAIM")
		if _patrol_timer <= 0.0:
			var wreck_pos: Vector3 = GameState.wreck["position"]
			var bearing := _rng.randf_range(0.0, TAU)
			var spawn := wreck_pos + Vector3(cos(bearing), 0.1, sin(bearing)) \
					* PATROL_SPAWN_RANGE
			_patrol_contact_id = GameState.register_contact(
					"%s PATROL" % MarketSystem.claim_faction(), spawn, true,
					SHIP_CONTACT_RADIUS, "PATROL")
			GameState.post_comms("SENSORS", "PATROL CONTACT ON INTERCEPT VECTOR")
		return
	var contact := GameState.get_contact(_patrol_contact_id)
	if contact.is_empty():
		_patrol_contact_id = -1
		return
	var ship_pos: Vector3 = GameState.local_ship()["transform"].origin
	var to_ship: Vector3 = ship_pos - contact["position"]
	# Facing the ship whether it is still closing or already holding at range.
	contact["heading"] = to_ship.normalized()
	# Running dark (a master electrical switch off) shrinks the range at which the
	# patrol can pick the ship out and enforce the claim.
	var enforce_range := PATROL_ENFORCE_RANGE * GameState.passive_signature()
	if to_ship.length() > enforce_range:
		contact["position"] += to_ship.normalized() * PATROL_SPEED * delta
	elif not _patrol_enforced:
		# Caught working the claim: fine + reputation hit with the holder.
		_patrol_enforced = true
		var faction := MarketSystem.claim_faction()
		GameState.credits = maxi(GameState.credits - PATROL_FINE, 0)
		GameState.credits_changed.emit(GameState.credits)
		if GameState.reputation.has(faction):
			GameState.reputation[faction] = clampf(
					GameState.reputation[faction] - PATROL_REP_HIT, 0.0, 1.0)
			GameState.reputation_changed.emit()
		GameState.post_comms("HARBOR",
				"CLAIM ENFORCEMENT — %d CR FINE LOGGED, %s STANDING REDUCED" % [
					PATROL_FINE, faction])


func _update_collapse(delta: float) -> void:
	if _collapsed:
		return
	var risk: float = GameState.structural_risk
	if risk <= COLLAPSE_RISK_FLOOR:
		return
	var chance_per_s := (risk - COLLAPSE_RISK_FLOOR) * COLLAPSE_CHANCE_SCALE
	if _rng.randf() > chance_per_s * delta:
		return
	_collapsed = true
	SalvageSystem.trigger_collapse()
	if SalvageSystem.wreck_distance() < COLLAPSE_DAMAGE_RANGE:
		var sections: Dictionary = GameState.local_ship()["hull_sections"]
		var keys: Array = sections.keys()
		for i in 2:
			var section: String = keys[_rng.randi_range(0, keys.size() - 1)]
			sections[section] = maxf(
					sections[section] - _rng.randf_range(0.1, 0.25), 0.05)
		GameState.hull_sections_changed.emit()
		GameState.post_comms("SYSTEM", "DEBRIS IMPACT — HULL SECTIONS DAMAGED")
