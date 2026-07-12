extends Node
## Single source of truth for all game state.
##
## Convention (enforced at code-review level): window/UI scripts only READ this
## singleton and call intent methods; only systems/*.gd mutate state and emit
## *_changed signals. Phase 1 has no systems yet, so the only mutation is the
## shared tick counter below, which exists to prove all four windows are
## reading the same in-memory state with zero drift.

signal tick_changed(tick: int)

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

## Shared tick counter, displayed on every window in Phase 1.
var tick: int = 0

var _tick_accum := 0.0


func _ready() -> void:
	ships[LOCAL_PEER_ID] = {
		"transform": Transform3D.IDENTITY,
		"hull": 1.0,
		"cargo": [],
		"power": {},
	}


func _process(delta: float) -> void:
	_tick_accum += delta
	while _tick_accum >= 1.0 / TICK_RATE_HZ:
		_tick_accum -= 1.0 / TICK_RATE_HZ
		tick += 1
		tick_changed.emit(tick)
