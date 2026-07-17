extends Node
## Headless checks for the Phase 5 scaffold: hid-gd extension loads, the
## switch-panel report decode matches the known byte layout, manual flight
## actions move/rotate the ship, and stick input disengages the approach
## autopilot. Real X52/X55 index discovery still needs hardware + InputEcho.
##
##   godot --headless res://tools/Phase5Smoke.tscn

const SwitchPanelBridge := preload("res://systems/hardware/SwitchPanelBridge.gd")

var _failures: Array[String] = []


func _ready() -> void:
	Engine.time_scale = 10.0
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame

	_check(ClassDB.class_exists("Hid"), "hid-gd extension registered class Hid")

	# Parser: bit 0 of byte 0 = MASTER_BAT; leading zero report id skipped;
	# GEAR_DOWN = bit 3 of byte 2.
	var s := SwitchPanelBridge.parse_report(PackedByteArray([0x01, 0x00, 0x00]))
	_check(s.get("MASTER_BAT") == true and s.get("MASTER_ALT") == false,
			"parse_report reads byte0/bit0 as MASTER_BAT")
	var s2 := SwitchPanelBridge.parse_report(PackedByteArray([0x00, 0x01, 0x00, 0x00]))
	_check(s2.get("MASTER_BAT") == true, "parse_report skips a leading zero report id")
	var s3 := SwitchPanelBridge.parse_report(PackedByteArray([0x00, 0x00, 0x08]))
	_check(s3.get("GEAR_DOWN") == true and s3.get("GEAR_UP") == false,
			"parse_report reads byte2/bit3 as GEAR_DOWN")

	# Manual flight: thrust forward must build -Z velocity and move the ship.
	var ship: Dictionary = GameState.local_ship()
	var start: Vector3 = ship["transform"].origin
	Input.action_press("thrust_forward")
	await _wait(2.0)
	Input.action_release("thrust_forward")
	var vel: Vector3 = ship["velocity"]
	_check(vel.z < -0.5, "forward thrust builds -Z velocity (got %.2f)" % vel.z)
	_check(ship["transform"].origin.z < start.z - 1.0, "ship actually moved forward")

	# Attitude: yaw left must swing the forward vector.
	var fwd_before: Vector3 = -ship["transform"].basis.z
	Input.action_press("yaw_left")
	await _wait(1.0)
	Input.action_release("yaw_left")
	var fwd_after: Vector3 = -ship["transform"].basis.z
	_check(fwd_before.angle_to(fwd_after) > 0.3,
			"yaw input rotates the ship (%.2f rad)" % fwd_before.angle_to(fwd_after))

	# Flight assist bleeds residual drift with no input.
	var drift: float = ship["velocity"].length()
	await _wait(4.0)
	_check(ship["velocity"].length() < drift * 0.5,
			"flight assist damps drift (%.2f -> %.2f m/s)" % [
				drift, ship["velocity"].length()])

	# Stick input disengages the approach autopilot.
	SalvageSystem.toggle_approach()
	_check(GameState.approach_state == "APPROACHING", "autopilot engages")
	Input.action_press("thrust_forward")
	await _wait(0.5)
	Input.action_release("thrust_forward")
	_check(GameState.approach_state == "HOLDING",
			"manual input disengages the autopilot")

	if _failures.is_empty():
		print("PHASE5 SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("PHASE5 SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


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
