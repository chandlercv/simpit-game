extends RefCounted
## Shared bordered/tinted StyleBoxFlat builders so hover alpha and content
## margins stay consistent across OpsBar, MarketPanel, and SensorModeBar.

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
