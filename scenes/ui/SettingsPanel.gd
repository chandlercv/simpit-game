extends Control
## MFD SETTINGS page — where the Tactical instrument band is configured from.
##
## The band itself takes no clicks (nothing on the Tactical display does), so
## everything it needs set has to be reachable from somewhere else: a mapped
## HOTAS button, or here. Every row below is the same intent a bound control
## calls, so the panel and the button can never disagree.
##
## The NAV REFERENCE row is the one that matters. It picks the datum that
## altitude, heading, range and attitude are ALL measured against — see
## NavReference — and it reports what AUTO has resolved to, because "AUTO" on
## its own does not tell a pilot what their altimeter is counting from.

const ButtonTheme := preload("res://scenes/ui/ButtonTheme.gd")
const Instrument := preload("res://scenes/ui/Instrument.gd")

@export var accent: Color = Color(0.3, 0.9, 0.78)

## Room under the rows for the resolved-datum explanation.
const FOOTER_H := 92.0

var _ref_buttons: Dictionary = {}
var _band_buttons: Dictionary = {}
var _rate_buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	GameState.nav_reference_changed.connect(func(_id: String) -> void: _sync())
	GameState.tactical_band_changed.connect(func(_on: bool) -> void: _sync())
	GameState.rate_scale_changed.connect(func(_s: String) -> void: _sync())
	# The resolved datum moves on its own — an approach starting, a target
	# selected — without the SELECTION changing, so the footer has to follow the
	# shared tick rather than only the intents above.
	GameState.tick_changed.connect(func(_t: int) -> void: queue_redraw())
	_sync()


func _build() -> void:
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_bottom = -FOOTER_H
	outer.add_theme_constant_override("separation", ButtonTheme.TOUCH_SEP)
	add_child(outer)

	_ref_buttons = _add_row(outer, "NAV REFERENCE", GameState.NAV_REFERENCES,
			GameState.set_nav_reference)
	_band_buttons = _add_row(outer, "TACTICAL BAND", ["SHOW", "HIDE"],
			func(choice: String) -> void: GameState.set_tactical_band(choice == "SHOW"))
	_rate_buttons = _add_row(outer, "RATE SCALE", GameState.RATE_SCALES,
			GameState.set_rate_scale)


## One labelled row of mutually exclusive touch buttons.
func _add_row(parent: Control, label: String, choices: Array,
		intent: Callable) -> Dictionary:
	var caption := Label.new()
	caption.text = label
	caption.add_theme_font_size_override("font_size", Instrument.ANNOT)
	caption.add_theme_color_override("font_color", Color(accent, 0.7))
	parent.add_child(caption)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ButtonTheme.TOUCH_SEP)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(row)

	var out: Dictionary = {}
	for choice: String in choices:
		var btn := ButtonTheme.make_touch_button(accent)
		btn.text = _short_label(choice)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(intent.bind(choice))
		row.add_child(btn)
		out[choice] = btn
	return out


## The datum's own label is written for the band's legend and is too long for a
## button; AUTO and INERTIAL read fine as they are.
func _short_label(choice: String) -> String:
	match choice:
		"PAD":
			return "PLATFORM"
		"WRECK":
			return "DERELICT"
		"TARGET":
			return "TARGET"
	return choice


func _sync() -> void:
	for id: String in _ref_buttons:
		_mark(_ref_buttons[id], id == GameState.nav_reference)
	_mark(_band_buttons["SHOW"], GameState.tactical_band)
	_mark(_band_buttons["HIDE"], not GameState.tactical_band)
	for scale: String in _rate_buttons:
		_mark(_rate_buttons[scale], scale == GameState.rate_scale)
	queue_redraw()


func _mark(btn: Button, active: bool) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		btn.add_theme_stylebox_override(state,
				ButtonTheme.make_toggle_stylebox(accent, active, state.begins_with("hover")))
	btn.add_theme_color_override("font_color",
			Color(0.02, 0.06, 0.06) if active else accent)
	btn.add_theme_color_override("font_hover_color",
			Color(0.02, 0.06, 0.06) if active else accent.lightened(0.2))


## What the selection actually resolved to, and why. A pinned datum that has
## lost its fix reports the fallback it is holding instead of quietly reading
## from somewhere the pilot did not choose.
func _draw() -> void:
	var font := ThemeDB.fallback_font
	var d: Dictionary = NavReference.datum()
	var y := size.y - FOOTER_H + 24.0
	draw_line(Vector2(0, y - 18.0), Vector2(size.x, y - 18.0), Color(accent, 0.25), 1.0)

	var headline := "MEASURING FROM %s" % d["label"]
	var color := accent
	if d["fallback"]:
		headline = "NO FIX ON %s — HOLDING %s" % [
			NavReference.label_for(GameState.nav_reference), d["label"]]
		color = Instrument.WARN
	elif d["auto"]:
		headline = "AUTO — MEASURING FROM %s" % d["label"]
	draw_string(font, Vector2(Instrument.INSET, y), headline, HORIZONTAL_ALIGNMENT_LEFT,
			size.x - Instrument.INSET * 2.0, Instrument.HEADING, color)

	var detail := "ALT %+.1f M   HDG %03d   RNG %d M" % [
		NavReference.altitude(), roundi(NavReference.heading()),
		roundi(NavReference.range_to())]
	if d["fallback"]:
		detail = "%s. %s" % [d["reason"], detail]
	draw_string(font, Vector2(Instrument.INSET, y + Instrument.HEADING + 8.0), detail,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - Instrument.INSET * 2.0,
			Instrument.DETAIL, Color(accent, 0.65))
