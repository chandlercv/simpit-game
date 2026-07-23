extends Node
## Consequences for running into things.
##
## Space flight in this game is hand-integrated: SalvageSystem writes the ship's
## transform/velocity into GameState each frame and there are no Godot physics
## bodies (Ship.gd only mirrors the transform). So collision is a
## post-integration proximity pass — after the ship has moved for the frame and
## after ThreatSystem has moved its contacts, we test the ship against every
## solid body (the wreck frame, the cosmetic debris chunks, and moving ships like
## the rival/patrol). On overlap the ship is pushed out of penetration (no
## tunnelling), the inward velocity is reflected/bled, and the hull section that
## faced the hit loses integrity proportional to closing speed. Runs last in the
## autoload order (after ThreatSystem) so it reads the frame's final positions.
##
## The ship is a CAPSULE (two local endpoints + radius, from ShipDefinition), so
## it fits the elongated hull and — because the endpoints are ship-local and
## transformed by the basis — the volume follows the model instead of sitting on
## the transform origin. A sphere is just the degenerate capsule (A == B), so
## every body is treated as a (possibly zero-length) segment + radius and one
## segment-vs-segment test covers ship-vs-sphere today and capsule-vs-capsule
## (oriented rivals, tailored wreck) later with no change to this pass.
##
## Damage today is recoverable hull wear, surfaced on HullHeatmap and the comms
## log exactly like ThreatSystem's collapse damage. `_apply_impact` is the single
## consequence hook, deliberately factored so crippling (system-degrading) damage
## and a destruction / game-over path can be layered on there without touching
## the detection pass.

## Fallback ship radius when a ship def has no baked capsule (A == B == 0).
const DEFAULT_SHIP_RADIUS := 2.5
## Derelict frame collision sphere. Kept small enough that the ship's forward
## reach + WRECK_RADIUS stays inside the matched-approach standoff
## (CUT_RANGE - 4 = 10, see SalvageSystem), so normal cutting never trips a
## collision — only a manual ram. The offset capsule reaches farther from the
## origin than the old origin-centred sphere did, so this is 4.0 (was 5.0);
## ShipColliderBake prints ship_reach() + WRECK_RADIUS against the standoff.
const WRECK_RADIUS := 4.0
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
	var ship_radius := _ship_radius()
	var moved := false
	for body: Dictionary in _collidables():
		# Rebuild the ship capsule from the running origin so multiple bodies in
		# one frame push the ship consistently (basis is fixed for the frame).
		var ship_a: Vector3 = origin + xform.basis * GameState.ship_def.collision_a
		var ship_b: Vector3 = origin + xform.basis * GameState.ship_def.collision_b
		var closest := _closest_points_between_segments(
				ship_a, ship_b, body["a"], body["b"])
		var on_ship: Vector3 = closest[0]
		var on_body: Vector3 = closest[1]
		var min_sep: float = ship_radius + body["radius"]
		var separation: Vector3 = on_ship - on_body
		var dist := separation.length()
		if dist >= min_sep:
			continue
		# Points from the body out toward the ship; a degenerate exact-overlap
		# falls back to the ship's forward axis so we still separate somewhere.
		var normal := separation.normalized() if dist > 0.001 else xform.basis.z
		var closing := -velocity.dot(normal)  # +ve = driving into the body
		origin += normal * (min_sep - dist)  # push out of penetration
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
## radius, so they aren't double-counted here. Each body is a segment + radius;
## spheres set a == b (a point), leaving room for oriented capsules later.
func _collidables() -> Array[Dictionary]:
	var bodies: Array[Dictionary] = []
	if not GameState.wreck.is_empty():
		var wreck_pos: Vector3 = GameState.wreck["position"]
		bodies.append({
			"key": "wreck", "name": "WRECK FRAME",
			"a": wreck_pos, "b": wreck_pos, "radius": WRECK_RADIUS,
		})
	for obstacle: Dictionary in GameState.obstacles:
		var pos: Vector3 = obstacle["position"]
		bodies.append({
			"key": "o%d" % obstacle["id"], "name": obstacle["name"],
			"a": pos, "b": pos, "radius": obstacle["radius"],
		})
	for contact: Dictionary in GameState.contacts:
		if contact.get("radius", 0.0) > 0.0:
			var pos: Vector3 = contact["position"]
			bodies.append({
				"key": "c%d" % contact["id"], "name": contact["name"],
				"a": pos, "b": pos, "radius": contact["radius"],
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


## Baked capsule radius, or the fallback sphere radius for an unbaked ship def.
func _ship_radius() -> float:
	var r: float = GameState.ship_def.collision_radius
	return r if r > 0.0 else DEFAULT_SHIP_RADIUS


## How far the ship capsule reaches from the transform origin (worst case, any
## direction). Used to size WRECK_RADIUS/standoff and reported by the bake tool.
func ship_reach() -> float:
	var def := GameState.ship_def
	return maxf(def.collision_a.length(), def.collision_b.length()) + _ship_radius()


## Closest points between segments p1q1 and p2q2 (Ericson, Real-Time Collision
## Detection §5.1.9). Returns [point_on_seg1, point_on_seg2]; handles either or
## both segments being degenerate (a point), which is how spheres/point-bodies
## flow through the same test.
func _closest_points_between_segments(p1: Vector3, q1: Vector3,
		p2: Vector3, q2: Vector3) -> Array:
	var d1 := q1 - p1  # direction of segment 1
	var d2 := q2 - p2  # direction of segment 2
	var r := p1 - p2
	var a := d1.dot(d1)  # squared length of segment 1
	var e := d2.dot(d2)  # squared length of segment 2
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 0.000001 and e <= 0.000001:
		return [p1, p2]  # both degenerate: two points
	if a <= 0.000001:
		# Segment 1 degenerate.
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 0.000001:
			# Segment 2 degenerate.
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom > 0.000001:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return [p1 + d1 * s, p2 + d2 * t]
