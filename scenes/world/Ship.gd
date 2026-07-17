extends Node3D
## Own ship's 3D body. View-side only: mirrors the authoritative transform
## SalvageSystem writes into GameState each frame (approach/match-velocity
## and Phase 5 manual flight), carrying the hull camera rig with it, and
## reflects cosmetic switch-panel state (nav/landing lights). No mutation
## here, per the convention.

@onready var _nav_l: OmniLight3D = $NavLightL
@onready var _nav_r: OmniLight3D = $NavLightR
@onready var _landing: SpotLight3D = $LandingLight


func _ready() -> void:
	GameState.panel_switch_changed.connect(_on_panel_switch)


func _process(_delta: float) -> void:
	transform = GameState.local_ship()["transform"]


func _on_panel_switch(switch_name: String, on: bool) -> void:
	match switch_name:
		"NAV":
			_nav_l.visible = on
			_nav_r.visible = on
		"LANDING":
			_landing.visible = on
