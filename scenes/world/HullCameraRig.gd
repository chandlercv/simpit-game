extends Node3D
## Two-axis hull-camera gimbal: yaw node -> pitch node -> Camera3D.
##
## The interaction is a *glance*, not a free-position pan (see plan Phase 2):
## holding a hat direction eases the camera toward a bounded look offset that
## way, and releasing eases it back to forward-center automatically — release
## IS the recenter, no separate binding needed. Digital hat input drives this
## naturally.

## How far a full glance looks to the side / up-down.
@export var glance_yaw_deg := 60.0
@export var glance_pitch_deg := 45.0

## Hard pitch clamp so the gimbal can never flip (plan: ~±80°).
@export var pitch_limit_deg := 80.0

## Exponential-ease responsiveness; higher = snappier glance and recenter.
@export var ease_response := 7.0

@onready var _yaw: Node3D = $Yaw
@onready var _pitch: Node3D = $Yaw/Pitch

## Current smoothed look offset in degrees (x = yaw right, y = pitch up).
var _offset := Vector2.ZERO


func _process(delta: float) -> void:
	var glance := InputRouter.get_glance()
	# get_vector's +y is down; positive pitch rotation looks up.
	var target := Vector2(glance.x * glance_yaw_deg, -glance.y * glance_pitch_deg)
	# Framerate-independent exponential ease, both toward the glance target and
	# back to (0, 0) on release.
	_offset = _offset.lerp(target, 1.0 - exp(-ease_response * delta))
	_yaw.rotation.y = deg_to_rad(-_offset.x)
	_pitch.rotation.x = deg_to_rad(clampf(_offset.y, -pitch_limit_deg, pitch_limit_deg))
