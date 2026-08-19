extends Node
## Headless checks that the fly-by-wire is a MECHANISM, not a constant.
##
## A perfect FBW is observationally identical to the old no-momentum flight
## model: every legacy smoke passes whether the system exists or not. So the
## checks here are the negative cases — drive authority down and prove the
## residual SURVIVES, switch the assist off and prove drift is left alone,
## degrade it and prove the align interlock refuses. Nothing else in the suite
## can tell "nulls correctly" from "nothing to null".
##
##   godot --headless res://tools/FlightSmoke.tscn

var _failures: Array[String] = []


func _ready() -> void:
	Engine.time_scale = 10.0
	# Keep each physics step at 1/60 s of game time under the accelerated clock
	# (steps per real second scale up; the sim's integration step does not).
	Engine.physics_ticks_per_second = roundi(60.0 * Engine.time_scale)
	# These checks drive the ship's state by hand; a live throttle or switch
	# panel on a dev box must not fight them (same silencing as DriftSmoke).
	InputRouter.set_process(false)
	for child in InputRouter.get_children():
		child.set_process(false)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var ship: Dictionary = GameState.local_ship()
	var sections: Dictionary = ship["hull_sections"]
	var drive_boot: float = sections["DRIVE"]

	# --- 1. Full authority: an imparted spin is nulled. ---
	_check(is_equal_approx(ShipMotion.authority(), 1.0),
			"an undamaged ship at boot allocation has full authority")
	ship["omega"] = Vector3(0, 0.8, 0)
	await _wait(1.0)
	_check((ship["omega"] as Vector3).length() < 0.05,
			"full authority nulls an imparted spin inside a second (%.3f rad/s left)"
					% (ship["omega"] as Vector3).length())

	# --- 2. Zero authority: the same spin SURVIVES. This is the check that
	# proves the mechanism exists — on the old rate-command model there is no
	# omega to read and nothing that could keep rotating. ---
	sections["DRIVE"] = GameState.ship_def.fbw_drive_dead
	GameState.hull_sections_changed.emit()
	_check(ShipMotion.authority() == 0.0,
			"DRIVE worn to the dead band is zero authority")
	ship["omega"] = Vector3(0, 0.8, 0)
	var fwd_before: Vector3 = -(ship["transform"] as Transform3D).basis.z
	await _wait(1.0)
	_check((ship["omega"] as Vector3).length() > 0.7,
			"zero authority leaves the spin uncancelled (%.3f rad/s survives)"
					% (ship["omega"] as Vector3).length())
	_check(fwd_before.angle_to(-(ship["transform"] as Transform3D).basis.z) > 0.5,
			"...and the ship actually rotates with it")

	# Direct thruster torque is all that remains — a dead-stick ship is still
	# flyable, it just keeps every rate the pilot starts.
	ship["omega"] = Vector3.ZERO
	SalvageSystem.set_manual_flight(Vector3.ZERO, Vector3(0.0, 1.0, 0.0))
	await _wait(0.5)
	SalvageSystem.set_manual_flight(Vector3.ZERO, Vector3.ZERO)
	_check((ship["omega"] as Vector3).length() > 0.2,
			"direct thruster torque still turns a dead-stick ship (%.3f rad/s)"
					% (ship["omega"] as Vector3).length())
	sections["DRIVE"] = drive_boot
	GameState.hull_sections_changed.emit()
	ShipMotion.seize(Transform3D.IDENTITY, Vector3.ZERO)

	# --- 3. Assist off: released controls do NOT bleed drift. ---
	ShipMotion.toggle_fbw()
	_check(ShipMotion.authority() == 0.0, "assist off is zero authority")
	ship["velocity"] = Vector3(3.0, 0.0, 0.0)  # pure lateral: the throttle law
	await _wait(2.0)                           # only ever touches fore-aft
	_check((ship["velocity"] as Vector3).x > 2.9,
			"assist off leaves drift alone (%.2f m/s of 3.0 kept)"
					% (ship["velocity"] as Vector3).x)
	ShipMotion.toggle_fbw()
	await _wait(2.0)
	_check((ship["velocity"] as Vector3).length() < 2.0,
			"re-engaged assist bleeds the same drift (%.2f m/s left)"
					% (ship["velocity"] as Vector3).length())

	# --- 3b. The linear null runs at two rates. Station-keeping (every control
	# released) is brisk; flying (anything under command, throttle included)
	# only tidies the uncommanded axes, and must be gentle or a deliberate
	# sidestep is wiped out before it carries the ship anywhere. Same drift,
	# same duration, and the flown case must keep materially more of it. ---
	ShipMotion.seize(Transform3D.IDENTITY, Vector3.ZERO)
	SalvageSystem.set_manual_flight(Vector3.ZERO, Vector3.ZERO)
	ship["velocity"] = Vector3(3.0, 0.0, 0.0)
	await _wait(3.0)
	var kept_parked: float = (ship["velocity"] as Vector3).x

	ShipMotion.seize(Transform3D.IDENTITY, Vector3.ZERO)
	ship["velocity"] = Vector3(3.0, 0.0, 0.0)
	var flown := 0.0
	while flown < 3.0:
		# Throttle held open, strafe released: the lateral axis is uncommanded
		# but the ship is being flown.
		SalvageSystem.set_manual_flight(Vector3(0.0, 0.0, 0.5), Vector3.ZERO)
		await get_tree().process_frame
		flown += get_process_delta_time()
	var kept_flying: float = (ship["velocity"] as Vector3).x
	SalvageSystem.set_manual_flight(Vector3.ZERO, Vector3.ZERO)
	_check(kept_flying > kept_parked + 0.8,
			"a sidestep survives under way but not at rest (%.2f m/s flying vs %.2f parked)"
					% [kept_flying, kept_parked])

	# --- 4. The align interlock reads authority. ---
	SalvageSystem.reset_site()
	GameState.wreck["scanned"] = true
	ship["power"]["CUTTER"] = 1.0
	var member_id: int = GameState.wreck["members"][0]["id"]
	GameState.approach_state = "HOLDING"
	SalvageSystem.select_member(member_id)
	GameState.approach_state = "MATCHED"
	GameState.matched_member_id = member_id
	sections["DRIVE"] = GameState.ship_def.fbw_drive_dead
	GameState.hull_sections_changed.emit()
	var comms_before := GameState.comms.size()
	SalvageSystem.request_cut()
	_check(GameState.align_state != "ALIGNING",
			"degraded stabilisation refuses the alignment")
	_check(_has_comms_since(comms_before, "STABILISATION DEGRADED"),
			"...and the refusal names the reason")
	sections["DRIVE"] = drive_boot
	GameState.hull_sections_changed.emit()
	SalvageSystem.request_cut()
	_check(GameState.align_state == "ALIGNING",
			"with authority restored the alignment opens")
	# Authority failing MID-align aborts, same as losing cutter power.
	sections["DRIVE"] = GameState.ship_def.fbw_drive_dead
	GameState.hull_sections_changed.emit()
	await _wait(0.3)
	_check(GameState.align_state == "IDLE",
			"authority lost mid-align aborts the alignment")
	_check(_has_comms_since(comms_before, "STABILISATION DEGRADED"),
			"...with the standard ALIGNMENT LOST call")
	sections["DRIVE"] = drive_boot
	GameState.hull_sections_changed.emit()

	if _failures.is_empty():
		print("FLIGHT SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("FLIGHT SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


func _wait(game_seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < game_seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _has_comms_since(index: int, needle: String) -> bool:
	for i in range(index, GameState.comms.size()):
		if String(GameState.comms[i]["text"]).contains(needle):
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
