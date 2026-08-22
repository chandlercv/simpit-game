class_name ShipDefinition
extends Resource
## Ship stats authored as data, not hardcoded fields on scripts/scenes (plan
## Phase 4 convention) — a second ship type is a new .tres in data/ships/,
## not a code change.

@export var display_name := "SHIP"

## Cargo hold limits (CargoSystem enforces both).
@export var cargo_mass_limit_t := 40.0
@export var cargo_vol_limit_m3 := 30.0

## Reactor output the power sliders share (sum of allocations that can run
## at once; the tablet warns past this).
@export var power_budget := 2.5

## Approach/match-velocity speed (SalvageSystem).
@export var approach_speed := 8.0

## Manual flight (Phase 5): thruster acceleration at full THRUST allocation,
## attitude rate at full stick, and a flight-assist speed ceiling.
## manual_accel is the RATED figure — the drive with both stages turning. Either
## stage alone delivers a fraction of it (below), and neither delivers none.
## max_speed is the DRAG-LIMITED ceiling: the speed at which the field stage's
## thrust and the hull's Higgs coupling balance. Reaction mass buys past it.
@export var manual_accel := 4.0
@export var rotation_rate_deg := 45.0
@export var max_speed := 25.0

## --- Hybrid drive -----------------------------------------------------------
## The drive is a field stage (electrodynamic, propellant-free, electrically
## expensive) and a nuclear-thermal stage (burns liquid hydrogen, electrically
## cheap), selected independently on the panel's five-position selector. These
## are the fractions of manual_accel each delivers ALONE; together they make the
## rated figure. The field stage is what a ship gets home on with dry tanks —
## which is why it is never zero.
@export var thrust_fraction_field := 0.4
@export var thrust_fraction_thermal := 0.6

## Multipliers on the THRUST channel's electrical demand for the stages running.
## Producing thrust without hydrogen costs electricity; producing it with hydrogen
## costs very little. This is what couples the propellant state to the battery:
## run the tank dry, recover onto the field stage, and the bus load jumps with it.
##
## Tuned so the BOOT MIX IS SUSTAINABLE. At the boot allocation (THRUST 0.80,
## CUTTER 0.00, SENSORS 0.60, LIFE 1.00) against a 2.5 alternator, running BOTH
## comes to 2.4 — just inside. Raising CUTTER to work a wreck is what tips the
## ship onto the battery, which is the right place for that cost to come from:
## something the pilot chose, not the factory settings.
@export var thrust_draw_electric := 1.0
@export var thrust_draw_thermal := 0.2

## Seconds the selector must sit at START before the drive will run. Thrust
## arrives only once it is moved off START onto a running position.
@export var drive_start_time := 10.0

## --- Propellant -------------------------------------------------------------
## Liquid hydrogen: the thermal stage's working fluid, and the booster's fuel.
## Burn rates are units per second at FULL commanded thrust and scale down with
## the throttle, so station-keeping is nearly free and a hard burn is not.
@export var lh2_capacity := 60.0
@export var lh2_burn_rate := 1.0
@export var lh2_burn_boost := 2.5
## Ceiling added while the thermal stage is running.
@export var thermal_speed_bonus := 10.0

## Liquid oxygen: burned with hydrogen in the combustion booster, and useless
## without it. The booster is the shortest-endurance stage by a wide margin.
@export var lox_capacity := 20.0
@export var lox_burn_boost := 2.0
## Ceiling added on top of the thermal stage's while boosting.
@export var boost_speed_bonus := 15.0

## Every directional thruster other than the main (forward) one — strafe,
## vertical, and reverse — is a smaller tap off the same drive, not a matched
## engine of its own: each rates at this fraction of forward performance
## (manual_accel for strafe/vertical, manual_accel and max_speed for reverse).
## One knob for all of them so the whole maneuvering profile tunes together.
@export var secondary_thrust_fraction := 0.5

## --- Fly-by-wire stability augmentation (ShipMotion) ------------------------
## Translation-nulling bleed rate (s^-1) at full authority, applied as
## v *= exp(-rate * dt). Two rates, because the same number cannot serve both
## jobs: STATION-KEEPING (every control released) pulls the ship to a stop
## beside a wreck and wants to be brisk; FLYING (any axis, including throttle,
## under command) only tidies the axes the pilot isn't using, and must be gentle
## or a deliberate sidestep is erased before it carries the ship anywhere.
@export var fbw_linear_rate := 0.35
@export var fbw_linear_rate_flying := 0.1
## Attitude-channel slew rate (s^-1): the residual rate is 95% nulled in
## roughly 3/rate seconds at full authority.
@export var fbw_angular_rate := 14.0
## Direct thruster torque, deg/s^2 at full stick — the attitude control that
## remains when the FBW has no authority.
@export var fbw_raw_torque_deg := 45.0
## THRUST allocation at and above which the FBW holds full authority; below
## the knee, authority falls in proportion.
@export var fbw_power_knee := 0.4
## DRIVE hull-integrity band for FBW authority: none at or below `dead`,
## unimpaired at or above `full`, linear between. The boot DRIVE value (0.85)
## sits above `full`, so an undamaged ship always starts at full authority.
@export var fbw_drive_dead := 0.3
@export var fbw_drive_full := 0.8
## Radius of gyration (m) for collision spin: a contact's delta-v applied at
## the contact point imparts delta-omega = r x dv / radius^2 (CollisionSystem).
@export var collision_spin_radius := 1.0

## Cutting-head throughput at full CUTTER allocation, fraction of a member
## severed per second.
@export var cut_rate := 0.35

## Collision capsule in ship-local space (CollisionSystem tests against it). The
## two endpoints define the capsule's spine and A == B degenerates to a sphere.
## Because the endpoints are local, the capsule follows the hull through the ship
## basis — and centering them on the model (not the transform origin) fixes the
## "collision volume sits beside the visible hull" bug. Bake these from the model
## with tools/ShipColliderBake rather than hand-tuning. collision_radius doubles
## as the fallback sphere radius if the capsule is left unbaked (A == B == 0).
@export var collision_a := Vector3.ZERO
@export var collision_b := Vector3.ZERO
@export var collision_radius := 2.5
