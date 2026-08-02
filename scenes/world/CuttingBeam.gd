extends MeshInstance3D
## The cutting torch as a world-space beam fired from the Kestrel's right wing to
## the cut point on the wreck. View-side only (reads GameState, mutates nothing):
##
##   ALIGNING — a thin targeting beam painting where the torch is aimed (the pilot
##     reticle mapped back into 3D via the same ship-axis projection SalvageSystem
##     uses for the seam), so lining the reticle up on the seam visibly walks the
##     beam onto the member.
##   CUTTING  — a thick, hot, flickering beam locked onto the member being severed,
##     with an impact glow at the contact point.
##
## Hidden any other time. `top_level` keeps this node in world space so it can span
## two world points regardless of the ship's transform; the emitter is derived from
## the ship pose each frame so the beam stays pinned to the wing.

## Right-side cutter hardpoint, in the ship's local frame. The hull camera sits near
## the nose (local z -0.55, looking down -z), so most of the craft_miner hull — the
## real right wingtip included, measured at (0.9, -0.55, 0.9) — is BEHIND the eye and
## a beam from there would streak across the view. This is the rightmost point still
## in front of the camera (the front-right hull corner), so the beam stays pinned to
## the ship and enters from the lower-right rather than floating out ahead of the nose.
const EMITTER_LOCAL := Vector3(0.69, -0.73, -0.7)

const ALIGN_COLOR := Color(1.0, 0.55, 0.2)
const CUT_COLOR := Color(1.0, 0.85, 0.5)
const ALIGN_RADIUS := 0.03
const CUT_RADIUS := 0.07

var _mat: StandardMaterial3D
var _impact: OmniLight3D
var _time := 0.0


func _ready() -> void:
	top_level = true
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 0
	mesh = cyl
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _mat
	_impact = OmniLight3D.new()
	_impact.omni_range = 3.0
	_impact.light_color = CUT_COLOR
	_impact.top_level = true
	_impact.visible = false
	add_child(_impact)
	visible = false


func _process(delta: float) -> void:
	_time += delta
	var aligning := GameState.align_state == "ALIGNING"
	var cutting: int = GameState.wreck.get("cutting_id", -1)
	if GameState.run_phase != "ON_SITE" or not (aligning or cutting != -1):
		visible = false
		_impact.visible = false
		return
	var xform: Transform3D = GameState.local_ship()["transform"]
	var origin: Vector3 = xform * EMITTER_LOCAL
	var target = _cut_point(aligning, cutting, xform)
	if target == null:
		visible = false
		_impact.visible = false
		return
	_orient(origin, target)


## The beam's far end: the aimed point while ALIGNING (reticle projected back into
## the member's plane), else the member being cut. null when there's no member.
func _cut_point(aligning: bool, cutting_id: int, xform: Transform3D) -> Variant:
	if aligning:
		var member := GameState.get_member(GameState.selected_member_id)
		if not member.has("center") or GameState.align.is_empty():
			return null
		var span: float = maxf(float(member.get("radius", 1.0)), 0.5) * SalvageSystem.ALIGN_SEAM_SPAN
		var r := Vector2(GameState.align["reticle"])
		# Inverse of SalvageSystem._seam_offset: walk out from the centroid in the
		# ship's right/up plane by the reticle, so aim lands on the seam when locked.
		return (member["center"] as Vector3) + xform.basis.x * (r.x * span) - xform.basis.y * (r.y * span)
	# Cutting: bite at the seam — a real hull vertex, so the beam always lands on
	# geometry. (The centroid can sit in empty space for hollow members like the
	# corridor-built aft hull or the ring spine.) The HUD cut-target diamond moves to
	# the same seam during the cut, so beam and marker still coincide.
	var cut_member := GameState.get_member(cutting_id)
	if cut_member.has("seam"):
		return cut_member["seam"]
	if cut_member.has("center"):
		return cut_member["center"]
	return null


## Stretch the cylinder (native axis +Y) to span origin→target and set the beam's
## look for the current phase, with a little flicker so it reads as live plasma.
func _orient(origin: Vector3, target: Vector3) -> void:
	var dir := target - origin
	var length := dir.length()
	if length < 0.01:
		visible = false
		_impact.visible = false
		return
	visible = true
	var y := dir / length
	var x := y.cross(Vector3.UP)
	if x.length() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var cutting: bool = GameState.wreck.get("cutting_id", -1) != -1
	var flicker := 0.85 + 0.15 * sin(_time * TAU * (11.0 if cutting else 6.0))
	var radius := (CUT_RADIUS if cutting else ALIGN_RADIUS) * flicker
	global_transform = Transform3D(
			Basis(x * radius, y * length, z * radius), origin + dir * 0.5)
	var col := CUT_COLOR if cutting else ALIGN_COLOR
	_mat.albedo_color = Color(col, (0.9 if cutting else 0.55) * flicker)
	_mat.emission_enabled = true
	_mat.emission = col
	_mat.emission_energy_multiplier = 4.0 if cutting else 1.5
	# Impact glow only bites while actually cutting.
	_impact.visible = cutting
	if cutting:
		_impact.global_position = target
		_impact.light_energy = 2.0 * flicker
