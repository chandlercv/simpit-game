extends Node
## Headless checks for how InputRouter drives a power channel from its remapper
## rows: an analog axis on a row acts as a slider, a digital key/button nudges the
## channel by POWER_STEP per press and holds, and — the regression this guards — a
## bound-but-idle digital event must NOT peg the channel to the midpoint. Also
## covers the GameState.power_target() getter the nudge steps.
##
## The nudge stepping is exercised through InputRouter._nudge_power(up, down),
## which takes the press booleans directly, so the checks are deterministic and
## don't depend on synthesising Godot's frame-latched is_action_just_pressed. The
## branch selection (analog vs digital vs unbound) is exercised through the real
## _process_power_axes, driven only by the InputMap events bound on each row.
##
##   godot --headless res://tools/PowerNudgeSmoke.tscn

var _failures: Array[String] = []

const STEP: float = InputRouter.POWER_STEP


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	# The live InputRouter autoload runs its own _process every frame, which also
	# runs the power pass. Silence it so nothing mutates power between our asserts.
	InputRouter.set_process(false)

	# 0. power_target() reflects the desired mix set through set_power.
	GameState.set_power("SENSORS", 0.3)
	_check(is_equal_approx(GameState.power_target("SENSORS"), 0.3),
			"power_target reflects set_power")

	# 1. Regression: a bound-but-idle DIGITAL event must not drive the channel.
	# (The old is_empty() guard let an idle key/button write the 50% midpoint every
	# frame, clobbering the sliders/switch panel.) A key is bound to the row but no
	# press fires, so the real _process_power_axes must leave the channel alone.
	var key := InputEventKey.new()
	key.physical_keycode = KEY_P
	InputMap.action_add_event("power_sensors_hi", key)
	GameState.set_power("SENSORS", 0.3)
	for _i in 5:
		InputRouter._process_power_axes()
	_check(is_equal_approx(GameState.power_target("SENSORS"), 0.3),
			"idle digital binding leaves channel untouched (no midpoint peg)")
	InputMap.action_erase_event("power_sensors_hi", key)

	# 2. An up press nudges the channel up by one STEP; a down press, down by one.
	GameState.set_power("SENSORS", 0.3)
	InputRouter._nudge_power("SENSORS", true, false)
	_check(is_equal_approx(GameState.power_target("SENSORS"), 0.3 + STEP),
			"up press nudges up by one STEP")
	InputRouter._nudge_power("SENSORS", false, true)
	_check(is_equal_approx(GameState.power_target("SENSORS"), 0.3),
			"down press nudges down by one STEP")

	# 3. Neither/both pressed is a no-op (both cancel), so the channel holds.
	InputRouter._nudge_power("SENSORS", false, false)
	InputRouter._nudge_power("SENSORS", true, true)
	_check(is_equal_approx(GameState.power_target("SENSORS"), 0.3),
			"no press and both-pressed both leave the channel unchanged")

	# 4. Nudges clamp at the 0..1 rails and never wrap.
	GameState.set_power("SENSORS", 0.95)
	for _i in 5:
		InputRouter._nudge_power("SENSORS", true, false)
	_check(is_equal_approx(GameState.power_target("SENSORS"), 1.0),
			"repeated up presses clamp at 1.0")
	GameState.set_power("SENSORS", 0.05)
	for _i in 5:
		InputRouter._nudge_power("SENSORS", false, true)
	_check(is_equal_approx(GameState.power_target("SENSORS"), 0.0),
			"repeated down presses clamp at 0.0")

	# 5. An ANALOG axis on a row takes the slider branch instead: with no stick
	# input its rest value maps to 0.5, re-asserted every frame (the intended
	# slider behaviour, and the contrast that proves the branch split works).
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_LEFT_Y
	InputMap.action_add_event("power_life_hi", motion)
	GameState.set_power("LIFE", 0.2)
	InputRouter._process_power_axes()
	_check(is_equal_approx(GameState.power_target("LIFE"), 0.5),
			"analog-bound row is a slider (idle axis -> 0.5 midpoint)")
	InputMap.action_erase_event("power_life_hi", motion)

	# 6. A channel with nothing bound is never driven by the power pass.
	GameState.set_power("CUTTER", 0.3)
	for _i in 5:
		InputRouter._process_power_axes()
	_check(is_equal_approx(GameState.power_target("CUTTER"), 0.3),
			"unbound channel is left untouched")

	if _failures.is_empty():
		print("POWER NUDGE SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("POWER NUDGE SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
