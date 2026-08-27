extends Node
## Faction pricing and reputation (feeds the Chart window's market panel).
## Factions and goods are authored as .tres Resources under data/ (plan
## Phase 4 convention) — a new faction or commodity is a data file, not code.
##
## Also owns the run-phase loop around the market: dock (abstract transit
## burn), sell the hold at the docked faction's prices, jump back to the
## claim (which resets the site for a fresh run).

const GOODS_DIR := "res://data/goods/"
const FACTIONS_DIR := "res://data/factions/"

## Abstract transit burn between the claim and a station, seconds.
const TRANSIT_TIME := 3.0

## Reputation gained per sale; prices scale 0.85..1.15 across rep 0..1.
const REP_PER_SALE := 0.03

## Propellant offered at a berth, in credits per unit of tank capacity. Hydrogen
## is the working fluid and is cheap by the tankful; oxygen is only good for the
## booster, and is priced as the luxury it is. Quoted in the commercial agent's
## schedule of prices (TerminalProceduresContent), never in the ship's handbook.
const LH2_PRICE_PER_UNIT := 8
const LOX_PRICE_PER_UNIT := 30

## What each propellant is called on the MARKET page and in the comms log.
const PROPELLANT_NAMES: Dictionary = {
	"LH2": "LIQUID HYDROGEN",
	"LOX": "LIQUID OXYGEN",
}

var _goods: Array = []      # GoodDefinition, parallel to GameState.market_goods
var _factions: Array = []   # FactionDefinition, parallel to GameState.market_factions
var _rng := RandomNumberGenerator.new()
## Per-good, per-faction dock-time price jitter, refreshed on each docking.
var _jitter: Array = []


func _ready() -> void:
	_rng.randomize()
	for resource in _load_dir(GOODS_DIR):
		_goods.append(resource)
	for resource in _load_dir(FACTIONS_DIR):
		_factions.append(resource)
	for faction: FactionDefinition in _factions:
		GameState.market_factions.append(faction.display_name)
		GameState.reputation[faction.display_name] = faction.starting_rep
	# Prices scale with reputation, so any rep change (a sale here, a patrol
	# fine in ThreatSystem) must refresh the cached table the Chart reads.
	GameState.reputation_changed.connect(_reprice)
	_reroll_jitter()
	_reprice()


func good(display_name: String) -> GoodDefinition:
	for g: GoodDefinition in _goods:
		if g.display_name == display_name:
			return g
	push_error("Unknown good: %s" % display_name)
	return GoodDefinition.new()


## The faction whose patrols enforce the salvage claim (ThreatSystem).
func claim_faction() -> String:
	for faction: FactionDefinition in _factions:
		if faction.holds_claim:
			return faction.display_name
	return ""


func price(good_index: int, faction_index: int) -> int:
	var g: GoodDefinition = _goods[good_index]
	var f: FactionDefinition = _factions[faction_index]
	var bias: float = f.price_bias.get(g.display_name, 1.0)
	var rep: float = GameState.reputation[f.display_name]
	return maxi(roundi(g.base_price * bias * (0.85 + 0.3 * rep)
			* _jitter[good_index][faction_index]), 1)


## What the current hold would fetch at a faction's prices.
func hold_value(faction_index: int) -> int:
	var total := 0
	for item: Dictionary in GameState.local_ship()["cargo"]:
		total += roundi(item["qty"] * price(_good_index(item["good"]), faction_index))
	return total


## --- Intents (Chart window) ------------------------------------------------


func request_dock(faction_index: int) -> void:
	if GameState.run_phase != "ON_SITE" or faction_index >= _factions.size():
		return
	if GameState.wreck["cutting_id"] != -1:
		GameState.post_comms("OPS", "DEPARTURE HELD — CUTTER ACTIVE")
		return
	if not GameState.hatch_secured():
		GameState.post_comms("OPS", "DEPARTURE HELD — SECURE CARGO HATCH FIRST")
		return
	var faction_name: String = GameState.market_factions[faction_index]
	_set_phase("TRANSIT")
	GameState.post_comms("OPS", "DEPARTURE BURN — BOUND FOR %s STATION" % faction_name)
	await get_tree().create_timer(TRANSIT_TIME).timeout
	# The burn only gets you to the station's outer approach. The berth is flown
	# for (DockingSystem) — or bought with an auto-berth handling fee — and only
	# complete_dock() below actually books it.
	_set_phase("APPROACH")
	DockingSystem.begin_approach(faction_index)


## DockingSystem: the ship is on the pad (a touchdown, or an auto-berth ATC flew
## in). The one door into DOCKED — both paths come through here so the market
## only ever wakes up one way.
func complete_dock(faction_index: int) -> void:
	if faction_index < 0 or faction_index >= _factions.size():
		return
	var faction_name: String = GameState.market_factions[faction_index]
	GameState.docked_faction = faction_index
	_reroll_jitter()
	_reprice()
	_set_phase("DOCKED")
	GameState.post_comms("HARBOR", "DOCKED AT %s STATION — MARKET FEED LIVE" % faction_name)


## DockingSystem: the approach was abandoned. Burn back to the claim WITHOUT
## resetting the site — no berth was made, so the run isn't over and the wreck
## is exactly as it was left.
func abort_dock() -> void:
	if GameState.run_phase != "APPROACH":
		return
	_set_phase("TRANSIT")
	GameState.post_comms("OPS", "APPROACH ABANDONED — BURNING FOR CLAIM 7741-C")
	await get_tree().create_timer(TRANSIT_TIME).timeout
	_place_ship_at_claim()
	_set_phase("ON_SITE")
	GameState.post_comms("OPS", "BACK ON STATION AT CLAIM 7741-C")


func sell_hold() -> void:
	if GameState.run_phase != "DOCKED":
		return
	# The hold is discharged through the cargo hatch, so it has to be open. This
	# is why the arrival procedure opens up before anything else: a buttoned-up
	# ship has nothing to hand over.
	if not GameState.hatch_open_locked():
		GameState.post_comms("MARKET", "DISCHARGE HELD — OPEN THE CARGO HATCH FIRST")
		return
	var faction_index := GameState.docked_faction
	var faction_name: String = GameState.market_factions[faction_index]
	var total := hold_value(faction_index)
	if total == 0:
		GameState.post_comms("MARKET", "NOTHING IN HOLD TO SELL")
		return
	CargoSystem.clear_hold()
	GameState.credits += total
	GameState.credits_changed.emit(GameState.credits)
	GameState.reputation[faction_name] = clampf(
			GameState.reputation[faction_name] + REP_PER_SALE, 0.0, 1.0)
	GameState.reputation_changed.emit()  # drives _reprice() via the _ready hook
	GameState.post_comms("MARKET", "HOLD SOLD TO %s — %d CR (REP RISING)" % [
		faction_name, total])


## Price of filling a tank to the top from where it stands, in credits. Part of
## a tank costs part of the price — there is no minimum uplift.
func propellant_quote(kind: String) -> int:
	var short := 0.0
	if kind == "LH2":
		short = GameState.ship_def.lh2_capacity - GameState.lh2_fuel
	elif kind == "LOX":
		short = GameState.ship_def.lox_capacity - GameState.lox_fuel
	return int(ceil(maxf(short, 0.0) * _propellant_price(kind)))


func _propellant_price(kind: String) -> int:
	return LH2_PRICE_PER_UNIT if kind == "LH2" else LOX_PRICE_PER_UNIT


## Buy propellant at the berth. Fills the named tank to the top and charges for
## what actually went in, so topping off a nearly-full tank is nearly free.
## Refused away from a berth, on a full tank, and when the credits are not there —
## partial uplifts on short money would turn every refuel into arithmetic.
func buy_propellant(kind: String) -> void:
	if not PROPELLANT_NAMES.has(kind):
		return
	var label: String = PROPELLANT_NAMES[kind]
	if GameState.run_phase != "DOCKED":
		GameState.post_comms("MARKET", "%s IS SOLD AT A BERTH ONLY" % label)
		return
	var cost := propellant_quote(kind)
	if cost <= 0:
		GameState.post_comms("MARKET", "%s TANK ALREADY FULL" % label)
		return
	if GameState.credits < cost:
		GameState.post_comms("MARKET", "%s REFUSED — %d CR REQUIRED, %d CR HELD" % [
			label, cost, GameState.credits])
		return
	var taken := GameState.add_propellant(kind, INF)
	GameState.credits -= cost
	GameState.credits_changed.emit(GameState.credits)
	GameState.post_comms("MARKET", "%s UPLIFTED — %.0f UNITS, %d CR" % [
		label, taken, cost])


## Leaving the berth is flown too: this lifts off into the departure pattern
## rather than jumping. The jump itself waits on complete_undock().
func request_undock() -> void:
	if GameState.run_phase != "DOCKED":
		return
	if not GameState.hatch_secured():
		GameState.post_comms("OPS", "DEPARTURE HELD — SECURE CARGO HATCH FIRST")
		return
	var faction_index := GameState.docked_faction
	GameState.docked_faction = -1
	_set_phase("APPROACH")
	DockingSystem.begin_departure(faction_index)


## DockingSystem: the ship is outbound past the hold marker and released by ATC.
## Now the abstract burn home runs, and a fresh run starts at the claim.
func complete_undock() -> void:
	_set_phase("TRANSIT")
	GameState.post_comms("OPS", "CLEAR OF THE PATTERN — BURNING FOR CLAIM 7741-C")
	await get_tree().create_timer(TRANSIT_TIME).timeout
	SalvageSystem.reset_site()
	ThreatSystem.reset_run()
	_place_ship_at_claim()
	_set_phase("ON_SITE")
	GameState.post_comms("OPS", "JUMP COMPLETE — ON STATION AT CLAIM 7741-C")


## Arriving at the claim: the fixed entry pose (the boot pose — origin, facing
## the wreck at DEFAULT_WRECK_POS down -Z), stopped. Without this the ship would
## still be wherever the station pattern left it, hundreds of metres from the
## claim it just jumped to.
func _place_ship_at_claim() -> void:
	ShipMotion.seize(Transform3D.IDENTITY, Vector3.ZERO)


## --- Internals --------------------------------------------------------------


func _set_phase(phase: String) -> void:
	if GameState.run_phase == "ON_SITE" and phase != "ON_SITE":
		SalvageSystem.reset_approach()
	GameState.run_phase = phase
	GameState.run_phase_changed.emit(phase)


## Rebuilds the replication-friendly table the Chart window reads.
func _reprice() -> void:
	GameState.market_goods = []
	for gi in _goods.size():
		var g: GoodDefinition = _goods[gi]
		var prices: Array = []
		for fi in _factions.size():
			prices.append(price(gi, fi))
		GameState.market_goods.append(
				{"name": g.display_name, "unit": g.unit, "prices": prices})
	GameState.market_changed.emit()


func _reroll_jitter() -> void:
	_jitter = []
	for gi in _goods.size():
		var row: Array = []
		for fi in _factions.size():
			row.append(_rng.randf_range(0.92, 1.08))
		_jitter.append(row)


func _good_index(display_name: String) -> int:
	for i in _goods.size():
		if _goods[i].display_name == display_name:
			return i
	return 0


func _load_dir(path: String) -> Array:
	var out: Array = []
	var names := DirAccess.get_files_at(path)
	names.sort()
	for file_name in names:
		# Exported builds may list remapped resources (.tres.remap).
		var res_name := file_name.trim_suffix(".remap")
		if res_name.get_extension() == "tres":
			out.append(load(path + res_name))
	return out
