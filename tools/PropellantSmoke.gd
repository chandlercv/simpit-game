extends Node
## Headless checks for the hybrid drive: the selector's positions, the two
## propellant tanks that feed it, the starter, and the electrical coupling that
## ties the two halves of the ship's systems together.
##
## THE RULE THIS FILE EXISTS TO PIN DOWN is that there is NO AUTOMATIC FALLBACK.
## A stage runs if it is SELECTED and it is SUPPLIED, and nothing steps in for a
## stage that isn't. At L with a dry hydrogen tank the ship makes no thrust at
## all until the pilot selects R or BOTH — that dead stop is the design, and a
## well-meant "just fall back to the field stage" would erase it.
##
##   godot --headless res://tools/PropellantSmoke.tscn

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	# InputRouter re-asserts the stick every frame, and on a headless rig that is a
	# zero command — it would wipe any flight command this test sets before the
	# next physics tick could burn anything. FlightSmoke silences it the same way.
	InputRouter.set_process(false)
	for child in InputRouter.get_children():
		child.set_process(false)
	var def: ShipDefinition = GameState.ship_def

	_test_selector(def)
	_test_dry_tanks(def)
	_test_boost(def)
	await _test_burn(def)
	_test_kinematic_burn(def)
	await _test_starter(def)
	_test_electrical_coupling(def)
	_test_purchase(def)

	if _failures.is_empty():
		print("PROPELLANT SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("PROPELLANT SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


# --- The selector -----------------------------------------------------------

## Every position's thrust, with both tanks aboard. BOTH is the rated case; each
## single stage is a degraded one; OFF and START are neither.
##
## The selector used to set a SPEED CEILING per position as well. It no longer
## does — speed is held by the fly-by-wire governor, which is a pilot setting and
## not a property of the drive — so what each position buys is thrust, and these
## check that the whole difference between the positions now lands there.
func _test_selector(def: ShipDefinition) -> void:
	_fill()
	GameState.set_drive_mode("BOTH")
	_check(is_equal_approx(GameState.thrust_fraction(), 1.0), "BOTH -> rated thrust")

	GameState.set_drive_mode("R")
	_check(is_equal_approx(GameState.thrust_fraction(), def.thrust_fraction_field),
			"R -> the field stage's thrust alone")

	GameState.set_drive_mode("L")
	_check(is_equal_approx(GameState.thrust_fraction(), def.thrust_fraction_thermal),
			"L -> the thermal stage's thrust alone")

	GameState.set_drive_mode("OFF")
	_check(GameState.thrust_fraction() == 0.0, "OFF -> no thrust at all")
	_check(not GameState.drive_live(), "OFF -> the drive is not live")


## The no-automatic-fallback rule, asserted in both directions.
func _test_dry_tanks(def: ShipDefinition) -> void:
	_fill()
	_start_drive()
	GameState.lh2_fuel = 0.0

	GameState.set_drive_mode("L")
	_check(GameState.thrust_fraction() == 0.0,
			"L with a dry LH2 tank makes NO thrust — nothing falls back for you")

	GameState.set_drive_mode("BOTH")
	_check(is_equal_approx(GameState.thrust_fraction(), def.thrust_fraction_field),
			"BOTH with a dry LH2 tank keeps flying on the field stage")
	_check(GameState.thrust_fraction() > 0.0,
			"a dry ship still accelerates — running out never strands you")

	# A full oxygen tank buys nothing without hydrogen to burn it with.
	GameState.lox_fuel = def.lox_capacity
	GameState.set_drive_boost(true)
	_check(not GameState.boosting(), "LOX is useless without LH2 — no boost")
	GameState.set_drive_boost(false)

	# The mirror: dry oxygen costs only the boost.
	_fill()
	GameState.lox_fuel = 0.0
	GameState.set_drive_mode("L")
	_check(is_equal_approx(GameState.thrust_fraction(), def.thrust_fraction_thermal),
			"a dry LOX tank leaves the thermal stage at full thrust")


func _test_boost(def: ShipDefinition) -> void:
	_fill()
	_start_drive()
	GameState.set_drive_mode("BOTH")
	GameState.set_drive_boost(true)
	_check(GameState.boosting(), "boost engages on a running thermal stage with both tanks")
	# The booster buys THRUST, and it is the only setting above the rated figure.
	# It used to buy a higher speed ceiling instead, which no longer exists to
	# raise — so if this ever came back as 1.0 the booster would cost two
	# propellants and do nothing whatever.
	_check(is_equal_approx(GameState.thrust_fraction(), def.thrust_fraction_boost),
			"boosting adds thrust on top of the rated figure")
	_check(def.thrust_fraction_boost > 1.0,
			"...and that figure is genuinely above rated, so the boost is worth burning LOX for")

	GameState.set_drive_mode("R")
	_check(not GameState.boosting(),
			"boost is refused on the field stage alone — there is nothing to burn LOX with")
	GameState.set_drive_mode("BOTH")
	GameState.set_drive_boost(false)
	_check(not GameState.boosting(), "boost is held, not latched")


# --- Burn accounting --------------------------------------------------------

## Burn is metered by COMMANDED thrust, so holding station beside a wreck is
## nearly free and a hard burn is not. Boost draws on both tanks at once. What is
## commanded is metered only to the extent it is DELIVERED, so a dead bus burns
## nothing. A burn the autopilot flies kinematically is charged too — see
## _test_kinematic_burn.
func _test_burn(_def: ShipDefinition) -> void:
	_fill()
	_start_drive()
	GameState.set_drive_mode("BOTH")
	GameState.run_phase = "ON_SITE"

	SalvageSystem.set_manual_flight(Vector3.ZERO, Vector3.ZERO)
	var idle_before := GameState.lh2_fuel
	await _wait(0.3)
	_check(is_equal_approx(GameState.lh2_fuel, idle_before),
			"a drive at rest burns nothing")

	SalvageSystem.set_manual_flight(Vector3(0, 0, 1.0), Vector3.ZERO)
	var burn_before := GameState.lh2_fuel
	await _wait(0.4)
	_check(GameState.lh2_fuel < burn_before, "commanded thrust burns LH2")

	_fill()
	GameState.set_drive_boost(true)
	var lh2_before := GameState.lh2_fuel
	var lox_before := GameState.lox_fuel
	await _wait(0.4)
	_check(GameState.lh2_fuel < lh2_before and GameState.lox_fuel < lox_before,
			"boosting draws on BOTH tanks at once")
	GameState.set_drive_boost(false)
	SalvageSystem.set_manual_flight(Vector3.ZERO, Vector3.ZERO)

	# The field stage needs no propellant, which is the whole reason R is the
	# position to select with the tanks low. An open lever costs amps and nothing
	# else there — no hydrogen is drawn because no hydrogen is being heated.
	_fill()
	GameState.set_drive_mode("R")
	var field_lh2 := GameState.lh2_fuel
	SalvageSystem.set_manual_flight(Vector3(0, 0, 1.0), Vector3.ZERO)
	await _wait(0.4)
	_check(is_equal_approx(GameState.lh2_fuel, field_lh2),
			"an open lever on the field stage alone burns nothing")
	SalvageSystem.set_manual_flight(Vector3.ZERO, Vector3.ZERO)
	GameState.set_drive_mode("BOTH")

	# The stage keeps turning on a dead bus, so thermal_stage_running() alone would
	# happily meter a burn that produced nothing: the acceleration is scaled by the
	# DELIVERED THRUST figure and goes to zero with it. A lever open against a dead
	# channel must cost neither speed nor propellant.
	_fill()
	GameState.set_master_alt(false)
	GameState.set_master_battery(false)
	_check(GameState.thermal_stage_running(),
			"a dead bus leaves the thermal stage turning")
	_check(GameState.power("THRUST") == 0.0, "...with nothing delivered to it")
	var dead_lh2 := GameState.lh2_fuel
	var dead_speed: float = (GameState.local_ship()["velocity"] as Vector3).length()
	SalvageSystem.set_manual_flight(Vector3(0, 0, 1.0), Vector3.ZERO)
	await _wait(0.4)
	_check(is_equal_approx(GameState.lh2_fuel, dead_lh2),
			"an open lever on a dead bus burns no LH2")
	_check(is_equal_approx((GameState.local_ship()["velocity"] as Vector3).length(), dead_speed),
			"...and produces no acceleration either")
	GameState.set_master_alt(true)
	GameState.set_master_battery(true)

	SalvageSystem.set_manual_flight(Vector3.ZERO, Vector3.ZERO)


## A burn flown as a KINEMATIC OVERRIDE — the approach autopilot, which seizes the
## motion state instead of commanding the drive — is charged like any other: the
## velocity change it imposes, measured against what the drive could have made in
## the same tick. Metering delta-v rather than speed is what leaves a coast free
## and still charges for the braking at the far end.
func _test_kinematic_burn(def: ShipDefinition) -> void:
	_fill()
	_start_drive()
	GameState.set_power("THRUST", 1.0)
	var step := 1.0 / 60.0
	# The same figure the drive flies on, so any delivery fraction cancels out of
	# the arithmetic below and these checks pin the LAW, not the allocation.
	var accel := ShipMotion.thrust_accel()
	_check(accel > 0.0, "the drive has an acceleration to charge a seize against")

	var before := GameState.lh2_fuel
	ShipMotion.burn_for_delta_v(Vector3.ZERO, step)
	_check(is_equal_approx(GameState.lh2_fuel, before),
			"a seize at constant velocity is a coast and burns nothing")

	before = GameState.lh2_fuel
	ShipMotion.burn_for_delta_v(Vector3(0.0, 0.0, accel * step * 0.5), step)
	_check(is_equal_approx(before - GameState.lh2_fuel, def.lh2_burn_rate * 0.5 * step),
			"half the drive's acceleration is charged at half the rated rate")

	before = GameState.lh2_fuel
	ShipMotion.burn_for_delta_v(Vector3(0.0, 0.0, accel * step * 10.0), step)
	_check(is_equal_approx(before - GameState.lh2_fuel, def.lh2_burn_rate * step),
			"a seize beyond what the drive could make is charged at the rated rate, not above it")

	# Nor does the field stage draw a tank it does not use. The autopilot flies on
	# R perfectly well — it is simply charged nothing for it, exactly as a pilot
	# flying the same burn by hand would be.
	_fill()
	GameState.set_drive_mode("R")
	before = GameState.lh2_fuel
	ShipMotion.burn_for_delta_v(Vector3(0.0, 0.0, ShipMotion.thrust_accel() * step), step)
	_check(ShipMotion.thrust_accel() > 0.0, "the field stage still makes thrust to be charged for")
	_check(is_equal_approx(GameState.lh2_fuel, before),
			"...but an autopilot burn on the field stage alone costs no propellant")
	GameState.set_drive_mode("BOTH")

	# The dead-bus rule reaches this path too — one meter, one set of gates.
	GameState.set_master_alt(false)
	GameState.set_master_battery(false)
	before = GameState.lh2_fuel
	ShipMotion.burn_for_delta_v(Vector3(0.0, 0.0, 1.0), step)
	_check(is_equal_approx(GameState.lh2_fuel, before),
			"a kinematic burn on a dead bus meters nothing either")
	GameState.set_master_alt(true)
	GameState.set_master_battery(true)


# --- The starter ------------------------------------------------------------

## START is a detent, not a momentary. It has to be occupied for the full hold,
## and thrust arrives only once the selector is turned back to a running
## position — sitting on START forever gets you nothing, because START does not
## run the drive.
func _test_starter(def: ShipDefinition) -> void:
	_fill()
	GameState.set_drive_mode("OFF")
	_check(not GameState.drive_live(), "OFF shuts the drive down")

	GameState.set_drive_mode("BOTH")
	_check(not GameState.drive_live(),
			"going straight from OFF to a running position does not start the drive")
	_check(GameState.thrust_fraction() == 0.0, "...and makes no thrust")

	# Leaving START early does not count.
	GameState.set_drive_mode("START")
	await _wait(minf(def.drive_start_time * 0.2, 1.0))
	_check(GameState.thrust_fraction() == 0.0, "START itself produces no thrust")
	GameState.set_drive_mode("BOTH")
	_check(not GameState.drive_live(), "leaving START early leaves the drive cold")

	# The full hold, then off START.
	GameState.set_drive_mode("START")
	await _wait(def.drive_start_time + 0.5)
	_check(GameState.drive_starting() == false, "the hold completes after its full time")
	_check(GameState.thrust_fraction() == 0.0,
			"...and STILL no thrust, because START is not a running position")
	GameState.set_drive_mode("BOTH")
	_check(GameState.drive_live(), "turning off START onto a running position starts it")
	_check(GameState.thrust_fraction() > 0.0, "...and thrust is available")


# --- The electrical coupling ------------------------------------------------

## Producing thrust without hydrogen costs a great deal of electricity; producing
## it with hydrogen costs very little. This is the link that turns an empty tank
## into a battery problem as well as a thrust problem.
func _test_electrical_coupling(_def: ShipDefinition) -> void:
	_fill()
	_start_drive()
	GameState.set_power("THRUST", 1.0)

	GameState.set_drive_mode("L")
	var thermal_demand := GameState.electrical_demand()
	GameState.set_drive_mode("BOTH")
	var field_demand := GameState.electrical_demand()
	_check(field_demand > thermal_demand,
			"running the field stage draws more than the thermal stage alone")

	# The accident itself: cruising cheap on L, the tank runs dry, and recovering
	# on R costs amps the alternator may not have.
	GameState.set_drive_mode("L")
	var cheap := GameState.electrical_demand()
	GameState.lh2_fuel = 0.0
	GameState.set_drive_mode("R")
	_check(GameState.electrical_demand() > cheap,
			"recovering a dry ship onto the field stage raises the bus load")
	_check(GameState.electrical_demand() > GameState.electrical_supply(),
			"...far enough, at full THRUST, to put the battery into discharge")


# --- Buying it --------------------------------------------------------------

func _test_purchase(def: ShipDefinition) -> void:
	GameState.run_phase = "ON_SITE"
	GameState.lh2_fuel = 0.0
	var credits_before := GameState.credits
	MarketSystem.buy_propellant("LH2")
	_check(GameState.lh2_fuel == 0.0 and GameState.credits == credits_before,
			"propellant is refused away from a berth")

	GameState.run_phase = "DOCKED"
	GameState.credits = 10
	MarketSystem.buy_propellant("LH2")
	_check(GameState.lh2_fuel == 0.0 and GameState.credits == 10,
			"propellant is refused when the credits are not there")

	GameState.credits = 100000
	var quote := MarketSystem.propellant_quote("LH2")
	_check(quote > 0, "an empty tank quotes a price")
	MarketSystem.buy_propellant("LH2")
	_check(is_equal_approx(GameState.lh2_fuel, def.lh2_capacity),
			"buying fills the tank to the top")
	_check(GameState.credits == 100000 - quote, "...and charges the quoted price")

	MarketSystem.buy_propellant("LH2")
	_check(GameState.credits == 100000 - quote, "a full tank is refused, not re-billed")
	_check(MarketSystem.propellant_quote("LH2") == 0, "...and quotes nothing")


# --- Helpers ----------------------------------------------------------------

func _fill() -> void:
	GameState.lh2_fuel = GameState.ship_def.lh2_capacity
	GameState.lox_fuel = GameState.ship_def.lox_capacity


## Put the drive in the started state without spending the starter hold, for the
## tests that are about something else.
func _start_drive() -> void:
	GameState.drive_started = true
	GameState.set_drive_mode("BOTH")


## Game-seconds, as a process_frame loop — burn and the starter hold both advance
## on the physics tick, which a SceneTreeTimer does not reliably interleave with.
func _wait(game_seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < game_seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
