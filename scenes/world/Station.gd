extends Node3D
## The 3D station the docking mini-game is flown around: structure, gate rings,
## the berth pad, and the collision hulls that make the tight bits bite.
##
## Nothing here authors geometry positions. The lane (gates, corridors, pad) is
## constant data on DockingSystem, and this node BUILDS ITS VISUALS FROM THAT
## DATA — the rings are placed at DockingSystem.GATES positions with exactly the
## GATES radii, the pad markings sit on PAD_LOCAL. The station's own placement is
## reported back with register_station(), which is the single transform the rules
## and the scene have to agree on. Change a gate in DockingSystem and the scene
## follows; there is no second copy of the lane to forget to update.
##
## (tools/build_station.py enforces the other half of that agreement at build
## time: the generated meshes are clearance-checked against the same lane, so the
## structure can't grow into a corridor the pilot is required to fly inside.)
##
## Solid structure registers as GameState obstacles with real convex hulls, the
## same per-mesh bake DebrisField uses for its chunks. The gate rings and the pad
## deck deliberately do NOT: you fly through the rings, and the pad is landed on
## by the touchdown test rather than bounced off by the collision one.

const STATION_DIR := "res://assets/cc0/station/"

## Ring tube thickness. Constant rather than scaled with the gate, so a 6.5 m
## DELTA ring doesn't render as a hairline next to ALPHA's 14 m.
const RING_TUBE := 0.35
## Gate rings are markings, not lights, but they need to read at range in the
## station's shadow — so they're emissive, and they warm up as the lane tightens.
const RING_NEAR := Color(1.0, 0.55, 0.15)
const RING_FAR := Color(0.3, 0.75, 1.0)

@onready var _structure: Node3D = $Structure
@onready var _decor: Node3D = $Decor
@onready var _rings: Node3D = $Gates

var _ring_nodes: Array[MeshInstance3D] = []
## Convex hulls baked once at _ready as {name, center, radius, hull}, then
## registered and unregistered as the pattern comes and goes.
var _hulls: Array[Dictionary] = []
var _obstacle_ids: Array[int] = []


func _ready() -> void:
	# Tell the rules where the station actually is before anything reads a gate
	# in world space.
	DockingSystem.register_station(global_transform)
	_build_structure()
	_build_gates()
	_build_pad()
	_bake_hulls()
	GameState.docking_changed.connect(_on_docking_changed)
	_on_docking_changed(GameState.docking_state)
	set_process(true)


## Ring visibility follows the gate index, which advances WITHOUT a state change
## (every marker on the CLEARED leg), so there is no signal to hang it on. Four
## visibility flags a frame is cheaper than adding one.
func _process(_delta: float) -> void:
	if DockingSystem.is_active():
		_update_rings()


## Structure is placed relative to the lane it was designed around: the drums
## straddle the CHARLIE gate at the offset build_station.py cleared them to.
func _build_structure() -> void:
	_add_part("hub_core", Vector3.ZERO)
	_add_part("berth_bay", Vector3.ZERO)
	_add_part("gantry", Vector3.ZERO)
	var charlie: Vector3 = DockingSystem.GATES[2]["position"]
	for side in [-1.0, 1.0]:
		var at := charlie + Vector3(side * _drum_offset(), 0.0, 0.0)
		_add_part("hab_drum", at)
		_add_part("hab_drum_caps", at)


## How far off the CHARLIE gate each hab drum stands. Mirrors DRUM_OFFSET in
## tools/build_station.py, which is where the value was cleared against the lane.
func _drum_offset() -> float:
	return 34.0


## `solid` decides which parent the part lands under, and that is the ONLY thing
## deciding whether it collides: _bake_hulls walks _structure and nothing else.
func _add_part(file: String, at: Vector3, solid := true) -> Node3D:
	var packed: PackedScene = load(STATION_DIR + file + ".glb")
	if packed == null:
		push_warning("Station: missing asset %s.glb — run tools/build_station.py" % file)
		return null
	var node: Node3D = packed.instantiate()
	node.position = at
	(_structure if solid else _decor).add_child(node)
	return node


## A ring per gate, at the gate's own radius, plus a name tag's worth of colour:
## the lane reads as a sequence you fly THROUGH rather than a set of waypoints.
func _build_gates() -> void:
	var gates: Array = DockingSystem.GATES
	for i in gates.size():
		var gate: Dictionary = gates[i]
		var torus := TorusMesh.new()
		var radius: float = gate["radius"]
		torus.inner_radius = radius - RING_TUBE
		torus.outer_radius = radius + RING_TUBE
		torus.rings = 24
		var mi := MeshInstance3D.new()
		mi.mesh = torus
		mi.position = gate["position"]
		# Stand the ring across the leg it is flown through, not across a fixed
		# axis: the lane doglegs, so a ring facing a constant -z would sit at an
		# angle to the path you actually cross it on.
		var through: Vector3 = _leg_into(i)
		if through.length() > 0.001:
			mi.basis = Basis.looking_at(through.normalized(), Vector3.UP) \
					* Basis(Vector3.RIGHT, PI / 2.0)
		mi.material_override = _ring_material(
				RING_FAR.lerp(RING_NEAR, float(i) / maxf(gates.size() - 1.0, 1.0)))
		_rings.add_child(mi)
		_ring_nodes.append(mi)


## Direction the pilot is travelling when they cross gate `index` — the leg that
## leads into it, which is also the axis DockingSystem tests the gate's plane
## against. Station-local; gate 0 is entered from the arrival point.
func _leg_into(index: int) -> Vector3:
	var here: Vector3 = DockingSystem.GATES[index]["position"]
	if index <= 0:
		return here - DockingSystem.ENTRY_LOCAL
	return here - (DockingSystem.GATES[index - 1]["position"] as Vector3)


## A ring you have already flown is clutter, and DELTA's is worse than that: it
## is centred 16 m above the pad with a 6.5 m radius, so it hangs edge-on
## straight down the descent path and puts a glowing bar across the one view the
## pilot needs while landing. Rings show only while they are still ahead.
func _update_rings() -> void:
	var gate: int = int(GameState.docking.get("gate", 0))
	var outbound: bool = DockingSystem.status().get("outbound", false)
	var final_leg: bool = GameState.docking_state == "FINAL"
	for i in _ring_nodes.size():
		var ring: MeshInstance3D = _ring_nodes[i]
		if final_leg:
			ring.visible = false           # every marker is behind you by now
		elif outbound:
			ring.visible = i <= gate       # counting down toward the exit
		else:
			ring.visible = i >= gate


func _ring_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	# Bright enough to pick out at range in the station's shadow, dim enough
	# not to bloom over the structure once you are inside the pattern.
	mat.emission_energy_multiplier = 0.9
	return mat


## The deck is landed ON, by DockingSystem's touchdown test, which judges gear,
## sink rate, attitude and where on the markings you put it. Making it a
## collision body too would just have the ship bounce off the thing it is trying
## to arrive on — so the pad is decor, and the floor slab under it (part of the
## bay) is what stops anything falling through.
func _build_pad() -> void:
	_add_part("pad_deck", Vector3.ZERO, false)
	_add_part("pad_markings", Vector3.ZERO, false)


## Bake a convex hull per structural mesh, so clipping a hab drum on the way
## through the slot costs hull exactly like clipping the derelict does. Baked
## once here (it walks every vertex); registered and dropped as the pattern comes
## and goes. Rings and the pad are not under _structure and so never bake —
## flying through a ring is the point of it, and the pad is landed on by the
## touchdown test rather than bounced off by the collision one.
func _bake_hulls() -> void:
	for node in _structure.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		if mi.mesh == null:
			continue
		var shape := mi.mesh.create_convex_shape(true, true)
		if shape == null or shape.points.is_empty():
			continue
		var hull := PackedVector3Array()
		var centroid := Vector3.ZERO
		var xform := mi.global_transform
		for p in shape.points:
			var wp: Vector3 = xform * p
			hull.append(wp)
			centroid += wp
		centroid /= float(hull.size())
		var radius := 0.0
		for p in hull:
			radius = maxf(radius, centroid.distance_to(p))
		_hulls.append({
			"name": "STATION %s" % mi.name.to_upper(),
			"center": centroid, "radius": radius, "hull": hull,
		})


## The station is only worth colliding against while a pattern is being flown.
## Registering/unregistering rather than flagging, because CollisionSystem tests
## every obstacle in the list — leaving a station in it would have the ship
## trading paint with scenery hundreds of metres from the claim it never left.
func _on_docking_changed(_state: String) -> void:
	var live: bool = DockingSystem.is_active()
	visible = live
	if live == not _obstacle_ids.is_empty():
		return
	if live:
		for body: Dictionary in _hulls:
			_obstacle_ids.append(GameState.register_obstacle(
					body["name"], body["center"], body["radius"], body["hull"]))
		return
	for id in _obstacle_ids:
		GameState.remove_obstacle(id)
	_obstacle_ids.clear()
