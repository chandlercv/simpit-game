extends RefCounted
## Shared drawing vocabulary for the custom-drawn MFD instrument pages —
## DockPanel, ScoopPanel, AlignPanel and ChecklistPanel.
##
## Two jobs. First, ONE TYPE SCALE: these pages are read at arm's length on a
## small panel while the ship is moving, and their type used to be the smallest
## on the screen (gate rows at 12, ATC detail at 10, traffic tags at 9). Sizes now
## come from here, so making the instruments more legible is a change to this file
## rather than a sweep through four others.
##
## Second, the helpers themselves: draw_gate, draw_notice, draw_meter, draw_diamond
## and draw_arrowhead each used to exist as a verbatim copy in two or three of the
## panels, which is how the value column drifted apart (x=92 in one, x=84 in the
## other). One copy now.
##
## Helpers take the Control they draw into, since a static function has no `self`
## to call draw_string on. Sizes are in the MFD window's 1280x800 virtual canvas.

## The boxed numeral in a tape's pointer — the one figure on an instrument
## that has to be readable without looking straight at it.
const READOUT := 28
## "NO APPROACH RUNNING" and the like.
const TITLE := 24
## Page header, ATC instruction, range readout.
const HEADING := 20
## Gate-checklist rows and meter labels — the text you actually read in flight.
const ROW := 17
## Field annotations: gate name, ALT/OFF/TILT, sink rate, closure.
const ANNOT := 15
## Traffic range tags: the smallest thing on the page, and still legible.
const TAG := 13
## Station / berth corner text.
const CORNER := 14
## A notice's sub-line, and ATC's detail line.
const DETAIL := 16

## Vertical pitch between gate-checklist rows, and between meters. Reserve heights
## are derived from these, so raising the type scale moves the layout with it.
const ROW_PITCH := 26.0
const METER_PITCH := 30.0
## Height of a meter's filled track.
const BAR_H := 16.0

## Left inset shared by every row, so labels line up down the page.
const INSET := 8.0
## Gap between the widest label and the value column beside it.
const COLUMN_GAP := 16.0

const GOOD := Color(0.45, 1.0, 0.55)
const WARN := Color(1.0, 0.62, 0.25)
const BAD := Color(1.0, 0.38, 0.32)


## Width to allow for a column of labels, measured from the widest of them rather
## than hardcoded — the literals this replaces (x=92, x=84, x=52) would each have
## been overrun by larger text, and would need re-tuning on every type change.
static func label_column(font: Font, labels: PackedStringArray) -> float:
	var widest := 0.0
	for label: String in labels:
		widest = maxf(widest, font.get_string_size(
				label, HORIZONTAL_ALIGNMENT_LEFT, -1, ROW).x)
	return widest + COLUMN_GAP


## One checklist row: name, live value against its limit, and a pass mark.
## `label_w` comes from label_column() over the page's own row labels.
static func draw_gate(ci: Control, font: Font, y: float, label: String,
		value: String, ok: bool, accent: Color, label_w: float) -> void:
	var col := GOOD if ok else WARN
	ci.draw_string(font, Vector2(INSET, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			ROW, Color(accent, 0.75))
	ci.draw_string(font, Vector2(INSET + label_w, y), value, HORIZONTAL_ALIGNMENT_LEFT,
			-1, ROW, col)
	ci.draw_string(font, Vector2(-INSET, y), "OK" if ok else "✗",
			HORIZONTAL_ALIGNMENT_RIGHT, ci.size.x, ROW, col)


## A page's "nothing to fly right now" state: a centred headline over the reason,
## in place of whatever the page normally draws.
static func draw_notice(ci: Control, font: Font, title: String, detail: String,
		accent: Color, footer_h: float) -> void:
	var mid := (ci.size.y - footer_h) / 2.0
	ci.draw_string(font, Vector2(0, mid), title, HORIZONTAL_ALIGNMENT_CENTER,
			ci.size.x, TITLE, Color(accent, 0.6))
	ci.draw_string(font, Vector2(0, mid + TITLE + 8.0), detail,
			HORIZONTAL_ALIGNMENT_CENTER, ci.size.x, DETAIL, Color(accent, 0.4))


## A labelled 0..1 bar: label on the left, filled track on the right.
static func draw_meter(ci: Control, font: Font, pos: Vector2, width: float,
		label: String, value: float, color: Color, label_w: float) -> void:
	ci.draw_string(font, pos + Vector2(0, ROW), label, HORIZONTAL_ALIGNMENT_LEFT,
			-1, ROW, color)
	var track_x := pos.x + label_w
	var track_w := width - label_w
	var track := Rect2(track_x, pos.y + 4.0, track_w, BAR_H)
	ci.draw_rect(track, Color(color, 0.12), true)
	ci.draw_rect(Rect2(track_x, pos.y + 4.0, track_w * clampf(value, 0.0, 1.0), BAR_H),
			color, true)
	ci.draw_rect(track, Color(color, 0.5), false, 1.0)


static func draw_diamond(ci: Control, c: Vector2, r: float, color: Color,
		width: float) -> void:
	ci.draw_polyline(PackedVector2Array([
			c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r),
			c + Vector2(-r, 0), c + Vector2(0, -r)]), color, width, true)


static func draw_arrowhead(ci: Control, tip: Vector2, dir: Vector2, r: float,
		color: Color) -> void:
	var d := dir.normalized()
	var n := Vector2(-d.y, d.x)
	ci.draw_colored_polygon(PackedVector2Array([
			tip, tip - d * r * 1.7 + n * r * 0.8, tip - d * r * 1.7 - n * r * 0.8]), color)
