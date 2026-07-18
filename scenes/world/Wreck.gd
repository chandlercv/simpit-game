extends Node3D
## Placeholder derelict built from engine primitives + PBR materials, standing
## in for Kenney/Quaternius modular kit pieces (see plan Phase 2 asset
## sourcing; real glTF assets drop into assets/cc0|cc-by|cc-by-nc later).
## Registers itself as the tracked sensor contact and pulses its beacon so
## Glow has something to bite on.
##
## Phase 4: reports its placement to SalvageSystem (the structural graph's
## member "node" fields name children here) and mirrors graph state in 3D —
## severed members disappear from the hull, a fresh site restores them.

@onready var _beacon_light: OmniLight3D = $BeaconLight

var _time := 0.0


func _ready() -> void:
	var id := GameState.register_contact("DERELICT FRIGATE", global_position)
	GameState.set_tracked_contact(id)
	SalvageSystem.register_wreck_position(global_position)
	GameState.wreck_member_cut.connect(_on_member_cut)
	GameState.wreck_members_lost.connect(_sync_members)
	GameState.site_reset.connect(_on_site_reset)
	_sync_members()


func _process(delta: float) -> void:
	_time += delta
	# Slow distress-beacon pulse.
	var pulse := 0.5 + 0.5 * sin(_time * TAU * 0.4)
	_beacon_light.light_energy = 1.0 + 5.0 * pulse


func _on_member_cut(id: int) -> void:
	var member := GameState.get_member(id)
	if not member.is_empty() and has_node(member["node"]):
		get_node(member["node"]).visible = false


func _on_site_reset() -> void:
	_sync_members()


## Mirror the graph's cut/destroyed state (covers both a fresh site and a
## window opening after cuts already happened).
func _sync_members() -> void:
	for member: Dictionary in GameState.wreck.get("members", []):
		if has_node(member["node"]):
			get_node(member["node"]).visible = \
					not (member["cut"] or member["destroyed"])
