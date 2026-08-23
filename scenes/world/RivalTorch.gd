extends TorchBeam
## The rival's cutting torch. Unlike the Kestrel's, this is not a cut you watch
## progress — by the time the signal arrives the member is already severed and
## adrift (ThreatSystem._update_rival_cut). This is the flare that goes with it:
## the moment the comms log calls "RIVAL CUTTER FLARE", made visible so a pilot
## working the far side of the hull can see the other boat taking a member off it.
##
## The span is captured at the moment of the cut rather than tracked. The rival is
## station-keeping on the wreck whenever it fires — that is the whole of the CUT
## state — so there is nothing to track.

## How long the flare stands, and the sting at the front of it. A cut that has
## already happened should read as a flash, not a beam that lingers.
const FLASH_TIME := 1.1
const COLOR := Color(1.0, 0.72, 0.34)
const RADIUS := 0.09

## How far forward of the rival's origin its torch boom reaches. ThreatSystem
## hands us the hull position because it is headless and knows nothing about the
## model; the boom is on the nose and the ship is pointed at what it is cutting
## whenever it fires, so walking the origin along the span puts the beam on the
## emitter head. Matches the boom tip built by tools/build_ships.py.
const BOOM_REACH := 1.85

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _left := 0.0
var _time := 0.0


func _ready() -> void:
	super()
	GameState.rival_cut_fired.connect(_on_fired)


func _on_fired(from: Vector3, to: Vector3) -> void:
	var span_v := to - from
	_from = from
	if span_v.length() > BOOM_REACH * 2.0:
		_from = from + span_v.normalized() * BOOM_REACH
	_to = to
	_left = FLASH_TIME
	_time = 0.0


func _process(delta: float) -> void:
	if _left <= 0.0:
		extinguish()
		return
	_left -= delta
	_time += delta
	# Fades over its life, with the same plasma flicker the Kestrel's torch has so
	# the two obviously come out of the same kind of machine.
	var fade: float = clampf(_left / FLASH_TIME, 0.0, 1.0)
	var flicker := 0.85 + 0.15 * sin(_time * TAU * 11.0)
	span(_from, _to, RADIUS * flicker * fade, COLOR, 0.9 * fade * flicker,
			4.0 * fade, 2.4 * fade * flicker)
