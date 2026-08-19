extends Node
## Property + differential fuzz for the hand-rolled GJK narrowphase
## (CollisionSystem._gjk_segment_hull).
##
## WHY THIS EXISTS. Convex-convex distance has one correct answer, and a mature
## physics library has already paid for the degenerate cases. We keep our own
## because the swap was measured and rejected — the narrowphase costs ~1% of the
## frame budget, so delegating it buys nothing we need and would cost a
## server-mirror layer plus a timing-semantics change (see CollisionSystem's
## header). The bargain is that OUR implementation has to earn the same trust,
## which is what this file is for. If a real narrowphase bug ever escapes these
## checks into play, that bargain has failed and the swap should happen.
##
## The bug that motivated it: support points off a thin slab are coplanar, the
## flat tetrahedron collapsed every face normal to zero, and the origin read as
## ENCLOSED at any distance — a ship 11 m above the berth floor was told it was
## inside it. That is why the bracket below is the core assertion: it is exactly
## the property that bug violated.
##
##   godot --headless res://tools/GjkFuzz.tscn

## Fixed seed: a failure must be reproducible. Printed on failure so a bad case
## can be replayed by hand.
const SEED := 0xC0FFEE
const HULLS_PER_FAMILY := 60
const QUERIES_PER_HULL := 24
## Slack on the brackets. The bounds are exact in real arithmetic; this only
## absorbs float error over hulls spanning tens of metres.
const EPS := 0.002

var _rng := RandomNumberGenerator.new()
var _failures: Array[String] = []
var _checked := 0


func _ready() -> void:
	_rng.seed = SEED
	_run.call_deferred()


func _run() -> void:
	await get_tree().physics_frame
	for family: String in ["cloud", "flat", "collinear", "single", "pair",
			"slab", "duplicates", "needle"]:
		_fuzz_family(family)
	# MUST be awaited: it steps the physics space between hulls, so calling it
	# bare would return a coroutine and let the verdict print before a single
	# comparison ran — a check that passes by never happening.
	await _differential()
	_transform_invariance()

	if _failures.is_empty():
		print("GJK FUZZ: ALL CHECKS PASSED (%d queries)" % _checked)
		get_tree().quit(0)
	else:
		printerr("seed was 0x%X" % SEED)
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("GJK FUZZ: %d FAILURE(S) over %d queries" % [_failures.size(), _checked])
		get_tree().quit(1)


## --- Hull families ----------------------------------------------------------
## Every degenerate shape the real game actually registers: flat radiator panels
## and bay walls (coplanar), the berth floor (thin slab), and the numerically
## awkward cases a bake can emit (duplicate/collinear vertices).
func _make_hull(family: String) -> PackedVector3Array:
	var pts := PackedVector3Array()
	match family:
		"cloud":
			for _i in _rng.randi_range(4, 20):
				pts.append(_rand_vec(12.0))
		"flat":  # coplanar — the flat-tetra bug class
			for _i in _rng.randi_range(3, 12):
				pts.append(Vector3(_rng.randf_range(-11, 11), 0.0, _rng.randf_range(-11, 11)))
		"collinear":
			var dir := _rand_vec(1.0).normalized()
			for _i in _rng.randi_range(2, 8):
				pts.append(dir * _rng.randf_range(-9.0, 9.0))
		"single":
			var p := _rand_vec(6.0)
			for _i in _rng.randi_range(1, 5):
				pts.append(p)
		"pair":
			pts.append(_rand_vec(6.0))
			pts.append(_rand_vec(6.0))
		"slab":  # the berth floor: 22 x 2 x 22
			var hx := _rng.randf_range(4.0, 11.0)
			var hy := _rng.randf_range(0.05, 1.0)
			var hz := _rng.randf_range(4.0, 11.0)
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						pts.append(Vector3(sx * hx, sy * hy, sz * hz))
		"duplicates":
			for _i in _rng.randi_range(2, 6):
				var p := _rand_vec(8.0)
				for _d in _rng.randi_range(1, 3):
					pts.append(p + _rand_vec(0.000001))
		"needle":  # one long thin axis, the worst conditioning
			var d := _rand_vec(1.0).normalized()
			for _i in _rng.randi_range(4, 10):
				pts.append(d * _rng.randf_range(-20.0, 20.0) + _rand_vec(0.01))
	return pts


func _fuzz_family(family: String) -> void:
	for _h in HULLS_PER_FAMILY:
		var hull := _make_hull(family)
		if hull.is_empty():
			continue
		for _q in QUERIES_PER_HULL:
			var a := _rand_vec(26.0)
			var b := a + _rand_vec(2.0)  # a ship-sized capsule spine
			_assert_brackets(family, hull, a, b)


## THE core property. The true segment-to-hull distance is bracketed on both
## sides by quantities needing no second GJK to compute:
##
##   LOWER — the hull lies inside its own AABB, so the distance to the hull can
##           never be LESS than the distance to that box. This is the assertion
##           the flat-tetra bug violated: it returned 0 with the query metres
##           outside the box.
##   UPPER — every vertex IS in the hull, so the distance can never be MORE than
##           the distance to the nearest vertex.
func _assert_brackets(family: String, hull: PackedVector3Array, a: Vector3, b: Vector3) -> void:
	_checked += 1
	var d: float = CollisionSystem.hull_distance(a, b, hull)
	if d < 0.0 or not is_finite(d):
		_failures.append("%s: distance not a non-negative real (%s)" % [family, d])
		return
	var lower := _segment_aabb_distance(a, b, hull)
	if d < lower - EPS:
		_failures.append("%s: %.4f is BELOW the AABB bound %.4f (a=%s b=%s n=%d)"
				% [family, d, lower, a, b, hull.size()])
	var upper := INF
	for p: Vector3 in hull:
		upper = minf(upper, _point_segment_distance(p, a, b))
	if d > upper + EPS:
		_failures.append("%s: %.4f is ABOVE the nearest-vertex bound %.4f (n=%d)"
				% [family, d, upper, hull.size()])


## --- Differential check against Godot's own convex collision -----------------
## The maturity argument for delegating the narrowphase, taken as a TEST rather
## than as a dependency: for hulls Godot will accept, our overlap verdict must
## match its ConvexPolygonShape3D verdict. Overlap (not distance) is the shared
## vocabulary — the server reports no signed distance when separated — and it is
## also exactly what gameplay consumes (`dist < radius` is the contact test).
func _differential() -> void:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var probe := PhysicsServer3D.sphere_shape_create()
	var radius := 0.6
	PhysicsServer3D.shape_set_data(probe, radius)
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, space)
	await get_tree().physics_frame
	var state := PhysicsServer3D.space_get_direct_state(space)
	if state == null:
		_failures.append("differential: no direct space state to query")
		return
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape_rid = probe

	var compared := 0
	var shapes: Array[RID] = []
	for family: String in ["cloud", "slab", "flat"]:
		for _h in 40:
			var hull := _make_hull(family)
			if hull.size() < 4:
				continue
			var shape := PhysicsServer3D.convex_polygon_shape_create()
			PhysicsServer3D.shape_set_data(shape, hull)
			shapes.append(shape)
			PhysicsServer3D.body_clear_shapes(body)
			PhysicsServer3D.body_add_shape(body, shape, Transform3D.IDENTITY)
			await get_tree().physics_frame
			for _q in 10:
				var at := _rand_vec(16.0)
				params.transform = Transform3D(Basis.IDENTITY, at)
				var theirs: bool = not state.intersect_shape(params, 1).is_empty()
				var ours: bool = CollisionSystem.hull_distance(at, at, hull) < radius
				_checked += 1
				compared += 1
				# Skip verdicts straddling the boundary, where a hair of float
				# difference legitimately separates the two.
				var margin: float = absf(CollisionSystem.hull_distance(at, at, hull) - radius)
				if ours != theirs and margin > 0.01:
					_failures.append(
						"differential(%s): ours=%s godot=%s at %s (gap %.4f, r %.2f)"
							% [family, ours, theirs, at,
								CollisionSystem.hull_distance(at, at, hull), radius])
	print("  differential: %d verdicts compared against Godot convex collision" % compared)
	for s in shapes:
		PhysicsServer3D.free_rid(s)
	PhysicsServer3D.free_rid(probe)
	PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(space)


## Distance is a rigid invariant: move the hull and the query together and the
## answer must not change. Catches any hidden dependence on absolute position
## or on the fixed Vector3(1,0,0) the simplex is seeded from.
func _transform_invariance() -> void:
	for family: String in ["cloud", "flat", "slab", "needle"]:
		for _h in 25:
			var hull := _make_hull(family)
			if hull.is_empty():
				continue
			var a := _rand_vec(20.0)
			var b := a + _rand_vec(2.0)
			var base: float = CollisionSystem.hull_distance(a, b, hull)
			var xf := Transform3D(
				Basis.from_euler(Vector3(_rng.randf_range(-PI, PI),
					_rng.randf_range(-PI, PI), _rng.randf_range(-PI, PI))),
				_rand_vec(40.0))
			var moved := PackedVector3Array()
			moved.resize(hull.size())
			for i in hull.size():
				moved[i] = xf * hull[i]
			var after: float = CollisionSystem.hull_distance(xf * a, xf * b, moved)
			_checked += 1
			if absf(after - base) > maxf(EPS, base * 0.001):
				_failures.append("%s: not rigid-invariant (%.4f -> %.4f)" % [family, base, after])


## --- Reference geometry (deliberately trivial, so it cannot share a bug) -----


## Exact distance between the segment's AABB and the hull's AABB. Both the
## segment and the hull are contained in their own boxes, so this can never
## exceed the true segment-to-hull distance — which is what makes it a sound
## lower bound. Computed in closed form, NOT by sampling the segment: a sampled
## minimum OVERestimates the true distance (the closest point usually falls
## between samples), which would make the bound unsound and fail honest hulls.
func _segment_aabb_distance(a: Vector3, b: Vector3, hull: PackedVector3Array) -> float:
	var lo: Vector3 = hull[0]
	var hi: Vector3 = hull[0]
	for p: Vector3 in hull:
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	var seg_lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var seg_hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	# Per-axis separation, zero where the extents overlap on that axis.
	var gap := Vector3(
		maxf(maxf(lo.x - seg_hi.x, seg_lo.x - hi.x), 0.0),
		maxf(maxf(lo.y - seg_hi.y, seg_lo.y - hi.y), 0.0),
		maxf(maxf(lo.z - seg_hi.z, seg_lo.z - hi.z), 0.0))
	return gap.length()


func _point_segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _rand_vec(scale: float) -> Vector3:
	return Vector3(_rng.randf_range(-scale, scale), _rng.randf_range(-scale, scale),
			_rng.randf_range(-scale, scale))
