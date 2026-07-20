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
## Collision radius for the rival/patrol ships (they're solid to ram into).
const SHIP_CONTACT_RADIUS := 4.0

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

var _rival_timer := 0.0
var _rival_contact_id := -1
var _rival_departing := false
var _strip_timer := 0.0

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
	_rival_departing = false
	_rival_timer = _rng.randf_range(RIVAL_SPAWN_MIN, RIVAL_SPAWN_MAX)
	_strip_timer = RIVAL_STRIP_INTERVAL
	_patrol_timer = _rng.randf_range(PATROL_WINDOW_MIN, PATROL_WINDOW_MAX)
	_patrol_enforced = false
	_warned_2min = false
	_warned_30s = false
	_collapsed = false


func _process(delta: float) -> void:
	if GameState.run_phase != "ON_SITE":
		return
	_update_rival(delta)
	_update_patrol(delta)
	_update_collapse(delta)


func _update_rival(delta: float) -> void:
	var wreck_pos: Vector3 = GameState.wreck["position"]
	if _rival_contact_id == -1:
		_rival_timer -= delta
		if _rival_timer <= 0.0 and not _rival_departing:
			var bearing := _rng.randf_range(0.0, TAU)
			var spawn := wreck_pos + Vector3(cos(bearing), _rng.randf_range(-0.2, 0.2),
					sin(bearing)) * RIVAL_SPAWN_RANGE
			_rival_contact_id = GameState.register_contact(
					"RIVAL CUTTER", spawn, true, SHIP_CONTACT_RADIUS)
			GameState.post_comms("SENSORS",
					"NEW CONTACT — RIVAL CUTTER CLOSING ON THE WRECK")
		return
	var contact := GameState.get_contact(_rival_contact_id)
	if contact.is_empty():
		_rival_contact_id = -1
		return
	if _rival_departing:
		# Burn away from the wreck; drop off the scope once clear.
		var away: Vector3 = (contact["position"] - wreck_pos).normalized()
		contact["position"] += away * RIVAL_SPEED * 2.0 * delta
		if contact["position"].distance_to(wreck_pos) > PATROL_SPAWN_RANGE:
			GameState.remove_contact(_rival_contact_id)
			_rival_contact_id = -1
			_rival_departing = false
			# Re-arm the spawn window so a fresh rival doesn't appear next frame.
			_rival_timer = _rng.randf_range(RIVAL_SPAWN_MIN, RIVAL_SPAWN_MAX)
		return
	var to_wreck: Vector3 = wreck_pos - contact["position"]
	if to_wreck.length() > RIVAL_WORK_RANGE:
		contact["position"] += to_wreck.normalized() * RIVAL_SPEED * delta
		return
	# On the wreck: strip a member every interval until nothing is left.
	_strip_timer -= delta
	if _strip_timer > 0.0:
		return
	_strip_timer = RIVAL_STRIP_INTERVAL
	var member := SalvageSystem.rival_strip_member()
	if member.is_empty():
		_rival_departing = true
		GameState.post_comms("SENSORS", "RIVAL CUTTER BURNING OUT OF THE VOLUME")
	else:
		GameState.post_comms("SALVAGE",
				"RIVAL CUTTER FLARE — %s STRIPPED BY RIVAL" % member["name"])


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
					SHIP_CONTACT_RADIUS)
			GameState.post_comms("SENSORS", "PATROL CONTACT ON INTERCEPT VECTOR")
		return
	var contact := GameState.get_contact(_patrol_contact_id)
	if contact.is_empty():
		_patrol_contact_id = -1
		return
	var ship_pos: Vector3 = GameState.local_ship()["transform"].origin
	var to_ship: Vector3 = ship_pos - contact["position"]
	if to_ship.length() > PATROL_ENFORCE_RANGE:
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
