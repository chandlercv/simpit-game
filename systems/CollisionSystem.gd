extends Node
## Consequences for running into things.
##
## Space flight in this game is hand-integrated: SalvageSystem writes the ship's
## transform/velocity into GameState each frame and there are no Godot physics
## bodies (Ship.gd only mirrors the transform). So collision is a
## post-integration proximity pass — after the ship has moved for the frame and
## after ThreatSystem has moved its contacts, we test the ship sphere against
## every solid body (the wreck frame, the cosmetic debris chunks, and moving
## ships like the rival/patrol). On overlap the ship is pushed back to the
## surface (no tunnelling), the inward velocity is reflected/bled, and the hull
## section that faced the hit loses integrity proportional to closing speed.
## Runs last in the autoload order (after ThreatSystem) so it reads the frame's
## final positions.
##
## Damage today is recoverable hull wear, surfaced on HullHeatmap and the comms
## log exactly like ThreatSystem's collapse damage. `_apply_impact` is the single
## consequence hook, deliberately factored so crippling (system-degrading) damage
## and a destruction / game-over path can be layered on there without touching
## the detection pass.

## Ship collision sphere. Kept small enough that SHIP_RADIUS + WRECK_RADIUS
## (7.5) stays inside the matched-approach standoff (CUT_RANGE - 4 = 10, see
## SalvageSystem), so normal cutting never trips a collision — only a manual ram.
const SHIP_RADIUS := 2.5
## Derelict frame collision sphere.
const WRECK_RADIUS := 5.0
## Below this closing speed (m/s) contact only separates the ship; no damage, so
## slow station-keeping drift against a body isn't punished.
const IMPACT_SPEED_FLOOR := 1.5
## Fraction of the inward velocity returned as a bounce.
const RESTITUTION := 0.3
## Hull integrity lost per m/s of closing speed above the floor.
const DAMAGE_PER_SPEED := 0.03
const MAX_IMPACT_DAMAGE := 0.6
## Matches ThreatSystem's collapse floor — sections never read fully dead yet.
const HULL_FLOOR := 0.05
## One damage event per body per window; grinding against a surface at low
## closing speed does almost nothing after the initial hit.
const IMPACT_COOLDOWN := 0.8

## Body key -> seconds of impact cooldown remaining.
var _cooldowns: Dictionary = {}


func _process(delta: float) -> void:
	if GameState.run_phase != "ON_SITE":
		_cooldowns.clear()
		return
	for key: String in _cooldowns.keys():
		_cooldowns[key] -= delta
		if _cooldowns[key] <= 0.0:
			_cooldowns.erase(key)

	var ship: Dictionary = GameState.local_ship()
	var xform: Transform3D = ship["transform"]
	var velocity: Vector3 = ship["velocity"]
	var origin: Vector3 = xform.origin
	var moved := false
	for body: Dictionary in _collidables():
		var min_sep: float = SHIP_RADIUS + body["radius"]
		var separation: Vector3 = origin - body["position"]
		var dist := separation.length()
		if dist >= min_sep:
			continue
		# Points from the body out toward the ship; a degenerate exact-overlap
		# falls back to the ship's forward axis so we still separate somewhere.
		var normal := separation.normalized() if dist > 0.001 else xform.basis.z
		var closing := -velocity.dot(normal)  # +ve = driving into the body
		origin = body["position"] + normal * min_sep  # unstick to the surface
		if closing > 0.0:
			velocity += normal * closing * (1.0 + RESTITUTION)  # reflect inward part
		moved = true
		_apply_impact(body, xform, normal, closing)
	if moved:
		xform.origin = origin
		ship["transform"] = xform
		ship["velocity"] = velocity


## Union of solid bodies this frame. The wreck is explicit (always on site); the
## cosmetic chunks come from GameState.obstacles; moving ships come from any
## contact registered with a radius. The wreck/debris sensor blips carry no
## radius, so they aren't double-counted here.
func _collidables() -> Array[Dictionary]:
	var bodies: Array[Dictionary] = []
	if not GameState.wreck.is_empty():
		bodies.append({
			"key": "wreck", "name": "WRECK FRAME",
			"position": GameState.wreck["position"], "radius": WRECK_RADIUS,
		})
	for obstacle: Dictionary in GameState.obstacles:
		bodies.append({
			"key": "o%d" % obstacle["id"], "name": obstacle["name"],
			"position": obstacle["position"], "radius": obstacle["radius"],
		})
	for contact: Dictionary in GameState.contacts:
		if contact.get("radius", 0.0) > 0.0:
			bodies.append({
				"key": "c%d" % contact["id"], "name": contact["name"],
				"position": contact["position"], "radius": contact["radius"],
			})
	return bodies


## Consequence hook. TODAY: recoverable, speed-scaled hull wear. FUTURE seam:
## branch here on severity / section loss for crippling damage (degrade a power
## channel) and destruction (emit a game-over via a new run phase) — the
## detection pass above does not need to change.
func _apply_impact(body: Dictionary, xform: Transform3D, normal: Vector3,
		closing: float) -> void:
	if _cooldowns.has(body["key"]):
		return
	if closing < IMPACT_SPEED_FLOOR:
		return  # gentle contact: unstuck above, no damage
	_cooldowns[body["key"]] = IMPACT_COOLDOWN
	var dmg := minf((closing - IMPACT_SPEED_FLOOR) * DAMAGE_PER_SPEED, MAX_IMPACT_DAMAGE)
	var section := _impact_section(xform, normal)
	var sections: Dictionary = GameState.local_ship()["hull_sections"]
	sections[section] = maxf(sections[section] - dmg, HULL_FLOOR)
	GameState.hull_sections_changed.emit()
	GameState.hull_impact.emit(section, dmg)
	GameState.post_comms("SYSTEM", "COLLISION — %s IMPACT, %s HULL -%d%%" % [
		body["name"], section, roundi(dmg * 100.0)])


## Which hull section faced the impact: transform the toward-body direction into
## ship-local axes (-Z fore, +X starboard, +Y up) and pick the dominant one.
func _impact_section(xform: Transform3D, normal: Vector3) -> String:
	var local := xform.basis.inverse() * (-normal)
	var ax := absf(local.x)
	var ay := absf(local.y)
	var az := absf(local.z)
	if az >= ax and az >= ay:
		return "BOW" if local.z < 0.0 else "DRIVE"
	if ax >= ay:
		return "STBD" if local.x > 0.0 else "PORT"
	return "CORE"
