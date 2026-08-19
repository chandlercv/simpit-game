extends RefCounted
## Shared bordered/tinted StyleBoxFlat builders so hover alpha and content
## margins stay consistent across OpsBar, MarketPanel, and SensorModeBar.

## Touch targets on the MFD panel, in the MFD window's 1280x800 virtual canvas.
## The MFDs are worked with a finger on a screen small enough that the canvas is
## scaled down, so a button sized for a mouse lands under a fingertip. These are
## what make_touch_button() applies; make_button() is unchanged, which is what
## keeps the mouse-driven displays (Tactical, title card, remapper) as they were.
const TOUCH_MIN_H := 56.0
const TOUCH_MARGIN := 14
const TOUCH_FONT := 18
## Gap to leave between adjacent touch targets, so a near-miss hits nothing
## rather than hitting the neighbour.
const TOUCH_SEP := 12


## make_button sized for a fingertip. Returns a plain Button like make_button
## does, so it drops into any call site unchanged.
static func make_touch_button(color: Color) -> Button:
	var button := make_button(color, TOUCH_MARGIN)
	button.custom_minimum_size = Vector2(0, TOUCH_MIN_H)
	button.add_theme_font_size_override("font_size", TOUCH_FONT)
	return button


static func make_button(color: Color, content_margin := 8) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(color, 0.08)
	normal.border_color = Color(color, 0.5)
	normal.set_border_width_all(1)
	normal.set_content_margin_all(content_margin)
	var hover := normal.duplicate()
	hover.bg_color = Color(color, 0.16)
	var disabled := normal.duplicate()
	disabled.border_color = Color(color, 0.2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", color.lightened(0.2))
	button.add_theme_color_override("font_disabled_color", Color(color, 0.35))
	return button


static func make_toggle_stylebox(color: Color, active: bool, hovering := false, content_margin := 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color if active else Color(color, 0.16 if hovering else 0.08)
	style.border_color = color if active else Color(color, 0.5)
	style.set_border_width_all(1)
	style.set_content_margin_all(content_margin)
	return style
