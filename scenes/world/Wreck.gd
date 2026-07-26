extends Node3D
## Placeholder derelict built from engine primitives + PBR materials, standing
## in for Kenney/Quaternius modular kit pieces (see plan Phase 2 asset
## sourcing; real glTF assets drop into assets/cc0|cc-by|cc-by-nc later).
## Registers itself as the tracked sensor contact and pulses its beacon so
## Glow has something to bite on.
##
## Phase 4: reports its placement to SalvageSystem (the structural graph's
## member "node" fields name children here) and mirrors graph state in 3D —
## severed members disappear from the hull, a fresh site restores them.

@onready var _beacon_light: OmniLight3D = $BeaconLight

var _time := 0.0
## Per-member collision: node name -> {hull: PackedVector3Array (world),
## center: Vector3, radius: float, id: int}. Baked once (the frame is static),
## and each member's obstacle is registered while it's intact / removed when it's
## cut or collapses, so the ship collides with exactly the visible structure.
var _member_bodies: Dictionary = {}


func _ready() -> void:
	var id := GameState.register_contact("DERELICT FRIGATE", global_position)
	GameState.set_tracked_contact(id)
	SalvageSystem.register_wreck_position(global_position)
	_bake_member_hulls()
	GameState.wreck_member_cut.connect(_on_member_cut)
	GameState.wreck_members_lost.connect(_sync_members)
	GameState.site_reset.connect(_on_site_reset)
	_sync_members()


func _exit_tree() -> void:
	for name: String in _member_bodies:
		var body: Dictionary = _member_bodies[name]
		if body["id"] != -1:
			GameState.remove_obstacle(body["id"])
			body["id"] = -1


func _process(delta: float) -> void:
	_time += delta
	# Slow distress-beacon pulse.
	var pulse := 0.5 + 0.5 * sin(_time * TAU * 0.4)
	_beacon_light.light_energy = 1.0 + 5.0 * pulse


func _on_member_cut(id: int) -> void:
	var member := GameState.get_member(id)
	if not member.is_empty():
		_apply_member(member)


func _on_site_reset() -> void:
	_sync_members()


## Mirror the graph's cut/destroyed state (covers both a fresh site and a
## window opening after cuts already happened).
func _sync_members() -> void:
	for member: Dictionary in GameState.wreck.get("members", []):
		_apply_member(member)


## Bring one member's 3D visibility and its collision body in line with the
## graph: an intact member is shown and solid; a cut/collapsed one vanishes and
## stops colliding (so the ship can fly through the gap it left).
func _apply_member(member: Dictionary) -> void:
	var node_name: String = member["node"]
	var solid: bool = not (member["cut"] or member["destroyed"])
	if has_node(node_name):
		get_node(node_name).visible = solid
	if not _member_bodies.has(node_name):
		return
	var body: Dictionary = _member_bodies[node_name]
	if solid and body["id"] == -1:
		body["id"] = GameState.register_obstacle(
				"WRECK: %s" % member["name"], body["center"], body["radius"],
				body["hull"], true)
	elif not solid and body["id"] != -1:
		GameState.remove_obstacle(body["id"])
		body["id"] = -1


## Bake each member's convex hull once (the frame is static). Hulls are in world
## space; a member's obstacle is (de)registered by _apply_member as it is cut.
func _bake_member_hulls() -> void:
	for member: Dictionary in GameState.wreck.get("members", []):
		var node_name: String = member["node"]
		if not has_node(node_name):
			continue
		var body := _bake_hull(get_node(node_name))
		if body["radius"] > 0.0:
			_member_bodies[node_name] = body


## World-space convex hull of a member node's meshes, with a bounding sphere for
## the GJK broadphase. `id` starts unregistered (-1). Radius 0 when it has no mesh.
func _bake_hull(node: Node3D) -> Dictionary:
	var pts := PackedVector3Array()
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child
		if mi.mesh == null:
			continue
		var shape := mi.mesh.create_convex_shape(true, true)
		if shape == null:
			continue
		for p in shape.points:
			pts.append(mi.global_transform * p)
	if pts.is_empty():
		return {"radius": 0.0, "id": -1}
	var centroid := Vector3.ZERO
	for p in pts:
		centroid += p
	centroid /= pts.size()
	var radius := 0.0
	for p in pts:
		radius = maxf(radius, centroid.distance_to(p))
	return {"hull": pts, "center": centroid, "radius": radius, "id": -1}
