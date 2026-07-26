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
## Per-chunk collision tracking: the live GameState obstacle dict, the chunk it
## belongs to, and the mesh centre in the chunk's LOCAL space. The Kenney meshes
## sit well off their node origins, so a tumbling chunk swings its mesh around
## the pivot — we re-derive the world centre each frame to keep the sphere on the
## geometry (a static sphere drifted off the rock and the ship flew through it).
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
		var sphere := _mesh_sphere(chunk3d)
		if sphere["radius"] > 0.0:
			var id: int = GameState.register_obstacle(
					chunk3d.name, sphere["center"], sphere["radius"])
			_obstacle_ids.append(id)
			_bodies.append({
				"obstacle": GameState.get_obstacle(id),
				"chunk": chunk3d,
				"local_center": chunk3d.global_transform.affine_inverse() * sphere["center"],
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
	# Follow each tumbling chunk's mesh centre so the collision sphere stays on the
	# rock. The dict is the live GameState entry, so writing "position" updates the
	# body CollisionSystem tests this frame.
	for body: Dictionary in _bodies:
		var chunk: Node3D = body["chunk"]
		body["obstacle"]["position"] = chunk.global_transform * body["local_center"]


## World-space collision sphere fitted to a chunk's mesh: centred on the AABB
## (meshes sit off the node origin) with a radius reaching the farthest actual
## vertex — the true bounding sphere. It hugs the geometry (no air gap at the
## bounce) yet still contains the mesh at any tumble orientation, since the sphere
## rides a fixed material point so the max vertex distance is rotation-invariant.
## Returns radius 0 for a chunk with no mesh.
func _mesh_sphere(chunk: Node3D) -> Dictionary:
	var meshes: Array[MeshInstance3D] = []
	var merged := AABB()
	var have_box := false
	for node in chunk.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		if mi.mesh == null:
			continue
		meshes.append(mi)
		var box := mi.global_transform * mi.get_aabb()
		merged = box if not have_box else merged.merge(box)
		have_box = true
	if not have_box:
		return {"center": chunk.global_position, "radius": 0.0}
	var center: Vector3 = merged.position + merged.size * 0.5
	var radius := 0.0
	for mi in meshes:
		var xform := mi.global_transform
		for v in mi.mesh.get_faces():
			radius = maxf(radius, center.distance_to(xform * v))
	return {"center": center, "radius": radius}
