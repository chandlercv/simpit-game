extends Node3D
## Phase 2 test environment: sun + space environment, one derelict wreck,
## slowly tumbling debris. The tumble is cosmetic drift so the scene reads as
## live salvage wreckage rather than a still render.

## One debris chunk is registered as a threat contact so the HUD's
## proximity/threat treatment has something real to react to.
const THREAT_CHUNK := "ChunkThreat"

## Approximate collision radius for a chunk, scaled off its transform so a big
## rock is more solid than a small barrel. Cosmetic geometry, so this is a
## generous sphere, not a tight fit.
const CHUNK_RADIUS_BASE := 2.0

@onready var _debris: Node3D = $Debris

var _spins: Array[Vector3] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xD3B815
	for chunk in _debris.get_children():
		var axis := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
		).normalized()
		_spins.append(axis * rng.randf_range(0.05, 0.3))
		# Solid body for CollisionSystem. Positions are static (the tumble is
		# rotation only), so registering once at setup is enough.
		var chunk3d: Node3D = chunk
		var radius := CHUNK_RADIUS_BASE * maxf(chunk3d.scale.x,
				maxf(chunk3d.scale.y, chunk3d.scale.z))
		GameState.register_obstacle(chunk3d.name, chunk3d.global_position, radius)
	GameState.register_contact(
		"UNSTABLE DEBRIS", _debris.get_node(THREAT_CHUNK).global_position, true)


func _process(delta: float) -> void:
	for i in _debris.get_child_count():
		var chunk: Node3D = _debris.get_child(i)
		chunk.rotate_object_local(_spins[i].normalized(), _spins[i].length() * delta)
