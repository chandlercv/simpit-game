extends Node3D
## Own ship's 3D body. View-side only: mirrors the authoritative transform
## SalvageSystem writes into GameState each frame (approach/match-velocity
## and Phase 5 manual flight), carrying the hull camera rig with it, and
## reflects cosmetic switch-panel state (nav/landing lights). No mutation
## here, per the convention.

const GEAR_MESH := "res://assets/cc0/station/landing_gear.glb"
## Where the three legs bolt on, in ship space. The y puts a fully-extended
## foot at -2.2, which is DockingSystem.GEAR_HEIGHT — so the legs touch the pad
## in the same frame the touchdown test says they do.
const GEAR_MOUNTS: Array[Vector3] = [
	Vector3(0.0, -1.1, -1.6),
	Vector3(-1.3, -1.1, 1.2),
	Vector3(1.3, -1.1, 1.2),
]
## How far a stowed leg swings up from vertical.
const GEAR_STOW_DEG := 82.0

@onready var _nav_l: OmniLight3D = $NavLightL
@onready var _nav_r: OmniLight3D = $NavLightR
@onready var _landing: SpotLight3D = $LandingLight

var _gear_legs: Array[Node3D] = []


func _ready() -> void:
	GameState.panel_switch_changed.connect(_on_panel_switch)
	_build_gear()


func _process(_delta: float) -> void:
	transform = GameState.local_ship()["transform"]
	_update_gear()


## Three legs instanced from the generated mesh. Built here rather than authored
## into Ship.tscn so the mount points stay next to the constant that ties them to
## GEAR_HEIGHT.
func _build_gear() -> void:
	var packed: PackedScene = load(GEAR_MESH)
	if packed == null:
		push_warning("Ship: missing landing_gear.glb — run tools/build_station.py")
		return
	for mount in GEAR_MOUNTS:
		var leg: Node3D = packed.instantiate()
		leg.position = mount
		add_child(leg)
		_gear_legs.append(leg)


## Swing the legs between stowed and down from GameState.gear_position — the
## travel GameState._advance_gear runs, so what the pilot sees hanging under the
## ship is the same number gear_locked_down() gates the landing on.
func _update_gear() -> void:
	if _gear_legs.is_empty():
		return
	var extended: float = GameState.gear_position
	var stowed := extended <= 0.0
	for leg in _gear_legs:
		leg.visible = not stowed
		if stowed:
			continue
		leg.rotation = Vector3(deg_to_rad(GEAR_STOW_DEG * (1.0 - extended)), 0.0, 0.0)


func _on_panel_switch(switch_name: String, on: bool) -> void:
	match switch_name:
		"NAV":
			_nav_l.visible = on
			_nav_r.visible = on
		"LANDING":
			_landing.visible = on
