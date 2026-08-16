extends Node3D
## Own ship's 3D body. View-side only: mirrors the authoritative transform
## SalvageSystem writes into GameState each frame (approach/match-velocity
## and Phase 5 manual flight), carrying the hull camera rig with it, and
## reflects cosmetic switch-panel state (nav/landing lights). No mutation
## here, per the convention.

const GEAR_MESH := "res://assets/cc0/station/landing_gear.glb"
## Where the four legs bolt on, in ship space, and which way each folds when it
## stows. Two constraints set these, and between them they rule out a tripod.
##
## WHERE they can go: a mount has to sit under solid hull or the leg hangs in
## space with nothing holding it up, and craft_miner is a TWIN-BOOM craft —
## forward of z=-0.2 the centreline is open air between two booms at x=+/-0.5,
## and only aft of that does it become a full-width body. So the forward pair
## live on the booms; there is no nose to hang a nose leg from.
##
## HOW FAR APART they have to be: the hull's centre of mass (uniform density, and
## it is a watertight mesh so this is exact) is at z=+0.402, well aft, sitting
## 0.865 m above the pad when parked. A landing is LEGAL up to
## DockingSystem.TILT_LIMIT_DEG, so the stance has to hold that much tilt without
## going over. A tripod cannot: putting the third leg on the keel at z=+0.85 puts
## the CM only 0.117 m from the line between it and either boom leg, which tips
## at 7.7 deg — the ship would topple on landings ATC had cleared and the
## touchdown check had passed. Squaring it off to four legs moves the worst edge
## out to 0.448 m, or 27.4 deg, which covers the whole legal envelope.
##
## `fold` is the sign of the stow rotation about x, chosen so each leg tucks up
## UNDER hull rather than out past an edge: the forward pair swing aft, the aft
## pair (already near the tail) swing forward. They stow into different stretches
## of belly, so folded legs never meet in the middle.
##
## The y is 0.05 above the deepest belly point, which buries the knuckle in the
## hull instead of leaving a seam. A leg drops 0.6 from its mount, so a
## fully-extended foot sits at -1.6 — DockingSystem.GEAR_HEIGHT, which is what
## makes the legs touch the pad in the same frame the touchdown test says they do.
const GEAR_LEGS := [
	{"mount": Vector3(-0.5, -1.0, -1.0), "fold": -1.0},
	{"mount": Vector3(0.5, -1.0, -1.0), "fold": -1.0},
	{"mount": Vector3(-0.5, -1.0, 0.85), "fold": 1.0},
	{"mount": Vector3(0.5, -1.0, 0.85), "fold": 1.0},
]
## How far a stowed leg swings up from vertical.
const GEAR_STOW_DEG := 82.0

@onready var _nav_l: OmniLight3D = $NavLightL
@onready var _nav_r: OmniLight3D = $NavLightR
@onready var _landing: SpotLight3D = $LandingLight

var _gear_legs: Array[Node3D] = []
var _gear_folds: Array[float] = []


func _ready() -> void:
	GameState.panel_switch_changed.connect(_on_panel_switch)
	_build_gear()


func _process(_delta: float) -> void:
	transform = GameState.local_ship()["transform"]
	_update_gear()


## The legs, instanced from the generated mesh. Built here rather than authored
## into Ship.tscn so the mount points stay next to the constant that ties them to
## GEAR_HEIGHT.
func _build_gear() -> void:
	var packed: PackedScene = load(GEAR_MESH)
	if packed == null:
		push_warning("Ship: missing landing_gear.glb — run tools/build_station.py")
		return
	for spec in GEAR_LEGS:
		var leg: Node3D = packed.instantiate()
		leg.position = spec["mount"]
		add_child(leg)
		_gear_legs.append(leg)
		_gear_folds.append(spec["fold"])


## Swing the legs between stowed and down from GameState.gear_position — the
## travel GameState._advance_gear runs, so what the pilot sees hanging under the
## ship is the same number gear_locked_down() gates the landing on.
func _update_gear() -> void:
	if _gear_legs.is_empty():
		return
	var extended: float = GameState.gear_position
	var stowed := extended <= 0.0
	for i in _gear_legs.size():
		var leg: Node3D = _gear_legs[i]
		leg.visible = not stowed
		if stowed:
			continue
		var swing := GEAR_STOW_DEG * _gear_folds[i] * (1.0 - extended)
		leg.rotation = Vector3(deg_to_rad(swing), 0.0, 0.0)


func _on_panel_switch(switch_name: String, on: bool) -> void:
	match switch_name:
		"NAV":
			_nav_l.visible = on
			_nav_r.visible = on
		"LANDING":
			_landing.visible = on
