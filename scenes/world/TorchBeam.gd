class_name TorchBeam
extends MeshInstance3D
## The body of a cutting torch's beam, shared by everyone who fires one: an
## additive, unshaded cylinder stretched between two world points with a glow at
## the far end. What it looks like is here; WHEN it fires and where it points
## belongs to the subclass.
##
## `top_level` keeps the node in world space, so a beam can span two world points
## regardless of what the ship carrying it is doing.
##
## Two torches use it today — scenes/world/CuttingBeam.gd for the Kestrel's, which
## reads the pilot's alignment and cut state every frame, and
## scenes/world/RivalTorch.gd for the rival's, which is a one-shot flash on a
## signal. They agree on the look because they share this and nothing else.

var _mat: StandardMaterial3D
var _impact: OmniLight3D


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
	_impact.light_color = Color(1.0, 0.85, 0.5)
	_impact.top_level = true
	_impact.visible = false
	add_child(_impact)
	visible = false


## Stretch the cylinder (native axis +Y) to span origin→target and set the beam's
## look. `impact_energy` above zero puts a glow on the far end where the torch is
## biting. Returns false — and hides the beam — for a span too short to orient.
func span(origin: Vector3, target: Vector3, radius: float, color: Color,
		alpha: float, energy: float, impact_energy := 0.0) -> bool:
	var dir := target - origin
	var length := dir.length()
	if length < 0.01:
		extinguish()
		return false
	visible = true
	var y := dir / length
	var x := y.cross(Vector3.UP)
	if x.length() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	global_transform = Transform3D(
			Basis(x * radius, y * length, z * radius), origin + dir * 0.5)
	_mat.albedo_color = Color(color, alpha)
	_mat.emission_enabled = true
	_mat.emission = color
	_mat.emission_energy_multiplier = energy
	_impact.visible = impact_energy > 0.0
	if impact_energy > 0.0:
		_impact.global_position = target
		_impact.light_color = color
		_impact.light_energy = impact_energy
	return true


func extinguish() -> void:
	visible = false
	if _impact != null:
		_impact.visible = false
