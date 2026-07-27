extends Node
## Headless checks for the switch-driven power model: the four channel switches
## drive their mapped channel between high/low, the master electrical switches
## override and lock the mix (restoring it on return), and passive-scanner
## visibility halves per master that is off.
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
	GameState.set_power_switch("DE_ICE", true)

	# 2. MASTER ALT off rigs power to thrust + life support and locks the mix.
	GameState.set_master_alt(false)
	_check(GameState.power("THRUST") == 1.0, "ALT off -> THRUST 100%")
	_check(GameState.power("LIFE") == 1.0, "ALT off -> LIFE 100%")
	_check(GameState.power("SENSORS") == 0.0 and GameState.power("CUTTER") == 0.0,
			"ALT off -> CUTTER/SENSORS 0")
	_check(GameState.power_locked(), "ALT off -> power locked")
	GameState.set_power("SENSORS", 0.5)
	GameState.set_power_switch("DE_ICE", false)
	_check(GameState.power("SENSORS") == 0.0 and GameState.power("CUTTER") == 0.0,
			"edits don't touch the live mix while locked")
	GameState.set_master_alt(true)
	# Touch-slider edits while locked are ignored (SENSORS restores to its pre-lock
	# high), but a physical channel switch flipped while locked is honored on
	# restore (DE_ICE off -> CUTTER low) so the mix matches the panel, not the old
	# state. Regression guard: intents used to be discarded, resurfacing stale.
	_check(GameState.power("THRUST") == hi and GameState.power("SENSORS") == hi \
			and GameState.power("CUTTER") == lo and GameState.power("LIFE") == 1.0,
			"ALT on -> mix restored to current switch positions")
	GameState.set_power_switch("DE_ICE", true)

	# 3. MASTER BAT off zeros everything and locks; on restores.
	GameState.set_master_battery(false)
	_check(GameState.power_total() == 0.0, "BAT off -> all channels 0")
	_check(GameState.power_locked(), "BAT off -> power locked")
	GameState.set_master_battery(true)
	_check(GameState.power("THRUST") == hi and GameState.power("LIFE") == 1.0,
			"BAT on -> prior mix restored")

	# 4. Passive-scanner visibility halves per master off, stacking to 0.25.
	_check(GameState.passive_signature() == 1.0, "signature 1.0 with both masters on")
	GameState.set_master_alt(false)
	_check(GameState.passive_signature() == 0.5, "signature 0.5 with ALT off")
	GameState.set_master_battery(false)
	_check(GameState.passive_signature() == 0.25, "signature 0.25 with both off")
	GameState.set_master_alt(true)
	GameState.set_master_battery(true)

	if _failures.is_empty():
		print("POWER SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("POWER SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
