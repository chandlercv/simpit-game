extends Node
## Headless checks for ControlsSetup._canonical_axis_key: a saved axis/hid spec
## whose (neg,pos) is in the AXIS_TARGETS order loads as-is, one in the SWAPPED
## order (how REV is encoded on save, and how a hand-authored profile may list a
## pair) folds back to the row's canonical key with reverse=true, and an unknown
## pair is left untouched. Regression guard for the bug where a reversed nub
## binding loaded under a phantom key and vanished from its row while still
## driving the axis at runtime.
##
##   godot --headless res://tools/AxisKeyNormalizeSmoke.tscn

var _failures: Array[String] = []


func _ready() -> void:
	var cs: ControlsSetup = ControlsSetup.new()

	# Canonical order (matches the Thrust U/D row) loads unchanged, unreversed.
	var c := cs._canonical_axis_key("thrust_down", "thrust_up")
	_check(c["key"] == "thrust_down|thrust_up" and c["reverse"] == false,
			"canonical order -> same key, not reversed")

	# Swapped order (the actual bug: a REV'd nub saved as thrust_up|thrust_down)
	# folds back to the row's canonical key and is marked reversed.
	c = cs._canonical_axis_key("thrust_up", "thrust_down")
	_check(c["key"] == "thrust_down|thrust_up" and c["reverse"] == true,
			"swapped order -> canonical key + reverse")

	# Same for another pair, to be sure it isn't hard-coded to one row.
	c = cs._canonical_axis_key("strafe_right", "strafe_left")
	_check(c["key"] == "strafe_left|strafe_right" and c["reverse"] == true,
			"swapped strafe -> canonical key + reverse")

	# An unknown pair is kept verbatim and unreversed (no phantom rewrite).
	c = cs._canonical_axis_key("made_up_neg", "made_up_pos")
	_check(c["key"] == "made_up_neg|made_up_pos" and c["reverse"] == false,
			"unknown pair -> kept as-is")

	cs.free()

	if _failures.is_empty():
		print("AXIS KEY NORMALIZE SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("AXIS KEY NORMALIZE SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
