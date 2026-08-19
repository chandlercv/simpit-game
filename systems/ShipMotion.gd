extends Node
## The single owner of the ship's momentum and its single integrator.
##
## Every contributor to the ship's motion feeds this pipeline; production code
## must not write GameState's ship transform/velocity/omega anywhere else while
## the ship is being flown. step() runs four named phases, in order:
##
##   1. command      — the pilot's stick and throttle become a commanded
##                     attitude rate and commanded accelerations,
##   2. contributors — accelerations accumulate into the tick's velocity,
##   3. fly-by-wire  — the control stage. It runs AFTER every contributor and
##                     BEFORE integration, so what it nulls is the true residual
##                     of the tick — this boundary is deliberate and load-bearing,
##   4. integrate    — semi-implicit Euler onto the transform, linear AND
##                     angular.
##
## The ship carries real angular momentum (ship["omega"], world-frame rad/s).
## The stick does not turn the ship directly — it commands a rate, and the
## fly-by-wire slews omega toward that rate and nulls the residual. At full
## authority that reproduces the old crisp rate command with a short, tuned
## settle; with the FBW degraded or off, only the direct thruster torque acts,
## and residual spin is the pilot's to cancel.
##
## Kinematic overrides — the approach autopilot's park, touchdown and deck
## placement, claim placement, the smoke tests' parking — go through seize(),
## the one sanctioned way to overwrite the motion state wholesale. seize()
## writes omega too (zero unless the caller says otherwise), so a parked ship
## can never inherit a spin from the flight that preceded it.
##
## SalvageSystem drives step() from its physics tick (it owns WHEN manual
## flight integrates); this node deliberately has no per-frame callback of its
## own, so autoload order cannot reorder the pipeline.

## FBW gains and authority limits live on ShipDefinition (fbw_linear_rate,
## fbw_angular_rate, fbw_raw_torque_deg, fbw_power_knee, fbw_drive_dead,
## fbw_drive_full) — they are the ship's numbers, quoted by her handbook, and a
## second hull tunes them in its own .tres rather than here.

## A command axis at or below this deflection counts as released, and the FBW
## nulls that axis's residual. Matches the old whole-vector rest threshold
## (length_squared 0.001 -> ~0.032 deflection).
const CMD_DEADBAND := 0.032

## Forward/back throttle command law. SPEED (default) treats the throttle as a
## target fraction of max_speed and closes on it — cruise-control style, no
## need to ride the lever to hold a speed. THRUST is the legacy behavior,
## where the throttle is felt directly as acceleration. Toggled in flight via
## a bindable button (throttle_cmd_toggle); independent of the per-device
## lever/gamepad binding curve set in the F7 remapper (ControlsSetup).
enum ThrottleCmdMode { SPEED, THRUST }
var _throttle_cmd_mode := ThrottleCmdMode.SPEED

## Pilot command for this tick, fed by SalvageSystem.set_manual_flight (which
## InputRouter calls every render frame — the freshest command when the physics
## tick consumes it). thrust is body-local (x right, y up, z forward), rot is
## (pitch, yaw, roll), all components -1..1; thrust.z carries the throttle.
var _cmd_thrust := Vector3.ZERO
var _cmd_rot := Vector3.ZERO


## --- Command intake ---------------------------------------------------------


func set_command(thrust: Vector3, rot: Vector3) -> void:
	_cmd_thrust = thrust
	_cmd_rot = rot


## The current forward throttle command, 0..1 — what the approach autopilot's
## arm interlock tests, and what the MFD CHECKLIST page displays.
func throttle_command() -> float:
	return _cmd_thrust.z


## Bindable (throttle_cmd_toggle): flip between SPEED and THRUST throttle
## command law. See ThrottleCmdMode above.
func toggle_throttle_cmd_mode() -> void:
	_throttle_cmd_mode = (ThrottleCmdMode.THRUST if _throttle_cmd_mode == ThrottleCmdMode.SPEED
			else ThrottleCmdMode.SPEED)
	GameState.post_comms("OPS", "THROTTLE — %s COMMAND" % ThrottleCmdMode.keys()[_throttle_cmd_mode])


## --- Authority --------------------------------------------------------------


## Master engage for the fly-by-wire (fbw_mode_cycle). Off is a pilot's choice:
## direct thruster torque only, no rate command, no translation null.
var _fbw_on := true


func fbw_engaged() -> bool:
	return _fbw_on


## Bindable (fbw_mode_cycle): flight assist on/off.
func toggle_fbw() -> void:
	_fbw_on = not _fbw_on
	GameState.post_comms("OPS",
			"FLIGHT ASSIST %s" % ("ENGAGED" if _fbw_on else "OFF — DIRECT CONTROL"))


## How much of its rated corrective effort the fly-by-wire can currently
## deliver, 0..1. Two factors, multiplied: THRUST allocation (the thrusters it
## corrects through are the same ones the pilot starves when the torch needs
## the budget) and DRIVE hull integrity (the section that carries the reaction
## control runs). An undamaged ship at cruise allocation holds 1.0; hard
## landings, gear overspeed and collapse events all wear DRIVE, and this is
## where that wear finally costs something.
func authority() -> float:
	if not _fbw_on:
		return 0.0
	var def: ShipDefinition = GameState.ship_def
	var power_term := clampf(GameState.power("THRUST") / def.fbw_power_knee, 0.0, 1.0)
	var drive: float = float(GameState.local_ship()["hull_sections"]["DRIVE"])
	var drive_term := clampf((drive - def.fbw_drive_dead)
			/ (def.fbw_drive_full - def.fbw_drive_dead), 0.0, 1.0)
	return power_term * drive_term


## --- Kinematic override -----------------------------------------------------


## Overwrite the ship's motion state wholesale. The pattern generalized here is
## the one MarketSystem/DockingSystem already used ad hoc: every transform
## write is paired with a velocity write — and now an omega write — so no
## seized pose inherits stale momentum from whatever flight preceded it.
func seize(transform: Transform3D, velocity: Vector3, omega := Vector3.ZERO) -> void:
	var ship: Dictionary = GameState.local_ship()
	ship["transform"] = transform
	ship["velocity"] = velocity
	ship["omega"] = omega


## The ship's angular velocity (world frame, rad/s). Collision response reads
## this to carry spin through its seize.
func ship_omega() -> Vector3:
	return GameState.local_ship().get("omega", Vector3.ZERO)


## --- The pipeline -----------------------------------------------------------


## One tick of manual flight. Newtonian-lite (plan Phase 5): rate-commanded
## attitude through the FBW slew, thruster acceleration gated by THRUST power,
## the fly-by-wire nulls, and a speed ceiling so the pit stays flyable without
## a full sim.
func step(delta: float) -> void:
	var ship: Dictionary = GameState.local_ship()
	var transform: Transform3D = ship["transform"]
	var velocity: Vector3 = ship["velocity"]
	var omega: Vector3 = ship.get("omega", Vector3.ZERO)
	var auth := authority()

	# 1. Command. The stick is a rate command (full deflection =
	# rotation_rate_deg/s) in the ship's own axes; world-frame for integration.
	var rate_cmd: Vector3 = transform.basis \
			* (_cmd_rot * deg_to_rad(GameState.ship_def.rotation_rate_deg))

	# 2. Contributors — angular: the direct thruster torque. It fades as FBW
	# authority rises, because a healthy FBW owns the same thrusters it fires
	# through; at zero authority this is all the attitude control there is.
	omega += transform.basis * (_cmd_rot * deg_to_rad(GameState.ship_def.fbw_raw_torque_deg)) \
			* (1.0 - auth) * delta

	# 2. Contributors — linear: strafe/vertical thrusters, then the throttle's
	# own control law on the forward axis.
	var accel: float = GameState.ship_def.manual_accel * maxf(GameState.power("THRUST"), 0.0)
	var lateral := Vector3(_cmd_thrust.x, _cmd_thrust.y, 0.0)
	if lateral.length_squared() > 0.001:
		velocity += transform.basis * lateral \
				* (accel * GameState.ship_def.secondary_thrust_fraction) * delta
	velocity = _apply_throttle_axis(transform, velocity, accel, delta)

	# 3. Fly-by-wire — slews omega onto the commanded rate and nulls the
	# uncommanded translation axes. Runs after every contributor so what it
	# corrects is the true residual of the tick.
	omega = rate_cmd + (omega - rate_cmd) * exp(-GameState.ship_def.fbw_angular_rate * auth * delta)
	velocity = _apply_fbw_linear(transform, velocity, auth, delta)

	# 4. Integrate — angular then linear, both semi-implicit.
	if omega.length_squared() > 0.00000001:
		transform.basis = transform.basis.rotated(
				omega.normalized(), omega.length() * delta).orthonormalized()
	velocity = velocity.limit_length(GameState.ship_def.max_speed)
	transform.origin += velocity * delta
	ship["transform"] = transform
	ship["velocity"] = velocity
	ship["omega"] = omega


## Advance `velocity`'s forward/back component only, per the active throttle
## command mode (see ThrottleCmdMode). Reverse is capped at
## secondary_thrust_fraction of forward — clamping the command rather than the
## result, so it scales both the THRUST-mode acceleration and the SPEED-mode
## target uniformly, whatever secondary_thrust_fraction is tuned to.
func _apply_throttle_axis(transform: Transform3D, velocity: Vector3, accel: float, delta: float) -> Vector3:
	var forward_dir: Vector3 = -transform.basis.z
	var reverse_cap: float = GameState.ship_def.secondary_thrust_fraction
	var z_cmd: float = clampf(_cmd_thrust.z, -reverse_cap, 1.0)
	var fwd_speed := velocity.dot(forward_dir)
	var new_fwd_speed: float
	if _throttle_cmd_mode == ThrottleCmdMode.THRUST:
		new_fwd_speed = fwd_speed + z_cmd * accel * delta
	else:
		new_fwd_speed = move_toward(fwd_speed, z_cmd * GameState.ship_def.max_speed, accel * delta)
	return velocity + forward_dir * (new_fwd_speed - fwd_speed)


## The fly-by-wire linear channel: bleed the residual on every axis the pilot
## is NOT commanding, per-axis in the ship's frame. An open throttle commands
## the forward axis and only that axis, so lateral and vertical drift are still
## tidied under way. (This retires the old whole-vector gate, under which ANY
## open throttle suspended all nulling and a cruise could never shed sideways
## drift; that gate was an artifact, not a design.)
##
## The rate depends on what the pilot is doing, not just on which axis. With
## every control released the ship is station-keeping and nulls briskly. With
## anything under command it is being flown, and the uncommanded axes are only
## tidied — gently enough that a sidestep still carries the ship somewhere after
## the control is released, instead of being wiped out from under it.
func _apply_fbw_linear(transform: Transform3D, velocity: Vector3, auth: float,
		delta: float) -> Vector3:
	if auth <= 0.0:
		return velocity
	var def: ShipDefinition = GameState.ship_def
	var flying: bool = _cmd_thrust.length_squared() > 0.001
	var rate: float = def.fbw_linear_rate_flying if flying else def.fbw_linear_rate
	var v_local: Vector3 = transform.basis.inverse() * velocity
	var fade := exp(-rate * auth * delta)
	if absf(_cmd_thrust.x) <= CMD_DEADBAND:
		v_local.x *= fade
	if absf(_cmd_thrust.y) <= CMD_DEADBAND:
		v_local.y *= fade
	if absf(_cmd_thrust.z) <= CMD_DEADBAND:
		v_local.z *= fade
	return transform.basis * v_local
