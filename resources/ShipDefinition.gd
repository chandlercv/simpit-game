class_name ShipDefinition
extends Resource
## Ship stats authored as data, not hardcoded fields on scripts/scenes (plan
## Phase 4 convention) — a second ship type is a new .tres in data/ships/,
## not a code change.

@export var display_name := "SHIP"

## --- Identity ---------------------------------------------------------------
## What is stamped on the builder's plate in the cockpit, and what the Tactical
## display's plate reproduces. `display_name` doubles as the radio callsign —
## the harbour addresses the ship by it in every ATC line.
@export var registry := ""
@export var hull_serial := ""
@export var builder := ""
@export var build_year := 0

## Cargo hold limits (CargoSystem enforces both).
@export var cargo_mass_limit_t := 40.0
@export var cargo_vol_limit_m3 := 30.0

## --- Power plant ------------------------------------------------------------
## The reactor is the ship's one energy source and it feeds two different things
## with two different currencies. The ALTERNATOR converts part of its output into
## electricity for the bus; the remainder is HEAT, and the heat is what the
## nuclear-thermal drive stage expands hydrogen with. That is the whole reason
## the thermal stage is nearly free on the bus while the field stage is not — the
## two stages are drawing on different products of the same reactor.
##
## The bus itself is denominated in abstract "units" (the four channel
## allocations, each 0..1, summed against power_budget). `power_unit_w` is what
## one of those units is worth in watts, and it is the only bridge between the
## two systems: the figures below are authored in SI and divided down, so the
## handbook can publish watts while the sliders keep counting in units.
@export var reactor_output_w := 1_200_000.0
@export var alternator_output_w := 500_000.0
@export var battery_capacity_j := 2.4e7
@export var power_unit_w := 200_000.0

## Approach/match-velocity speed (SalvageSystem).
@export var approach_speed := 8.0

## --- Mass and inertia -------------------------------------------------------
## The ship's acceleration is not authored — it is thrust over mass, and mass is
## live: dry hull, plus whatever is in the tanks, plus whatever is in the hold
## (GameState.ship_mass). A full ship is roughly 1.7 times a dry one and flies
## like it, on every axis.
##
## `inertia_kgm2` is the principal moments about the body axes in (pitch, yaw,
## roll) order — the same order NavReference.body_rates() reports and the rate
## ribbons draw. Roll is much smaller than the other two because it is the moment
## about the long axis, so the roll axis answers a control input faster than
## pitch or yaw does. That asymmetry is the point of carrying a tensor at all.
@export var dry_mass_kg := 60_000.0
@export var inertia_kgm2 := Vector3(9.0e5, 9.0e5, 2.0e5)

## Main thruster force with both drive stages turning. 240 kN against a dry
## 60 t hull is 4.0 m/s², the ship's rated figure; either stage alone delivers a
## fraction of it (below), and neither delivers none.
@export var main_thrust_n := 240_000.0

## Attitude control torque at full deflection, (pitch, yaw, roll) N·m. Divided by
## the moments above this is the angular acceleration available, and that is now
## the ship's ONE attitude authority: it bounds the pilot's direct control under
## DIRECT law and it bounds how hard the augmentation may correct under NORMAL.
##
## Those used to be different numbers, and one of them was infinite — the
## augmentation slewed onto a commanded rate at a gain with no limit, so it could
## null a tumble a pilot on the same thrusters could not. Giving it a real
## ceiling is what makes the moments above mean anything.
##
## Authored for 90°/s² on pitch and yaw at dry mass, and 135°/s² in roll. Roll is
## the quicker axis because it is the smaller moment, but not by the full ratio:
## the roll thrusters work on a far shorter arm than the ones at the nose and
## tail, which is what this asymmetry between torque and moment represents.
@export var attitude_torque_nm := Vector3(1_413_700.0, 1_413_700.0, 471_200.0)

## Attitude rate commanded at full control deflection. A COMMAND, not a limit:
## every axis is commanded to the same rate, and the torque and moments above
## decide how quickly each one gets there.
@export var rotation_rate_deg := 45.0

## --- Hybrid drive -----------------------------------------------------------
## The drive is a field stage (electrodynamic, propellant-free, electrically
## expensive) and a nuclear-thermal stage (burns liquid hydrogen, electrically
## cheap), selected independently on the panel's five-position selector. These
## are the fractions of main_thrust_n each delivers ALONE; together they make the
## rated figure. The field stage is what a ship gets home on with dry tanks —
## which is why it is never zero.
##
## The combustion booster layers on TOP of the rated figure rather than beside
## it: it is the only setting above 1.0, and it is what the booster buys. (It
## used to buy a higher speed ceiling instead. There is no ceiling to raise now —
## speed is limited by the fly-by-wire governor, which is a pilot setting and not
## a property of the drive — so the booster buys thrust, which is what a
## combustion chamber actually produces.)
@export var thrust_fraction_field := 0.4
@export var thrust_fraction_thermal := 0.6
@export var thrust_fraction_boost := 1.5

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

## Liquid oxygen: burned with hydrogen in the combustion booster, and useless
## without it. The booster is the shortest-endurance stage by a wide margin.
@export var lox_capacity := 20.0
@export var lox_burn_boost := 2.0

## What a unit of each propellant weighs. Full tanks are about 3.6 t, which the
## ship has to accelerate along with everything else — burning down is the one
## way the hull gets lighter in flight (GameState.ship_mass).
@export var lh2_kg_per_unit := 40.0
@export var lox_kg_per_unit := 60.0

## Every directional thruster other than the main (forward) one — strafe,
## vertical, and reverse — is a smaller tap off the same drive, not a matched
## engine of its own: each rates at this fraction of forward performance — the
## available acceleration for strafe and vertical, and the commanded travel for
## reverse, which is why stopping from speed rewards turning the ship around
## rather than braking on the reverse tap.
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
## roughly 3/rate seconds at full authority — BUT only where the thrusters can
## deliver it. The correction is clamped to attitude_torque_nm over the live
## moments, so this rate is what a dry ship achieves and a loaded one falls short
## of. It is a gain, not a promise.
@export var fbw_angular_rate := 14.0
## THRUST allocation at and above which the FBW holds full authority; below
## the knee, authority falls in proportion.
@export var fbw_power_knee := 0.4
## DRIVE hull-integrity band for FBW authority: none at or below `dead`,
## unimpaired at or above `full`, linear between. The boot DRIVE value (0.85)
## sits above `full`, so an undamaged ship always starts at full authority.
@export var fbw_drive_dead := 0.3
@export var fbw_drive_full := 0.8

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
