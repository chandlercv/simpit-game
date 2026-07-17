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

## Approach/match-velocity performance (SalvageSystem).
@export var approach_accel := 3.0
@export var approach_speed := 8.0

## Cutting-head throughput at full CUTTER allocation, fraction of a member
## severed per second.
@export var cut_rate := 0.35
