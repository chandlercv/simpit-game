extends Node
## Single source of truth for all game state.
##
## Convention (enforced at code-review level): window/UI scripts only READ this
## singleton and call intent methods — either the thin setters below or the
## gameplay intents on systems/*.gd (SalvageSystem, CargoSystem, MarketSystem,
## ThreatSystem). Only intents/systems mutate state; changes fan out through
## the *_changed signals declared here so every display window reacts to the
## same shared state.

signal tick_changed(tick: int)
signal contacts_changed
signal tracked_contact_changed(id: int)
signal sensor_mode_changed(mode: String)
signal power_changed
signal comms_posted(entry: Dictionary)

## Phase 4 signals, emitted by systems/*.gd (declared here so any display can
## subscribe without knowing which system drives them).
@warning_ignore_start("unused_signal")
signal structural_risk_changed(risk: float)
signal hull_sections_changed
signal cargo_changed
signal credits_changed(credits: int)
signal reputation_changed
signal market_changed
signal run_phase_changed(phase: String)
signal approach_changed(state: String)
signal selected_member_changed(id: int)
signal wreck_scanned
signal wreck_member_cut(id: int)
## Frame collapse destroyed the remaining uncut members in bulk (no per-member
## cut signal). The 3D wreck re-syncs its meshes from the graph's destroyed flag.
signal wreck_members_lost
## A collision damaged a hull section (CollisionSystem). Carries the section and
## the integrity lost. Extension seam: future crippling/destruction consequences
## and view juice (camera shake, alarms) subscribe here.
signal hull_impact(section: String, amount: float)
signal site_reset
signal panel_switch_changed(switch_name: String, on: bool)
@warning_ignore_restore("unused_signal")

## Godot's convention for the local/server peer. GameState.ships is keyed by
## peer id from day one so networked multiplayer later is additive, not a
## retrofit (see Docs/Plans/simpit-plan.md, "Networking").
const LOCAL_PEER_ID := 1

## How often the shared tick counter advances.
const TICK_RATE_HZ := 10.0

const SENSOR_MODES: Array[String] = ["PASSIVE", "ACTIVE", "STRUCT"]

## Power allocation channels, each 0..1. The reactor can't run everything at
## full: the UI warns when the summed allocation exceeds power_budget().
const POWER_CHANNELS: Array[String] = ["THRUST", "CUTTER", "SENSORS", "LIFE"]

const HULL_SECTIONS: Array[String] = ["BOW", "PORT", "STBD", "CORE", "AFT", "DRIVE"]

## Run phases: ON_SITE (at the salvage claim), TRANSIT (abstract burn to/from
## a station), DOCKED (at a faction station, hold can be sold).
const RUN_PHASES: Array[String] = ["ON_SITE", "TRANSIT", "DOCKED"]

## Approach states (SalvageSystem): HOLDING (free drift), APPROACHING
## (closing/matching), MATCHED (inside cutting range, velocity matched).
const APPROACH_STATES: Array[String] = ["HOLDING", "APPROACHING", "MATCHED"]

## Own-ship stats, authored as a Resource (plan Phase 4 convention).
var ship_def: ShipDefinition = load("res://data/ships/kestrel.tres")

## peer_id -> ship state. Replication-friendly types only (Dictionary, Array,
## Vector3, float, int, String) so a future MultiplayerSynchronizer can point
## at fields directly.
var ships: Dictionary = {}

## Sensor contacts. Replication-friendly Dictionaries:
## { "id": int, "name": String, "position": Vector3, "threat": bool,
##   "radius": float }.
## World nodes register the static ones at scene setup; ThreatSystem spawns,
## moves, and removes the gameplay-driven ones. "radius" > 0 marks a contact as
## a solid body CollisionSystem tests the ship against (moving ships like the
## rival/patrol); 0 means sensor-only (the wreck and debris blips, whose solid
## bodies live in `obstacles` / the wreck graph instead — see register_contact).
var contacts: Array[Dictionary] = []

## Static solid bodies the ship can run into that are NOT sensor contacts: the
## cosmetic debris chunks. Replication-friendly Dictionaries:
## { "id": int, "name": String, "position": Vector3, "radius": float }.
## World nodes (DebrisField) register these at scene setup; CollisionSystem reads
## them. Kept separate from `contacts` so solid clutter doesn't fill the scope.
var obstacles: Array[Dictionary] = []

## Contact currently locked for the HUD/Tactical displays, -1 for none.
var tracked_contact_id: int = -1

## Active sensor mode, one of SENSOR_MODES (drives the Tactical scope).
var sensor_mode: String = "PASSIVE"

## 0..1, owned by SalvageSystem: eases toward a baseline that ratchets up with
## each structural cut, and spikes when a load-bearing member is severed.
var structural_risk: float = 0.15

## Structural graph of the wreck on site, owned by SalvageSystem:
## { "scanned": bool, "scan_progress": float 0..1, "position": Vector3,
##   "members": Array[Dictionary] } — each member:
## { "id": int, "name": String, "node": String (Wreck.tscn child name),
##   "sx"/"sy": float (schematic coords -1..1), "load": float 0..1,
##   "links": Array[int] (member ids), "cut": bool, "destroyed": bool,
##   "good": String, "qty": float }.
var wreck: Dictionary = {}

## Structural member currently selected as the cut target, -1 for none.
var selected_member_id: int = -1

## SalvageSystem approach/match-velocity state, one of APPROACH_STATES.
var approach_state: String = "HOLDING"

## Current run phase, one of RUN_PHASES.
var run_phase: String = "ON_SITE"

## Faction index docked at (into market_factions), -1 when not docked.
var docked_faction: int = -1

var credits: int = 500

## Faction display_name -> reputation 0..1 (MarketSystem).
var reputation: Dictionary = {}

## Market table, owned by MarketSystem (built from data/factions + data/goods
## .tres, repriced on dock). prices[] is parallel to market_factions.
var market_factions: Array[String] = []
var market_goods: Array[Dictionary] = []

## Saitek switch panel state, switch name -> bool (SwitchPanelBridge). Views
## may read cosmetic switches directly (e.g. NAV/LANDING lights on Ship.gd);
## systemic switches route through intents in the bridge.
var panel_switches: Dictionary = {}

## Comms/mission log entries: { "tick": int, "source": String, "text": String }.
var comms: Array[Dictionary] = []

## Shared tick counter, displayed on every window (kept from Phase 1 as the
## cheapest way to spot a stalled window over spacedesk).
var tick: int = 0

var _tick_accum := 0.0
var _next_contact_id := 0

## Power allocations captured when the master battery is cut, so switching it
## back restores the prior mix. Owned here (not in a driver node) so every input
## surface — switch panel, touch UI, future ones — shares one power model.
var _power_before_bat: Dictionary = {}


func _ready() -> void:
	ships[LOCAL_PEER_ID] = {
		"transform": Transform3D.IDENTITY,
		"velocity": Vector3.ZERO,
		# Per-section integrity 0..1; collapse events (ThreatSystem) damage it.
		"hull_sections": {
			"BOW": 0.96, "PORT": 0.88, "STBD": 0.92,
			"CORE": 1.0, "AFT": 0.9, "DRIVE": 0.85,
		},
		"cargo": [],
		"cargo_mass_limit_t": ship_def.cargo_mass_limit_t,
		"cargo_vol_limit_m3": ship_def.cargo_vol_limit_m3,
		"power": {"THRUST": 0.8, "CUTTER": 0.0, "SENSORS": 0.6, "LIFE": 1.0},
	}
	post_comms("SYSTEM", "DISPLAY NETWORK ONLINE — %s" % ship_def.display_name)


func local_ship() -> Dictionary:
	return ships[LOCAL_PEER_ID]


## World-scene setup, not gameplay mutation: world nodes (wreck, debris) call
## this once when they enter the tree so displays have something to read.
## Gameplay-driven contact churn goes through ThreatSystem per the mutation
## convention above.
## radius > 0 also makes the contact a solid body for CollisionSystem (moving
## ships). Leave it 0 for sensor-only blips whose collidable form lives
## elsewhere (the wreck via the wreck graph, debris via `obstacles`).
func register_contact(contact_name: String, position: Vector3, threat := false,
		radius := 0.0) -> int:
	var id := _next_contact_id
	_next_contact_id += 1
	contacts.append({
		"id": id,
		"name": contact_name,
		"position": position,
		"threat": threat,
		"radius": radius,
	})
	contacts_changed.emit()
	return id


## Systems-side contact removal (rival departs, patrol stands down).
func remove_contact(id: int) -> void:
	for i in contacts.size():
		if contacts[i]["id"] == id:
			contacts.remove_at(i)
			if tracked_contact_id == id:
				set_tracked_contact(-1)
			contacts_changed.emit()
			return


## World-scene setup: register a static solid body (debris chunk) the ship can
## collide with. Shares the contact id counter so ids never clash across lists.
func register_obstacle(obstacle_name: String, position: Vector3, radius: float) -> int:
	var id := _next_contact_id
	_next_contact_id += 1
	obstacles.append({
		"id": id,
		"name": obstacle_name,
		"position": position,
		"radius": radius,
	})
	return id


func remove_obstacle(id: int) -> void:
	for i in obstacles.size():
		if obstacles[i]["id"] == id:
			obstacles.remove_at(i)
			return


func get_contact(id: int) -> Dictionary:
	for contact in contacts:
		if contact["id"] == id:
			return contact
	return {}


## The returned dict is the live entry (Dictionaries are references), so a
## caller tracking a moving body can update its "position" in place — that's how
## DebrisField keeps a tumbling chunk's collision sphere on the mesh.
func get_obstacle(id: int) -> Dictionary:
	for obstacle in obstacles:
		if obstacle["id"] == id:
			return obstacle
	return {}


## Member lookup in the wreck structural graph, {} if absent.
func get_member(id: int) -> Dictionary:
	for member: Dictionary in wreck.get("members", []):
		if member["id"] == id:
			return member
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
	var power: Dictionary = local_ship()["power"]
	if not power.has(channel):
		return
	power[channel] = clampf(value, 0.0, 1.0)
	power_changed.emit()


## Master-battery intent: off snapshots and zeroes every channel; on restores
## the snapshot. Idempotent on repeated off (a second off won't overwrite the
## snapshot with all-zeros), which the panel's change-dedup used to guarantee
## implicitly but a touch toggle would not.
func set_master_battery(on: bool) -> void:
	if on:
		for channel: String in _power_before_bat:
			set_power(channel, _power_before_bat[channel])
		_power_before_bat = {}
	else:
		if _power_before_bat.is_empty():
			_power_before_bat = local_ship()["power"].duplicate()
		for channel: String in POWER_CHANNELS:
			set_power(channel, 0.0)


func power(channel: String) -> float:
	return local_ship()["power"].get(channel, 0.0)


func power_total() -> float:
	var total := 0.0
	for value: float in local_ship()["power"].values():
		total += value
	return total


func power_budget() -> float:
	return ship_def.power_budget


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
