extends Node
## Owns adrift salvage pieces: a cut member becomes a physical, drifting body
## (GameState.salvage_pieces) instead of teleporting straight into the hold.
## Integrates each piece's hand-integrated drift, keeps its collidable obstacle
## and sensor contact glued to it, and runs the player's scoop-collection
## interaction. ThreatSystem drives the rival's half of the same loop through
## collect_for_rival().
##
## Autoload order matters: this runs AFTER SalvageSystem/ThreatSystem (so a cut
## completing this frame spawns a piece before it's first integrated) and
## BEFORE CollisionSystem (so a piece's position this frame is settled before
## collision tests it and may write a fresh impulse into its obstacle's "vel"
## for DriftSystem to pick up next frame — the same owner/collider split
## SalvageSystem's ship integration and CollisionSystem's bounce already use).
##
## Motion has no engine physics behind it, same as everywhere else in this
## project: a piece is a Dictionary carrying transform/velocity, mirrored each
## frame into its GameState.obstacles entry so CollisionSystem can test and
## push it, and into a zero-radius sensor contact so Tactical can track it.

## Outward speed a severed piece gets on top of the member's orbital velocity
## at the instant of the cut (see SalvageSystem._publish_world's v = ω × r) —
## reads as the torch's parting kick, not just inheriting the wreck's spin.
const SEPARATION_KICK := 0.6

## Cosmetic post-cut tumble band, gentler than the intact wreck's (a loose
## piece reads as drifting, not spinning).
const TUMBLE_RATE_MIN := 0.05
const TUMBLE_RATE_MAX := 0.25

## Drift speed ceiling so a hard collision knock doesn't fling a piece off to
## infinity and out of reach.
const MAX_DRIFT_SPEED := 6.0

## Collection gates (all must hold, hatch open being the prerequisite the
## player controls directly): surface-to-surface range, relative speed, and
## the forward cone the hatch has to face the piece within.
const SCOOP_RANGE := 4.0
const COLLECT_REL_SPEED := 1.5
const COLLECT_CONE_DEG := 35.0
## Seconds of steady holding (all gates true) to fill the scoop from 0 to 1.
const SCOOP_TIME := 1.5
## Scoop bleeds off faster than it fills once a gate breaks, so a botched
## approach reads immediately rather than lingering near-full.
const SCOOP_DECAY_MULT := 1.5

var _rng := RandomNumberGenerator.new()
var _next_piece_id := 0


func _ready() -> void:
	_rng.randomize()
	GameState.site_reset.connect(_on_site_reset)


func _physics_process(delta: float) -> void:
	if GameState.run_phase != "ON_SITE":
		return
	for piece: Dictionary in GameState.salvage_pieces:
		_integrate_piece(piece, delta)
	_update_collection(delta)


## --- Intents (SalvageSystem / ThreatSystem) --------------------------------


## SalvageSystem._complete_cut / rival_strip_member: a member was just severed
## — detach it as a drifting, collectible body instead of stowing it directly.
## `qty` is the already quality-scaled yield (SalvageSystem owns that math, the
## same as before this change). Returns the new piece id.
func spawn_piece(member: Dictionary, qty: float) -> int:
	var center: Vector3 = member.get("center", GameState.wreck.get("position", Vector3.ZERO))
	var seam: Vector3 = member.get("seam", center)
	var radius: float = maxf(float(member.get("radius", 1.5)), 0.6)
	# Kick outward along the seam-from-centroid direction — the side the torch
	# cut from — so the piece visibly parts from the hull, not just floats off
	# on its inherited orbital velocity.
	var outward := seam - center
	outward = outward.normalized() if outward.length() > 0.01 else Vector3.UP
	var base_vel: Vector3 = member.get("vel", Vector3.ZERO)
	var velocity := base_vel + outward * SEPARATION_KICK
	var id := _next_piece_id
	_next_piece_id += 1
	var piece := {
		"id": id,
		"member_id": member["id"],
		"name": member["name"],
		"good": member["good"],
		"qty": qty,
		"transform": Transform3D(Basis.IDENTITY, center),
		"velocity": velocity,
		"omega": _random_tumble(),
		"radius": radius,
		"obstacle_id": -1,
		"contact_id": -1,
		"scoop": 0.0,
		# Wreck.tscn child name — SalvagePieces duplicates that mesh subtree as
		# the free-floating visual and hands back the real starting pose.
		"node": member["node"],
	}
	# A movable sphere body (no hull: pieces collide as spheres, simpler than
	# baking a hull for a body that's constantly translating) so CollisionSystem
	# can push and be pushed by it.
	piece["obstacle_id"] = GameState.register_obstacle(
			"SALVAGE: %s" % member["name"], center, radius, PackedVector3Array(),
			false, CollisionSystem.body_mass(radius))
	var obstacle := GameState.get_obstacle(piece["obstacle_id"])
	if not obstacle.is_empty():
		obstacle["vel"] = velocity
	piece["contact_id"] = GameState.register_contact(
			"SALVAGE: %s" % member["name"], center)
	GameState.add_salvage_piece(piece)
	GameState.post_comms("SALVAGE", "%s ADRIFT — OPEN HATCH TO COLLECT" % member["name"])
	return id


## ThreatSystem: the rival closed on its own severed piece and held long
## enough to claim it. Same removal as a player scoop, minus the stow — the
## yield is kept by the rival narratively, nothing lands in our hold.
func collect_for_rival(id: int) -> void:
	_despawn(id)


## --- Queries (read-only, safe for displays) --------------------------------


## Whether the collection loop is actually running. _process pauses off-site,
## and docking does NOT remove pieces that were still adrift — they stay frozen
## in GameState.salvage_pieces until the next site reset clears them on arrival
## back at the claim. Instruments must ask this before drawing a rendezvous:
## collection_status happily keeps evaluating a frozen piece, and live range,
## drift and gate readings for something you cannot reach (or even see, having
## left the claim) are worse than showing nothing.
func is_collecting() -> bool:
	return GameState.run_phase == "ON_SITE"


## The adrift piece closest to the ship, {} when nothing is adrift. The scoop
## takes whichever piece meets the gates, so the instruments (the MFD SCOOP
## page) work off this one — the piece you're realistically flying.
func nearest_piece() -> Dictionary:
	var ship_pos: Vector3 = (GameState.local_ship()["transform"] as Transform3D).origin
	var best: Dictionary = {}
	var best_dist := INF
	for piece: Dictionary in GameState.salvage_pieces:
		var dist := ship_pos.distance_to((piece["transform"] as Transform3D).origin)
		if dist < best_dist:
			best_dist = dist
			best = piece
	return best


## Full gate evaluation for one piece, in one place: _update_collection scoops
## from this and the SCOOP page / HUD read from it, so the numbers on the
## instruments are exactly the ones the scoop tests — no parallel copy of the
## math to drift out of step. {} for an empty piece.
##
## Directions come back in the reticle convention the rest of the UI uses
## (+x screen-right, +y screen-down), relative to the ship's nose:
##   aim         — where the piece sits off the nose; the vector's MAGNITUDE is
##                 the off-axis angle in degrees, so `aim.length() <= cone` is
##                 exactly the cone gate, and its direction is which way to steer
##   rel_lateral — the piece's velocity relative to ours across the line of sight
##                 (m/s): which way it's sliding, and so which way to thrust
##   closure     — relative speed along the line of sight, + = closing
func collection_status(piece: Dictionary) -> Dictionary:
	if piece.is_empty():
		return {}
	var ship: Dictionary = GameState.local_ship()
	var xform: Transform3D = ship["transform"]
	var pos: Vector3 = (piece["transform"] as Transform3D).origin
	var to_piece: Vector3 = pos - xform.origin
	var dist := to_piece.length()
	var los := to_piece / dist if dist > 0.0001 else -xform.basis.z
	# Hull-to-surface, measured off the ship's REACH (the far end of its
	# collision capsule), not just the capsule's radius: the Kestrel is
	# elongated, so radius-only overstated the real clearance by ~1.2 m and the
	# SCOOP page read "in range" while the nose was already nearly touching.
	var gap := dist - CollisionSystem.ship_reach() - float(piece["radius"])
	var rel: Vector3 = (piece["velocity"] as Vector3) - (ship.get("velocity", Vector3.ZERO) as Vector3)
	var rel_speed := rel.length()
	var inv := xform.basis.inverse()
	# Off-nose angle, and the screen direction to steer to close it.
	var local := inv * los
	var off_axis := rad_to_deg(acos(clampf(-local.z, -1.0, 1.0)))
	var lateral := Vector2(local.x, -local.y)
	var aim := (lateral.normalized() * off_axis) if lateral.length() > 0.0001 else Vector2.ZERO
	var rel_local := inv * rel
	# The aperture, not the lever: a door still travelling will not take a piece.
	var hatch: bool = GameState.hatch_open_locked()
	var in_range := gap < SCOOP_RANGE
	var speed_ok := rel_speed < COLLECT_REL_SPEED
	var in_cone := off_axis <= COLLECT_CONE_DEG
	return {
		"id": piece["id"],
		"name": piece["name"],
		"range": dist,
		"gap": gap,
		"rel_speed": rel_speed,
		"off_axis": off_axis,
		"aim": aim,
		"rel_lateral": Vector2(rel_local.x, -rel_local.y),
		"closure": rel.dot(-los),
		"scoop": float(piece.get("scoop", 0.0)),
		"hatch": hatch,
		"in_range": in_range,
		"speed_ok": speed_ok,
		"in_cone": in_cone,
		"gated": hatch and in_range and speed_ok and in_cone,
	}


## --- Per-frame simulation ---------------------------------------------------


## Advance one piece's drift and keep its obstacle/contact glued to it. Velocity
## AND position are read from the OBSTACLE, not the piece dict, because
## CollisionSystem may have written a fresh impulse into obstacle["vel"] and a
## push-out into obstacle["position"] last tick (ship ram, a movable-pair knock,
## or contact with the station/derelict) — same owner/collider split as the
## ship's own velocity. Reading the position back is what makes a piece SOLID
## against static geometry: without it this line would overwrite the push-out
## from the piece's own transform every tick and the piece would sink through.
func _integrate_piece(piece: Dictionary, delta: float) -> void:
	var obstacle := GameState.get_obstacle(int(piece["obstacle_id"]))
	var vel: Vector3 = (obstacle["vel"] if not obstacle.is_empty() else piece["velocity"])
	vel = vel.limit_length(MAX_DRIFT_SPEED)
	var xform: Transform3D = piece["transform"]
	if not obstacle.is_empty():
		xform.origin = obstacle["position"]
	xform.origin += vel * delta
	var omega: Vector3 = piece["omega"]
	if omega.length() > 0.0001:
		xform.basis = xform.basis.rotated(omega.normalized(), omega.length() * delta)
	piece["transform"] = xform
	piece["velocity"] = vel
	if not obstacle.is_empty():
		obstacle["position"] = xform.origin
		obstacle["vel"] = vel
	var contact := GameState.get_contact(int(piece["contact_id"]))
	if not contact.is_empty():
		contact["position"] = xform.origin


## The player's scoop: every adrift piece checks the same four gates each frame
## (hatch open, in range, relative speed nulled, inside the forward cone — all
## evaluated by collection_status, which the instruments read too) and
## fills/bleeds a 0..1 scoop meter. Crossing 1.0 attempts the stow.
func _update_collection(delta: float) -> void:
	for piece: Dictionary in GameState.salvage_pieces.duplicate():
		var status := collection_status(piece)
		var was_ready: bool = float(piece["scoop"]) >= 1.0
		if status["gated"]:
			piece["scoop"] = minf(float(piece["scoop"]) + delta / SCOOP_TIME, 1.0)
		else:
			piece["scoop"] = maxf(
					float(piece["scoop"]) - delta / SCOOP_TIME * SCOOP_DECAY_MULT, 0.0)
		if float(piece["scoop"]) >= 1.0 and not was_ready:
			_try_stow(piece)


func _try_stow(piece: Dictionary) -> void:
	if CargoSystem.stow_salvage(piece["name"], piece["good"], piece["qty"]):
		_despawn(int(piece["id"]))
	else:
		# Hold full: CargoSystem already posted the ADRIFT line. Reset instead
		# of holding at 1.0 so the pilot isn't stuck re-triggering a failed
		# stow every frame — jettison something and come back around.
		piece["scoop"] = 0.0


func _despawn(id: int) -> void:
	var piece := GameState.get_salvage_piece(id)
	if piece.is_empty():
		return
	if int(piece.get("obstacle_id", -1)) != -1:
		GameState.remove_obstacle(piece["obstacle_id"])
	if int(piece.get("contact_id", -1)) != -1:
		GameState.remove_contact(piece["contact_id"])
	GameState.remove_salvage_piece(id)


func _on_site_reset() -> void:
	for piece: Dictionary in GameState.salvage_pieces.duplicate():
		_despawn(int(piece["id"]))


func _random_tumble() -> Vector3:
	var axis := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0))
	axis = axis.normalized() if axis.length() > 0.01 else Vector3.UP
	return axis * _rng.randf_range(TUMBLE_RATE_MIN, TUMBLE_RATE_MAX)


## The ship's extent comes from CollisionSystem.ship_reach() (see
## collection_status), so there's no local copy of the capsule fallback here.
