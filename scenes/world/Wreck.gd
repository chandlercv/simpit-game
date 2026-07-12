extends Node3D
## Placeholder derelict built from engine primitives + PBR materials, standing
## in for Kenney/Quaternius modular kit pieces (see plan Phase 2 asset
## sourcing; real glTF assets drop into assets/cc0|cc-by|cc-by-nc later).
## Registers itself as the tracked sensor contact and pulses its beacon so
## Glow has something to bite on.

@onready var _beacon_light: OmniLight3D = $BeaconLight

var _time := 0.0


func _ready() -> void:
	var id := GameState.register_contact("DERELICT FRIGATE", global_position)
	GameState.set_tracked_contact(id)


func _process(delta: float) -> void:
	_time += delta
	# Slow distress-beacon pulse.
	var pulse := 0.5 + 0.5 * sin(_time * TAU * 0.4)
	_beacon_light.light_energy = 1.0 + 5.0 * pulse
