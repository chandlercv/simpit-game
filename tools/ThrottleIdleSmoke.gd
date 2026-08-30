extends Node
## Headless checks for the throttle's unsampled-axis gate: a bound throttle whose
## axis the engine has not reported yet must read IDLE, not the half-open that
## every lever curve maps its raw 0.0 to. Regression guard for the bug where the
## ship departed the wreck under power at scene entry with the lever physically
## shut — Input.get_joy_axis() answers 0.0 for an axis it has never sampled, and
## 0.0 on a lever is mid-travel. Also guards the companion fix: a flight command
## latched on the boot frame must not survive the title card's pause into the
## first physics tick after LAUNCH.
##
##   godot --headless res://tools/ThrottleIdleSmoke.tscn

## The X52 lever spec, in the legacy form that took the vulnerable branch. Kept
## at the ORIGINAL 0.95 threshold rather than tracking the shipped default: these
## rows test the curve's shape, and a saved user profile can still carry any
## threshold at all. _check_shipped_margin covers the shipped number itself.
const X52_SPEC := {"axis": 2, "idle_deadzone": 0.95}

## What this rig's X52 lever actually reads at its mechanical stop, measured with
## InputEcho. The number the shipped idle band has to clear.
const X52_MEASURED_REST := 0.9524

var _failures: Array[String] = []


func _ready() -> void:
	_check_curve()
	_check_shipped_margin()
	_check_gate()
	_check_pause_clear()

	if _failures.is_empty():
		print("THROTTLE IDLE SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("THROTTLE IDLE SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


## The raw curve, spec form by spec form. Endpoints must be exact (idle commands
## nothing, full commands everything) and the mid-travel rows must stay near half
## open — that is the hazard the gate in throttle() exists to keep off the drive.
func _check_curve() -> void:
	# 0.95 is the idle threshold, so the travel below it carries the whole
	# command: mid-travel is 0.95 / 1.95, not 0.5.
	_near(InputRouter._throttle_curve(0.0, X52_SPEC), 0.4872,
			"X52 lever: an UNSAMPLED raw 0.0 curves to about half open")
	_near(InputRouter._throttle_curve(1.0, X52_SPEC), 0.0, "X52 lever: idle (+1) -> 0")
	_near(InputRouter._throttle_curve(-1.0, X52_SPEC), 1.0, "X52 lever: full (-1) -> 1")

	var lever := {"axis": 0, "idle": 1.0, "full": -1.0}
	_near(InputRouter._throttle_curve(0.0, lever), 0.4737, "general lever: raw 0.0 -> about half")
	_near(InputRouter._throttle_curve(1.0, lever), 0.0, "general lever: idle -> 0")
	_near(InputRouter._throttle_curve(-1.0, lever), 1.0, "general lever: full -> 1")

	var inverted := {"axis": 0, "idle": -1.0, "full": 1.0}
	_near(InputRouter._throttle_curve(0.0, inverted), 0.4737, "inverted lever: raw 0.0 -> about half")
	_near(InputRouter._throttle_curve(-1.0, inverted), 0.0, "inverted lever: idle -> 0")
	_near(InputRouter._throttle_curve(1.0, inverted), 1.0, "inverted lever: full -> 1")

	var pad := {"axis": 1, "mode": "gamepad", "invert": false}
	_near(InputRouter._throttle_curve(0.0, pad), 0.0, "gamepad: centre -> 0")
	_near(InputRouter._throttle_curve(1.0, pad), 1.0, "gamepad: +1 -> full forward")
	_near(InputRouter._throttle_curve(-1.0, pad), -1.0, "gamepad: -1 -> full reverse")

	_check_no_idle_floor()


## The docking creep. Every form must be able to command an ARBITRARILY SMALL
## throttle as the lever leaves idle — a deadband that clips instead of rescaling
## leaves the smallest commandable value equal to the deadband itself, which the
## lever cannot get under. On this rig that floor was 2.5% (~0.9 m/s), enough to
## slide through a 3 m/s docking hold with the lever shut, and the X52's measured
## rest of +0.9524 against the 0.95 threshold sat right on the edge of it.
func _check_no_idle_floor() -> void:
	# Raw value at each form's idle-band edge, and one a hair PAST it (which is
	# toward -1 on a normal lever, toward +1 on an inverted one and on the
	# centre-rest gamepad axis). The general form's band is IDLE_DEADZONE
	# NORMALIZED, so on a ±1 lever its raw edge is 1.0 - 0.05 * 2.0 = 0.90.
	var specs := {
		"X52 lever": [X52_SPEC, 0.95, 0.948],
		"general lever": [{"axis": 0, "idle": 1.0, "full": -1.0}, 0.90, 0.898],
		"inverted lever": [{"axis": 0, "idle": -1.0, "full": 1.0}, -0.90, -0.898],
		"gamepad": [{"axis": 1, "mode": "gamepad"}, 0.05, 0.052],
	}
	for label: String in specs:
		var spec: Dictionary = specs[label][0]
		# At the very edge of the idle band the command is exactly zero...
		_near(InputRouter._throttle_curve(specs[label][1], spec), 0.0,
				"%s: idle band edge -> exactly 0" % label)
		# ...and a hair past it, a hair of throttle — far under the old 2.5% floor.
		var out: float = absf(InputRouter._throttle_curve(specs[label][2], spec))
		_check(out > 0.0 and out < 0.005,
				"%s: a hair past idle commands a hair of throttle (got %.4f)" % [label, out])


## The shipped X52 idle band has to clear a real lever's mechanical rest by a
## workable margin, not by a rounding error. The rest position varies between
## units and with wear, so a band that only just covers the one it was written on
## is a band that fails on the next one — which is how the docking creep got in.
func _check_shipped_margin() -> void:
	var shipped: Dictionary = {}
	for profile: Dictionary in InputRouter.BUILTIN_PROFILES:
		if profile.get("name", "") == "Saitek X52 Flight Control System":
			shipped = profile.get("throttle", {})
	_check(not shipped.is_empty(), "the shipped X52 profile still carries a throttle")
	if shipped.is_empty():
		return

	_near(InputRouter._throttle_curve(X52_MEASURED_REST, shipped), 0.0,
			"shipped band: a lever at the measured rest (%.4f) commands nothing" % X52_MEASURED_REST)
	# Real margin, in raw axis units, between the measured rest and the band edge.
	var edge := float(shipped.get("idle_deadzone", shipped.get("idle", 1.0)))
	_check(X52_MEASURED_REST - edge >= 0.03,
			"shipped band clears that rest by a workable margin (%.4f)" % (X52_MEASURED_REST - edge))
	# Still a usable lever: full travel reaches full command.
	_near(InputRouter._throttle_curve(-1.0, shipped), 1.0, "shipped band: full lever -> 1")

	# What the REMAPPER writes when a throttle is re-bound — plain ±1 endpoints,
	# no explicit deadzone, so it falls back on IDLE_DEADZONE. It must not hand
	# back a tighter idle band than the shipped profile it replaces, which is
	# exactly what it did while that default was 0.02 (raw edge 0.96).
	var rebound := {"axis": 2, "idle": 1.0, "full": -1.0}
	_near(InputRouter._throttle_curve(X52_MEASURED_REST, rebound), 0.0,
			"a re-bound throttle idles at that rest too, not just the shipped one")


## The gate. Headless, Input.get_joy_axis() returns 0.0 for everything — exactly
## the unsampled case — so binding a throttle by hand and flipping _throttle_seen
## isolates the gate as the only thing standing between that 0.0 and half thrust.
func _check_gate() -> void:
	InputRouter._throttle_device = 0
	InputRouter._throttle_axis = 2
	InputRouter._throttle_spec = X52_SPEC
	InputRouter._throttle_seen = false
	_near(InputRouter.throttle(), 0.0, "bound but UNSAMPLED throttle reads idle")

	InputRouter._throttle_seen = true
	_near(InputRouter.throttle(), 0.4872,
			"the gate, and only the gate, is what suppressed it")

	# A rebind (replug) must re-arm the gate rather than trust a cache the
	# disconnect emptied. This also restores the real binding for this rig.
	InputRouter._bind_hotas()
	_check(not InputRouter._throttle_seen, "_bind_hotas re-arms the gate")


## A command latched on the boot frame must not outlive the title card. The boot
## frame runs unpaused (WindowManager defers the _setup() that pauses the tree),
## and physics runs ahead of idle, so without this the first tick after LAUNCH
## spends whatever was read back at boot.
func _check_pause_clear() -> void:
	ShipMotion.set_command(Vector3(0.0, 0.0, 0.5), Vector3.ZERO)
	get_tree().paused = true
	InputRouter._process(1.0 / 60.0)
	_near(ShipMotion.throttle_command(), 0.0,
			"a command latched before the pause is cleared, not carried across it")
	get_tree().paused = false


func _near(value: float, expected: float, label: String) -> void:
	_check(absf(value - expected) < 0.001,
			"%s (expected %.3f, got %.3f)" % [label, expected, value])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
