extends Node
## The single owner of the ship's momentum and its single integrator.
##
## Every contributor to the ship's motion feeds this pipeline; production code
## must not write GameState's ship transform/velocity/omega anywhere else while
## the ship is being flown. step() divides the tick into as many sub-steps as the
## ship's speed needs (see MAX_SUBSTEPS) and runs _integrate() for each; that is
## where the four named phases live, in order:
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
## fly-by-wire slews omega toward that rate and nulls the residual. The slew is
## bounded by the torque the thrusters can make against the ship's live moments,
## so a loaded hull comes onto a rate slower than an empty one and roll answers
## quicker than pitch or yaw. Under DIRECT law only the raw thruster torque acts,
## and residual spin is the pilot's to cancel.
##
## Two things bound the ship's speed and NEITHER is a property of space. The
## GOVERNOR is a flight-computer limit, set by the pilot on the MFD SETTINGS page
## and measured against the selected navigation datum (_apply_governor); DIRECT
## law removes it. Everything else is propellant, amps and how long you are
## willing to burn.
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
## fbw_angular_rate, fbw_power_knee, fbw_drive_dead, fbw_drive_full), as do the
## mass, moments and torques the flight model derives everything else from — they
## are the ship's numbers, quoted by her handbook, and a second hull tunes them in
## its own .tres rather than here.

## A command axis at or below this deflection counts as released, and the FBW
## nulls that axis's residual. Matches the old whole-vector rest threshold
## (length_squared 0.001 -> ~0.032 deflection).
const CMD_DEADBAND := 0.032

## Forward/back throttle command law. THIS IS A PROPERTY OF THE HARDWARE, not a
## second assist switch — a throttle is one of two physical shapes and they want
## opposite laws.
##
## COMBINED — for an absolute LEVER. Position commands both the speed converged
## on and the thrust used getting there. Park it at half and the ship eases to
## half the governor's setting on half thrust and holds it, hands off.
## THRUST — for a self-centring GAMEPAD axis. Position commands force alone.
##
## The shapes cannot share a law. A centring axis reads exactly zero at rest
## (InputRouter._throttle_curve, {mode:"gamepad"}), so under COMBINED a released
## stick is a full-authority braking command and holding any speed means holding
## the stick forward for as long as you want to be moving. A lever under THRUST
## has the mirror problem: parked anywhere but the stop it is a permanent burn,
## and an absolute lever cannot be let go of.
##
## So the DEFAULT follows the device — see sync_throttle_law, which reads the
## profile the F7 remapper wrote — and throttle_cmd_toggle overrides it for the
## pilot who disagrees. DIRECT law forces THRUST whatever is selected: a
## speed-holding loop is fly-by-wire by definition and cannot outlive it.
enum ThrottleCmdMode { COMBINED, THRUST }
var _throttle_cmd_mode := ThrottleCmdMode.COMBINED
## True once the pilot has overridden the device default, so a later profile
## reload does not quietly undo their choice.
var _throttle_law_pinned := false

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


## The whole commanded translation, body-local (x right, y up, z forward), each
## component -1..1. Exposed for readers that need the manoeuvring axes and not
## just the throttle — the audio layer fires a thruster valve per axis, which it
## cannot do from thrust.z alone. Compare against CMD_DEADBAND to decide whether
## an axis is being held at all.
func command_thrust() -> Vector3:
	return _cmd_thrust


## The commanded rotation, (pitch, yaw, roll), each -1..1. Same reason.
func command_rotation() -> Vector3:
	return _cmd_rot


## How hard the drive is being worked right now, 0..1: the throttle plus whatever
## the manoeuvring thrusters are doing, since they are fed by the same drive.
##
## This is the figure the propellant meter charges a burn against (see
## _burn_propellant), and it is exposed rather than inlined so that the engine
## note and the fuel gauge cannot disagree about how hard you are pushing.
func drive_load() -> float:
	var lateral := Vector3(_cmd_thrust.x, _cmd_thrust.y, 0.0)
	return clampf(absf(_cmd_thrust.z) + lateral.length(), 0.0, 1.0)


## Bindable (throttle_cmd_toggle): override the device default and flip between
## the COMBINED and THRUST throttle laws. See ThrottleCmdMode above.
func toggle_throttle_cmd_mode() -> void:
	_throttle_cmd_mode = (ThrottleCmdMode.THRUST if _throttle_cmd_mode == ThrottleCmdMode.COMBINED
			else ThrottleCmdMode.COMBINED)
	_throttle_law_pinned = true
	GameState.post_comms("OPS", "THROTTLE — %s COMMAND" % ThrottleCmdMode.keys()[_throttle_cmd_mode])


## The throttle law in force this tick. DIRECT overrides the selection because a
## speed-holding loop is fly-by-wire and cannot survive the law that removes it.
func throttle_law() -> int:
	return ThrottleCmdMode.THRUST if not GameState.fbw_engaged() else _throttle_cmd_mode


## Adopt the law the fitted throttle wants, unless the pilot has already chosen.
## Called when an input profile loads (InputRouter), which is the only moment the
## fitted shape can change.
func sync_throttle_law() -> void:
	if _throttle_law_pinned:
		return
	_throttle_cmd_mode = (ThrottleCmdMode.THRUST if InputRouter.throttle_is_centering()
			else ThrottleCmdMode.COMBINED)


## --- Authority --------------------------------------------------------------


## The control law is GameState's (FBW_LAWS) because the annunciator, the speed
## tape, the handbook and the SETTINGS page all have to name it. This node
## implements it; it does not own it.
func fbw_engaged() -> bool:
	return GameState.fbw_engaged()


## Bindable (fbw_mode_cycle): step the control law.
func toggle_fbw() -> void:
	GameState.cycle_fbw_law()


## How much of its rated corrective effort the fly-by-wire can currently
## deliver, 0..1. Two factors, multiplied: THRUST allocation (the thrusters it
## corrects through are the same ones the pilot starves when the torch needs
## the budget) and DRIVE hull integrity (the section that carries the reaction
## control runs). An undamaged ship at cruise allocation holds 1.0; hard
## landings, gear overspeed and collapse events all wear DRIVE, and this is
## where that wear finally costs something.
func authority() -> float:
	if not GameState.fbw_engaged():
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


## Sub-steps a tick may be divided into. This is a frame-time guard, and it is
## also the point past which sub-stepping stops being a guarantee.
##
## Against the smallest body in the game (0.35 m, a gate ring's tube) passed
## BROADSIDE, thirty-two sub-steps at 60 Hz hold the full safety margin below
## 1.34 km/s. Between there and about 2.7 km/s the margin is gone but the
## samples still usually land on the body; past 2.7 km/s the ship can cross it
## between two tested positions and misses become common. The failure is gradual
## rather than a cliff, and 1.34 km/s is seventeen minutes of unbroken
## full-throttle burn away under DIRECT law with nothing in front of you.
##
## It can be raised — each sub-step is one collision pass, and the gate below is
## path-aware, so the cap is only ever approached while actually alongside
## something. Thirty-two passes is roughly 6 ms in the worst tick, which is the
## budget this number is really spending; sixty-four would double both the
## ceiling and that cost.
const MAX_SUBSTEPS := 32

## Fraction of the detection window the ship may cross in one sub-step. A half
## means two samples always land inside the window, so a body cannot fall between
## consecutive tested positions.
const SUBSTEP_SAFETY := 0.5


## One tick of manual flight, sub-stepped as fast as the ship is actually going.
##
## Collision is a DISCRETE overlap test run after the position update
## (CollisionSystem), so a ship that crosses a body in less than a tick is never
## tested against it and passes clean through. That is not hypothetical at the
## governor's default: 60 m/s is 1.0 m per 60 Hz tick against a hull 0.7 m
## across, and DIRECT law removes the governor entirely.
##
## So the integration and the collision pass sub-step together — sub-stepping the
## motion alone would buy nothing, because the test would still run once at the
## end. The division is GATED on what the tick's path actually passes near
## (CollisionSystem.path_window), so open space costs one sweep of the registries
## however fast the ship is going, and the sub-steps are spent where the bodies
## are rather than everywhere.
##
## The ship only. ThreatSystem's contacts and DriftSystem's pieces move slowly
## enough that their own once-a-tick pass is sound, and CollisionSystem still
## runs its authoritative pass at the end of the tick with their final positions.
func step(delta: float) -> void:
	var ship: Dictionary = GameState.local_ship()
	var origin: Vector3 = (ship["transform"] as Transform3D).origin
	var travel: Vector3 = (ship["velocity"] as Vector3) * delta
	# What the ship can pass THROUGH on this tick's path, and over how much travel
	# it would be detectable while doing so. INF when the path passes nothing, and
	# then one sub-step is right however fast the ship is going.
	var window := CollisionSystem.path_window(origin, origin + travel)
	var steps := 1
	if is_finite(window):
		steps = clampi(ceili(travel.length() / maxf(SUBSTEP_SAFETY * window, 0.01)),
				1, MAX_SUBSTEPS)
	# The datum is resolved ONCE for the tick and carried into every sub-step. It
	# cannot change under the loop — what the ship is referenced to is not a
	# function of where the ship is — and resolving it per sub-step measured
	# 5.7 us a time, which across a saturated tick is real money for an answer
	# that would be identical every time.
	var reference := NavReference.datum_velocity()
	var sub := delta / float(steps)
	for _i in steps:
		_integrate(sub, reference)
		if steps > 1:
			CollisionSystem.resolve_ship(sub)


## One integration sub-step: rate-commanded attitude through the FBW slew,
## thruster acceleration gated by THRUST power and by the ship's live mass, the
## fly-by-wire nulls, and the governor.
func _integrate(delta: float, reference: Vector3) -> void:
	var ship: Dictionary = GameState.local_ship()
	var transform: Transform3D = ship["transform"]
	var velocity: Vector3 = ship["velocity"]
	var omega: Vector3 = ship.get("omega", Vector3.ZERO)
	var auth := authority()

	# 1. Command. The stick is a rate command (full deflection =
	# rotation_rate_deg/s) in the ship's own axes; world-frame for integration.
	var rate_cmd: Vector3 = transform.basis \
			* (_cmd_rot * deg_to_rad(GameState.ship_def.rotation_rate_deg))

	# 2. Contributors — angular: the direct thruster torque, which is now a real
	# torque over a real moment (GameState.angular_authority) rather than an
	# authored deg/s^2. It fades as FBW authority rises, because a healthy FBW
	# owns the same thrusters it fires through; at zero authority this is all the
	# attitude control there is.
	var alpha := GameState.angular_authority()
	omega += transform.basis * (_cmd_rot * alpha) * (1.0 - auth) * delta

	# 2. Contributors — linear: strafe/vertical thrusters, then the throttle's
	# own control law on the forward axis, both scaled by what the drive can
	# currently make (see thrust_accel, which the propellant meter reads too).
	var accel := thrust_accel()
	var lateral := Vector3(_cmd_thrust.x, _cmd_thrust.y, 0.0)
	if lateral.length_squared() > 0.001:
		velocity += transform.basis * lateral \
				* (accel * GameState.ship_def.secondary_thrust_fraction) * delta
	velocity = _apply_throttle_axis(transform, velocity, accel, delta)
	_burn_propellant(delta)

	# 3. Fly-by-wire — slews omega onto the commanded rate and nulls the
	# uncommanded translation axes. Runs after every contributor so what it
	# corrects is the true residual of the tick.
	omega = _slew_omega(transform, omega, rate_cmd, alpha, auth, delta)
	velocity = _apply_fbw_linear(transform, velocity, auth, delta)

	# 4. Integrate — angular then linear, both semi-implicit.
	if omega.length_squared() > 0.00000001:
		transform.basis = transform.basis.rotated(
				omega.normalized(), omega.length() * delta).orthonormalized()
	velocity = _apply_governor(velocity, reference)
	transform.origin += velocity * delta
	ship["transform"] = transform
	ship["velocity"] = velocity
	ship["omega"] = omega


## The speed governor: hold the ship to her setting RELATIVE TO THE SELECTED
## NAVIGATION DATUM, which is the whole substance of the limit.
##
## A cap on speed through space would be meaningless anywhere near something that
## moves — there is no such thing as an absolute speed to be limited to. A cap on
## how fast the ship is closing on the thing she is being flown at means the same
## thing everywhere, which is why the datum is subtracted before the limit and
## added back after it.
##
## It is a flight-computer limit, not a property of the drive and not a property
## of space, so DIRECT law removes it: governor_limit() returns INF and
## limit_length becomes a no-op without a special case here.
func _apply_governor(velocity: Vector3, reference: Vector3) -> Vector3:
	return reference + (velocity - reference).limit_length(GameState.governor_limit())


## Slew omega onto the commanded rate, bounded by the torque the attitude
## thrusters can actually deliver against the ship's live moments.
##
## The exponential alone is a gain with no limit — it would put a fully loaded
## ship onto a commanded rate exactly as fast as an empty one, which is the whole
## thing mass is supposed to cost. Clamping the correction to alpha * dt is what
## makes the moments matter: roll answers quicker than pitch and yaw because it
## is the smaller moment, and every axis slows as the hold fills.
func _slew_omega(transform: Transform3D, omega: Vector3, rate_cmd: Vector3,
		alpha: Vector3, auth: float, delta: float) -> Vector3:
	if auth <= 0.0:
		return omega
	var wanted: Vector3 = (rate_cmd - omega) \
			* (1.0 - exp(-GameState.ship_def.fbw_angular_rate * auth * delta))
	# The budget is per BODY axis, so resolve the correction there, clamp it, and
	# put it back — a world-frame clamp would mix the axes' very different limits.
	var local: Vector3 = transform.basis.inverse() * wanted
	var budget := alpha * auth * delta
	local.x = clampf(local.x, -budget.x, budget.x)
	local.y = clampf(local.y, -budget.y, budget.y)
	local.z = clampf(local.z, -budget.z, budget.z)
	return omega + transform.basis * local


## Advance `velocity`'s forward/back component only, per the active throttle law
## (see ThrottleCmdMode). Reverse is capped at secondary_thrust_fraction of
## forward — clamping the COMMAND rather than the result, so it scales the thrust
## and the commanded speed together whatever that fraction is tuned to, and
## stopping from speed rewards turning the ship around over braking on the tap.
func _apply_throttle_axis(transform: Transform3D, velocity: Vector3, accel: float, delta: float) -> Vector3:
	var forward_dir: Vector3 = -transform.basis.z
	var reverse_cap: float = GameState.ship_def.secondary_thrust_fraction
	var z_cmd: float = clampf(_cmd_thrust.z, -reverse_cap, 1.0)
	var fwd_speed := velocity.dot(forward_dir)
	var new_fwd_speed: float
	if throttle_law() == ThrottleCmdMode.THRUST:
		new_fwd_speed = fwd_speed + z_cmd * accel * delta
	else:
		# COMBINED: the lever's position commands the speed AND the thrust used
		# reaching it, so half a lever is half thrust easing onto half the
		# governor's setting rather than a full-thrust slam that stops dead there.
		# That is what makes fine work possible on an absolute lever — a tenth of
		# travel is a tenth of the drive, not all of it for a tenth of the time.
		#
		# Deceleration is deliberately NOT scaled by the lever. Scaling both ways
		# makes a closed lever command zero speed with zero authority, which does
		# nothing at all and leaves the ship coasting with the throttle shut.
		# Closing the lever means "arrest me with everything you have".
		var target := z_cmd * GameState.governor_speed
		var closing := absf(target) < absf(fwd_speed)
		var authority_now := accel if closing else absf(z_cmd) * accel
		new_fwd_speed = move_toward(fwd_speed, target, authority_now * delta)
	return velocity + forward_dir * (new_fwd_speed - fwd_speed)


## The acceleration the drive can currently make: thrust over the ship's LIVE
## mass, scaled by BOTH the electrical allocation actually delivered and the
## stages the selector has turning — so a starved bus and a dead stage cost the
## same way, and OFF (or L with a dry tank) leaves nothing at all. It is also the
## yardstick the propellant meter measures a burn against, so both read the same
## figure.
##
## Mass is live, so this falls as the hold fills and rises as the tanks burn
## down: 4.0 m/s^2 on a dry hull, nearer 2.3 at forty tonnes and full tanks.
func thrust_accel() -> float:
	return GameState.ship_def.main_thrust_n / maxf(GameState.ship_mass(), 1.0) \
			* maxf(GameState.power("THRUST"), 0.0) * GameState.thrust_fraction()


## Meter propellant against COMMANDED thrust rather than against speed: holding
## station beside a wreck costs almost nothing and a hard burn costs plenty,
## which is the shape that makes a tank a resource rather than a timer.
func _burn_propellant(delta: float) -> void:
	_meter_propellant(drive_load(), delta)


## Meter propellant for a burn flown as a KINEMATIC OVERRIDE rather than through
## the command path above — the approach autopilot, which seizes the motion state
## every tick and so never touches _cmd_thrust. It flies on the drive like any
## other burn and is charged like one: the velocity change it imposes is measured
## against what the drive could make in the same tick, which meters a manoeuvre at
## its delta-v and leaves a coast at constant velocity free.
##
## The seize can impose more delta-v in a tick than the drive could actually make
## — engagement, where it overrides whatever the pilot was carrying. The clamp
## inside _meter_propellant charges the drive's maximum for that tick rather than
## inventing a rate above it.
func burn_for_delta_v(delta_v: Vector3, delta: float) -> void:
	var accel := thrust_accel()
	if accel <= 0.0 or delta <= 0.0:
		return
	_meter_propellant(delta_v.length() / (accel * delta), delta)


## The one metering law, given how hard the drive is being worked (0..1). The
## booster draws on both tanks; the thermal stage on hydrogen alone.
func _meter_propellant(demand: float, delta: float) -> void:
	if not GameState.thermal_stage_running():
		return
	# A stage turning is not a stage being worked. The drive draws on the THRUST
	# channel, and with nothing delivered against it the acceleration is zero
	# however far the lever is open — so metering against the COMMAND alone would
	# drain the tank on a dead bus for a burn that never happened. Nothing
	# delivered, nothing metered; the same figure gates both.
	if GameState.power("THRUST") <= 0.0:
		return
	demand = clampf(demand, 0.0, 1.0)
	if demand <= 0.0:
		return
	var def := GameState.ship_def
	if GameState.boosting():
		GameState.burn_propellant(def.lh2_burn_boost * demand * delta,
				def.lox_burn_boost * demand * delta)
	else:
		GameState.burn_propellant(def.lh2_burn_rate * demand * delta, 0.0)


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
