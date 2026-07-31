extends Node3D
## External-camera rig for the Camera display. It lives under the CameraWindow's
## SubViewport (whose World3D is the shared Main world, assigned by CameraWindow),
## so its single Camera3D renders the SAME scene as the hull-cam from a selectable
## external vantage.
##
## One camera with eased placement (not four cameras): each frame it reads the
## authoritative ship pose from GameState.local_ship()["transform"] — the same
## source Ship.gd uses to place the ship in the world — and glides the camera's
## ship-local offset / aim-point toward the current view's spec, so switching
## REAR ⇄ SIDE ⇄ CHASE ⇄ TOP sweeps rather than snaps.

## Ship-local placement per view: `offset` = camera position relative to the ship
## (Godot axes: +x starboard, +y up, −z forward), `look` = point it aims at.
## REAR sits just aft looking further aft (a rear-view of the space behind you),
## SIDE frames the profile, CHASE trails behind+above looking forward, TOP looks
## straight down.
const VIEWS := {
	"REAR": {"offset": Vector3(0.0, 1.2, 3.5), "look": Vector3(0.0, 0.6, 60.0)},
	"SIDE": {"offset": Vector3(11.0, 2.5, 0.5), "look": Vector3(0.0, 0.0, 0.0)},
	"CHASE": {"offset": Vector3(0.0, 3.2, 11.0), "look": Vector3(0.0, 0.6, -18.0)},
	"TOP": {"offset": Vector3(0.0, 20.0, 0.2), "look": Vector3(0.0, 0.0, 0.0)},
}
const EASE_RESPONSE := 6.0

var _cam: Camera3D
var _offset: Vector3
var _look: Vector3


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.current = true
	add_child(_cam)
	var v: Dictionary = VIEWS.get(GameState.external_view, VIEWS["CHASE"])
	_offset = v["offset"]
	_look = v["look"]
	# Place immediately so the first frame isn't from the origin.
	_apply(1.0)


func _process(delta: float) -> void:
	_apply(1.0 - exp(-EASE_RESPONSE * delta))


func _apply(weight: float) -> void:
	var target: Dictionary = VIEWS.get(GameState.external_view, VIEWS["CHASE"])
	_offset = _offset.lerp(target["offset"], weight)
	_look = _look.lerp(target["look"], weight)
	var xform: Transform3D = GameState.local_ship()["transform"]
	_cam.global_position = xform * _offset
	# Looking straight down, world-up is parallel to the view direction and
	# look_at would be undefined; use the ship's forward as up so the top-down
	# frame stays oriented with the hull.
	var up := -xform.basis.z if GameState.external_view == "TOP" else Vector3.UP
	_cam.look_at(xform * _look, up)
