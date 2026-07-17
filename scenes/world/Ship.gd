extends Node3D
## Own ship's 3D body. View-side only: mirrors the authoritative transform
## SalvageSystem writes into GameState each frame (approach/match-velocity),
## carrying the hull camera rig with it. No mutation here, per the convention.


func _process(_delta: float) -> void:
	transform = GameState.local_ship()["transform"]
