extends Node
## Author-time bake of the ship's collision capsule from its model, written back
## into the ship's .tres so the runtime never has to measure the SHIP's 3D scene.
## Only the ship's: obstacle hulls (station, wreck members, debris) are baked
## from live meshes at runtime and re-published as they move, so collision
## DEGRADES headless rather than being scene-independent — see
## CollisionSystem.wreck_surface_distance's INF fallback.
##
##   godot --headless res://tools/ShipColliderBake.tscn
##
## Merges every MeshInstance3D under Ship.tscn's Hull into one ship-local AABB
## (so the Hull's offset from the transform origin is captured), fits a capsule to
## it — longest axis becomes the spine, radius from the smaller cross-section —
## and saves collision_a/b/radius. Assumes the longest AABB axis is the intended
## (fore-aft) capsule axis; hand-edit the .tres if a model breaks that.

const SHIP_SCENE := "res://scenes/world/Ship.tscn"
const SHIP_DEF := "res://data/ships/kestrel.tres"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var ship_root: Node3D = load(SHIP_SCENE).instantiate()
	add_child(ship_root)
	await get_tree().process_frame  # let children enter the tree / meshes resolve

	var hull := ship_root.get_node_or_null("Hull")
	if hull == null:
		push_error("Ship.tscn has no Hull node")
		get_tree().quit(1)
		return

	# Merge each mesh's AABB into ship-local space. MeshInstance3D only, so the
	# rig's camera and the nav/thruster lights (also VisualInstance3D) are
	# excluded. The Hull node's offset falls out of the transforms.
	var to_local := ship_root.global_transform.affine_inverse()
	var merged := AABB()
	var have_box := false
	for node in hull.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		if mi.mesh == null:
			continue
		var box := (to_local * mi.global_transform) * mi.get_aabb()
		merged = box if not have_box else merged.merge(box)
		have_box = true
	if not have_box:
		push_error("No MeshInstance3D with a mesh found under Hull")
		get_tree().quit(1)
		return

	var ext := merged.size
	var center := merged.position + ext * 0.5

	# Longest AABB axis is the capsule spine.
	var axis_i := 0
	if ext[1] > ext[axis_i]:
		axis_i = 1
	if ext[2] > ext[axis_i]:
		axis_i = 2
	var cross: Array[float] = []
	for i in 3:
		if i != axis_i:
			cross.append(ext[i])
	var radius := 0.5 * minf(cross[0], cross[1])
	var seg_half := maxf(ext[axis_i] * 0.5 - radius, 0.0)
	var dir := Vector3.ZERO
	dir[axis_i] = 1.0
	var a := center - dir * seg_half
	var b := center + dir * seg_half

	# Patch only the collision_ lines in the .tres text. ResourceSaver would
	# rewrite the whole resource and strip every field left at its script
	# default, silently coupling the ship's stats to those defaults; a targeted
	# text patch keeps the authored file intact and yields a minimal diff. Patch
	# first so a re-bake heals a previously corrupted file before we reload it.
	var err: int = _patch_collision_lines(a, b, radius)
	if err != OK:
		push_error("Failed to save %s (err %d)" % [SHIP_DEF, err])
		get_tree().quit(1)
		return
	var def := load(SHIP_DEF) as ShipDefinition
	var ship_name: String = def.display_name if def != null else "ship"

	print("--- ShipColliderBake: %s ---" % ship_name)
	print("collision_a = ", a)
	print("collision_b = ", b)
	print("collision_radius = ", radius)
	var reach := maxf(a.length(), b.length()) + radius
	var standoff: float = SalvageSystem.CUT_RANGE - 4.0
	var margin := standoff - (reach + CollisionSystem.WRECK_RADIUS)
	print("ship_reach = %.2f  reach + WRECK_RADIUS = %.2f  standoff = %.2f  margin = %.2f" % [
		reach, reach + CollisionSystem.WRECK_RADIUS, standoff, margin])
	if margin < 0.5:
		push_warning("Capsule crowds the matched-approach standoff (margin %.2f) — "
				% margin + "lower WRECK_RADIUS or tighten the capsule.")
	print("Saved to %s" % SHIP_DEF)
	get_tree().quit(0)


## Replace (or append) the three collision_ lines in the .tres text, leaving
## every other authored line untouched. Values go through _fmt (fixed 0.001
## precision, trailing zeros trimmed) so raw float32 AABB noise (-0.70000005)
## doesn't leak into the file and a re-bake of an unchanged model produces no diff.
func _patch_collision_lines(a: Vector3, b: Vector3, radius: float) -> int:
	var text := FileAccess.get_file_as_string(SHIP_DEF)
	if text.is_empty():
		return ERR_FILE_CANT_READ
	var kept: Array[String] = []
	for line in text.split("\n"):
		var head: String = line.strip_edges()
		if head.begins_with("collision_a =") or head.begins_with("collision_b =") \
				or head.begins_with("collision_radius ="):
			continue
		kept.append(line)
	while kept.size() > 0 and kept[kept.size() - 1].strip_edges().is_empty():
		kept.remove_at(kept.size() - 1)
	kept.append("collision_a = " + _vec_literal(a))
	kept.append("collision_b = " + _vec_literal(b))
	kept.append("collision_radius = " + _fmt(radius))
	var out := FileAccess.open(SHIP_DEF, FileAccess.WRITE)
	if out == null:
		return FileAccess.get_open_error()
	out.store_string("\n".join(kept) + "\n")
	out.close()
	return OK


func _vec_literal(v: Vector3) -> String:
	return "Vector3(%s, %s, %s)" % [_fmt(v.x), _fmt(v.y), _fmt(v.z)]


## Fixed 0.001-precision float literal with trailing zeros trimmed (GDScript's
## % operator has no %g), so the written .tres is clean and re-bake-stable.
func _fmt(x: float) -> String:
	if absf(x) < 0.0005:
		return "0"
	var s := "%.3f" % x
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s
