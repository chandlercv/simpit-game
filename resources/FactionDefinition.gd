class_name FactionDefinition
extends Resource
## A market faction authored as data (plan Phase 4 convention). MarketSystem
## builds the price table from these; ThreatSystem uses holds_claim to decide
## whose patrol enforces the salvage claim.

@export var display_name := "FACTION"

## Price multiplier per good display_name; goods not listed trade at 1.0.
@export var price_bias: Dictionary = {}

## Starting reputation 0..1 (feeds the price multiplier and drifts as you
## trade with — or annoy — this faction).
@export var starting_rep := 0.5

## Whether this faction's patrols enforce the salvage claim at the site.
@export var holds_claim := false
