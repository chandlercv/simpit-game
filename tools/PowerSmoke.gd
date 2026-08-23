extends Node
## Headless checks for the alternator/battery power model: the four channel
## switches drive their mapped channel between high/low, the alternator supplies
## the bus and charges the battery with its surplus, the battery covers a deficit
## until it is flat, the battery switch is the buffer rather than a kill switch,
## and passive-scanner visibility halves per master that is off.
##
## It also covers the exterior lights, because they are an electrical item and not
## a decoration: they are a token load on the bus, they go out when the bus has no
## source behind it, and every group that is not burning takes a bite out of the
## ship's signature.
##
## THE ASSERTION THAT MATTERS MOST is the last group: an electrical condition
## changes what is DELIVERED and never what is SET. A starved bus that quietly
## rewrote the pilot's allocation would be indistinguishable, on the instrument,
## from a control that had moved on its own.
##
##   godot --headless res://tools/PowerSmoke.tscn

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame

	var hi := GameState.power_high
	var lo := GameState.power_low

	# 1. Channel switches drive their mapped channel (thematic mapping).
	GameState.set_power_switch("FUEL_PUMP", true)
	GameState.set_power_switch("AVIONICS", true)
	GameState.set_power_switch("DE_ICE", true)
	GameState.set_power_switch("PITOT_HEAT", true)
	_check(GameState.power("THRUST") == hi, "FUEL_PUMP on -> THRUST high")
	_check(GameState.power("SENSORS") == hi, "AVIONICS on -> SENSORS high")
	_check(GameState.power("CUTTER") == hi, "DE_ICE on -> CUTTER high")
	_check(GameState.power("LIFE") == 1.0, "PITOT_HEAT on -> LIFE 100%")
	GameState.set_power_switch("DE_ICE", false)
	_check(GameState.power("CUTTER") == lo, "DE_ICE off -> CUTTER low")

	# 2. Supply and demand. The alternator makes the budget; demand is what the
	# channels are set to, with THRUST scaled by what the drive is doing.
	GameState.set_drive_mode("BOTH")
	_check(is_equal_approx(GameState.electrical_supply(), GameState.power_budget()),
			"the alternator supplies the reactor's budget while ALT is on")
	var field_demand := GameState.electrical_demand()
	GameState.set_drive_mode("L")
	_check(GameState.electrical_demand() < field_demand,
			"the thermal stage alone draws less than the field stage")
	GameState.set_drive_mode("BOTH")

	# 3. The battery charges on a surplus and discharges on a deficit.
	GameState.battery_charge = GameState.BATTERY_CAPACITY * 0.5
	_set_all_channels(0.0)
	await _wait(0.4)
	_check(GameState.battery_charge > GameState.BATTERY_CAPACITY * 0.5,
			"a surplus charges the battery")
	_check(GameState.battery_flow() > 0.0, "...and the flow reads as charging")

	_set_all_channels(1.0)
	var charge_before := GameState.battery_charge
	await _wait(0.4)
	_check(GameState.battery_charge < charge_before,
			"a load over the alternator's output discharges the battery")
	_check(GameState.battery_flow() < 0.0, "...and the flow reads as discharging")
	_check(is_equal_approx(GameState.power("THRUST"), GameState.power_target("THRUST")),
			"...while the battery holds out, every channel is delivered in full")

	# 4. ALT off runs the ship off the battery, and a flat battery is a dark ship.
	GameState.set_master_alt(false)
	_check(GameState.electrical_supply() == 0.0, "ALT off -> the alternator makes nothing")
	_check(is_equal_approx(GameState.power("LIFE"), GameState.power_target("LIFE")),
			"ALT off -> the ship runs on the battery, at full delivery")
	GameState.battery_charge = 0.0
	await _wait(0.2)
	_check(GameState.power_total() == 0.0,
			"a flat battery with no alternator delivers nothing at all")
	_check(GameState.power_target("LIFE") > 0.0,
			"...and the allocation it cannot deliver is still set")
	GameState.set_master_alt(true)
	_set_all_channels(0.2)
	await _wait(0.2)
	_check(is_equal_approx(GameState.power("LIFE"), GameState.power_target("LIFE")),
			"restoring the alternator restores delivery without a snapshot")

	# 5. BAT off removes the buffer: delivery is capped at what the alternator is
	# making right now, shared proportionally. It is NOT a kill switch.
	GameState.set_master_battery(false)
	_set_all_channels(0.1)
	await _wait(0.2)
	_check(GameState.power_total() > 0.0,
			"BAT off with a light load still delivers — the alternator carries it")
	_set_all_channels(1.0)
	await _wait(0.2)
	_check(GameState.power_total() <= GameState.power_budget() + 0.001,
			"BAT off with a heavy load sheds down to the alternator's output")
	_check(GameState.power("THRUST") < GameState.power_target("THRUST"),
			"...by starving delivery")
	_check(is_equal_approx(GameState.power_target("THRUST"), 1.0),
			"...and not by moving the setting")
	GameState.set_master_battery(true)

	# 6. Settings survive every starved state, and edits made while starved take
	# effect. This is the whole settings-versus-availability contract.
	GameState.battery_charge = 0.0
	GameState.set_master_alt(false)
	GameState.set_master_battery(false)
	await _wait(0.2)
	_check(GameState.power_total() == 0.0, "both masters off -> a quiet ship")
	_set_all_channels(0.2)
	GameState.set_power("CUTTER", 0.42)
	GameState.set_power_switch("DE_ICE", false)
	_check(is_equal_approx(GameState.power_target("CUTTER"), lo),
			"a switch moved on a dark ship still records its position")
	GameState.set_power("SENSORS", 0.33)
	_check(is_equal_approx(GameState.power_target("SENSORS"), 0.33),
			"a slider moved on a dark ship still records its setting")
	GameState.set_master_alt(true)
	GameState.set_master_battery(true)
	await _wait(0.2)
	_check(is_equal_approx(GameState.power("SENSORS"), 0.33)
			and is_equal_approx(GameState.power("CUTTER"), lo),
			"power returns to exactly what was set while it was out")

	# 7. Passive-scanner visibility halves per master off, stacking to 0.25 — with
	# the lights burning, which is how the ship boots.
	_check(GameState.passive_signature() == 1.0, "signature 1.0 with both masters on")
	GameState.set_master_alt(false)
	_check(GameState.passive_signature() == 0.5, "signature 0.5 with ALT off")
	GameState.set_master_battery(false)
	# Both masters off is a DARK ship: the lights go out with everything else, so
	# the two effects compound and a blacked-out hull sits below a bare quarter.
	# That is the whole point of the lights being on the bus rather than beside it.
	var lights_out: float = pow(GameState.LIGHT_GROUP_SIGNATURE,
			GameState.exterior_lights.size())
	_check(is_equal_approx(GameState.passive_signature(), 0.25 * lights_out),
			"signature 0.25 with both off, less again for the lights they took out")
	GameState.set_master_alt(true)
	GameState.set_master_battery(true)

	# 8. The exterior lights: a load, a bus dependency, and a signature term.
	await _wait(0.2)
	_check(GameState.bus_live(), "a healthy bus is live")
	_check(GameState.light_group_lit("NAV") and GameState.light_group_lit("BEACON")
			and GameState.light_group_lit("STROBE"),
			"every light group burns on a healthy bus")
	_check(GameState.passive_signature() == 1.0, "a fully lit ship has signature 1.0")

	var lit_demand := GameState.electrical_demand()
	GameState.set_exterior_light("STROBE", false)
	_check(GameState.electrical_demand() < lit_demand,
			"a group switched off stops drawing")
	_check(is_equal_approx(GameState.electrical_demand(),
			lit_demand - GameState.LIGHT_GROUP_DRAW),
			"the draw it stops is exactly one group's worth")
	_check(is_equal_approx(GameState.passive_signature(),
			GameState.LIGHT_GROUP_SIGNATURE),
			"one group out takes LIGHT_GROUP_SIGNATURE off the signature")
	_check(GameState.passive_signature() > 0.5,
			"the whole fit is still worth less than a single master")
	_check(GameState.delivery_fraction() == 1.0,
			"the lights are too small a load to starve a healthy bus")
	GameState.set_exterior_light("STROBE", true)

	# The lights need a source, not merely a switch: selected on, both masters off,
	# and they are not burning. Same rule as everything else on the bus — an
	# electrical condition changes what is DELIVERED and never what is SET.
	GameState.set_master_alt(false)
	GameState.set_master_battery(false)
	_check(not GameState.bus_live(), "both masters off -> no source behind the bus")
	_check(not GameState.light_group_lit("NAV"),
			"the lights are out on a dark ship")
	_check(GameState.exterior_lights["NAV"] == true,
			"...with the switch still selected on")
	GameState.set_master_alt(true)
	await _wait(0.2)
	_check(GameState.light_group_lit("NAV"),
			"restoring the bus lights them again with no switch touched")

	# A flat battery on the alternator alone is the same dark ship, which is the
	# case the literal "both masters off" test would miss.
	GameState.set_master_alt(false)
	var saved_charge := GameState.battery_charge
	GameState.battery_charge = 0.0
	_check(not GameState.bus_live(), "ALT off and the battery flat -> no source")
	_check(not GameState.light_group_lit("BEACON"),
			"a flat battery puts the lights out too")
	GameState.battery_charge = saved_charge
	GameState.set_master_alt(true)
	await _wait(0.2)

	if _failures.is_empty():
		print("POWER SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("POWER SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


func _set_all_channels(value: float) -> void:
	for channel: String in GameState.POWER_CHANNELS:
		GameState.set_power(channel, value)


## Wait game-seconds, the same way every other smoke here does. It has to be a
## process_frame loop rather than a SceneTreeTimer: the electrical balance
## advances on the PHYSICS tick, and a timer resumes on a frame that has not
## necessarily stepped physics at all, so the timer version reads the balance
## before anything has integrated it.
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
