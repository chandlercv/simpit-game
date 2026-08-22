extends Node
## Headless checks for the remapper's shared-control detection: binding a key or
## button that another row already holds must BIND (a pilot rearranging a layout
## passes through that state constantly) but must never do so silently — both
## rows carry CLASH_MARK, and the capture names the row it collides with.
##
## Guards the failure this was written for: two actions on one key fire together,
## and the symptom (one press doing two things, or a control that "does nothing"
## because its default was quietly skipped) looks nothing like the cause.
##
##   godot --headless res://tools/BindClashSmoke.tscn

var _failures: Array[String] = []


func _ready() -> void:
	var cs: ControlsSetup = ControlsSetup.new()

	# --- naming a row --------------------------------------------------------
	_check(cs._row_label_for("master_bat") == "Master BAT",
			"a button row is named as its row reads")
	_check(cs._row_label_for("thrust_forward") == "+Thrust F/B"
			and cs._row_label_for("thrust_back") == "−Thrust F/B",
			"the two halves of an axis pair are named apart, by sign")
	_check(cs._row_label_for("no_such_action") == "no_such_action",
			"an action with no row falls back to its own name")

	# --- which rows already hold a control ------------------------------------
	cs._key_binds = {"view_rear": KEY_1, "master_bat": KEY_9}
	_check(Array(cs._rows_on_key(KEY_1, "power_thrust_lo")) == ["View Rear"],
			"a taken key reports the row that holds it")
	_check(cs._rows_on_key(KEY_1, "view_rear").is_empty(),
			"rebinding a row to the key it already has is not a clash")
	_check(cs._rows_on_key(KEY_5, "power_thrust_lo").is_empty(),
			"a free key reports nothing")

	# A button is a (device, button) pair: the same index on another stick is a
	# different physical control and must not be reported.
	var stick := "0300493438070000"
	var throttle := "0300ea18a3060000"
	cs._button_binds = {"ops_cut": {"guid": stick, "button": 0}}
	_check(Array(cs._rows_on_button(stick, 0, "ops_approach")) == ["Cut"],
			"a taken button reports the row that holds it")
	_check(cs._rows_on_button(throttle, 0, "ops_approach").is_empty(),
			"the same button index on another device is not a clash")

	# --- the marks the rows carry ---------------------------------------------
	cs._key_binds = {"view_rear": KEY_1, "power_thrust_lo": KEY_1, "master_bat": KEY_9}
	cs._button_binds = {
		"ops_cut": {"guid": stick, "button": 0},
		"ops_approach": {"guid": stick, "button": 0},
		"landing_gear": {"guid": throttle, "button": 0},
	}
	cs._recompute_clashes()
	_check(cs._key_mark("view_rear") == ControlsSetup.CLASH_MARK
			and cs._key_mark("power_thrust_lo") == ControlsSetup.CLASH_MARK,
			"BOTH rows sharing a key are marked, not just the newer one")
	_check(cs._key_mark("master_bat") == "", "a key on one row only is unmarked")
	_check(cs._key_mark("drive_boost") == "", "an unbound row is unmarked")
	_check(cs._button_mark("ops_cut") == ControlsSetup.CLASH_MARK
			and cs._button_mark("ops_approach") == ControlsSetup.CLASH_MARK,
			"both rows sharing a button are marked")
	_check(cs._button_mark("landing_gear") == "",
			"the same index on another device is left unmarked")

	# --- the marks reach the row text, which is what tints the row ------------
	_check(cs._button_row_text("ops_cut").contains(ControlsSetup.CLASH_MARK),
			"a button row's text carries the mark")
	_check(not cs._button_row_text("landing_gear").contains(ControlsSetup.CLASH_MARK),
			"a clear button row's text does not")
	_check(cs._axis_row_text("power_thrust_lo", "power_thrust_hi")
				.contains(ControlsSetup.CLASH_MARK),
			"an axis row's per-direction key carries the mark")
	_check(not cs._axis_row_text("pitch_down", "pitch_up")
				.contains(ControlsSetup.CLASH_MARK),
			"an unbound axis row's text does not")

	cs.free()

	if _failures.is_empty():
		print("BIND CLASH SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("BIND CLASH SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
