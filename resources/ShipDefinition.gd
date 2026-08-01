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
