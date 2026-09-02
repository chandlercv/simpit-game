extends Node
## The ship's annunciator logic: what is wrong, how badly, and — the part that
## matters — whether it has already been said.
##
## Why this exists
## ---------------
## Every warning in the game except the low battery was re-evaluated every frame
## with nothing latching it. That was fine while warnings were only ever drawn:
## a red line redrawn sixty times a second still reads as one red line. The
## moment a warning makes a NOISE it stops being fine, because sixty alarms a
## second is not an alarm.
##
## GameState._announce_battery is the one place in the project that already gets
## this right — it fires once on the way down and rearms on the way back up.
## This generalises that, and nothing else.
##
## The levels are the HANDBOOK'S levels, not new ones. PilotManualContent
## declares exactly three callouts and CLAUDE.md requires every hazard to use
## them, so the ship's alarms speak the same three words the printed manual does
## rather than inventing a fourth vocabulary beside Instrument.GOOD/WARN/BAD.
##
## Every predicate below calls the SAME function the instruments call —
## gear_stowed(), authority(), battery_fraction(), current_instruction(). This is
## a second READER of those facts, never a second copy of them: if the rule for
## gear overspeed changes in DockingSystem, this follows it automatically because
## it never knew the rule, only where to ask.
##
## Hysteresis is per-condition and explicit. A quantity sitting exactly on its
## threshold must not chatter, so `clear` is a separate test from `raise` and is
## deliberately slacker — you have to actually fix something to silence it.

## Damage to the ship, or salvage lost. HELD: it sounds until it is cleared.
##
## Reserved for conditions the pilot can end by doing something now — an open bus,
## the gear out above its limit. A condition that cannot be silenced by flying
## well does not belong at this level however serious it is, because an alarm you
## cannot answer is an alarm you stop hearing, and it takes the answerable ones
## down with it. Those are cautions instead. See FRAME_RISK below.
const WARNING := "WARNING"
## An interlock, a refusal, a limit. Fires once.
const CAUTION := "CAUTION"
## Clarification. Fires once, quietly.
const NOTE := "NOTE"

const LEVELS: Array[String] = [WARNING, CAUTION, NOTE]

## Battery headroom that must be won back before a low-battery caution rearms.
const BATTERY_REARM := 0.05
## Speed below the gear limit that counts as having slowed down, m/s.
const GEAR_REARM := 1.5
## Risk that must be shed before a collapse warning stops.
const RISK_REARM := 0.05
## Authority that must be recovered before a degraded-assist caution rearms.
const AUTHORITY_REARM := 0.1

signal alert_raised(id: String, level: String)
signal alert_cleared(id: String)

## id -> { level, raise: Callable, clear: Callable }. Built in _ready because
## Callables cannot live in a const.
var _conditions: Dictionary = {}
## id -> true while the condition is standing.
var _active: Dictionary = {}


func _ready() -> void:
	_declare()


func _declare() -> void:
	# --- Electrical ----------------------------------------------------------
	_add("BUS_DEAD", WARNING,
			func() -> bool: return not GameState.bus_live(),
			func() -> bool: return GameState.bus_live())

	_add("BATTERY_LOW", CAUTION,
			func() -> bool: return GameState.battery_fraction() < GameState.BATTERY_LOW,
			func() -> bool: return GameState.battery_fraction() > GameState.BATTERY_LOW + BATTERY_REARM)

	# --- Propellant ----------------------------------------------------------
	# Only worth saying while the stage that needs it is actually turning. A dry
	# LH2 tank on a ship flying the field stage is not news.
	_add("LH2_EXHAUSTED", CAUTION,
			func() -> bool: return GameState.thermal_stage_running() and GameState.lh2_fuel <= 0.0,
			func() -> bool: return GameState.lh2_fuel > 0.0 or not GameState.thermal_stage_running())

	_add("LOX_EXHAUSTED", NOTE,
			func() -> bool: return GameState.boosting() and GameState.lox_fuel <= 0.0,
			func() -> bool: return GameState.lox_fuel > 0.0 or not GameState.boosting())

	# --- Airframe ------------------------------------------------------------
	# The same test DockingSystem._update_gear_stress does the damage on, asked
	# of the same two functions.
	_add("GEAR_OVERSPEED", WARNING,
			func() -> bool: return not GameState.gear_stowed() and _speed() > GameState.GEAR_LIMIT_SPEED,
			func() -> bool: return GameState.gear_stowed() or _speed() < GameState.GEAR_LIMIT_SPEED - GEAR_REARM)

	# --- Fly-by-wire ---------------------------------------------------------
	# DIRECT law is a decision, not a fault, so it is a NOTE — even though it also
	# removes the speed governor, because choosing to fly without a limit is still
	# choosing. Assist SELECTED and unable to deliver is a fault, and that is the
	# caution.
	_add("ASSIST_OFF", NOTE,
			func() -> bool: return not ShipMotion.fbw_engaged(),
			func() -> bool: return ShipMotion.fbw_engaged())

	_add("ASSIST_DEGRADED", CAUTION,
			func() -> bool: return ShipMotion.fbw_engaged() \
					and ShipMotion.authority() < SalvageSystem.MIN_ALIGN_AUTHORITY,
			func() -> bool: return not ShipMotion.fbw_engaged() \
					or ShipMotion.authority() > SalvageSystem.MIN_ALIGN_AUTHORITY + AUTHORITY_REARM)

	# --- The wreck -----------------------------------------------------------
	# Past this floor ThreatSystem can collapse the frame and take every uncut
	# member with it, so by the handbook's definition — salvage lost — this reads
	# as a WARNING. It is a CAUTION anyway, and deliberately.
	#
	# The resting risk does NOT fall (see the handbook, Structural loading). A
	# held warning here would therefore start on the cut that crosses the floor
	# and sound for the rest of the site, whatever the pilot did about it. An
	# alarm you cannot silence by flying well is an alarm you stop hearing, and it
	# would take the two that DO mean something down with it. Crossing the floor
	# is news exactly once.
	_add("FRAME_RISK", CAUTION,
			func() -> bool: return GameState.structural_risk > ThreatSystem.COLLAPSE_RISK_FLOOR,
			func() -> bool: return GameState.structural_risk < ThreatSystem.COLLAPSE_RISK_FLOOR - RISK_REARM)

	# --- The harbour ---------------------------------------------------------
	# ATC's own urgency flag, which is the only severity the project had before
	# this file existed. Also a CAUTION, for the same reason: a standing urgent
	# instruction stays urgent until the harbour supersedes it, so "HOLD AT ALPHA
	# — YOU ARE STILL MOVING" would warble until a clearance arrived. Urgency on
	# an instruction means read it now, not that the ship is coming apart, and the
	# banner is already pulsing red to say so.
	_add("ATC_URGENT", CAUTION,
			func() -> bool: return bool(DockingSystem.current_instruction().get("urgent", false)),
			func() -> bool: return not bool(DockingSystem.current_instruction().get("urgent", false)))


func _add(id: String, level: String, raise: Callable, clear: Callable) -> void:
	_conditions[id] = {"level": level, "raise": raise, "clear": clear}
	_active[id] = false


## World (inertial) speed — see GameState.ships on the frame. Nothing is
## subtracted, so this is speed through space, not closing speed on anything.
func _speed() -> float:
	return (GameState.local_ship().get("velocity", Vector3.ZERO) as Vector3).length()


## Latch every declared condition once a frame. Raising and clearing are
## deliberately asymmetric: a condition raises on its own test and clears only on
## the slacker one, so nothing sitting on a threshold can chatter.
func _process(_delta: float) -> void:
	for id: String in _conditions:
		var spec: Dictionary = _conditions[id]
		var standing: bool = _active[id]
		if not standing and (spec["raise"] as Callable).call():
			_active[id] = true
			alert_raised.emit(id, spec["level"])
		elif standing and (spec["clear"] as Callable).call():
			_active[id] = false
			alert_cleared.emit(id)


## True while any WARNING-level condition is standing — what holds the master
## warble on. Cautions and notes are said once and are not asked about again.
func has_warning() -> bool:
	for id: String in _conditions:
		if _active[id] and _conditions[id]["level"] == WARNING:
			return true
	return false


func is_active(id: String) -> bool:
	return bool(_active.get(id, false))


## Every standing condition, worst first. The order of LEVELS is the order of
## severity, so this needs no second ranking table.
func standing() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for level: String in LEVELS:
		for id: String in _conditions:
			if _active[id] and _conditions[id]["level"] == level:
				out.append({"id": id, "level": level})
	return out


## Every declared condition id. AudioSmoke walks this to prove each predicate
## runs without erroring against a booted ship.
func condition_ids() -> Array:
	return _conditions.keys()


## Run one condition's raise test. Used by AudioSmoke to prove the predicates
## are wired to functions that still exist.
func test_raise(id: String) -> bool:
	if not _conditions.has(id):
		return false
	return bool((_conditions[id]["raise"] as Callable).call())
