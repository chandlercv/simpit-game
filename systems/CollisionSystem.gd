extends Node
## Consequences for running into things.
##
## Space flight in this game is hand-integrated: SalvageSystem writes the ship's
## transform/velocity into GameState each physics tick and there are no Godot
## physics bodies (Ship.gd only mirrors the transform). So collision is a
## post-integration proximity pass — after the ship has moved for the tick and
## after ThreatSystem has moved its contacts, we test the ship against every
## solid body (the wreck frame, the cosmetic debris chunks, and moving ships like
## the rival/patrol). On overlap the ship is pushed out of penetration, the
## inward velocity is reflected/bled, and the hull section that faced the hit
## loses integrity proportional to closing speed. Runs last in the autoload order
## (after ThreatSystem) so it reads the tick's final positions.
##
## TUNNELLING is the standing weakness of testing after the fact, and it is not
## hypothetical: at 60 m/s the ship crosses a metre per 60 Hz tick against a hull
## 0.7 m across, and DIRECT law removes the speed governor entirely. So
## resolve_ship() is exposed for ShipMotion to drive per SUB-STEP whenever the
## ship is passing something it could cross inside one tick — path_hazard() is
## what it gates on, and it reports the stretches of the path to sample and how
## finely each — while _physics_process still runs the authoritative pass at the
## end of the tick against everything's final position.
##
## Every mass here is in KILOGRAMS, on the same scale as the ship's own
## (GameState.ship_mass): bodies are massed from their radius at BODY_DENSITY,
## and mass 0 still means immovable. That is what lets a ship-vs-body impulse
## split by mass like any other pair, so ramming a boulder throws the ship and
## ramming a light chunk throws the chunk.
##
## The ship is a CAPSULE (two local endpoints + radius, from ShipDefinition), so
## it fits the elongated hull and — because the endpoints are ship-local and
## transformed by the basis — the volume follows the model instead of sitting on
## the transform origin. A sphere is just the degenerate capsule (A == B), so
## every body is treated as a (possibly zero-length) segment + radius and one
## segment-vs-segment test covers ship-vs-sphere today and capsule-vs-capsule
## (oriented rivals, tailored wreck) later with no change to this pass.
##
## WHY THE NARROWPHASE IS STILL OURS. Delegating segment-vs-hull to
## PhysicsServer3D was evaluated with numbers, not opinion, and rejected. The
## server does work headless, so it was a real option — but this GJK costs
## ~187 us/tick against the whole station and derelict (27 hulls, 691 verts)
## with NO broadphase, i.e. about 1% of a 60 Hz budget, and real ticks pay far
## less because _test_body rejects on the bounding sphere first. Against that,
## the swap wanted a server-mirror layer, hull registration moved from world to
## local space across Wreck/Station/DebrisField, and — the sharp one — server
## queries only resolve after the space has STEPPED, where ours answer the same
## tick a body is registered. Every smoke test that registers a body and asserts
## on it immediately would have had to absorb that latency.
##
## The bargain: we keep the code, so it has to earn the trust a mature library
## would have brought. tools/GjkFuzz.tscn is that payment — property brackets
## plus a differential check against Godot's own convex collision.
##
## REVISIT THIS if a real narrowphase bug ever reaches play again. One escape
## was affordable and is now pinned; a second means the fuzz is not catching
## what this code gets wrong, and the swap should happen instead of a third fix.
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
## Hull integrity lost per m/s of closing speed above the floor.
const DAMAGE_PER_SPEED := 0.03
const MAX_IMPACT_DAMAGE := 0.6
## Matches ThreatSystem's collapse floor — sections never read fully dead yet.
const HULL_FLOOR := 0.05
## One damage event per body per window; grinding against a surface at low
## closing speed does almost nothing after the initial hit.
const IMPACT_COOLDOWN := 0.8
## Ceiling (m/s) on how fast a penetrating body is pushed back out. A body can
## be born deeply overlapping something — a severed piece starts inside the
## frame it was just cut from, and its collision sphere encloses neighbouring
## members a long spar never actually touches — and correcting that in one tick
## is a teleport (measured at 3.96 m for the spine truss). Separating at a bounded
## rate instead reads as the piece easing clear of the hull.
const MAX_SEPARATION_SPEED := 6.0

## Cap on the spin (rad/s) a single contact can impart, so a grind along a
## surface stays a shove and not a spin cycle. A healthy FBW nulls an imparted
## spin in a couple of tenths of a second; a degraded one leaves it with the
## pilot, which is the intended cost.
##
## It is a backstop now rather than the usual outcome: _impact_spin divides by
## the ship's real moments, so a hard knock lands near this figure and a graze
## far below it, where before every contact saturated it identically.
const MAX_IMPART_SPIN := 1.5

## Density (kg/m^3) every movable body in the scene is massed at — debris chunks
## and severed salvage pieces alike, from their bounding radius. One figure so
## the two kinds trade momentum proportionately, and a real one so their masses
## are on the same scale as the ship's (GameState.ship_mass) rather than in units
## of their own.
##
## It is deliberately well under rock. These are hollow slag and shredded
## structure, not solid stone, and at true rock density a three-metre chunk
## outweighs the ship four times over and reads as a wall. Raise it to make the
## field heavier; the ship is 60 t and that is the figure to weigh it against.
const BODY_DENSITY := 500.0

## Body key -> seconds of impact cooldown remaining.
var _cooldowns: Dictionary = {}
## This step's length, for the rate-limited separation below.
var _delta := 0.0


## Mass in kilograms of a movable body of this bounding radius. The one place
## radius becomes mass, so debris and salvage cannot drift onto different scales.
static func body_mass(radius: float) -> float:
	return BODY_DENSITY * (4.0 / 3.0) * PI * radius * radius * radius


func _physics_process(delta: float) -> void:
	# Collisions bite wherever the ship is actually being flown — at the claim and
	# in the station's docking pattern, where clipping a hab drum or a tug is the
	# whole reason the lane is tight.
	if not GameState.flight_active():
		_cooldowns.clear()
		return
	# Cooldown decay is per TICK, not per sub-step. ShipMotion may call
	# resolve_ship several times inside one tick at speed (ShipMotion.step), and
	# ageing the cooldowns once per sub-step would let a single grind register as
	# several separate impacts.
	for key: String in _cooldowns.keys():
		_cooldowns[key] -= delta
		if _cooldowns[key] <= 0.0:
			_cooldowns.erase(key)
	resolve_ship(delta)
	_resolve_movable_bodies(_collidables())


## The ship against every solid body, once. Called at the end of the tick by
## _physics_process — where it reads ThreatSystem's and DriftSystem's final
## positions, which is why this system is ordered last — and additionally by
## ShipMotion once per sub-step whenever the ship is moving fast enough to cross
## a body inside a single tick.
##
## Idempotent by construction: it acts on penetration, and a pass that finds none
## does nothing. So the tick-end call is free after a sub-stepped tick has
## already separated the ship, and the cooldowns above keep one contact from
## being charged as damage twice.
func resolve_ship(delta: float) -> void:
	if not GameState.flight_active():
		return
	_delta = delta

	var ship: Dictionary = GameState.local_ship()
	var xform: Transform3D = ship["transform"]
	var velocity: Vector3 = ship["velocity"]
	var omega: Vector3 = ShipMotion.ship_omega()
	var origin: Vector3 = xform.origin
	var ship_radius := _ship_radius()
	var moved := false
	# Built once and shared with the movable passes below: _collidables()
	# allocates a fresh dict per body, and the static pass needs the same list.
	var bodies := _collidables()
	for body: Dictionary in bodies:
		# Rebuild the ship capsule from the running origin so multiple bodies in
		# one frame push the ship consistently (basis is fixed for the frame).
		var ship_a: Vector3 = origin + xform.basis * GameState.ship_def.collision_a
		var ship_b: Vector3 = origin + xform.basis * GameState.ship_def.collision_b
		var contact := _test_body(ship_a, ship_b, ship_radius, body, xform.basis.z)
		if contact.is_empty():
			continue
		var normal: Vector3 = contact["normal"]
		var closing := -velocity.dot(normal)  # +ve = driving into the body
		# Report every contact, not just the damaging ones. The push-out below
		# moves the ship whatever the closing speed was, so a gentle graze is
		# still something that happened TO the pilot and systems downstream
		# (DockingSystem's corridor rules) have to be able to know about it.
		GameState.ship_contact.emit(String(body["name"]), closing)
		origin += normal * float(contact["depth"])  # push out of penetration
		if closing > 0.0:
			var dv := normal * closing * (1.0 + RESTITUTION) * _ship_share(body)
			velocity += dv
			omega += _impact_spin(ship_a, ship_b, origin, body, normal, dv)
			_impart_body_velocity(body, normal, closing)
		moved = true
		_apply_impact(body, xform, normal, closing)
	if moved:
		xform.origin = origin
		ShipMotion.seize(xform, velocity, omega)
		# A bounce during an active approach means something is on the path (rival/
		# debris) — the kinematic autopilot can't model the contact and would drive
		# straight back in and grind, so hand control back to the pilot.
		if GameState.approach_state != "HOLDING":
			SalvageSystem.abort_approach_on_collision()


## The fraction of the exchange the SHIP takes, by mass.
##
## Fixed structure — the wreck frame, the station, the deck, anything registered
## with mass 0 — is infinite-mass and the ship takes all of it: 1.0, which is the
## reflection this function used to be a constant for. Against something that can
## move, the two split the way _resolve_pair splits any other pair, so ramming a
## boulder that outweighs the ship hurts the ship and ramming a light chunk
## mostly just moves the chunk.
func _ship_share(body: Dictionary) -> float:
	var mass: float = body.get("mass", 0.0)
	if mass <= 0.0:
		return 1.0
	return mass / (GameState.ship_mass() + mass)


## What the tick's path can run into, and WHERE ALONG IT. Empty when the path is
## clear; otherwise DISJOINT stretches of the path in order of approach, each
## {window, lo, hi}. This is what ShipMotion gates its sub-stepping on.
##
##   window — the distance the ship may travel while still overlapping the
##            tightest body in that stretch. A sub-step longer than this can
##            straddle the body and register nothing.
##   lo/hi  — the fraction of the path over which overlap with it is possible.
##
## The intervals are the important half, and they are what make sub-stepping
## bounded in speed. Sampling the whole tick finely costs more the faster the
## ship goes, so a fixed budget always buys a speed ceiling. But contact is only
## possible while the ship is actually alongside something, and that span is set
## by how big the body is — not by how fast the ship crossed it. Sampling only
## the hazard stretches costs the same handful of passes whether the ship is
## doing 100 m/s or 10 km/s.
##
## SEPARATE bodies stay SEPARATE stretches; only overlapping ones merge (taking
## the tighter window, since one sampling grid must catch both). Folding
## everything into a single [min lo, max hi] span sampled at the global minimum
## window reintroduces the speed ceiling by the back door: two thin walls 150 m
## apart on a fast path became one 170 m interval divided at one wall's 2.3 m
## window — a demand of 150-odd steps against the 32-step cap the sampler then
## had, with the shortfall spent finely sampling the EMPTY GAP between them
## while both walls went under-sampled. Measured before the split: 1 of 8
## alignments crossed both walls clean at 12 km/s. As disjoint stretches each
## wall costs its own handful of steps and the gap between them costs one.
##
## The window is measured ALONG THE PATH, not from the body's bounding sphere.
## For anything carrying a baked hull the two are wildly different: a station bay
## wall is 18 m by 16 m by 1.6 m thick, so its bounding radius is 12 m but flown at
## square-on it is detectable over 1.6 m of travel. Sizing the window from the
## radius says 24 m and lets the ship step clean over the wall. The same hull hit
## edge-on is genuinely 18 m thick and genuinely wants the wide window, so the
## thickness is projected onto the direction of travel rather than reduced to one
## number per body — and the interval is cut down by the same projection, so the
## two agree (see _hazard_of).
##
## The ship contributes its RADIUS and not its reach: the capsule is 2.6 m long
## and 0.7 m across, so a body passed broadside is only detectable over 0.7 m of
## travel even though the same body nose-on is detectable over 2.6 m. Gating on
## the generous orientation is how a ship tunnels while flying sideways.
func path_hazard(from: Vector3, to: Vector3) -> Array[Dictionary]:
	var span := to - from
	var distance := span.length()
	if distance <= 0.0:
		return []
	var along := span / distance
	var reach := ship_reach()
	var radius := _ship_radius()
	var found: Array[Dictionary] = []
	for obstacle: Dictionary in GameState.obstacles:
		var hazard := _hazard_of(from, span, along, obstacle["position"],
				float(obstacle["radius"]), obstacle.get("hull", PackedVector3Array()),
				reach, radius)
		if not hazard.is_empty():
			found.append(hazard)
	for contact: Dictionary in GameState.contacts:
		# Contacts with no radius are sensor blips, not bodies — they are not in
		# _collidables() either and cannot be collided with, let alone tunnelled.
		var r: float = contact.get("radius", 0.0)
		if r <= 0.0:
			continue
		var hazard := _hazard_of(from, span, along, contact["position"], r,
				PackedVector3Array(), reach, radius)
		if not hazard.is_empty():
			found.append(hazard)
	if found.size() <= 1:
		return found
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["lo"]) < float(b["lo"]))
	var merged: Array[Dictionary] = [found[0]]
	for hazard: Dictionary in found.slice(1):
		var last: Dictionary = merged[merged.size() - 1]
		if float(hazard["lo"]) <= float(last["hi"]):
			last["hi"] = maxf(float(last["hi"]), float(hazard["hi"]))
			last["window"] = minf(float(last["window"]), float(hazard["window"]))
		else:
			merged.append(hazard)
	return merged


## One body's hazard, or {} when the path never comes within reach of it.
##
## The interval starts as a ray-sphere intersection against the body's BOUNDING
## radius grown by the ship's reach, and for a hulled body it is then CUT DOWN by
## the same projection that sizes the window: the stretch of path over which the
## ship's own extent can overlap the hull's shadow on the direction of travel.
## The two measures have to agree. Sizing the window from the thickness while
## sizing the interval from the sphere makes the sample count scale with the
## hull's ASPECT RATIO — a broad thin wall wants its whole 27 m chord divided at
## its 2.3 m window — and any fixed step budget then buys a wall size that
## exhausts it. Cut to the slab, the interval is never longer than roughly one
## window, and the demand per body is a size-independent handful.
func _hazard_of(from: Vector3, span: Vector3, along: Vector3, at: Vector3,
		body_radius: float, hull: PackedVector3Array, reach: float,
		radius: float) -> Dictionary:
	var offset := from - at
	var envelope := body_radius + reach
	var a := span.length_squared()
	if a <= 0.0:
		return {}
	var b := 2.0 * offset.dot(span)
	var c := offset.length_squared() - envelope * envelope
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return {}
	var root := sqrt(discriminant)
	var t0 := (-b - root) / (2.0 * a)
	var t1 := (-b + root) / (2.0 * a)
	if t1 < 0.0 or t0 > 1.0:
		return {}
	var lo := maxf(t0, 0.0)
	var hi := minf(t1, 1.0)
	# A sphere is as thick as it is wide whichever way it is crossed; a hull is
	# only as thick as its own shadow on the direction of travel.
	var thickness := body_radius * 2.0
	if not hull.is_empty():
		var low := INF
		var high := -INF
		for point: Vector3 in hull:
			var d := point.dot(along)
			low = minf(low, d)
			high = maxf(high, d)
		thickness = high - low
		# The slab cut: overlap is only possible while the ship's projection onto
		# the travel direction (its origin ± reach, the conservative bound in any
		# orientation) intersects the hull's [low, high]. Outside that stretch the
		# ship is cleanly fore or aft of the wall however far inside the bounding
		# sphere it is, which for a broad thin hull is most of the sphere.
		var start := from.dot(along)
		var distance := sqrt(a)
		lo = maxf(lo, (low - reach - start) / distance)
		hi = minf(hi, (high + reach - start) / distance)
		if hi < lo:
			return {}
	# The ship's own width always counts, so a vanishingly thin hull still leaves
	# a window rather than demanding an infinite number of sub-steps.
	return {
		"window": thickness + 2.0 * radius,
		"lo": lo,
		"hi": hi,
	}


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
		var hull_dist: float = gjk["dist"]
		if hull_dist >= ship_radius:
			return {}
		var hull_normal: Vector3 = gjk["normal"] if not gjk["inside"] and hull_dist > 0.0001 \
				else fallback
		return {"normal": hull_normal, "depth": ship_radius - hull_dist}
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


## Spin imparted to the ship by a contact: the bounce's delta-v taken as applied
## at the contact point, resolved through the ship's real moments of inertia —
## delta-omega = I^-1 (r x m dv), per body axis. The contact point is
## approximated as the capsule spine's closest approach to the body, pushed out
## to the capsule surface — not a true GJK witness point; this is a believable
## kick, not a solver. A dead-centre hit has its moment arm along the normal and
## imparts nothing, which is what a pilot expects.
##
## This used to divide by a scalar radius of gyration of 1.0, which made the
## divisor 1 and saturated MAX_IMPART_SPIN on essentially every contact — every
## impact spun the ship exactly as hard as every other. Against the real tensor a
## hard knock lands just under the cap and a graze well below it, so how badly
## the ship is thrown finally reports how badly it was hit.
func _impact_spin(ship_a: Vector3, ship_b: Vector3, origin: Vector3,
		body: Dictionary, normal: Vector3, dv: Vector3) -> Vector3:
	var spine: Vector3 = _closest_points_between_segments(
			ship_a, ship_b, body["a"], body["b"])[0]
	var contact := spine - normal * _ship_radius()
	# The angular impulse is a world-frame moment, but the moments of inertia are
	# per BODY axis and differ from one another — roll is much the smallest — so
	# resolve into the hull's frame to divide, then put it back.
	var basis: Basis = (GameState.local_ship()["transform"] as Transform3D).basis
	var moment: Vector3 = basis.inverse() \
			* (contact - origin).cross(dv * GameState.ship_mass())
	var inertia := GameState.ship_inertia()
	var local := Vector3(
			moment.x / maxf(inertia.x, 1.0),
			moment.y / maxf(inertia.y, 1.0),
			moment.z / maxf(inertia.z, 1.0))
	return (basis * local).limit_length(MAX_IMPART_SPIN)


## Kick a movable body (a drifting salvage piece, a knocked debris chunk) on ship
## contact. This is the body's half of the exchange; _ship_share above is the
## ship's, and the two are the same split seen from either end. A body far
## heavier than the ship barely moves and throws the ship instead.
func _impart_body_velocity(body: Dictionary, normal: Vector3, closing: float) -> void:
	var mass: float = body.get("mass", 0.0)
	if mass <= 0.0:
		return
	var src: Dictionary = body["src"]
	var ship_mass := GameState.ship_mass()
	var frac := ship_mass / (ship_mass + mass)
	src["vel"] = (src.get("vel", Vector3.ZERO) as Vector3) \
			- normal * closing * (1.0 + RESTITUTION) * frac


## Everything a movable body (a drifting salvage piece, a knocked debris chunk)
## can hit, in two passes.
##
## Movable vs MOVABLE is sphere-sphere and splits by inverse mass — these bodies
## are constantly translating, so baking a hull for them isn't worth it.
##
## Movable vs STATIC (station structure, the derelict's intact members, traffic)
## is the infinite-mass case: the mover takes the whole push-out and the whole
## bounce. It runs through the SAME tight narrowphase the ship uses — a piece is
## just a degenerate capsule — so a piece meets a bay wall on its real hull, not
## on a bounding sphere that would stop it metres short.
func _resolve_movable_bodies(bodies: Array[Dictionary]) -> void:
	var movable: Array[Dictionary] = []
	for obstacle: Dictionary in GameState.obstacles:
		if float(obstacle.get("mass", 0.0)) > 0.0:
			movable.append(obstacle)
	if movable.is_empty():
		return
	for i in movable.size():
		for j in range(i + 1, movable.size()):
			_resolve_pair(movable[i], movable[j])
	for body: Dictionary in bodies:
		if float(body.get("mass", 0.0)) > 0.0:
			continue  # handled by the movable-vs-movable pass above
		for mover: Dictionary in movable:
			_resolve_static(mover, body)


## One movable body against one immovable one. Writes the correction into the
## live obstacle dict; the owning system (DriftSystem for salvage pieces) reads
## `position` and `vel` back out on its next tick, the same owner/collider split
## the ship's own bounce uses.
func _resolve_static(mover: Dictionary, body: Dictionary) -> void:
	var pos: Vector3 = mover["position"]
	var radius: float = float(mover["radius"])
	var away: Vector3 = pos - (body["a"] as Vector3)
	var fallback := away.normalized() if away.length() > 0.001 else Vector3.UP
	var contact := _test_body(pos, pos, radius, body, fallback)
	if contact.is_empty():
		return
	var normal: Vector3 = contact["normal"]
	var push: float = minf(float(contact["depth"]), MAX_SEPARATION_SPEED * _delta)
	mover["position"] = pos + normal * push
	var vel: Vector3 = mover.get("vel", Vector3.ZERO)
	var closing := -vel.dot(normal)
	if closing > 0.0:
		mover["vel"] = vel + normal * closing * (1.0 + RESTITUTION)


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
		# Penetration is reported by the sub-distance routine, which is the only
		# thing that actually knows. Inferring it from "four vertices survived"
		# meant any degenerate simplex that failed to reduce read as a hit.
		if bool(sub.get("inside", false)):
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
	# A FLAT tetrahedron encloses nothing, and must not be allowed to reach the
	# containment conclusion below.
	#
	# _origin_outside_face works from the face normal (b-a)x(c-a). Squash the
	# tetra flat and every normal collapses toward zero, so every face scores
	# ~0 and reports "origin not outside" — which reads as "origin inside", i.e.
	# penetration, no matter how far away the origin actually is. Support points
	# taken from a thin slab are coplanar exactly like this: it is how a ship
	# 11 m ABOVE the berth's floor plate was told it was inside it, and it would
	# do the same for any flat hull (a wall, a deck, a radiator panel).
	if _tetra_is_flat(a, b, c, d):
		return _best_face(verts, faces)
	var best := {"point": Vector3.ZERO, "ids": [0, 1, 2, 3], "inside": false}
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
			best = {"point": sub["point"], "ids": ids, "inside": false}
	if not any_outside:  # origin genuinely enclosed by a non-degenerate tetra
		return {"point": Vector3.ZERO, "ids": [0, 1, 2, 3], "inside": true}
	return best


## Is this tetrahedron flat enough that it bounds no volume? Measured against
## its own size, so it holds for a hull a metre across and one a hundred metres
## across alike.
func _tetra_is_flat(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> bool:
	var volume6 := absf((b - a).cross(c - a).dot(d - a))
	var scale := maxf(maxf((b - a).length(), (c - a).length()), (d - a).length())
	return volume6 <= 1e-6 * scale * scale * scale


## Closest point on any of the tetra's four faces — what a flat tetra reduces
## to, since it has an inside/outside only in the plane's sense.
func _best_face(verts: Array, faces: Array) -> Dictionary:
	var best := {"point": verts[0], "ids": [0], "inside": false}
	var best_sq := INF
	for f: Array in faces:
		var sub := _sub_tri(verts[f[0]], verts[f[1]], verts[f[2]])
		var sq: float = (sub["point"] as Vector3).length_squared()
		if sq < best_sq:
			best_sq = sq
			var ids: Array = []
			for li: int in sub["ids"]:
				ids.append(f[li])
			best = {"point": sub["point"], "ids": ids, "inside": false}
	return best


## Is the origin on the far side of plane (a,b,c) from vertex `opp`?
func _origin_outside_face(a: Vector3, b: Vector3, c: Vector3, opp: Vector3) -> bool:
	var n := (b - a).cross(c - a)
	return n.dot(-a) * n.dot(opp - a) < 0.0
