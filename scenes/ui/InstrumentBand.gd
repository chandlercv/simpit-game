extends Control
## The Tactical display's glass-cockpit instrument band: heading, speed,
## attitude, altitude, rotation rates, propellant and the ship's plate, framing
## whichever mode (SCOPE / CHART) is up.
##
## LAYOUT. VEL, the attitude indicator and ALT form ONE FLIGHT BLOCK on the
## left, in that order, with the tactical picture outboard on the right. That is
## the arrangement a pilot's eye is trained on, and it is why the attitude
## indicator is the largest thing here: it is the one reading that has to work in
## peripheral vision. The reserves below are public because TacticalContent sets
## the mode panels' margins from them and the smoke test audits them — there is
## one copy of the geometry, not two that drift.
##
## MEASURED AGAINST WHAT. Every reading on this band except speed and propellant
## comes from NavReference's datum, so they cannot disagree about which way is
## up. The datum is named on the legend and again on the attitude indicator's
## ground field, because "level" means level with the SELECTED datum and that
## changes under the pilot when AUTO switches.
##
## READ-ONLY, and mouse-transparent. Nothing on the Tactical display takes a
## click; the datum, the rate scale and this band's own visibility are set from
## a HOTAS button or the MFD SETTINGS page.
##
## CADENCE. Redraws on the shared 10 Hz tick, never per-frame — this window is
## streamed to a second screen and nothing here animates continuously.

const Instrument := preload("res://scenes/ui/Instrument.gd")
const TailPlateScript := preload("res://scenes/ui/TailPlate.gd")

@export var accent: Color = Color(1.0, 0.72, 0.2)

# --- Reserves. TacticalContent's margins and InstrumentBandSmoke read these. ---
## Heading tape plus the datum legend line beneath it.
const HDG_H := 56.0
## Speed tape, left of the attitude indicator.
const SPD_W := 96.0
## The attitude indicator: the centre of the flight block.
const ADI_W := 340.0
## Altitude tape, right of the attitude indicator.
const ALT_W := 104.0
## Plate, rate ribbons and propellant.
const BOTTOM_H := 120.0
## Everything left of the mode pane: the whole flight block.
const FLIGHT_W := SPD_W + ADI_W + ALT_W

## Height of the heading tape itself; the rest of HDG_H carries the legend.
## Deep enough for a label ABOVE its tick — at anything shallower the glyphs hang
## off the top of the pane and clip.
const HDG_TAPE_H := 40.0
## Baseline of the tape's degree labels, and the top of the ticks under them.
const HDG_LABEL_Y := 16.0
const HDG_TICK_TOP := 21.0

# --- Instrument scales -------------------------------------------------------
## Heading tape: about ±69° of arc across a full-width tape.
const HDG_PX_PER_DEG := 9.0
## Speed tape: about ±18 m/s either side of the pointer.
const SPD_PX_PER_MS := 14.0
## Altitude tape. Deliberately FIXED rather than fitted to the datum: an
## altimeter tape shows the neighbourhood you are in, not the whole range, and a
## scale that rescaled itself under you would be unreadable on final.
const ALT_PX_PER_M := 4.0
## Vertical-speed trend arrow off the altitude pointer.
const VS_PX_PER_MS := 12.0
const VS_TREND_MAX_PX := 70.0
## Attitude: ±30° fills the ball.
const PITCH_PX_PER_DEG := 6.5

## Below this, a tank tape ambers; at zero it reddens.
const TANK_LOW := 0.25
## Spacing of the diagonals in an over-a-limit band.
const HATCH_STEP := 8.0

const SKY := Color(0.05, 0.09, 0.15)
const GROUND := Color(0.15, 0.10, 0.035)
## TacticalWindow's own background. A tape's scale runs the full height of its
## pane by design, so the strip its caption sits in has to be painted out from
## under it — otherwise the caption lands on whichever tick happens to be there.
const PANEL_BG := Color(0.04, 0.028, 0.008)
## Height of that strip, at the foot of each instrument.
const CAPTION_H := 22.0

var _panes: Array[Control] = []
var _plate: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	GameState.tick_changed.connect(_on_tick)
	resized.connect(_layout)
	_layout()


## One clipped sub-canvas per tape. Clipping is the reason these are nodes and
## not four more calls in _draw(): a tape's labels and an attitude ball both run
## past their own edges by design, and clip_contents is the only thing in Godot
## that stops them writing over the instrument next door.
class Pane:
	extends Control
	var painter: Callable

	func _init(paint: Callable) -> void:
		painter = paint
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		painter.call(self)


func _build() -> void:
	for painter: Callable in [_paint_hdg, _paint_speed, _paint_adi, _paint_alt]:
		var pane := Pane.new(painter)
		add_child(pane)
		_panes.append(pane)
	_plate = TailPlateScript.new()
	_plate.accent = accent
	add_child(_plate)


func _layout() -> void:
	if _panes.size() < 4:
		return
	var mid_h := maxf(size.y - HDG_H - BOTTOM_H, 0.0)
	var mid_y := HDG_H
	_panes[0].position = Vector2.ZERO
	_panes[0].size = Vector2(size.x, HDG_TAPE_H)
	_panes[1].position = Vector2(0, mid_y)
	_panes[1].size = Vector2(SPD_W, mid_h)
	_panes[2].position = Vector2(SPD_W, mid_y)
	_panes[2].size = Vector2(ADI_W, mid_h)
	_panes[3].position = Vector2(SPD_W + ADI_W, mid_y)
	_panes[3].size = Vector2(ALT_W, mid_h)
	# Plate: bottom-left of the bottom band, sized to the rows it actually has.
	var plate_h := minf(BOTTOM_H - 16.0, 96.0)
	_plate.position = Vector2(4.0, size.y - BOTTOM_H + 8.0)
	_plate.size = Vector2(210.0, plate_h)


func _on_tick(_tick: int) -> void:
	queue_redraw()
	for pane: Control in _panes:
		pane.queue_redraw()


# --- Pure geometry. Public so the smoke test can assert the symbology rather ---
# --- than eyeball pixels; both are the whole reason a reading is legible.    ---

## Pixels the horizon sits BELOW the attitude indicator's centre, for a given
## pitch. Positive for NOSE UP — that sign is the instrument: pitching up drops
## the horizon and fills the ball with sky, which is the cue that reads without
## being looked at.
func horizon_offset(pitch_deg: float) -> float:
	return pitch_deg * PITCH_PX_PER_DEG


## Pixels a tape value sits from its pointer. Positive is UP the tape (a higher
## value), which on screen means a smaller y — callers subtract.
func tape_offset(value: float, pointer: float, px_per_unit: float) -> float:
	return (value - pointer) * px_per_unit


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var font := ThemeDB.fallback_font
	_draw_legend(font)
	_draw_rates(font)
	_draw_propellant(font)


# --- Heading -----------------------------------------------------------------

func _paint_hdg(ci: Control) -> void:
	var font := ThemeDB.fallback_font
	var d: Dictionary = NavReference.datum()
	var hdg := NavReference.heading()
	var cx := ci.size.x / 2.0
	var base := ci.size.y - 6.0
	_draw_hline(ci, base, Color(accent, 0.35))

	# Ticks are walked in whole degrees around the current heading so the tape
	# scrolls continuously rather than snapping at label boundaries.
	var span := int(ci.size.x / (2.0 * HDG_PX_PER_DEG)) + 2
	var centre := roundi(hdg)
	for offset in range(-span, span + 1):
		var deg := centre + offset
		if deg % 5 != 0:
			continue
		var x := cx + float(deg - hdg) * HDG_PX_PER_DEG
		if x < -40.0 or x > ci.size.x + 40.0:
			continue
		var major := deg % 10 == 0
		ci.draw_line(Vector2(x, base), Vector2(x, HDG_TICK_TOP + (0.0 if major else 6.0)),
				Color(accent, 0.75 if major else 0.4), 1.0)
		if major:
			ci.draw_string(font, Vector2(x - 22.0, HDG_LABEL_Y),
					"%03d" % (posmod(deg, 360)), HORIZONTAL_ALIGNMENT_CENTER, 44.0,
					Instrument.TAG, Color(accent, 0.85))

	# The bug marks where the datum lies, which is what keeps the datum from
	# having to redefine north for every target the pilot picks.
	var bug_dx := _shortest_arc(NavReference.bearing_to_datum(), hdg) * HDG_PX_PER_DEG
	var bug_x := clampf(cx + bug_dx, 6.0, ci.size.x - 6.0)
	Instrument.draw_arrowhead(ci, Vector2(bug_x, base - 2.0), Vector2.DOWN, 7.0,
			Color(accent, 0.85) if not d["fallback"] else Color(Instrument.WARN, 0.8))

	# Lubber line last, over everything, so "what am I pointing at" is one glance.
	ci.draw_line(Vector2(cx, base), Vector2(cx, HDG_LABEL_Y), accent, 2.0)
	var box := Rect2(cx - 30.0, 0.0, 60.0, HDG_LABEL_Y + 4.0)
	ci.draw_rect(box, Color(0.0, 0.0, 0.0, 0.85), true)
	ci.draw_rect(box, accent, false, 1.0)
	ci.draw_string(font, Vector2(box.position.x, HDG_LABEL_Y), "%03d" % roundi(hdg),
			HORIZONTAL_ALIGNMENT_CENTER, box.size.x, Instrument.ANNOT, accent)


## Signed degrees from `from` to `to`, taking the short way round (-180..180).
func _shortest_arc(to: float, from: float) -> float:
	return wrapf(to - from, -180.0, 180.0)


func _draw_hline(ci: Control, y: float, color: Color) -> void:
	ci.draw_line(Vector2(0, y), Vector2(ci.size.x, y), color, 1.0)


## Clear the caption strip at an instrument's foot and write its caption on it.
## Returns the y the instrument's own scale must stop at.
func _draw_caption(ci: Control, font: Font, text: String, size_px: int,
		color: Color) -> float:
	var top := ci.size.y - CAPTION_H
	ci.draw_rect(Rect2(0, top, ci.size.x, CAPTION_H), PANEL_BG, true)
	ci.draw_line(Vector2(0, top), Vector2(ci.size.x, top), Color(accent, 0.25), 1.0)
	ci.draw_string(font, Vector2(0, ci.size.y - 6.0), text, HORIZONTAL_ALIGNMENT_CENTER,
			ci.size.x, size_px, color)
	return top


# --- Legend ------------------------------------------------------------------

## What the band is measured against, and how far off it is — plus the mode
## legend, which stands where the SCOPE/CHART tabs used to: it reports the mode,
## it does not offer it.
func _draw_legend(font: Font) -> void:
	var d: Dictionary = NavReference.datum()
	var y := HDG_H - 6.0
	var text := "REF %s" % d["label"]
	if d["auto"]:
		text += " (AUTO)"
	var color := Color(accent, 0.7)
	if d["fallback"]:
		text = "REF %s — %s, HOLDING %s" % [
			NavReference.label_for(GameState.nav_reference), d["reason"], d["label"]]
		color = Instrument.WARN
	text += "   ·   RNG %d M" % roundi(NavReference.range_to())
	draw_string(font, Vector2(Instrument.INSET, y), text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, Instrument.ANNOT, color)
	draw_string(font, Vector2(0, y), GameState.tactical_view, HORIZONTAL_ALIGNMENT_RIGHT,
			size.x - Instrument.INSET, Instrument.ANNOT, Color(accent, 0.55))


# --- Speed -------------------------------------------------------------------

func _paint_speed(ci: Control) -> void:
	var font := ThemeDB.fallback_font
	# World (inertial) speed — see GameState.ships on the frame. The tape reads
	# speed through space; the datum-relative readings are ALT/VS/RNG beside it.
	var speed: float = (GameState.local_ship().get("velocity", Vector3.ZERO) as Vector3).length()
	var cy := ci.size.y / 2.0
	var y_for := func(v: float) -> float: return cy - tape_offset(v, speed, SPD_PX_PER_MS)

	# Bands first, under the scale. What the drive can hold, and — separately —
	# what the extended legs will take, which is the lower of the two whenever
	# the gear is out and is the one that costs you a leg rather than nothing.
	_draw_limit_band(ci, y_for.call(GameState.speed_ceiling()), Instrument.BAD)
	if not GameState.gear_stowed():
		_draw_limit_band(ci, y_for.call(GameState.GEAR_LIMIT_SPEED), Instrument.WARN)

	var top: int = int(floor(speed + ci.size.y / (2.0 * SPD_PX_PER_MS))) + 1
	var bottom: int = int(ceil(speed - ci.size.y / (2.0 * SPD_PX_PER_MS))) - 1
	for v in range(maxi(bottom, 0), top + 1):
		var y: float = y_for.call(float(v))
		var major := v % 5 == 0
		ci.draw_line(Vector2(ci.size.x - (14.0 if major else 8.0), y),
				Vector2(ci.size.x, y), Color(accent, 0.7 if major else 0.35), 1.0)
		if major:
			ci.draw_string(font, Vector2(2.0, y + 5.0), str(v), HORIZONTAL_ALIGNMENT_RIGHT,
					ci.size.x - 18.0, Instrument.TAG, Color(accent, 0.8))

	# ATC's limit is an instruction, so it gets a bug rather than a band.
	var docking: Dictionary = DockingSystem.status()
	if not docking.is_empty():
		var limit_y: float = y_for.call(float(docking["speed_limit"]))
		var limit_color: Color = accent if docking["speed_ok"] else Instrument.BAD
		ci.draw_line(Vector2(0, limit_y), Vector2(ci.size.x, limit_y), limit_color, 2.0)

	_draw_caption(ci, font, "VEL M/S", Instrument.TAG, Color(accent, 0.6))
	_draw_pointer(ci, font, cy, "%.1f" % speed, accent, true)


## A hatched band from `y` to the TOP of a tape — "past here is over a limit".
## Both of the speed tape's limits are ceilings, so the band only ever runs
## upward. Hatched rather than filled so the ticks under it stay readable.
##
## The diagonals are clipped to the band by hand. The pane's clip_contents stops
## at the PANE, and a hatch that escaped the band would run on down over the
## scale it is supposed to be qualifying.
func _draw_limit_band(ci: Control, y: float, color: Color) -> void:
	var band := Rect2(0.0, 0.0, ci.size.x, minf(y, ci.size.y))
	if band.size.y <= 0.0:
		return
	ci.draw_rect(band, Color(color, 0.12), true)
	var x := -band.size.y
	while x < band.size.x:
		# One 45-degree line from (x, top) to (x + height, bottom), entering at
		# the band's left edge and leaving at its right or its bottom.
		var ax := maxf(x, 0.0)
		var ay := band.position.y + (ax - x)
		var bx := minf(x + band.size.y, band.size.x)
		var by := minf(band.position.y + (bx - x), band.end.y)
		if ay < band.end.y:
			ci.draw_line(Vector2(ax, ay), Vector2(bx, by), Color(color, 0.35), 1.0)
		x += HATCH_STEP
	ci.draw_line(Vector2(0, y), Vector2(ci.size.x, y), color, 2.0)


## The boxed live figure a tape is read from. `left_notch` points the box at the
## instrument it belongs to, so the speed box points right and altitude left.
func _draw_pointer(ci: Control, font: Font, cy: float, text: String, color: Color,
		notch_right: bool) -> void:
	var h := 30.0
	var box := Rect2(0, cy - h / 2.0, ci.size.x, h)
	ci.draw_rect(box, Color(0.0, 0.0, 0.0, 0.85), true)
	ci.draw_rect(box, color, false, 2.0)
	var tip_x := ci.size.x if notch_right else 0.0
	var dir := Vector2.RIGHT if notch_right else Vector2.LEFT
	Instrument.draw_arrowhead(ci, Vector2(tip_x, cy) + dir * 6.0, dir, 7.0, color)
	ci.draw_string(font, Vector2(0, cy + 9.0), text, HORIZONTAL_ALIGNMENT_CENTER,
			ci.size.x, Instrument.READOUT, color)


# --- Altitude ----------------------------------------------------------------

func _paint_alt(ci: Control) -> void:
	var font := ThemeDB.fallback_font
	var d: Dictionary = NavReference.datum()
	var alt := NavReference.altitude()
	var vs := NavReference.vertical_speed()
	var cy := ci.size.y / 2.0
	var y_for := func(v: float) -> float: return cy - tape_offset(v, alt, ALT_PX_PER_M)

	# On a platform the datum's plane is a real deck, so it gets a real ground
	# band. Elsewhere it is a reference plane and drawing a floor would be a lie.
	if d["id"] == "PAD":
		var deck_y: float = y_for.call(0.0)
		if deck_y < ci.size.y:
			ci.draw_rect(Rect2(0, deck_y, ci.size.x, ci.size.y - deck_y),
					Color(GROUND, 0.7), true)
			ci.draw_line(Vector2(0, deck_y), Vector2(ci.size.x, deck_y), accent, 2.0)

	var half_m := ci.size.y / (2.0 * ALT_PX_PER_M)
	var top: int = int(floor((alt + half_m) / 5.0)) + 1
	var bottom: int = int(ceil((alt - half_m) / 5.0)) - 1
	for step in range(bottom, top + 1):
		var v := float(step * 5)
		var y: float = y_for.call(v)
		var major := step % 2 == 0
		ci.draw_line(Vector2(0, y), Vector2(14.0 if major else 8.0, y),
				Color(accent, 0.7 if major else 0.35), 1.0)
		if major:
			ci.draw_string(font, Vector2(18.0, y + 5.0), "%d" % roundi(v),
					HORIZONTAL_ALIGNMENT_LEFT, ci.size.x - 20.0, Instrument.TAG,
					Color(accent, 0.8))

	# Trend: where the tape will be in a moment, which is the reading that
	# actually flies an approach.
	if absf(vs) > 0.05:
		var trend := clampf(-vs * VS_PX_PER_MS, -VS_TREND_MAX_PX, VS_TREND_MAX_PX)
		var x := ci.size.x - 8.0
		var tip := Vector2(x, cy + trend)
		var vs_color := accent
		if -vs > DockingSystem.HARD_RATE:
			vs_color = Instrument.BAD
		elif -vs > DockingSystem.FIRM_RATE:
			vs_color = Instrument.WARN
		ci.draw_line(Vector2(x, cy), tip, vs_color, 2.0)
		Instrument.draw_arrowhead(ci, tip, Vector2(0, signf(trend)), 6.0, vs_color)

	_draw_pointer(ci, font, cy, "%.1f" % alt, accent, false)
	_draw_caption(ci, font, "ALT M   VS %+.1f" % vs, Instrument.TAG, Color(accent, 0.6))


# --- Attitude ----------------------------------------------------------------

func _paint_adi(ci: Control) -> void:
	var font := ThemeDB.fallback_font
	var d: Dictionary = NavReference.datum()
	var att := NavReference.attitude()
	var pitch := att.x
	var roll := att.y
	var c := Vector2(ci.size.x / 2.0, (ci.size.y - CAPTION_H) / 2.0)
	var half_h := c.y
	# Big enough that the sky and ground fields still cover the pane at any roll.
	var reach := ci.size.length()
	var horizon_y := horizon_offset(pitch)

	# The ball rotates OPPOSITE to the roll: drop the right wing and the world's
	# right-hand side comes up. Godot's 2D +y is down, so that is a negative angle.
	ci.draw_set_transform(c, deg_to_rad(-roll), Vector2.ONE)
	ci.draw_rect(Rect2(-reach, -reach, reach * 2.0, reach + horizon_y), SKY, true)
	ci.draw_rect(Rect2(-reach, horizon_y, reach * 2.0, reach), GROUND, true)
	# The ground is a reference PLANE, not terrain, so it is stippled rather than
	# solid — it reads as a datum you are above, not as a surface you are over.
	var stipple := horizon_y + 12.0
	while stipple < reach:
		ci.draw_line(Vector2(-reach, stipple), Vector2(reach, stipple),
				Color(accent, 0.10), 1.0)
		stipple += 14.0
	ci.draw_line(Vector2(-reach, horizon_y), Vector2(reach, horizon_y), accent, 2.0)
	_draw_ladder(ci, font, pitch, horizon_y)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_roll_scale(ci, c, roll, minf(c.x, half_h) - 8.0)
	_draw_waterline(ci, c)

	# Which plane "level" means, on the field it refers to.
	ci.draw_string(font, Vector2(0, ci.size.y - CAPTION_H - 10.0), String(d["plane_label"]),
			HORIZONTAL_ALIGNMENT_CENTER, ci.size.x, Instrument.TAG, Color(accent, 0.5))
	# The horizon can leave the ball entirely; the chevron keeps the instrument
	# from ever going blank by pointing the short way back to level.
	if absf(horizon_y) > half_h:
		var edge := c.y + (half_h - 14.0) * signf(horizon_y)
		Instrument.draw_arrowhead(ci, Vector2(c.x, edge), Vector2(0, signf(horizon_y)),
				10.0, Color(accent, 0.8))
	_draw_caption(ci, font, "P %+03d      R %+03d" % [roundi(pitch), roundi(roll)],
			Instrument.ANNOT, accent)


## Pitch bars every 5°, labelled every 10°. Solid above the horizon and dashed
## below — which side of the horizon you are on has to be readable from the bar
## itself, not only from where it sits. Bars shorten with angle, so the taper
## alone says how far from level you are.
func _draw_ladder(ci: Control, font: Font, pitch: float, horizon_y: float) -> void:
	for step in range(-18, 19):
		var deg := step * 5
		if deg == 0:
			continue
		var y := horizon_y - float(deg) * PITCH_PX_PER_DEG
		var labelled := deg % 10 == 0
		var half := (54.0 if labelled else 26.0) \
				* (1.0 - clampf(absf(float(deg)) / 300.0, 0.0, 0.4))
		var color := Color(accent, 0.7 if labelled else 0.45)
		if deg > 0:
			ci.draw_line(Vector2(-half, y), Vector2(half, y), color, 1.5)
		else:
			var x := -half
			while x < half:
				ci.draw_line(Vector2(x, y), Vector2(minf(x + 7.0, half), y), color, 1.5)
				x += 13.0
		if labelled:
			var text := str(absi(deg))
			ci.draw_string(font, Vector2(-half - 30.0, y + 5.0), text,
					HORIZONTAL_ALIGNMENT_RIGHT, 24.0, Instrument.TAG, color)
			ci.draw_string(font, Vector2(half + 6.0, y + 5.0), text,
					HORIZONTAL_ALIGNMENT_LEFT, 24.0, Instrument.TAG, color)


## Fixed scale on the bezel, pointer riding with the ball. Wings are level when
## the pointer sits on the index at the top — the same fact the flat horizon
## line reports, said a second way.
func _draw_roll_scale(ci: Control, c: Vector2, roll: float, radius: float) -> void:
	for mark in [-60, -45, -30, -20, -10, 10, 20, 30, 45, 60]:
		var ang := deg_to_rad(-90.0 + float(mark))
		var dir := Vector2.from_angle(ang)
		var length := 10.0 if absi(mark) % 30 == 0 else 6.0
		ci.draw_line(c + dir * radius, c + dir * (radius - length), Color(accent, 0.6), 1.0)
	ci.draw_arc(c, radius, deg_to_rad(-155.0), deg_to_rad(-25.0), 64, Color(accent, 0.35), 1.0)
	# Index: fixed, pointing down at the scale from outside.
	Instrument.draw_arrowhead(ci, c + Vector2(0, -radius + 2.0), Vector2.DOWN, 8.0,
			Color(accent, 0.9))
	# Pointer: rotates with the ball, so it reads the roll angle off the scale.
	var pointer_dir := Vector2.from_angle(deg_to_rad(-90.0 - roll))
	Instrument.draw_arrowhead(ci, c + pointer_dir * (radius - 12.0), -pointer_dir, 8.0,
			accent)


## The one thing on the instrument that never moves. Everything else moves
## behind it, which is what turns "am I level" into a coincidence you can see
## rather than an angle you have to estimate — so it is the BOLDEST mark here,
## and it is laid over a dark outline because it has to hold its contrast
## against the sky field and the ground field both.
func _draw_waterline(ci: Control, c: Vector2) -> void:
	var inner := 20.0
	var outer := 74.0
	var drop := 11.0
	for pass_i in 2:
		var color := Color(0.0, 0.0, 0.0, 0.75) if pass_i == 0 else accent
		var width := 7.0 if pass_i == 0 else 3.5
		for sign_x in [-1.0, 1.0]:
			var a := c + Vector2(sign_x * outer, 0.0)
			var b := c + Vector2(sign_x * inner, 0.0)
			ci.draw_line(a, b, color, width)
			ci.draw_line(b, b + Vector2(0, drop), color, width)
	ci.draw_rect(Rect2(c - Vector2(5.0, 5.0), Vector2(10.0, 10.0)),
			Color(0.0, 0.0, 0.0, 0.75), true)
	ci.draw_rect(Rect2(c - Vector2(3.5, 3.5), Vector2(7.0, 7.0)), accent, true)


# --- Rotation rates ----------------------------------------------------------

## Centre-zero ribbons rather than needles: what you are doing about a tumble is
## driving three numbers to zero, and three pointers lining up on one centre
## line is the fastest way to see that you have.
func _draw_rates(font: Font) -> void:
	var rates := NavReference.body_rates()
	var full := GameState.rate_scale_deg()
	var x := 236.0
	var width := 250.0
	var y := size.y - BOTTOM_H + 20.0
	var labels: PackedStringArray = ["PITCH", "YAW", "ROLL"]
	var label_w: float = Instrument.label_column(font, labels)
	draw_string(font, Vector2(x, y - 6.0), "RATE °/S  ±%d" % roundi(full),
			HORIZONTAL_ALIGNMENT_LEFT, -1, Instrument.TAG, Color(accent, 0.5))
	for i in 3:
		var row_y := y + 10.0 + float(i) * Instrument.ROW_PITCH
		var value: float = rates[i]
		draw_string(font, Vector2(x, row_y + Instrument.ROW * 0.5), labels[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, Instrument.ANNOT, Color(accent, 0.7))
		var track := Rect2(x + label_w, row_y, width, Instrument.BAR_H)
		draw_rect(track, Color(accent, 0.10), true)
		draw_rect(track, Color(accent, 0.4), false, 1.0)
		var mid := track.position.x + track.size.x / 2.0
		draw_line(Vector2(mid, track.position.y), Vector2(mid, track.end.y),
				Color(accent, 0.5), 1.0)
		var frac := clampf(value / maxf(full, 0.001), -1.0, 1.0)
		var fill := Rect2(minf(mid, mid + frac * track.size.x / 2.0), track.position.y + 2.0,
				absf(frac) * track.size.x / 2.0, track.size.y - 4.0)
		draw_rect(fill, Color(accent, 0.75), true)
		draw_string(font, Vector2(track.end.x + 8.0, row_y + Instrument.ROW * 0.85),
				"%+5.1f" % value, HORIZONTAL_ALIGNMENT_LEFT, -1, Instrument.TAG,
				Color(accent, 0.8))


# --- Propellant --------------------------------------------------------------

## Vertical tapes, because a tank is a vertical thing and a level in one is read
## the same way as a level in the other. Quantity is the MFD POWER page's job;
## what belongs beside the flight instruments is how much is left.
func _draw_propellant(font: Font) -> void:
	var tanks: Array[Dictionary] = [
		{"label": "LH2", "fraction": GameState.lh2_fraction()},
		{"label": "LOX", "fraction": GameState.lox_fraction()},
	]
	var w := 34.0
	var gap := 26.0
	var h := BOTTOM_H - 46.0
	var top := size.y - BOTTOM_H + 22.0
	var x := size.x - Instrument.INSET - (w * 2.0 + gap)
	for i in tanks.size():
		var tank: Dictionary = tanks[i]
		var fraction: float = tank["fraction"]
		var color := accent
		if fraction <= 0.0:
			color = Instrument.BAD
		elif fraction < TANK_LOW:
			color = Instrument.WARN
		var tape := Rect2(x + float(i) * (w + gap), top, w, h)
		draw_rect(tape, Color(color, 0.10), true)
		draw_rect(Rect2(tape.position.x, tape.end.y - tape.size.y * fraction,
				tape.size.x, tape.size.y * fraction), Color(color, 0.7), true)
		draw_rect(tape, Color(color, 0.55), false, 1.0)
		for quarter in range(1, 4):
			var tick_y := tape.position.y + tape.size.y * float(quarter) / 4.0
			draw_line(Vector2(tape.position.x, tick_y),
					Vector2(tape.position.x + 6.0, tick_y), Color(color, 0.5), 1.0)
		draw_string(font, Vector2(tape.position.x - 8.0, tape.position.y - 6.0),
				tank["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, Instrument.TAG,
				Color(accent, 0.7))
		draw_string(font, Vector2(tape.position.x - 8.0, tape.end.y + 15.0),
				"%d%%" % roundi(fraction * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1,
				Instrument.TAG, color)
