extends Node
## Single source of truth for all game state.
##
## Convention (enforced at code-review level): window/UI scripts only READ this
## singleton and call intent methods; only systems/*.gd mutate state and emit
## *_changed signals. Phase 4 systems don't exist yet, so the intent methods
## below mutate directly for now — when systems/*.gd land, gameplay-driven
## mutation moves there and these methods stay as the UI's single entry points.

signal tick_changed(tick: int)
signal contacts_changed
signal tracked_contact_changed(id: int)
signal sensor_mode_changed(mode: String)
signal power_changed
signal comms_posted(entry: Dictionary)
## Emitted by Phase 4 systems (SalvageSystem/ThreatSystem/CargoSystem); the
## Phase 3 displays already listen so wiring them up later is emit-only.
@warning_ignore("unused_signal")
signal structural_risk_changed(risk: float)
@warning_ignore("unused_signal")
signal hull_sections_changed
@warning_ignore("unused_signal")
signal cargo_changed

## Godot's convention for the local/server peer. GameState.ships is keyed by
## peer id from day one so networked multiplayer later is additive, not a
## retrofit (see Docs/Plans/simpit-plan.md, "Networking").
const LOCAL_PEER_ID := 1

## How often the shared tick counter advances.
const TICK_RATE_HZ := 10.0

const SENSOR_MODES: Array[String] = ["PASSIVE", "ACTIVE", "STRUCT"]

## Power allocation channels, each 0..1. The reactor can't run everything at
## full: the UI warns when the summed allocation exceeds POWER_BUDGET.
const POWER_CHANNELS: Array[String] = ["THRUST", "CUTTER", "SENSORS", "LIFE"]
const POWER_BUDGET := 2.5

const HULL_SECTIONS: Array[String] = ["BOW", "PORT", "STBD", "CORE", "AFT", "DRIVE"]

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

## Active sensor mode, one of SENSOR_MODES (drives the Tactical scope).
var sensor_mode: String = "PASSIVE"

## 0..1. Placeholder value until Phase 4, where SalvageSystem's structural
## graph drives it from which members have been cut.
var structural_risk: float = 0.22

## Placeholder market table until systems/MarketSystem.gd (Phase 4) owns
## faction pricing/reputation. prices[] is parallel to market_factions.
## Faction names are placeholders pending a simpit-world.md naming pass.
var market_factions: Array[String] = ["LAGRANGE UNION", "MERIDIAN CO.", "FREEHOLD"]
var market_goods: Array[Dictionary] = [
	{"name": "HULL ALLOY", "unit": "T", "prices": [412, 388, 445]},
	{"name": "FUSED OPTICS", "unit": "KG", "prices": [95, 118, 87]},
	{"name": "VOLATILES", "unit": "T", "prices": [61, 55, 74]},
	{"name": "RARE ISOTOPES", "unit": "G", "prices": [230, 244, 198]},
	{"name": "INTACT NAV CORES", "unit": "EA", "prices": [1250, 1600, 1100]},
]

## Comms/traffic log entries: { "tick": int, "source": String, "text": String }.
var comms: Array[Dictionary] = []

## Shared tick counter, displayed on every window (kept from Phase 1 as the
## cheapest way to spot a stalled window over spacedesk).
var tick: int = 0

var _tick_accum := 0.0
var _next_contact_id := 0


func _ready() -> void:
	ships[LOCAL_PEER_ID] = {
		"transform": Transform3D.IDENTITY,
		"velocity": Vector3.ZERO,
		"hull": 1.0,
		# Placeholder per-section integrity (0..1) so the tablet heatmap has a
		# varied read; Phase 4 damage events will drive this.
		"hull_sections": {
			"BOW": 0.92, "PORT": 0.64, "STBD": 0.88,
			"CORE": 0.97, "AFT": 0.71, "DRIVE": 0.55,
		},
		# Placeholder salvage already aboard so the inventory grid has tiles.
		"cargo": [
			{"id": 0, "name": "ALLOY SPAR", "mass_t": 3.2, "vol_m3": 4.1},
			{"id": 1, "name": "FUSED OPTICS", "mass_t": 0.4, "vol_m3": 0.3},
			{"id": 2, "name": "COOLANT CELL", "mass_t": 1.1, "vol_m3": 0.9},
			{"id": 3, "name": "NAV CORE (DAMAGED)", "mass_t": 0.8, "vol_m3": 0.6},
		],
		"cargo_mass_limit_t": 40.0,
		"power": {"THRUST": 0.8, "CUTTER": 0.0, "SENSORS": 0.6, "LIFE": 1.0},
	}
	post_comms("SYSTEM", "DISPLAY NETWORK ONLINE")
	post_comms("HARBOR", "TRAFFIC ADVISORY: SALVAGE CLAIM 7741-C ACTIVE IN THIS VOLUME")
	post_comms("SENSORS", "PASSIVE SWEEP NOMINAL")


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


func set_sensor_mode(mode: String) -> void:
	if mode == sensor_mode or not SENSOR_MODES.has(mode):
		return
	sensor_mode = mode
	sensor_mode_changed.emit(mode)
	post_comms("SENSORS", "SWEEP MODE %s" % mode)


func set_power(channel: String, value: float) -> void:
	var power: Dictionary = ships[LOCAL_PEER_ID]["power"]
	if not power.has(channel):
		return
	power[channel] = clampf(value, 0.0, 1.0)
	power_changed.emit()


func power_total() -> float:
	var total := 0.0
	for value: float in ships[LOCAL_PEER_ID]["power"].values():
		total += value
	return total


func post_comms(source: String, text: String) -> void:
	var entry := {"tick": tick, "source": source, "text": text}
	comms.append(entry)
	comms_posted.emit(entry)


func _process(delta: float) -> void:
	_tick_accum += delta
	while _tick_accum >= 1.0 / TICK_RATE_HZ:
		_tick_accum -= 1.0 / TICK_RATE_HZ
		tick += 1
		tick_changed.emit(tick)
