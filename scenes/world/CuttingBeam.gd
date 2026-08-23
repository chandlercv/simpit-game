extends TorchBeam
## The cutting torch as a world-space beam fired from the Kestrel's right wing to
## the cut point on the wreck. The beam's body — the cylinder, the additive
## material, the impact glow — is TorchBeam; this is the Kestrel's half: when it
## fires and what it is pointed at. View-side only (reads GameState, mutates
## nothing):
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

var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	var aligning := GameState.align_state == "ALIGNING"
	var cutting: int = GameState.wreck.get("cutting_id", -1)
	if GameState.run_phase != "ON_SITE" or not (aligning or cutting != -1):
		extinguish()
		return
	var xform: Transform3D = GameState.local_ship()["transform"]
	var origin: Vector3 = xform * EMITTER_LOCAL
	var target = _cut_point(aligning, cutting, xform)
	if target == null:
		extinguish()
		return
	_orient(origin, target)


## The beam's far end: the aimed point while ALIGNING (reticle projected back into
## the member's plane), else the member being cut. null when there's no member.
func _cut_point(aligning: bool, cutting_id: int, xform: Transform3D) -> Variant:
	if aligning:
		var member := GameState.get_member(GameState.selected_member_id)
		if not member.has("center") or GameState.align.is_empty():
			return null
		# Named seam_span, not span: TorchBeam.span() is a method on this class now.
		var seam_span: float = maxf(float(member.get("radius", 1.0)), 0.5) * SalvageSystem.ALIGN_SEAM_SPAN
		var r := Vector2(GameState.align["reticle"])
		# Inverse of SalvageSystem._seam_offset: walk out from the centroid in the
		# ship's right/up plane by the reticle, so aim lands on the seam when locked.
		return (member["center"] as Vector3) + xform.basis.x * (r.x * seam_span) - xform.basis.y * (r.y * seam_span)
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


## Set the beam's look for the current phase, with a little flicker so it reads as
## live plasma, and hand the span to TorchBeam to stretch. The impact glow only
## bites while actually cutting — a targeting beam is not burning anything.
func _orient(origin: Vector3, target: Vector3) -> void:
	var cutting: bool = GameState.wreck.get("cutting_id", -1) != -1
	var flicker := 0.85 + 0.15 * sin(_time * TAU * (11.0 if cutting else 6.0))
	span(origin, target,
			(CUT_RADIUS if cutting else ALIGN_RADIUS) * flicker,
			CUT_COLOR if cutting else ALIGN_COLOR,
			(0.9 if cutting else 0.55) * flicker,
			4.0 if cutting else 1.5,
			2.0 * flicker if cutting else 0.0)
