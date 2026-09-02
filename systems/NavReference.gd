extends Node
## The navigation reference datum: what altitude, heading, range and attitude
## are all measured against.
##
## In space none of those four readings mean anything on their own. A datum
## supplies the missing half — an ORIGIN (what range is measured to, and where
## the altitude plane sits) and a FRAME (`up`, the plane's normal; `north`, the
## zero-bearing direction in it). Every readout on the Tactical instrument band
## comes from one datum, so they cannot disagree about which way is up.
##
## Read-only. This node mutates nothing: the selection lives on
## GameState.nav_reference and everything here derives from it plus the ship
## state. Safe for any display to call from _draw().
##
## WRECK and TARGET deliberately borrow the STATION's up/north rather than the
## object's own basis. A derelict tumbles, and an attitude horizon pinned to a
## tumbling body is unusable — what the object supplies is the origin, so ALT
## reads height above a level plane through it and RNG reads distance to it.

## Datum catalogue. Data, not a match statement, so a real planetoid becomes one
## more entry once one exists in the world with a world position.
const DATUMS: Array[Dictionary] = [
	{"id": "AUTO", "label": "AUTO"},
	{"id": "PAD", "label": "LANDING PLATFORM"},
	{"id": "WRECK", "label": "DERELICT"},
	{"id": "TARGET", "label": "CUT TARGET"},
	{"id": "INERTIAL", "label": "INERTIAL"},
]

## What the ADI's ground field is captioned with, per resolved datum.
const PLANE_LABELS: Dictionary = {
	"PAD": "PLATFORM PLANE",
	"WRECK": "DERELICT PLANE",
	"TARGET": "TARGET PLANE",
	"INERTIAL": "INERTIAL",
}


func label_for(id: String) -> String:
	for entry: Dictionary in DATUMS:
		if entry["id"] == id:
			return String(entry["label"])
	return id


## --- Resolution -------------------------------------------------------------

## The datum in force, resolved to a frame:
##   id / label   — what it resolved TO (never "AUTO")
##   auto         — true when AUTO picked it rather than the pilot
##   origin       — world point; range is to here, the altitude plane passes here
##   velocity     — how fast the origin itself is going, world frame. Subtract it
##                  from the ship's to get a reading RELATIVE to the datum, which
##                  is what every reading here is supposed to be
##   up           — plane normal (unit)
##   north        — zero bearing in the plane (unit, perpendicular to up)
##   east         — north x up, the handedness heading is measured with
##   plane_label  — caption for the ADI's ground field
##   fallback     — true when the pinned datum has no fix and this is a stand-in
##   reason       — why, when it does
func datum() -> Dictionary:
	var wanted: String = GameState.nav_reference
	var auto := wanted == "AUTO"
	var resolved := _auto_pick() if auto else wanted
	var out := _resolve(resolved)
	if not out["valid"] and not auto:
		# A pinned datum that lost its fix falls back the way AUTO would, and
		# says so — rather than reporting an altitude above an origin that is
		# not there.
		var reason: String = out["reason"]
		out = _resolve(_auto_pick())
		out["fallback"] = true
		out["reason"] = reason
	out["auto"] = auto
	return out


## AUTO's order of preference: the approach being flown beats the piece being
## cut, which beats the hull it came off, which beats nothing at all.
func _auto_pick() -> String:
	if DockingSystem.is_active():
		return "PAD"
	if _target_origin() != null:
		return "TARGET"
	if _wreck_origin() != null:
		return "WRECK"
	return "INERTIAL"


func _resolve(id: String) -> Dictionary:
	var station := DockingSystem.station_transform()
	var up := station.basis.y.normalized()
	var north := (-station.basis.z).normalized()
	var origin := Vector3.ZERO
	# What the datum itself is doing. The station, its pad and a derelict on site
	# are all static in world space today, so this is zero for them — but it is
	# resolved here rather than assumed, because TARGET is NOT: it can be pinned
	# to a rival under way or a traffic ship on its route, and then every reading
	# taken against this datum has to have this subtracted from it.
	var velocity := Vector3.ZERO
	var valid := true
	var reason := ""
	match id:
		"PAD":
			origin = DockingSystem.pad_world()
			up = DockingSystem.pad_up()
			north = DockingSystem.pad_forward()
		"WRECK":
			var wreck_at: Variant = _wreck_origin()
			if wreck_at == null:
				valid = false
				reason = "NO DERELICT ON SITE"
			else:
				origin = wreck_at
		"TARGET":
			var target_at: Variant = _target_origin()
			if target_at == null:
				valid = false
				reason = "NO TARGET SELECTED"
			else:
				origin = target_at
				velocity = _target_velocity()
		_:
			id = "INERTIAL"
			up = Vector3.UP
			north = Vector3.FORWARD
	# Re-orthogonalise rather than trusting the source transform: a scaled or
	# skewed station basis would otherwise make every heading subtly wrong, and
	# a degenerate one would put NaN through every readout on the band.
	up = up.normalized()
	north = north - up * north.dot(up)
	if not up.is_finite() or not north.is_finite() or north.length_squared() < 0.000001:
		up = Vector3.UP
		north = Vector3.FORWARD
	north = north.normalized()
	return {
		"id": id,
		"label": label_for(id),
		"auto": false,
		"origin": origin,
		"velocity": velocity,
		"up": up,
		"north": north,
		"east": north.cross(up),
		"plane_label": String(PLANE_LABELS.get(id, id)),
		"valid": valid,
		"fallback": false,
		"reason": reason,
	}


## The derelict's world position, or null when there is no wreck on site.
func _wreck_origin() -> Variant:
	var wreck: Dictionary = GameState.wreck
	if wreck.is_empty() or not wreck.has("position"):
		return null
	return wreck["position"] as Vector3


## The selected cut member's world centre, else the designated contact, else
## null. Both are things the pilot deliberately picked, which is what makes them
## reasonable to measure a run against.
##
## A member's centre is baked by the 3D wreck, so it falls back to the wreck's
## own centre when there is no 3D scene — the same idiom, and the same reason,
## as SalvageSystem's approach target.
func _target_origin() -> Variant:
	var member := GameState.get_member(GameState.selected_member_id)
	if not member.is_empty():
		var wreck_at: Variant = _wreck_origin()
		if member.has("center"):
			return member["center"] as Vector3
		if wreck_at != null:
			return wreck_at
	var contact := GameState.get_contact(GameState.tracked_contact_id)
	if not contact.is_empty():
		return contact["position"] as Vector3
	return null


## How fast the TARGET datum's origin is going. A cut member rides the derelict,
## which holds station on site — it tumbles, but its centre does not travel — so
## the only target that moves is a designated CONTACT, and it carries its own
## velocity (see GameState.contacts, written by whoever owns its motion).
func _target_velocity() -> Vector3:
	if not GameState.get_member(GameState.selected_member_id).is_empty():
		return Vector3.ZERO
	var contact := GameState.get_contact(GameState.tracked_contact_id)
	if contact.is_empty():
		return Vector3.ZERO
	return contact.get("velocity", Vector3.ZERO)


## --- Derived readings -------------------------------------------------------

## Height above the datum's plane, metres, signed.
##
## On the PAD datum this subtracts GEAR_HEIGHT so it is the LEGS' height above
## the deck — the same number DockingSystem.status()["altitude"] reports and the
## HUD landing ladder shows. Two instruments disagreeing on short final is worse
## than one instrument fewer.
func altitude() -> float:
	var d := datum()
	var xform: Transform3D = GameState.local_ship()["transform"]
	var alt: float = (xform.origin - (d["origin"] as Vector3)).dot(d["up"])
	if d["id"] == "PAD":
		alt -= DockingSystem.GEAR_HEIGHT
	return alt


## How fast the ship is going RELATIVE TO THE DATUM — her world velocity with the
## datum's own motion taken out (see GameState.ships on the frame).
##
## This is the velocity every reading on the band is supposed to be taken
## against, and the one the speed governor holds the ship to. Against a static
## datum it is simply her world velocity, which is every datum but a designated
## contact today; against a rival under way it is genuinely different, and that
## difference is the point.
func relative_velocity() -> Vector3:
	var velocity: Vector3 = GameState.local_ship().get("velocity", Vector3.ZERO)
	return velocity - (datum()["velocity"] as Vector3)


## The datum's own world velocity, for callers that need to take a reading out of
## the world frame and put it back — ShipMotion's governor clamp does exactly
## that. Separate from relative_velocity() only so the clamp can add it back
## afterwards without resolving the datum twice.
func datum_velocity() -> Vector3:
	return datum()["velocity"]


## Rate of climb against the datum's plane, m/s, POSITIVE UP. DockingSystem's
## "descent" is this negated — it counts sink, this counts altitude.
func vertical_speed() -> float:
	return relative_velocity().dot(datum()["up"])


## Distance from the ship to the datum's origin, metres.
func range_to() -> float:
	var xform: Transform3D = GameState.local_ship()["transform"]
	return xform.origin.distance_to(datum()["origin"] as Vector3)


## The HULL's bearing in the datum plane, 0..360, measured from `north` toward
## `east`. Note this is the hull, not the camera: the flight HUD's HDG readout is
## the camera's bearing by design, and the two are different numbers whenever the
## pilot is glancing.
func heading() -> float:
	var xform: Transform3D = GameState.local_ship()["transform"]
	return bearing_of(-xform.basis.z, datum())


## Bearing of any world direction in a datum's plane, 0..360. With up = +Y and
## north = -Z this reduces to atan2(dir.x, -dir.z) — the formula the flight HUD
## already uses, which is what makes the datum a generalisation of it rather than
## a second convention to keep in step.
func bearing_of(dir: Vector3, d: Dictionary) -> float:
	return fposmod(rad_to_deg(atan2(dir.dot(d["east"]), dir.dot(d["north"]))), 360.0)


## Bearing from the ship to the datum's origin — what the heading tape's bug
## marks. Sitting on the origin there is no bearing to take, so the bug parks
## under the lubber line rather than snapping about.
func bearing_to_datum() -> float:
	var d := datum()
	var xform: Transform3D = GameState.local_ship()["transform"]
	var to_datum: Vector3 = (d["origin"] as Vector3) - xform.origin
	if to_datum.length_squared() < 0.0001:
		return bearing_of(-xform.basis.z, d)
	return bearing_of(to_datum, d)


## (pitch, roll) in degrees against the datum's plane. Pitch is positive NOSE UP;
## roll is positive RIGHT WING DOWN. Heading is the third angle of the same
## attitude and comes from heading() rather than being returned twice.
func attitude() -> Vector2:
	var xform: Transform3D = GameState.local_ship()["transform"]
	var d := datum()
	# The datum as a basis: x = east, y = up, z = south — so its -z is north, and
	# the ship's own -z (her nose) compares against it directly.
	var ref := Basis(d["east"], d["up"], -(d["north"] as Vector3))
	# Orthonormal, so the transpose IS the inverse, and is cheaper.
	var rel := ref.transposed() * xform.basis
	var nose: Vector3 = -rel.z
	var pitch := rad_to_deg(asin(clampf(nose.y, -1.0, 1.0)))
	var roll := rad_to_deg(atan2(-rel.x.y, rel.y.y))
	return Vector2(pitch, roll)


## Body-frame angular rates in deg/s as (pitch, yaw, roll) — the axis ORDER the
## stick commands in (ShipMotion's _cmd_rot), so a ribbon and the axis that
## drives it can never be mismatched.
##
## The SIGNS are the instrument's, not the stick's, and two of three are flipped
## against it: positive here is nose-up, nose-RIGHT and right-wing-DOWN, which
## agrees with attitude() above. The command axes read the other way on yaw and
## roll (rot.y is yaw_left-positive, rot.z is roll_left-positive), and a ribbon
## that ran backwards from the horizon beside it would be worse than no ribbon.
func body_rates() -> Vector3:
	var ship: Dictionary = GameState.local_ship()
	var xform: Transform3D = ship["transform"]
	var omega: Vector3 = ship.get("omega", Vector3.ZERO)
	var body := xform.basis.inverse() * omega
	return Vector3(rad_to_deg(body.x), rad_to_deg(-body.y), rad_to_deg(-body.z))
