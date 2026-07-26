extends Node3D
## Phase 2 test environment: sun + space environment, one derelict wreck,
## slowly tumbling debris. The tumble is cosmetic drift so the scene reads as
## live salvage wreckage rather than a still render.

## One debris chunk is registered as a threat contact so the HUD's
## proximity/threat treatment has something real to react to.
const THREAT_CHUNK := "ChunkThreat"

@onready var _debris: Node3D = $Debris

var _spins: Array[Vector3] = []
## Obstacle ids we registered in GameState, so a re-instantiated field removes
## its own solid bodies instead of leaving stale/duplicate ones behind.
var _obstacle_ids: Array[int] = []
## Per-chunk collision tracking. Each entry: the live GameState obstacle dict,
## the chunk node, the chunk-LOCAL convex hull point cloud, and the hull centroid
## in chunk-local space. The Kenney meshes are flat/L-shaped and sit well off
## their node origins, so a single sphere both over-covered the shape and drifted
## off it as the chunk tumbled. Instead each chunk carries its convex hull, and
## we re-transform the hull (and its bounding-sphere centre) into world space
## every frame so CollisionSystem's GJK test stays exact under the tumble.
var _bodies: Array[Dictionary] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xD3B815
	for chunk in _debris.get_children():
		var axis := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
		).normalized()
		_spins.append(axis * rng.randf_range(0.05, 0.3))
		var chunk3d: Node3D = chunk
		var body := _mesh_body(chunk3d)
		if body["radius"] > 0.0:
			var id: int = GameState.register_obstacle(
					chunk3d.name, body["center"], body["radius"], body["hull_world"])
			_obstacle_ids.append(id)
			_bodies.append({
				"obstacle": GameState.get_obstacle(id),
				"chunk": chunk3d,
				"hull_local": body["hull_local"],
				"local_center": chunk3d.global_transform.affine_inverse() * body["center"],
			})
	GameState.register_contact(
		"UNSTABLE DEBRIS", _debris.get_node(THREAT_CHUNK).global_position, true)


## Drop our solid bodies when the field leaves the tree so a re-instantiated
## world doesn't accumulate duplicate or stale obstacles in GameState.
func _exit_tree() -> void:
	for id in _obstacle_ids:
		GameState.remove_obstacle(id)
	_obstacle_ids.clear()
	_bodies.clear()


func _process(delta: float) -> void:
	for i in _debris.get_child_count():
		var chunk: Node3D = _debris.get_child(i)
		chunk.rotate_object_local(_spins[i].normalized(), _spins[i].length() * delta)
	# Re-transform each chunk's hull into world space so the tight collision test
	# follows the tumble. The dict is the live GameState entry, so writing "hull"
	# and "position" updates the body CollisionSystem tests this frame. The
	# bounding radius is rotation-invariant, so it stays as registered.
	for body: Dictionary in _bodies:
		var xform: Transform3D = (body["chunk"] as Node3D).global_transform
		var hull_local: PackedVector3Array = body["hull_local"]
		var world := PackedVector3Array()
		world.resize(hull_local.size())
		for i in hull_local.size():
			world[i] = xform * hull_local[i]
		var obstacle: Dictionary = body["obstacle"]
		obstacle["hull"] = world
		obstacle["position"] = xform * body["local_center"]


## Collision data for a chunk: the convex hull of its mesh vertices (in both
## chunk-LOCAL space, for cheap per-frame re-transform, and rest-pose WORLD
## space, for registration) plus a bounding sphere (centre + radius) used for the
## GJK broadphase. Returns radius 0 for a chunk with no mesh.
func _mesh_body(chunk: Node3D) -> Dictionary:
	var to_local := chunk.global_transform.affine_inverse()
	var hull_local := PackedVector3Array()
	for node in chunk.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		if mi.mesh == null:
			continue
		# clean + simplify keeps the hull to a handful of vertices per chunk.
		var shape := mi.mesh.create_convex_shape(true, true)
		if shape == null:
			continue
		var rel := to_local * mi.global_transform
		for p in shape.points:
			hull_local.append(rel * p)
	if hull_local.is_empty():
		return {"center": chunk.global_position, "radius": 0.0,
				"hull_local": hull_local, "hull_world": hull_local}
	var xform := chunk.global_transform
	var hull_world := PackedVector3Array()
	var centroid := Vector3.ZERO
	for p in hull_local:
		var wp: Vector3 = xform * p
		hull_world.append(wp)
		centroid += wp
	centroid /= hull_world.size()
	var radius := 0.0
	for wp in hull_world:
		radius = maxf(radius, centroid.distance_to(wp))
	return {"center": centroid, "radius": radius,
			"hull_local": hull_local, "hull_world": hull_world}
