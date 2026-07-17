class_name GoodDefinition
extends Resource
## A market commodity authored as data (plan Phase 4 convention). Salvage
## items reference a good by display_name and carry a quantity in this good's
## unit; mass/volume/value all derive from the per-unit figures here.

@export var display_name := "GOOD"

## Unit the market prices per ("T", "KG", "G", "EA").
@export var unit := "T"

## Credits per unit before faction bias / reputation / dock jitter.
@export var base_price := 100

@export var mass_t_per_unit := 1.0
@export var vol_m3_per_unit := 1.0
