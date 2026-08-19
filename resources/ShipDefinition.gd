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
@export var manual_accel := 4.0
@export var rotation_rate_deg := 45.0
@export var max_speed := 25.0

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
