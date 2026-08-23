extends Control
## The builder's plate — the etched panel riveted in the cockpit that says which
## hull this is. Registry, hull serial, yard and year, all quoted from the ship's
## ShipDefinition rather than written here, so a second hull carries its own
## plate without a code change.
##
## It is the one thing on the Tactical display that never changes in flight, and
## it is drawn once: no signal, no tick. That is what a plate is.

const Instrument := preload("res://scenes/ui/Instrument.gd")

@export var accent: Color = Color(1.0, 0.72, 0.2)

## Inset of the etched text from the plate's border.
const PAD := 10.0
## Pitch between the small stamped rows under the name.
const STAMP_PITCH := 17.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## What the plate reads, top line first. Blank fields are dropped rather than
## stamped empty — an unfilled row on a real plate would be a blank, not a label
## with nothing after it.
func rows() -> PackedStringArray:
	var ship: ShipDefinition = GameState.ship_def
	var out: PackedStringArray = []
	if ship.registry != "":
		out.append("REG %s" % ship.registry)
	if ship.hull_serial != "":
		out.append("HULL %s" % ship.hull_serial)
	var built := ship.builder
	if ship.build_year > 0:
		built = "%s  %d" % [built, ship.build_year] if built != "" else str(ship.build_year)
	if built != "":
		out.append(built)
	return out


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var plate := Rect2(Vector2.ZERO, size)
	# Etched metal: a dark field, a bright rule, and a second rule inside it —
	# the plate reads as a physical object rather than as more screen text.
	draw_rect(plate, Color(accent, 0.06), true)
	draw_rect(plate, Color(accent, 0.55), false, 1.0)
	draw_rect(plate.grow(-3.0), Color(accent, 0.22), false, 1.0)

	var y := PAD + Instrument.ROW
	draw_string(font, Vector2(PAD, y), GameState.ship_def.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2.0, Instrument.ROW, accent)
	y += 6.0
	draw_line(Vector2(PAD, y), Vector2(size.x - PAD, y), Color(accent, 0.3), 1.0)
	y += STAMP_PITCH
	for row: String in rows():
		draw_string(font, Vector2(PAD, y), row, HORIZONTAL_ALIGNMENT_LEFT,
				size.x - PAD * 2.0, Instrument.TAG, Color(accent, 0.62))
		y += STAMP_PITCH
