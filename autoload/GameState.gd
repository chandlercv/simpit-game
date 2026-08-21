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
## External-camera vantage changed (the Camera display), one of EXTERNAL_VIEWS.
signal external_view_changed(view: String)
## Tactical display mode changed (SCOPE / CHART), one of TACTICAL_VIEWS.
signal tactical_view_changed(view: String)
signal power_changed
## Battery charge changed, as a 0..1 fraction of capacity.
signal battery_changed(fraction: float)
## Drive selector moved, one of DRIVE_MODES.
signal drive_mode_changed(mode: String)
## A propellant tank was filled or drawn down.
signal propellant_changed
## Passive-scanner visibility multiplier changed (master electrical switches).
signal signature_changed(value: float)
signal comms_posted(entry: Dictionary)
## Title-card scenario selection changed (one of SCENARIOS' ids).
signal scenario_changed(id: String)
## The chosen scenario was committed by the title card's LAUNCH — the run starts.
signal scenario_launched(id: String)

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
## ANY resolved contact between the ship and a solid body (CollisionSystem),
## including ones too gentle to do damage. hull_impact is the damage event;
## this is the "you touched something" event, and it fires even when the only
## consequence was being pushed back out of the body. DockingSystem needs the
## gentle ones: they still shove the ship off its line, and being knocked out of
## a corridor by scenery should not read to the pilot as their own bad flying.
signal ship_contact(body_name: String, closing: float)
signal site_reset
signal panel_switch_changed(switch_name: String, on: bool)
## Pre-cut alignment mini-game phase changed (SalvageSystem), one of ALIGN_STATES.
signal align_changed(state: String)
## DriftSystem: an adrift salvage piece's lifecycle. Views (SalvagePieces, HUD)
## key their per-piece state off the id these carry.
signal salvage_pieces_changed
signal salvage_piece_spawned(id: int)
signal salvage_piece_removed(id: int)
## Cargo hatch position changed (GameState.set_cargo_hatch/toggle_cargo_hatch).
signal cargo_hatch_changed(open: bool)
## Landing-gear lever moved (GameState.set_landing_gear/toggle_landing_gear).
## The gear then TRAVELS over GEAR_TRAVEL_TIME — read gear_position for how far
## it actually is, and gear_locked_down() for "safe to land on".
signal landing_gear_changed(down: bool)
## DockingSystem: the docking/landing approach phase changed, one of DOCK_STATES.
signal docking_changed(state: String)
## DockingSystem: a fresh ATC instruction was issued. Carries the instruction
## dict (see GameState.docking["atc"]) so an instrument can flash the new call
## rather than diffing text every frame.
signal atc_instruction(instruction: Dictionary)
## DockingSystem: the station's traffic list changed (a ship joined or left the
## pattern). Positions move every frame without this — it's arrivals/departures.
signal traffic_changed
@warning_ignore_restore("unused_signal")

## Godot's convention for the local/server peer. GameState.ships is keyed by
## peer id from day one so networked multiplayer later is additive, not a
## retrofit (see Docs/Plans/simpit-plan.md, "Networking").
const LOCAL_PEER_ID := 1

## How often the shared tick counter advances.
const TICK_RATE_HZ := 10.0

const SENSOR_MODES: Array[String] = ["PASSIVE", "ACTIVE", "STRUCT"]

## External-camera vantages for the Camera display (see ExternalCameraRig):
## REAR looks aft (a rear-view), SIDE frames the ship's profile, CHASE trails it,
## TOP looks straight down.
## BELLY looks straight down past the hull — the landing view, since a berth
## pad sits directly under a ship that has to stay level to touch down.
const EXTERNAL_VIEWS: Array[String] = ["REAR", "SIDE", "CHASE", "TOP", "BELLY"]

## Tactical display modes (see TacticalContent): SCOPE (sensor scope + hull
## status) and CHART (system star chart).
const TACTICAL_VIEWS: Array[String] = ["SCOPE", "CHART"]

## Power allocation channels, each 0..1. The reactor can't run everything at
## full: the UI warns when the summed allocation exceeds power_budget().
const POWER_CHANNELS: Array[String] = ["THRUST", "CUTTER", "SENSORS", "LIFE"]

## Switch-panel toggle -> power channel it drives (thematic pairing). ON sets the
## channel to power_high, OFF to power_low. SwitchPanelBridge reads this to route
## the four channel switches; gameplay semantics live here, not in the bridge.
const CHANNEL_SWITCHES: Dictionary = {
	"FUEL_PUMP": "THRUST",
	"AVIONICS": "SENSORS",
	"DE_ICE": "CUTTER",
	"PITOT_HEAT": "LIFE",
}

## Channels whose switch "high" isn't the shared power_high: LIFE runs full when
## its switch is on (life support isn't something you run at part power).
const CHANNEL_HIGH_OVERRIDE: Dictionary = {"LIFE": 1.0}

## Battery capacity, in unit-seconds of the same abstract units power_total()
## sums — so a steady 1.0-unit deficit runs a full battery flat in this many
## seconds. The battery is a BUFFER between what the alternator makes and what
## the channels ask for; it is not a second reactor.
const BATTERY_CAPACITY := 120.0

## Ceiling on how fast surplus alternator output is returned to the battery, in
## the same units. Recharging from flat therefore takes at least
## BATTERY_CAPACITY / BATTERY_CHARGE_RATE seconds of running under-loaded.
const BATTERY_CHARGE_RATE := 1.0

## Charge fraction below which the low-battery call is made — once per crossing,
## not every frame (see _advance_electrical).
const BATTERY_LOW := 0.2

## Drive selector positions, in the order the panel's magneto sweeps them, which
## is also the order step_drive_mode() walks. They are NOT power settings: the
## masters own the electrical bus, and this owns the drive.
##   OFF   — nothing runs; the ship will not manoeuvre however healthy the bus is
##   R     — the field stage alone: no propellant, 40% thrust, expensive in amps
##   L     — the nuclear-thermal stage alone: burns LH2, 60% thrust, cheap in amps
##   BOTH  — both stages: full thrust, burns LH2, expensive in amps
##   START — the starter detent; see DRIVE_START_TIME. Produces no thrust itself.
const DRIVE_MODES: Array[String] = ["OFF", "R", "L", "BOTH", "START"]

## Positions that actually run the drive. START and OFF are not among them, so
## thrust is zero at either.
const DRIVE_RUN_MODES: Array[String] = ["R", "L", "BOTH"]

## Positions running the electrodynamic FIELD stage — the one that costs
## electricity and needs no propellant.
const DRIVE_FIELD_MODES: Array[String] = ["R", "BOTH"]

## Positions running the NUCLEAR THERMAL stage — the one that burns liquid
## hydrogen and barely touches the bus.
const DRIVE_THERMAL_MODES: Array[String] = ["L", "BOTH"]

const HULL_SECTIONS: Array[String] = ["BOW", "PORT", "STBD", "CORE", "AFT", "DRIVE"]

## Every comms line is mirrored here as it is posted (see post_comms), so a run
## can be read back from disk rather than photographed off the screen. Its real
## location is printed at boot; on Windows it lands under
## %APPDATA%\Godot\app_userdata\<project>\.
const COMMS_LOG_PATH := "user://comms_log.txt"

## Run phases: ON_SITE (at the salvage claim), TRANSIT (abstract burn to/from
## a station), APPROACH (hand-flying the station's docking pattern — the
## docking/landing mini-game, DockingSystem), DOCKED (berthed at a faction
## station, hold can be sold).
const RUN_PHASES: Array[String] = ["ON_SITE", "TRANSIT", "APPROACH", "DOCKED"]

## Phases where the pilot is hand-flying a real ship in a real volume, so manual
## flight integrates and collisions bite (SalvageSystem, CollisionSystem). The
## claim and the station pattern are both "in the air"; TRANSIT and DOCKED are
## not — the ship is parked while the burn/berth is resolved.
const FLIGHT_PHASES: Array[String] = ["ON_SITE", "APPROACH"]

## Docking/landing approach states (DockingSystem):
##   INACTIVE — not flying a pattern
##   INBOUND  — proceed to the hold marker (also where a wave-off puts you)
##   HOLD     — holding at the marker, waiting on a clearance from ATC
##   CLEARED  — cleared inbound, flying the lane's gates in order
##   FINAL    — over the pad, cleared to land; descend onto it
##   LANDED   — on the pad, berthing handed back to MarketSystem
##   DEPART_HOLD — on the pad after undocking, waiting on a departure clearance
##   DEPARTING   — cleared out, flying the same lane in reverse to leave
const DOCK_STATES: Array[String] = ["INACTIVE", "INBOUND", "HOLD", "CLEARED",
		"FINAL", "LANDED", "DEPART_HOLD", "DEPARTING"]

## Seconds the landing gear takes to travel between stowed and locked down. It
## is deliberately slow enough that "GEAR DOWN BY THE FINAL GATE" is a call you
## have to act on early, not a switch you flick on short final.
const GEAR_TRAVEL_TIME := 3.0

## Airspeed (m/s) the extended gear is rated for. Flying faster than this with
## the gear off the stops wears it — see DockingSystem, which does the damage.
const GEAR_LIMIT_SPEED := 18.0

## Approach states (SalvageSystem): HOLDING (free drift), APPROACHING
## (closing/matching), MATCHED (inside cutting range, velocity matched).
const APPROACH_STATES: Array[String] = ["HOLDING", "APPROACHING", "MATCHED"]

## Pre-cut alignment phases (SalvageSystem): IDLE (not aligning), ALIGNING (the
## crosshair mini-game is live). A committed alignment hands straight to the
## existing cutting_id path, so no persistent third state is needed.
const ALIGN_STATES: Array[String] = ["IDLE", "ALIGNING"]

## Runs offered on the launch title card (scenes/displays/TitleCard.gd), in the
## order they're listed there. Scenarios are DATA, not code: a second run is an
## entry here (plus whatever world/system setup it asks for), not another branch
## in the launch UI. Only the demo run exists today.
##   "id"       — stable key stored in `scenario`
##   "name"     — button label
##   "subtitle" — one-line framing under the name
##   "blurb"    — what the player is signing up for
const SCENARIOS: Array[Dictionary] = [
	{
		"id": "demo",
		"name": "DEMO RUN",
		"subtitle": "Freehold claim · derelict frigate",
		"blurb": "The sandbox the game ships with: one tumbling frigate on a "
			+ "Freehold claim, a rival cutter working the same hull, and a patrol "
			+ "that fines you for running dark too close. Scan it, cut a member "
			+ "free, scoop the piece before the rival does, then dock and sell the "
			+ "hold. Nothing is on a timer.",
	},
]

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

## Active external-camera vantage, one of EXTERNAL_VIEWS (drives the Camera
## display's ExternalCameraRig).
var external_view: String = "CHASE"

## Active Tactical display mode, one of TACTICAL_VIEWS (drives TacticalContent).
var tactical_view: String = "SCOPE"

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

## Which member the current MATCHED belongs to, -1 when not matched. The approach
## autopilot now flies to and parks off the *selected* member, so a match is tied
## to that one member; picking a different target drops the match and forces a
## reposition (SalvageSystem.select_member / _set_approach).
var matched_member_id: int = -1

## Pre-cut alignment phase, one of ALIGN_STATES (owned by SalvageSystem).
var align_state: String = "IDLE"

## Alignment mini-game state, owned/mutated by SalvageSystem while align_state is
## ALIGNING. Replication-friendly: { "reticle": Vector2 (-1..1, player aim),
## "target": Vector2 (-1..1, drifting seam point), "lock": float 0..1,
## "slip": float 0..1, "quality": float 0..1 }.
var align: Dictionary = {}

## Adrift salvage pieces cut free of the wreck, owned by DriftSystem. Each:
## { "id": int, "member_id": int, "name": String, "good": String, "qty": float
##   (already quality-scaled), "transform": Transform3D, "velocity": Vector3,
##   "omega": Vector3, "radius": float, "obstacle_id": int, "contact_id": int,
##   "scoop": float 0..1, "node": String (Wreck.tscn child name, for the visual) }.
var salvage_pieces: Array[Dictionary] = []

## Cargo hatch position, owned by GameState (DriftSystem gates collection on it;
## SalvageSystem/MarketSystem interlock cutting and jump/dock while it's open).
var cargo_hatch_open: bool = false

## Landing-gear LEVER position (what the pilot selected), and how far the gear
## has actually travelled toward it (0 = stowed, 1 = down and locked). The lever
## is the intent; the position is the machine catching up, advanced here in
## _process so the gear keeps travelling in every run phase — it's ship
## equipment, not something the claim or the station owns.
var gear_down: bool = false
var gear_position: float = 0.0

## Docking/landing approach state, one of DOCK_STATES (owned by DockingSystem).
var docking_state: String = "INACTIVE"

## Live docking/landing mini-game state, owned/mutated by DockingSystem while
## docking_state != INACTIVE. Replication-friendly:
## { "faction": int (index into market_factions), "station": String,
##   "gate": int (index of the next gate to fly), "gates": Array[Dictionary]
##   (each { "name": String, "position": Vector3, "radius": float,
##   "lane": float }), "pad": Vector3, "pad_up": Vector3, "pad_forward": Vector3,
##   "speed_limit": float, "hold": bool (ATC is holding you where you are),
##   "atc": Dictionary (the standing instruction: { "text", "detail", "urgent" }),
##   "wave_offs": int, "quality": float 0..1 (last touchdown's score) }.
var docking: Dictionary = {}

## Station traffic in the pattern, owned by DockingSystem. Each:
## { "id": int, "name": String, "kind": String, "transform": Transform3D,
##   "radius": float, "contact_id": int, "conflict": bool (currently fouling
##   the lane) }. StationTraffic (view) mirrors these into meshes.
var traffic: Array[Dictionary] = []

## Scenario picked on the title card, one of SCENARIOS' ids.
var scenario: String = SCENARIOS[0]["id"]

## False until the title card's LAUNCH commits the scenario. WindowManager reads
## it to decide between showing the card and building the display windows; while
## it's false the card holds the scene tree paused, so the world a scenario sets
## up isn't already running behind the launch screen.
var scenario_started: bool = false

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
## Open handle for COMMS_LOG_PATH; null if the file could not be opened.
var _comms_log: FileAccess

## Shared tick counter, displayed on every window (kept from Phase 1 as the
## cheapest way to spot a stalled window over spacedesk).
var tick: int = 0

var _tick_accum := 0.0
var _next_contact_id := 0

## High/low settings the channel switches toggle between (0..1). Plain vars, not
## const, so a future settings surface can rewrite them per player.
var power_high := 0.8
var power_low := 0.2

## Master electrical switches. ALT is the alternator — it turns reactor output
## into electricity for the bus. BAT is the battery, which buffers the difference
## between what the alternator makes and what the channels draw. Neither is an
## override on the mix: they decide what is AVAILABLE, never what is SET.
var master_bat := true
var master_alt := true

## Battery charge, 0..BATTERY_CAPACITY. Boots full.
var battery_charge := BATTERY_CAPACITY

## Latch for the low-battery call, so it is made on the crossing rather than
## every frame below the threshold.
var _battery_low_called := false

## Desired per-channel allocation the switches and touch sliders write. This is
## what the pilot ASKED FOR and nothing in the electrical model ever rewrites it;
## local_ship()["power"] is what is actually DELIVERED against it. Losing the
## alternator or flattening the battery starves delivery and leaves the settings
## standing, so full output resumes the moment supply does — no snapshot, and no
## surprise when the lights come back.
## Owned here (not in a driver node) so every input surface — switch panel, touch
## UI, future ones — shares one power model.
var _power_target: Dictionary = {}

## Drive selector position, one of DRIVE_MODES. Driven by the panel's magneto or
## by drive_mode_prev/next.
var drive_mode := "BOTH"

## Seconds the selector has been sitting at START. Reset whenever it leaves.
var _drive_start_hold := 0.0

## True once a start has completed. Cleared by selecting OFF, which is what makes
## shutting the drive down a commitment rather than a habit.
var drive_started := true

## True while the combustion booster is commanded (a held control, not a latch).
var drive_boost := false

## Liquid hydrogen and liquid oxygen aboard, in the units ShipDefinition's tank
## and burn-rate figures use. Both board full.
var lh2_fuel := 0.0
var lox_fuel := 0.0


func _ready() -> void:
	_open_comms_log()
	ships[LOCAL_PEER_ID] = {
		"transform": Transform3D.IDENTITY,
		"velocity": Vector3.ZERO,
		# Angular velocity, world frame, rad/s. ShipMotion integrates it; the
		# stick commands a rate the FBW slews this toward, and collision can
		# write spin into it. seize() zeroes it with every kinematic override.
		"omega": Vector3.ZERO,
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
	_power_target = ships[LOCAL_PEER_ID]["power"].duplicate()
	lh2_fuel = ship_def.lh2_capacity
	lox_fuel = ship_def.lox_capacity
	post_comms("SYSTEM", "DISPLAY NETWORK ONLINE — %s" % ship_def.display_name)


func local_ship() -> Dictionary:
	return ships[LOCAL_PEER_ID]


## The SCENARIOS entry for an id, {} if there's no such scenario.
func scenario_def(id: String) -> Dictionary:
	for entry: Dictionary in SCENARIOS:
		if entry["id"] == id:
			return entry
	return {}


## Title-card intent: pick which run to fly. Unknown ids are ignored, so a stale
## saved/typed id can't leave the card pointing at nothing.
func set_scenario(id: String) -> void:
	if id == scenario or scenario_def(id).is_empty():
		return
	scenario = id
	scenario_changed.emit(id)


## Title-card intent: commit the chosen scenario — the run starts. WindowManager
## then places the display windows and unpauses the tree. Idempotent, so a second
## LAUNCH (or a stray Enter) can't restart a run that's already going.
func launch_scenario() -> void:
	if scenario_started:
		return
	scenario_started = true
	post_comms("SYSTEM", "SCENARIO %s — RUN START" % scenario_def(scenario).get("name", scenario))
	scenario_launched.emit(scenario)


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
## `hull` is an optional world-space convex point cloud: when non-empty the ship
## is tested against the tight hull (CollisionSystem GJK) and position/radius
## serve only as the broadphase bounding sphere; empty leaves the body a plain
## sphere/capsule. A tumbling chunk rewrites position + hull each frame via the
## live dict from get_obstacle(). `is_wreck` tags the derelict's own members so
## the approach autopilot can measure distance to the wreck surface
## (CollisionSystem.wreck_surface_distance) apart from stray debris.
## `mass` > 0 marks the body MOVABLE: CollisionSystem may write its `vel` field
## on impact (ship or another movable body knocking it) instead of treating it
## as an immovable wall. The owner (DriftSystem for salvage pieces, DebrisField
## for chunks) integrates position from `vel` and `position` each frame. A mass-0
## body (station structure, the derelict's intact members) is IMMOVABLE, not
## absent: it never gets pushed, but it does push — a movable body meets it on
## its tight hull and bounces off (CollisionSystem._resolve_static).
func register_obstacle(obstacle_name: String, position: Vector3, radius: float,
		hull := PackedVector3Array(), is_wreck := false, mass := 0.0) -> int:
	var id := _next_contact_id
	_next_contact_id += 1
	obstacles.append({
		"id": id,
		"name": obstacle_name,
		"position": position,
		"radius": radius,
		"hull": hull,
		"wreck": is_wreck,
		"mass": mass,
		"vel": Vector3.ZERO,
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


## DriftSystem: register a freshly severed piece and fan out its arrival. The
## returned dict is the live entry (Dictionaries are references) so DriftSystem
## can keep writing "transform"/"velocity"/"scoop" into it in place.
func add_salvage_piece(piece: Dictionary) -> void:
	salvage_pieces.append(piece)
	salvage_pieces_changed.emit()
	salvage_piece_spawned.emit(piece["id"])


## DriftSystem: a piece was stowed (player) or claimed (rival) — drop it.
func remove_salvage_piece(id: int) -> void:
	for i in salvage_pieces.size():
		if salvage_pieces[i]["id"] == id:
			salvage_pieces.remove_at(i)
			salvage_pieces_changed.emit()
			salvage_piece_removed.emit(id)
			return


func get_salvage_piece(id: int) -> Dictionary:
	for piece: Dictionary in salvage_pieces:
		if piece["id"] == id:
			return piece
	return {}


## Cargo-hatch intent (keybind / COWL switch): must be closed to fire the
## cutter or jump/dock (SalvageSystem.request_cut, MarketSystem) and open to
## scoop an adrift piece (DriftSystem).
func set_cargo_hatch(open: bool) -> void:
	if open == cargo_hatch_open:
		return
	cargo_hatch_open = open
	cargo_hatch_changed.emit(open)
	post_comms("OPS", "CARGO HATCH %s" % ("OPEN" if open else "SECURED"))


func toggle_cargo_hatch() -> void:
	set_cargo_hatch(not cargo_hatch_open)


## Landing-gear intent (keybind / the switch panel's GEAR lever / the MFD DOCK
## page). Only moves the LEVER — the gear itself travels over GEAR_TRAVEL_TIME
## in _process, so selecting down is a decision you make ahead of the final gate,
## not on top of it.
func set_landing_gear(down: bool) -> void:
	if down == gear_down:
		return
	gear_down = down
	landing_gear_changed.emit(down)
	post_comms("OPS", "LANDING GEAR — %s" % ("DOWN SELECTED" if down else "UP SELECTED"))


func toggle_landing_gear() -> void:
	set_landing_gear(not gear_down)


## Gear down AND fully travelled: the state a landing needs and the cutter
## interlock trips on. Mid-travel is neither stowed nor usable.
func gear_locked_down() -> bool:
	return gear_down and gear_position >= 1.0


## Gear fully stowed — the cutter needs this (an extended leg sits in the torch's
## arc), and it's what "clean" reads as on the instruments.
func gear_stowed() -> bool:
	return not gear_down and gear_position <= 0.0


## True while the pilot is hand-flying in a real volume (see FLIGHT_PHASES) —
## the claim or the station's docking pattern. Systems that integrate the ship
## or punish it for hitting things gate on this rather than on ON_SITE alone.
func flight_active() -> bool:
	return FLIGHT_PHASES.has(run_phase)


## DockingSystem: register a ship in the station's traffic pattern. Returns the
## live entry (Dictionaries are references) so the caller keeps writing its
## transform in place, exactly like salvage pieces.
func add_traffic(entry: Dictionary) -> void:
	traffic.append(entry)
	traffic_changed.emit()


func remove_traffic(id: int) -> void:
	for i in traffic.size():
		if traffic[i]["id"] == id:
			traffic.remove_at(i)
			traffic_changed.emit()
			return


func set_tracked_contact(id: int) -> void:
	tracked_contact_id = id
	tracked_contact_changed.emit(id)


## Step the locked contact to the next in the contact list (mapped contact-cycle
## intent); wraps, and locks the first when nothing is tracked. No-op with no
## contacts.
func cycle_tracked_contact(delta: int) -> void:
	if contacts.is_empty():
		return
	var here := -1
	for i in contacts.size():
		if contacts[i]["id"] == tracked_contact_id:
			here = i
			break
	if here == -1:
		set_tracked_contact(contacts[0 if delta >= 0 else contacts.size() - 1]["id"])
	else:
		var step := 1 if delta >= 0 else -1
		set_tracked_contact(contacts[(here + step + contacts.size()) % contacts.size()]["id"])


func set_sensor_mode(mode: String) -> void:
	if mode == sensor_mode or not SENSOR_MODES.has(mode):
		return
	sensor_mode = mode
	sensor_mode_changed.emit(mode)
	post_comms("SENSORS", "SWEEP MODE %s" % mode)


## Cycle the sensor mode to the next in SENSOR_MODES (mapped control intent).
func cycle_sensor_mode() -> void:
	var idx := SENSOR_MODES.find(sensor_mode)
	set_sensor_mode(SENSOR_MODES[(idx + 1) % SENSOR_MODES.size()])


## Camera-display intent: pick an external vantage (one of EXTERNAL_VIEWS).
func set_external_view(view: String) -> void:
	if view == external_view or not EXTERNAL_VIEWS.has(view):
		return
	external_view = view
	external_view_changed.emit(view)


## Cycle to the next external vantage (mapped view-cycle intent).
func cycle_external_view() -> void:
	var idx := EXTERNAL_VIEWS.find(external_view)
	set_external_view(EXTERNAL_VIEWS[(idx + 1) % EXTERNAL_VIEWS.size()])


## Tactical-display intent: pick a mode (SCOPE / CHART).
func set_tactical_view(view: String) -> void:
	if view == tactical_view or not TACTICAL_VIEWS.has(view):
		return
	tactical_view = view
	tactical_view_changed.emit(view)


## Toggle the Tactical display between SCOPE and CHART (mapped HOTAS-button
## intent).
func cycle_tactical_view() -> void:
	var idx := TACTICAL_VIEWS.find(tactical_view)
	set_tactical_view(TACTICAL_VIEWS[(idx + 1) % TACTICAL_VIEWS.size()])


## Touch-slider intent: set a channel's desired allocation. Always accepted — a
## setting is what the pilot asked for, and no electrical condition rewrites it.
## A starved bus changes what is delivered against this, not this.
func set_power(channel: String, value: float) -> void:
	if not _power_target.has(channel):
		return
	_power_target[channel] = clampf(value, 0.0, 1.0)
	_apply_electrical()


## Channel-switch intent (SwitchPanelBridge): ON = high setting, OFF = low.
func set_power_switch(switch_name: String, on: bool) -> void:
	if not CHANNEL_SWITCHES.has(switch_name):
		return
	var channel: String = CHANNEL_SWITCHES[switch_name]
	var hi: float = CHANNEL_HIGH_OVERRIDE.get(channel, power_high)
	_power_target[channel] = hi if on else power_low
	_apply_electrical()


## Master-alternator intent. The alternator turns reactor output into electricity;
## off, it makes none and the ship runs on the battery until that is flat.
func set_master_alt(on: bool) -> void:
	master_alt = on
	_apply_electrical()
	signature_changed.emit(passive_signature())


## Master-battery intent. The battery buffers the difference between supply and
## demand; off, there is no buffer and delivery is capped at whatever the
## alternator is making right now.
func set_master_battery(on: bool) -> void:
	master_bat = on
	_apply_electrical()
	signature_changed.emit(passive_signature())


## Electrical supply, in the units power_total() sums: the alternator's output
## when it is running, nothing when it is not. The reactor is always lit — ALT is
## what converts its output into amps.
func electrical_supply() -> float:
	return power_budget() if master_alt else 0.0


## Electrical demand: the sum of what the channels are SET to, with THRUST scaled
## by what the drive is actually doing. The field stage is electrically expensive
## and the thermal stage is nearly free, so demand moves with the drive selector
## and with whether there is hydrogen left to burn — see ShipDefinition.
func electrical_demand() -> float:
	var total := 0.0
	for channel: String in POWER_CHANNELS:
		var value: float = _power_target.get(channel, 0.0)
		if channel == "THRUST":
			value *= thrust_draw_factor()
		total += value
	return total


## Multiplier on THRUST-channel demand for the stages currently running. Nothing
## running draws nothing; the field stage is dear, the thermal stage cheap.
func thrust_draw_factor() -> float:
	if field_stage_running():
		return ship_def.thrust_draw_electric
	if thermal_stage_running():
		return ship_def.thrust_draw_thermal
	return 0.0


## Fraction of demand the bus can actually deliver, 0..1. Full whenever supply
## covers demand, or whenever the battery is there to make up the difference;
## otherwise the shortfall is shared proportionally across every channel.
func delivery_fraction() -> float:
	var demand := electrical_demand()
	if demand <= 0.0:
		return 1.0
	var supply := electrical_supply()
	if supply >= demand:
		return 1.0
	if master_bat and battery_charge > 0.0:
		return 1.0
	return clampf(supply / demand, 0.0, 1.0)


## Recompute delivered per-channel power from the settings and what the bus can
## carry, then emit power_changed once. The settings themselves are never touched
## here: a starved channel reads low on the instrument and comes back by itself.
func _apply_electrical() -> void:
	var power: Dictionary = local_ship()["power"]
	var fraction := delivery_fraction()
	for channel: String in POWER_CHANNELS:
		power[channel] = clampf(_power_target.get(channel, 0.0) * fraction, 0.0, 1.0)
	power_changed.emit()


## Charge or drain the battery against the standing supply/demand balance, and
## re-apply delivery. Called every physics tick.
func _advance_electrical(delta: float) -> void:
	var supply := electrical_supply()
	var demand := electrical_demand()
	var before := battery_charge
	if supply > demand:
		if master_bat:
			battery_charge = minf(BATTERY_CAPACITY,
					battery_charge + minf(supply - demand, BATTERY_CHARGE_RATE) * delta)
	elif supply < demand and master_bat:
		battery_charge = maxf(0.0, battery_charge - (demand - supply) * delta)
	_announce_battery(before)
	_apply_electrical()
	if not is_equal_approx(before, battery_charge):
		battery_changed.emit(battery_fraction())


## The low-battery and flat-battery calls, made on the crossing rather than every
## frame. Rearms once the charge climbs back above the threshold, so a pilot who
## runs it down twice is told twice.
func _announce_battery(before: float) -> void:
	var fraction := battery_fraction()
	if fraction > BATTERY_LOW:
		_battery_low_called = false
		return
	if _battery_low_called:
		return
	_battery_low_called = true
	if battery_charge <= 0.0 and before > 0.0:
		post_comms("OPS", "BATTERY FLAT — BUS UNPOWERED, RESTORE THE ALTERNATOR")
	else:
		post_comms("OPS", "BATTERY LOW — %.0f%% REMAINING" % (fraction * 100.0))


## Battery charge as a fraction of capacity, for instruments and checklist rows.
func battery_fraction() -> float:
	return clampf(battery_charge / BATTERY_CAPACITY, 0.0, 1.0)


## Net battery current, in the units power_total() sums: positive charging,
## negative discharging, zero when the balance is even or there is no buffer.
func battery_flow() -> float:
	if not master_bat:
		return 0.0
	var supply := electrical_supply()
	var demand := electrical_demand()
	if supply > demand and battery_charge < BATTERY_CAPACITY:
		return minf(supply - demand, BATTERY_CHARGE_RATE)
	if supply < demand and battery_charge > 0.0:
		return -(demand - supply)
	return 0.0


## Visibility to passive scanners, 0..1. Running dark on a master halves it;
## both off multiply to 0.25. Consumed by ThreatSystem (patrol enforce range).
func passive_signature() -> float:
	var s := 1.0
	if not master_alt:
		s *= 0.5
	if not master_bat:
		s *= 0.5
	return s


func power(channel: String) -> float:
	return local_ship()["power"].get(channel, 0.0)


## What a channel is SET to, as opposed to what power() reports being delivered
## against it. The two differ only while the bus is starved, and every instrument
## that shows a setting reads this one.
func power_target(channel: String) -> float:
	return _power_target.get(channel, 0.0)


func power_total() -> float:
	var total := 0.0
	for value: float in local_ship()["power"].values():
		total += value
	return total


func power_budget() -> float:
	return ship_def.power_budget


# --- Drive selector and propellant -------------------------------------------

## Drive-selector intent (the panel's magneto, or drive_mode_prev/next). Selecting
## OFF shuts the drive down, which costs a full start to undo — that is what makes
## the shutdown on the arrival checklist a decision rather than a formality.
func set_drive_mode(mode: String) -> void:
	if not DRIVE_MODES.has(mode) or mode == drive_mode:
		return
	var was_start := drive_mode == "START"
	drive_mode = mode
	if mode == "OFF":
		drive_started = false
		_drive_start_hold = 0.0
		post_comms("OPS", "DRIVE SHUT DOWN")
	elif mode == "START":
		_drive_start_hold = 0.0
	elif was_start:
		# Leaving START is what completes a start: the hold has to have been served
		# in full, and thrust only arrives once the selector is on a running detent.
		if _drive_start_hold >= ship_def.drive_start_time:
			drive_started = true
			post_comms("OPS", "DRIVE RUNNING — %s" % mode)
		else:
			post_comms("OPS", "START ABANDONED — %0.0f OF %0.0f SECONDS SERVED"
					% [_drive_start_hold, ship_def.drive_start_time])
		_drive_start_hold = 0.0
	_apply_electrical()
	drive_mode_changed.emit(drive_mode)


## Step the selector along DRIVE_MODES (mapped-button intent). Clamped rather than
## wrapped: a magneto does not wrap from START round to OFF, and neither should
## the keys that stand in for one.
func step_drive_mode(direction: int) -> void:
	var idx := DRIVE_MODES.find(drive_mode)
	set_drive_mode(DRIVE_MODES[clampi(idx + direction, 0, DRIVE_MODES.size() - 1)])


## Held-boost intent. Only meaningful while the thermal stage is running and both
## tanks have something in them; the burn itself is metered by ShipMotion.
func set_drive_boost(on: bool) -> void:
	drive_boost = on


## True while the selector is at START and the hold is still being served. The
## checklist row and the comms progress call read this.
func drive_starting() -> bool:
	return drive_mode == "START" and _drive_start_hold < ship_def.drive_start_time


## Seconds served at START, for the checklist row's live value.
func drive_start_progress() -> float:
	return _drive_start_hold


## Advance the starter hold. Only counts while the selector actually sits at
## START, and only with the bus alive — a dead ship cannot crank.
func _advance_drive_start(delta: float) -> void:
	if drive_mode != "START":
		return
	if delivery_fraction() <= 0.0 or electrical_supply() <= 0.0 and battery_charge <= 0.0:
		return
	var before := _drive_start_hold
	_drive_start_hold = minf(_drive_start_hold + delta, ship_def.drive_start_time)
	if before < ship_def.drive_start_time and _drive_start_hold >= ship_def.drive_start_time:
		post_comms("OPS", "START COMPLETE — SELECT A RUNNING POSITION")


## True while the drive is capable of producing thrust at all: a running detent,
## and a start that has been served since the last shutdown.
func drive_live() -> bool:
	return drive_started and DRIVE_RUN_MODES.has(drive_mode)


## True while the electrodynamic FIELD stage is turning: selected, and live. It
## needs no propellant, so nothing else can stop it.
func field_stage_running() -> bool:
	return drive_live() and DRIVE_FIELD_MODES.has(drive_mode)


## True while the NUCLEAR THERMAL stage is turning: selected, live, and with
## hydrogen left to heat. There is no automatic fallback — at L with a dry tank
## this goes false and NOTHING else takes over, because nothing else is selected.
func thermal_stage_running() -> bool:
	return drive_live() and DRIVE_THERMAL_MODES.has(drive_mode) and lh2_fuel > 0.0


## True while the combustion booster is actually burning: commanded, layered on a
## running thermal stage, and with oxygen as well as hydrogen aboard.
func boosting() -> bool:
	return drive_boost and thermal_stage_running() and lox_fuel > 0.0


## Thrust as a fraction of the ship's rated figure, from the stages actually
## turning. Both is the rated case; either alone is a degraded one; neither —
## selector at OFF or START, or L with a dry tank — is no thrust at all.
func thrust_fraction() -> float:
	var field := field_stage_running()
	var thermal := thermal_stage_running()
	if field and thermal:
		return 1.0
	if thermal:
		return ship_def.thrust_fraction_thermal
	if field:
		return ship_def.thrust_fraction_field
	return 0.0


## The speed the Higgs drag holds the ship to, given what the drive is doing. The
## field stage alone is the drag-limited maximum; reaction mass buys past it.
func speed_ceiling() -> float:
	var ceiling: float = ship_def.max_speed
	if thermal_stage_running():
		ceiling += ship_def.thermal_speed_bonus
		if boosting():
			ceiling += ship_def.boost_speed_bonus
	return ceiling


## Fill a tank from a berth. Returns the units actually taken, which is what the
## buyer is charged for — a part-empty tank costs part price.
func add_propellant(kind: String, units: float) -> float:
	var taken := 0.0
	if kind == "LH2":
		taken = minf(units, ship_def.lh2_capacity - lh2_fuel)
		lh2_fuel += taken
	elif kind == "LOX":
		taken = minf(units, ship_def.lox_capacity - lox_fuel)
		lox_fuel += taken
	if taken > 0.0:
		propellant_changed.emit()
	return taken


## Burn intent from ShipMotion, metered by commanded thrust. Announces the dry
## tank, because losing the thermal stage is something the pilot has to act on.
func burn_propellant(lh2: float, lox: float) -> void:
	if lh2 <= 0.0 and lox <= 0.0:
		return
	var had_lh2 := lh2_fuel > 0.0
	var had_lox := lox_fuel > 0.0
	lh2_fuel = maxf(0.0, lh2_fuel - lh2)
	lox_fuel = maxf(0.0, lox_fuel - lox)
	if had_lh2 and lh2_fuel <= 0.0:
		post_comms("OPS", "LH2 EXHAUSTED — THERMAL STAGE DEAD, SELECT R OR BOTH")
	if had_lox and lox_fuel <= 0.0:
		post_comms("OPS", "LOX EXHAUSTED — NO BOOST AVAILABLE")
	propellant_changed.emit()


func lh2_fraction() -> float:
	return clampf(lh2_fuel / maxf(ship_def.lh2_capacity, 0.001), 0.0, 1.0)


func lox_fraction() -> float:
	return clampf(lox_fuel / maxf(ship_def.lox_capacity, 0.001), 0.0, 1.0)


func post_comms(source: String, text: String) -> void:
	var entry := {"tick": tick, "source": source, "text": text}
	comms.append(entry)
	comms_posted.emit(entry)
	_write_comms_log(entry)


## Open (and truncate) this session's comms log, and print where it landed so
## the path never has to be hunted for.
func _open_comms_log() -> void:
	_comms_log = FileAccess.open(COMMS_LOG_PATH, FileAccess.WRITE)
	if _comms_log == null:
		push_warning("GameState: could not open %s for writing" % COMMS_LOG_PATH)
		return
	_comms_log.store_line("# Salvager session log — %s" %
			Time.get_datetime_string_from_system())
	_comms_log.flush()
	print("comms log: ", ProjectSettings.globalize_path(COMMS_LOG_PATH))


## Mirror every comms line to a file so a session can be read afterwards instead
## of photographed. The in-game log scrolls and holds a limited history, and the
## things worth reading back — what was hit, where, and in what order — are
## exactly the things that scroll away while you are busy flying.
##
## Truncated at each launch: a log you have to scroll to the end of to find the
## current run is barely better than a screenshot.
func _write_comms_log(entry: Dictionary) -> void:
	if _comms_log == null:
		return
	_comms_log.store_line("[T+%08.1f] %-7s %s" % [
		float(entry["tick"]) / TICK_RATE_HZ, entry["source"], entry["text"]])
	# Flushed per line: the runs worth reading back are the ones that ended in a
	# crash or a force-quit, which is precisely when buffered output is lost.
	_comms_log.flush()


## Gear travel, the electrical balance and the starter hold are all simulation
## state that other systems read as truth, so they advance on the physics tick
## with the rest of the sim rather than on the frame.
func _physics_process(delta: float) -> void:
	_advance_gear(delta)
	# Order matters: the starter needs a bus, and the bus balance depends on what
	# the drive is doing, so settle the electrics first and crank against them.
	_advance_electrical(delta)
	_advance_drive_start(delta)


func _process(delta: float) -> void:
	_tick_accum += delta
	while _tick_accum >= 1.0 / TICK_RATE_HZ:
		_tick_accum -= 1.0 / TICK_RATE_HZ
		tick += 1
		tick_changed.emit(tick)


## Run the gear toward wherever the lever is. Lives here rather than in
## DockingSystem because the gear is ship equipment: it must keep travelling
## while docking is INACTIVE (you can cycle it at the claim, where it interlocks
## the cutter) and it has to reach the stops for gear_locked_down() to mean
## anything. Announces only the two ends — the travel itself is silent.
func _advance_gear(delta: float) -> void:
	var target := 1.0 if gear_down else 0.0
	# Exact compare, not is_equal_approx: move_toward lands exactly on `target`,
	# and an approx guard would stop a hair short of the stops — leaving the gear
	# permanently "in transit" and gear_locked_down() permanently false.
	if gear_position == target:
		return
	gear_position = move_toward(gear_position, target, delta / GEAR_TRAVEL_TIME)
	if gear_position >= 1.0:
		post_comms("OPS", "LANDING GEAR DOWN AND LOCKED")
	elif gear_position <= 0.0:
		post_comms("OPS", "LANDING GEAR UP AND STOWED")
