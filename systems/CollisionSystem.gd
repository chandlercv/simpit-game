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
## Legacy derelict-frame collision radius. The wreck is no longer a single
## sphere — it collides through its per-member hulls (Wreck.gd, tagged `wreck`
## obstacles) and the approach parks off the surface (wreck_surface_distance).
## Kept only as the reference figure ShipColliderBake still prints against the
## standoff when validating the ship capsule.
const WRECK_RADIUS := 4.0
## Below this closing speed (m/s) contact only separates the ship; no damage, so
## slow station-keeping drift against a body isn't punished.
const IMPACT_SPEED_FLOOR := 1.5
## Fraction of the inward velocity returned as a bounce.
const RESTITUTION := 0.3
## Nominal ship mass for the ship-vs-movable-body impulse below — heavy enough
## that a light salvage piece/debris chunk takes a believable kick without the
## ship itself needing a real mass in its own bounce (that formula, above,
## deliberately stays as before: infinite-mass-target shorthand).
const SHIP_MASS := 500.0
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
	# Collisions bite wherever the ship is actually being flown — at the claim and
	# in the station's docking pattern, where clipping a hab drum or a tug is the
	# whole reason the lane is tight.
	if not GameState.flight_active():
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
		var contact := _test_body(ship_a, ship_b, ship_radius, body, xform.basis.z)
		if contact.is_empty():
			continue
		var normal: Vector3 = contact["normal"]
		var closing := -velocity.dot(normal)  # +ve = driving into the body
		origin += normal * float(contact["depth"])  # push out of penetration
		if closing > 0.0:
			velocity += normal * closing * (1.0 + RESTITUTION)  # reflect inward part
			_impart_body_velocity(body, normal, closing)
		moved = true
		_apply_impact(body, xform, normal, closing)
	if moved:
		xform.origin = origin
		ship["transform"] = xform
		ship["velocity"] = velocity
		# A bounce during an active approach means something is on the path (rival/
		# debris) — the kinematic autopilot can't model the contact and would drive
		# straight back in and grind, so hand control back to the pilot.
		if GameState.approach_state != "HOLDING":
			SalvageSystem.abort_approach_on_collision()
	_resolve_movable_pairs()


## Union of solid bodies this frame. Everything solid — the wreck's per-member
## hulls, the cosmetic debris chunks, and any moving ship — lives in
## GameState.obstacles / .contacts; the wreck's members are just obstacles tagged
## `wreck` (registered by Wreck.gd, tight hulls). The wreck/debris sensor blips
## carry no radius, so they aren't double-counted here. Each body is a segment +
## radius (spheres set a == b), or a `hull` point cloud tested tight by GJK.
func _collidables() -> Array[Dictionary]:
	var bodies: Array[Dictionary] = []
	for obstacle: Dictionary in GameState.obstacles:
		var pos: Vector3 = obstacle["position"]
		# `a`/`b`/`radius` double as the broadphase bounding sphere; `hull`, when
		# present, is the tight convex point cloud the GJK test uses. `mass` > 0
		# marks the body movable (a drifting salvage piece or a knocked debris
		# chunk); `src` is the live obstacle dict so a ship impact can write an
		# impulse straight into its "vel" for the owning system to integrate.
		bodies.append({
			"key": "o%d" % obstacle["id"], "name": obstacle["name"],
			"a": pos, "b": pos, "radius": obstacle["radius"],
			"hull": obstacle.get("hull", PackedVector3Array()),
			"mass": obstacle.get("mass", 0.0), "src": obstacle,
		})
	for contact: Dictionary in GameState.contacts:
		if contact.get("radius", 0.0) > 0.0:
			var pos: Vector3 = contact["position"]
			bodies.append({
				"key": "c%d" % contact["id"], "name": contact["name"],
				"a": pos, "b": pos, "radius": contact["radius"],
			})
	return bodies


## One body's overlap test. Returns {} for no contact, else {normal, depth} with
## `normal` pointing from the body out toward the ship and `depth` the push-out
## distance. A body carrying a non-empty `hull` point cloud is tested tight
## (GJK, ship segment vs convex hull) behind a bounding-sphere broadphase; every
## other body is the segment+radius capsule test that covers spheres and the
## wreck. `fallback` is the separation direction for an exact overlap where the
## real contact normal is undefined.
func _test_body(ship_a: Vector3, ship_b: Vector3, ship_radius: float,
		body: Dictionary, fallback: Vector3) -> Dictionary:
	var hull: PackedVector3Array = body.get("hull", PackedVector3Array())
	if not hull.is_empty():
		# Broadphase: reject on the bounding sphere before the per-vertex GJK.
		var near: Vector3 = _closest_points_between_segments(
				ship_a, ship_b, body["a"], body["b"])[0]
		if near.distance_to(body["a"]) >= ship_radius + float(body["radius"]):
			return {}
		var gjk := _gjk_segment_hull(ship_a, ship_b, hull)
		var dist: float = gjk["dist"]
		if dist >= ship_radius:
			return {}
		var normal: Vector3 = gjk["normal"] if not gjk["inside"] and dist > 0.0001 \
				else fallback
		return {"normal": normal, "depth": ship_radius - dist}
	var closest := _closest_points_between_segments(ship_a, ship_b, body["a"], body["b"])
	var min_sep: float = ship_radius + float(body["radius"])
	var separation: Vector3 = closest[0] - closest[1]
	var dist := separation.length()
	if dist >= min_sep:
		return {}
	var normal := separation.normalized() if dist > 0.001 else fallback
	return {"normal": normal, "depth": min_sep - dist}


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


## Kick a movable body (a drifting salvage piece, a knocked debris chunk) on
## ship contact. The ship's own bounce above deliberately keeps its old
## infinite-target-mass shorthand regardless of what it hit; this is the
## separate, additive reaction on the body's side, scaled down as its mass
## approaches the ship's nominal SHIP_MASS so a heavy body barely moves.
func _impart_body_velocity(body: Dictionary, normal: Vector3, closing: float) -> void:
	var mass: float = body.get("mass", 0.0)
	if mass <= 0.0:
		return
	var src: Dictionary = body["src"]
	var frac := SHIP_MASS / (SHIP_MASS + mass)
	src["vel"] = (src.get("vel", Vector3.ZERO) as Vector3) \
			- normal * closing * (1.0 + RESTITUTION) * frac


## Movable bodies (salvage pieces, knocked debris) can also knock each other —
## a sphere-sphere pass over just that subset, separate from the ship-vs-body
## test above (which still uses the tight hull/capsule test where a hull is
## present). Kept to spheres: these bodies are constantly translating, so
## baking/re-transforming a hull for this pass isn't worth it.
func _resolve_movable_pairs() -> void:
	var movable: Array[Dictionary] = []
	for obstacle: Dictionary in GameState.obstacles:
		if float(obstacle.get("mass", 0.0)) > 0.0:
			movable.append(obstacle)
	for i in movable.size():
		for j in range(i + 1, movable.size()):
			_resolve_pair(movable[i], movable[j])


## Standard impulse-based sphere response: separate along the contact normal
## (split by inverse mass, so the lighter body gives way more) and exchange the
## closing part of their relative velocity, damped by RESTITUTION. `a`/`b` are
## the live obstacle dicts (Dictionaries are references), written in place.
func _resolve_pair(a: Dictionary, b: Dictionary) -> void:
	var pos_a: Vector3 = a["position"]
	var pos_b: Vector3 = b["position"]
	var min_sep: float = float(a["radius"]) + float(b["radius"])
	var sep: Vector3 = pos_a - pos_b
	var dist := sep.length()
	if dist >= min_sep:
		return
	var normal := sep.normalized() if dist > 0.0001 else Vector3.UP
	var inv_a := 1.0 / float(a["mass"])
	var inv_b := 1.0 / float(b["mass"])
	var total_inv := inv_a + inv_b
	var pen := min_sep - dist
	a["position"] = pos_a + normal * pen * (inv_a / total_inv)
	b["position"] = pos_b - normal * pen * (inv_b / total_inv)
	var vel_a: Vector3 = a.get("vel", Vector3.ZERO)
	var vel_b: Vector3 = b.get("vel", Vector3.ZERO)
	var rel := (vel_a - vel_b).dot(normal)
	if rel >= 0.0:
		return  # already separating
	var j := -(1.0 + RESTITUTION) * rel / total_inv
	a["vel"] = vel_a + normal * (j * inv_a)
	b["vel"] = vel_b - normal * (j * inv_b)


## Which hull section faced the impact: transform the toward-body direction into
## ship-local axes (-Z fore, +X starboard, +Y up) and pick the dominant one.
## Returns BOW/DRIVE/PORT/STBD/CORE only — never AFT. AFT shares DRIVE's rear
## bearing from the centroid, and a direction-only test can't separate two
## sections on the same axis, so rear impacts intentionally tag DRIVE (the
## exposed rearmost block). AFT is an interior section that degrades only via
## collapse/debris (see ThreatSystem._update_collapse).
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


## --- Segment vs convex hull (GJK) -----------------------------------------
## Tight collision for the flat/awkward debris chunks a bounding sphere or
## capsule can't hug (plate, L-bent pipe). Each such body carries a world-space
## convex point cloud (baked from the mesh, retumbled each frame by DebrisField)
## and the ship's capsule spine is tested against it here. GJK needs only the
## support point — the hull vertex farthest along a direction — so a raw vertex
## cloud is enough; no face/edge structure is required.


## Test seam + gameplay entry: closest distance from the ship-style segment
## [sa,sb] to the convex hull of `points`. 0.0 when the segment core is inside.
func hull_distance(sa: Vector3, sb: Vector3, points: PackedVector3Array) -> float:
	return _gjk_segment_hull(sa, sb, points)["dist"]


## Closest distance from the ship capsule spine [sa,sb] to any intact wreck
## member's hull, or INF when no wreck hulls are registered (e.g. a headless run
## with no 3D scene — the approach autopilot then falls back to a centre-based
## standoff). SalvageSystem uses this to park a fixed gap off the frame surface
## regardless of approach angle, instead of a single radius around its centre.
func wreck_surface_distance(sa: Vector3, sb: Vector3) -> float:
	var best := INF
	for obstacle: Dictionary in GameState.obstacles:
		if not obstacle.get("wreck", false):
			continue
		var hull: PackedVector3Array = obstacle.get("hull", PackedVector3Array())
		if not hull.is_empty():
			best = minf(best, _gjk_segment_hull(sa, sb, hull)["dist"])
	return best


## GJK distance between segment [sa,sb] and the convex hull of `points`. Returns
## {dist, normal, inside}: `normal` is the unit (segment − hull) direction, i.e.
## it points from the hull out toward the ship, and is what the caller pushes
## along. On penetration `dist` is 0, `inside` true, and `normal` zero (the
## caller substitutes its fallback axis).
func _gjk_segment_hull(sa: Vector3, sb: Vector3, points: PackedVector3Array) -> Dictionary:
	if points.is_empty():
		return {"dist": INF, "normal": Vector3.ZERO, "inside": false}
	const EPS := 0.0000001
	var simplex: Array[Vector3] = [_mink_support(sa, sb, points, Vector3(1, 0, 0))]
	var v: Vector3 = simplex[0]
	for _iter in 32:
		var vv := v.length_squared()
		if vv < EPS:
			return {"dist": 0.0, "normal": Vector3.ZERO, "inside": true}
		var w := _mink_support(sa, sb, points, -v)
		# Converged: the support toward the origin can't get past the current
		# closest point, so |v| is the true distance.
		if vv - v.dot(w) <= EPS * vv:
			break
		var dup := false
		for sp: Vector3 in simplex:
			if sp.distance_squared_to(w) < EPS:
				dup = true
				break
		if dup:
			break
		simplex.append(w)
		var sub := _closest_sub(simplex)
		v = sub["point"]
		var kept: Array[Vector3] = []
		for k: int in sub["ids"]:
			kept.append(simplex[k])
		simplex = kept
		if simplex.size() == 4:  # origin enclosed by the simplex: penetration
			return {"dist": 0.0, "normal": Vector3.ZERO, "inside": true}
	var dist := v.length()
	return {
		"dist": dist,
		"normal": v / dist if dist > EPS else Vector3.ZERO,
		"inside": false,
	}


## Support of the Minkowski difference (segment ⊖ hull) along `d`: the segment
## point farthest along +d minus the hull point farthest along −d.
func _mink_support(sa: Vector3, sb: Vector3, points: PackedVector3Array,
		d: Vector3) -> Vector3:
	var seg := sa if sa.dot(d) >= sb.dot(d) else sb
	var hull := points[0]
	var best := hull.dot(-d)
	for i in range(1, points.size()):
		var dp := points[i].dot(-d)
		if dp > best:
			best = dp
			hull = points[i]
	return seg - hull


## Closest point on the current simplex (1–4 Minkowski points) to the origin,
## plus the indices of the vertices that feature keeps — GJK reduces to those.
func _closest_sub(s: Array) -> Dictionary:
	match s.size():
		1:
			return {"point": s[0], "ids": [0]}
		2:
			return _sub_seg(s[0], s[1])
		3:
			return _sub_tri(s[0], s[1], s[2])
		_:
			return _sub_tetra(s[0], s[1], s[2], s[3])


func _sub_seg(a: Vector3, b: Vector3) -> Dictionary:
	var ab := b - a
	var denom := ab.dot(ab)
	if denom < 1e-12:
		return {"point": a, "ids": [0]}
	var t := -a.dot(ab) / denom
	if t <= 0.0:
		return {"point": a, "ids": [0]}
	if t >= 1.0:
		return {"point": b, "ids": [1]}
	return {"point": a + ab * t, "ids": [0, 1]}


## Closest point on triangle abc to the origin (Ericson RTCD §5.1.5, query point
## = origin), with the retained vertex indices.
func _sub_tri(a: Vector3, b: Vector3, c: Vector3) -> Dictionary:
	var ab := b - a
	var ac := c - a
	var d1 := ab.dot(-a)
	var d2 := ac.dot(-a)
	if d1 <= 0.0 and d2 <= 0.0:
		return {"point": a, "ids": [0]}
	var d3 := ab.dot(-b)
	var d4 := ac.dot(-b)
	if d3 >= 0.0 and d4 <= d3:
		return {"point": b, "ids": [1]}
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return {"point": a + ab * (d1 / (d1 - d3)), "ids": [0, 1]}
	var d5 := ab.dot(-c)
	var d6 := ac.dot(-c)
	if d6 >= 0.0 and d5 <= d6:
		return {"point": c, "ids": [2]}
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return {"point": a + ac * (d2 / (d2 - d6)), "ids": [0, 2]}
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return {"point": b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6))), "ids": [1, 2]}
	var sum := va + vb + vc
	if absf(sum) < 1e-12:  # degenerate (collinear) triangle: fall back to edges
		return _best_edge(a, b, c)
	var denom := 1.0 / sum
	return {"point": a + ab * (vb * denom) + ac * (vc * denom), "ids": [0, 1, 2]}


## Closest of a triangle's three edges to the origin, with global ids — the
## degenerate-triangle escape hatch for _sub_tri.
func _best_edge(a: Vector3, b: Vector3, c: Vector3) -> Dictionary:
	var edges := [[0, 1, a, b], [1, 2, b, c], [0, 2, a, c]]
	var best := {"point": Vector3.ZERO, "ids": []}
	var best_sq := INF
	for e: Array in edges:
		var sub := _sub_seg(e[2], e[3])
		var sq: float = (sub["point"] as Vector3).length_squared()
		if sq < best_sq:
			best_sq = sq
			var ids: Array = []
			for li: int in sub["ids"]:
				ids.append(e[li])
			best = {"point": sub["point"], "ids": ids}
	return best


## Closest point on tetrahedron abcd to the origin, with retained ids. Tests the
## faces the origin lies outside of and keeps the nearest; if the origin is
## outside none, it's enclosed — penetration (ids for all four vertices).
func _sub_tetra(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Dictionary:
	var verts := [a, b, c, d]
	# [v0, v1, v2, opposite] index sets for the four faces.
	var faces := [[0, 1, 2, 3], [0, 2, 3, 1], [0, 3, 1, 2], [1, 3, 2, 0]]
	var best := {"point": Vector3.ZERO, "ids": [0, 1, 2, 3]}
	var best_sq := INF
	var any_outside := false
	for f: Array in faces:
		var p0: Vector3 = verts[f[0]]
		var p1: Vector3 = verts[f[1]]
		var p2: Vector3 = verts[f[2]]
		if not _origin_outside_face(p0, p1, p2, verts[f[3]]):
			continue
		any_outside = true
		var sub := _sub_tri(p0, p1, p2)
		var sq: float = (sub["point"] as Vector3).length_squared()
		if sq < best_sq:
			best_sq = sq
			var ids: Array = []
			for li: int in sub["ids"]:
				ids.append(f[li])
			best = {"point": sub["point"], "ids": ids}
	if not any_outside:  # origin inside the tetra
		return {"point": Vector3.ZERO, "ids": [0, 1, 2, 3]}
	return best


## Is the origin on the far side of plane (a,b,c) from vertex `opp`?
func _origin_outside_face(a: Vector3, b: Vector3, c: Vector3, opp: Vector3) -> bool:
	var n := (b - a).cross(c - a)
	return n.dot(-a) * n.dot(opp - a) < 0.0
