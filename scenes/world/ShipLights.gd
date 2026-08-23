class_name ShipLights
extends Node3D
## The standard exterior light fit, worn by every ship in the world: the Kestrel
## and both of ThreatSystem's. Written once and measured off the hull it is bolted
## to, so the three of them carry the same scheme rather than three hand-placed
## approximations of it that drift apart.
##
## The fit is the ordinary one:
##   NAV     red to port, green to starboard, white on the tail. Steady.
##   STROBE  white, on both wingtips and the tail. A double pulse, about 1 Hz.
##   BEACON  red, above and below the fuselage. A slow flash, about 45 a minute.
##
## MOUNTS ARE MEASURED, NOT WRITTEN DOWN. build() merges the AABBs of every
## MeshInstance3D under the hull — the same technique tools/ShipColliderBake.gd
## uses to fit the ship's collision capsule, and it absorbs the Kestrel's offset
## Hull node for free — and hangs the lights off that box's extremes. Re-export a
## model wider and the wingtip lights move out with it; nothing here needs editing.
##
## View-only, like every other node under DebrisField: it reads GameState and
## mutates nothing.

## Each light is an additive unshaded billboard rather than an OmniLight3D alone.
## An omni casts light on nearby surfaces but has no visible body, which is fine at
## ten metres and useless at a hundred — and a hundred is where you are when you
## are trying to work out what a contact is. The quad reads as a source at any
## range, and it clears the environment's glow_hdr_threshold so it blooms.
## Kept only just over the environment's glow_hdr_threshold for the steady lamps.
## Higher and the bloom swells a 0.15 m lamp into a blob the size of the ship
## carrying it, which is worse at every range, not just close up.
const NAV_ENERGY := 2.0
const STROBE_ENERGY := 7.0
const BEACON_ENERGY := 4.0

const PORT_COLOR := Color(1.0, 0.09, 0.06)
const STARBOARD_COLOR := Color(0.09, 1.0, 0.22)
const TAIL_COLOR := Color(1.0, 0.97, 0.92)
const STROBE_COLOR := Color(1.0, 1.0, 1.0)
const BEACON_COLOR := Color(1.0, 0.11, 0.05)

## Flash timings, in seconds. Anti-collision beacons run about 45 a minute and
## strobes about 60, and the strobe fires as a double pulse — which is most of what
## makes a strobe read as a strobe rather than a blinking lamp.
const BEACON_PERIOD := 1.35
const BEACON_ON := 0.22
const STROBE_PERIOD := 1.0
const STROBE_PULSE := 0.05
const STROBE_GAP := 0.12

## Billboard size as a fraction of the hull's longest horizontal dimension, floored
## so a small hull still gets a lamp you can pick out.
const LAMP_SCALE := 0.05
const LAMP_MIN := 0.10

## Visual layer the OWN SHIP's lamps are put on (layer 2), so the hull camera can
## be told not to draw them.
##
## The pilot's eye sits INSIDE his own light fit — the wingtip lamps are less than
## a metre either side of it — so from that seat an additive, blooming quad is a
## sheet of white across half the windscreen rather than a light on a wingtip. The
## external camera keeps the layer and still sees the ship lit correctly, and the
## omni lights are not moved, so the hull goes on being lit by its own lamps from
## every view. See HullCameraRig.tscn's cull_mask, which is the other half of this.
const OWN_SHIP_LAMP_LAYER := 1 << 1

## One entry per lamp: { "group": String, "quad": MeshInstance3D, "omni": OmniLight3D }.
var _lamps: Array[Dictionary] = []
## Group -> whether it is currently selected on.
var _on: Dictionary = {"NAV": true, "BEACON": true, "STROBE": true}
## Own-ship lights follow the panel switches and the bus; the AI ships are simply
## always lit. GameState's electrical state is the KESTREL's, and flipping her
## master must not put a rival's navigation lights out.
var _follow_ship_state := false
var _time := 0.0


## Bolt the fit onto `host`, measured off the meshes under `hull`. `follow_state`
## makes the groups obey GameState (own ship only); `with_omni` adds a real light
## to the nav pair and the beacons, which is worth it on the hull you fly inside
## and not on a contact 150 m away.
static func attach(host: Node3D, hull: Node3D, follow_state := false,
		with_omni := false) -> ShipLights:
	var rig := ShipLights.new()
	rig.name = "ShipLights"
	rig._follow_ship_state = follow_state
	host.add_child(rig)
	rig._build(host, hull, with_omni)
	return rig


func _ready() -> void:
	# A phase offset per ship, so several in one volume never flash in lockstep.
	_time = randf() * BEACON_PERIOD
	if _follow_ship_state:
		GameState.exterior_lights_changed.connect(_refresh)
		GameState.power_changed.connect(_refresh)
		_refresh()


func _process(delta: float) -> void:
	_time += delta
	for lamp: Dictionary in _lamps:
		var lit: bool = bool(_on.get(lamp["group"], false)) and _phase(lamp["group"])
		(lamp["quad"] as MeshInstance3D).visible = lit
		var omni: OmniLight3D = lamp["omni"]
		if omni != null:
			omni.visible = lit


## Whether a group's flash is in its ON window this instant. NAV is steady.
func _phase(group: String) -> bool:
	match group:
		"BEACON":
			return fmod(_time, BEACON_PERIOD) < BEACON_ON
		"STROBE":
			var t := fmod(_time, STROBE_PERIOD)
			return t < STROBE_PULSE or (t >= STROBE_GAP and t < STROBE_GAP + STROBE_PULSE)
	return true


## Selected on/off for one group. The own ship routes GameState here; the AI ships
## never call it.
func set_group(group: String, on: bool) -> void:
	_on[group] = on


## Own ship: a group burns only if it is switched on AND the bus can carry it, so a
## dark ship goes dark outside too. Both halves of that live in GameState, which is
## what keeps the checklists and the signature agreeing with what the pilot can
## actually see out of the window.
func _refresh() -> void:
	for group: String in _on:
		set_group(group, GameState.light_group_lit(group))


# --- Construction -----------------------------------------------------------

func _build(host: Node3D, hull: Node3D, with_omni: bool) -> void:
	var box := _hull_box(host, hull)
	if box.size == Vector3.ZERO:
		push_warning("ShipLights: no MeshInstance3D under %s — no lights fitted"
				% hull.name)
		return
	var centre := box.get_center()
	var lamp := maxf(maxf(box.size.x, box.size.z) * LAMP_SCALE, LAMP_MIN)
	# Forward is -z, so the tail is the box's FAR face.
	var port := box.position.x
	var starboard := box.end.x
	var tail := box.end.z
	# Strobes sit just aft of the position lights on the same wingtip, the way they
	# do on a real tip fairing, so the two never occupy one point.
	var strobe_z: float = centre.z + box.size.z * 0.12

	_add("NAV", Vector3(port, centre.y, centre.z), PORT_COLOR, NAV_ENERGY,
			lamp, with_omni)
	_add("NAV", Vector3(starboard, centre.y, centre.z), STARBOARD_COLOR,
			NAV_ENERGY, lamp, with_omni)
	_add("NAV", Vector3(centre.x, centre.y, tail), TAIL_COLOR, NAV_ENERGY,
			lamp, false)
	_add("STROBE", Vector3(port, centre.y, strobe_z), STROBE_COLOR,
			STROBE_ENERGY, lamp, false)
	_add("STROBE", Vector3(starboard, centre.y, strobe_z), STROBE_COLOR,
			STROBE_ENERGY, lamp, false)
	_add("STROBE", Vector3(centre.x, centre.y, tail), STROBE_COLOR,
			STROBE_ENERGY, lamp * 0.8, false)
	_add("BEACON", Vector3(centre.x, box.end.y, centre.z), BEACON_COLOR,
			BEACON_ENERGY, lamp, with_omni)
	_add("BEACON", Vector3(centre.x, box.position.y, centre.z), BEACON_COLOR,
			BEACON_ENERGY, lamp, with_omni)


## The hull's bounding box in `host`-local space. MeshInstance3D only, so a camera
## rig or an existing light under the hull is not measured as structure.
func _hull_box(host: Node3D, hull: Node3D) -> AABB:
	var to_local := host.global_transform.affine_inverse()
	var merged := AABB()
	var have_box := false
	for node in hull.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		if mi.mesh == null:
			continue
		var box := (to_local * mi.global_transform) * mi.get_aabb()
		merged = box if not have_box else merged.merge(box)
		have_box = true
	return merged if have_box else AABB()


func _add(group: String, at: Vector3, color: Color, energy: float, size: float,
		with_omni: bool) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	# Same treatment as the cutting torch: unshaded and additive, so the lamp is a
	# source rather than a lit surface and it survives being seen against the sun.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.disable_receive_shadows = true
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	quad.material = mat

	var node := MeshInstance3D.new()
	node.mesh = quad
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _follow_ship_state:
		node.layers = OWN_SHIP_LAMP_LAYER
	add_child(node)

	var omni: OmniLight3D = null
	if with_omni:
		omni = OmniLight3D.new()
		omni.position = at
		omni.light_color = color
		omni.light_energy = 0.7
		omni.omni_range = maxf(size * 24.0, 3.0)
		omni.shadow_enabled = false
		add_child(omni)

	_lamps.append({"group": group, "quad": node, "omni": omni})
