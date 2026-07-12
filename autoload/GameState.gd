extends Node
## Single source of truth for all game state.
##
## Convention (enforced at code-review level): window/UI scripts only READ this
## singleton and call intent methods; only systems/*.gd mutate state and emit
## *_changed signals. Phase 1 has no systems yet, so the only mutation is the
## shared tick counter below, which exists to prove all four windows are
## reading the same in-memory state with zero drift.

signal tick_changed(tick: int)
signal contacts_changed
signal tracked_contact_changed(id: int)

## Godot's convention for the local/server peer. GameState.ships is keyed by
## peer id from day one so networked multiplayer later is additive, not a
## retrofit (see Docs/Plans/simpit-plan.md, "Networking").
const LOCAL_PEER_ID := 1

## How often the shared tick counter advances.
const TICK_RATE_HZ := 10.0

## peer_id -> ship state. Replication-friendly types only (Dictionary, Array,
## Vector3, float, int, String) so a future MultiplayerSynchronizer can point
## at fields directly.
var ships: Dictionary = {}

## Sensor contacts. Replication-friendly Dictionaries:
## { "id": int, "name": String, "position": Vector3, "threat": bool }.
## Phase 2 populates this at world-scene setup (see register_contact below);
## gameplay-driven contact churn arrives with systems/ThreatSystem.gd in Phase 4.
var contacts: Array[Dictionary] = []

## Contact currently locked for the HUD/Tactical displays, -1 for none.
var tracked_contact_id: int = -1

## Shared tick counter, displayed on every window in Phase 1.
var tick: int = 0

var _tick_accum := 0.0
var _next_contact_id := 0


func _ready() -> void:
	ships[LOCAL_PEER_ID] = {
		"transform": Transform3D.IDENTITY,
		"velocity": Vector3.ZERO,
		"hull": 1.0,
		"cargo": [],
		"power": {},
	}


## World-scene setup, not gameplay mutation: world nodes (wreck, debris) call
## this once when they enter the tree so displays have something to read.
## Once Phase 4 systems exist, contact changes driven by gameplay go through
## systems/*.gd per the mutation convention above.
func register_contact(contact_name: String, position: Vector3, threat := false) -> int:
	var id := _next_contact_id
	_next_contact_id += 1
	contacts.append({
		"id": id,
		"name": contact_name,
		"position": position,
		"threat": threat,
	})
	contacts_changed.emit()
	return id


func get_contact(id: int) -> Dictionary:
	for contact in contacts:
		if contact["id"] == id:
			return contact
	return {}


func set_tracked_contact(id: int) -> void:
	tracked_contact_id = id
	tracked_contact_changed.emit(id)


func _process(delta: float) -> void:
	_tick_accum += delta
	while _tick_accum >= 1.0 / TICK_RATE_HZ:
		_tick_accum -= 1.0 / TICK_RATE_HZ
		tick += 1
		tick_changed.emit(tick)
