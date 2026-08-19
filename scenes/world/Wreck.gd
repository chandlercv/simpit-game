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
## This site's tumble angular velocity (parent space, rad/s), read from the wreck
## graph — SalvageSystem.reset_site() rolls a fresh axis + rate per claim, so no two
## derelicts spin alike. Gentle enough to read as adrift, not spinning. Published
## per member as v = ω × r so the approach autopilot can track the orbiting standoff.
var _tumble_omega: Vector3 = Vector3.ZERO
## Per-member collision/geometry, node name -> {hull_local, center_local,
## seam_local: (all wreck-local), radius: float, id: int}. Baked once in the
## wreck's local frame (the body is rigid); each frame _publish_world transforms
## it by the live tumble to refresh the member's world center/seam and its
## registered obstacle, so collision and the cut seam ride the visible rotation.
var _member_bodies: Dictionary = {}


func _ready() -> void:
	var id := GameState.register_contact("DERELICT FRIGATE", global_position)
	GameState.set_tracked_contact(id)
	SalvageSystem.register_wreck_position(global_position)
	_bake_member_hulls()
	GameState.wreck_member_cut.connect(_on_member_cut)
	GameState.wreck_members_lost.connect(_sync_members)
	GameState.site_reset.connect(_on_site_reset)
	_tumble_omega = GameState.wreck.get("tumble_omega", Vector3.ZERO)
	_sync_members()


func _exit_tree() -> void:
	for name: String in _member_bodies:
		var body: Dictionary = _member_bodies[name]
		if body["id"] != -1:
			GameState.remove_obstacle(body["id"])
			body["id"] = -1


func _physics_process(delta: float) -> void:
	_time += delta
	# Advance this site's tumble (spin about ω in parent space) and refresh every
	# intact member's world geometry + collision body against the new orientation.
	if _tumble_omega.length() > 0.0001:
		rotate(_tumble_omega.normalized(), _tumble_omega.length() * delta)
	for member: Dictionary in GameState.wreck.get("members", []):
		if not (member["cut"] or member["destroyed"]) and _member_bodies.has(member["node"]):
			_publish_world(member, _member_bodies[member["node"]])
	# Slow distress-beacon pulse.
	var pulse := 0.5 + 0.5 * sin(_time * TAU * 0.4)
	_beacon_light.light_energy = 1.0 + 5.0 * pulse


func _on_member_cut(id: int) -> void:
	var member := GameState.get_member(id)
	if not member.is_empty():
		_apply_member(member)


func _on_site_reset() -> void:
	# Fresh claim → fresh tumble (and a random start orientation so the new derelict
	# isn't caught mid-pose from the last one; the site swap hides the snap).
	_tumble_omega = GameState.wreck.get("tumble_omega", Vector3.ZERO)
	basis = Basis.from_euler(Vector3(randf_range(-PI, PI), randf_range(-PI, PI), randf_range(-PI, PI)))
	_sync_members()


## Mirror the graph's cut/destroyed state (covers both a fresh site and a
## window opening after cuts already happened).
func _sync_members() -> void:
	for member: Dictionary in GameState.wreck.get("members", []):
		_apply_member(member)


## SalvagePieces: the member's own mesh subtree in this scene, so a freshly
## severed piece can duplicate it as a free-floating drift visual instead of
## rebuilding geometry from scratch. null if the node doesn't exist (headless).
func member_visual(node_name: String) -> Node3D:
	return get_node(node_name) if has_node(node_name) else null


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
	if solid:
		# Seed the graph's world center/seam/vel now; _process keeps them live as the
		# wreck tumbles. reset_site() rebuilds the members array, so re-write on sync.
		_publish_world(member, body)
		if body["id"] == -1:
			body["id"] = GameState.register_obstacle(
					"WRECK: %s" % member["name"], member["center"], body["radius"],
					_world_hull(body), true)
	elif body["id"] != -1:
		GameState.remove_obstacle(body["id"])
		body["id"] = -1


## Transform a member's baked local geometry by the wreck's current tumble and
## write the results into the graph (world centroid, cut-seam point, and the
## orbital velocity ω × r the autopilot feed-forwards) plus its live obstacle
## dict, so collision, approach, and the alignment seam all track the rotation.
func _publish_world(member: Dictionary, body: Dictionary) -> void:
	var xform := global_transform
	member["center"] = xform * body["center_local"]
	member["seam"] = xform * body["seam_local"]
	member["radius"] = body["radius"]
	member["vel"] = _tumble_omega.cross(member["center"] - global_position)
	if body["id"] != -1:
		var obstacle := GameState.get_obstacle(body["id"])
		if not obstacle.is_empty():
			obstacle["position"] = member["center"]
			obstacle["hull"] = _world_hull(body)


## The member's convex hull in world space for this frame's orientation.
func _world_hull(body: Dictionary) -> PackedVector3Array:
	var xform := global_transform
	var out := PackedVector3Array()
	for p: Vector3 in body["hull_local"]:
		out.append(xform * p)
	return out


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


## Convex hull of a member node's meshes in the wreck's LOCAL frame (the body is
## rigid, so it's baked once and re-transformed by the live tumble each frame),
## with a bounding-sphere radius for the GJK broadphase and a seam point — the
## hull vertex farthest along local +Y, a fixed spot on the member's surface that
## the pre-cut alignment targets as it swings around with the spin. `id` starts
## unregistered (-1). Radius 0 when the node has no mesh.
func _bake_hull(node: Node3D) -> Dictionary:
	var to_local := global_transform.affine_inverse()
	var pts := PackedVector3Array()
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child
		if mi.mesh == null:
			continue
		var shape := mi.mesh.create_convex_shape(true, true)
		if shape == null:
			continue
		for p in shape.points:
			pts.append(to_local * (mi.global_transform * p))
	if pts.is_empty():
		return {"radius": 0.0, "id": -1}
	var centroid := Vector3.ZERO
	for p in pts:
		centroid += p
	centroid /= pts.size()
	var radius := 0.0
	var seam: Vector3 = pts[0]
	for p in pts:
		radius = maxf(radius, centroid.distance_to(p))
		if p.y > seam.y:
			seam = p
	return {"hull_local": pts, "center_local": centroid, "seam_local": seam,
			"radius": radius, "id": -1}
