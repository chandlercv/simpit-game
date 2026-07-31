extends Control
## Read-only Tactical display with two selectable modes:
##   SCOPE — sensor scope + hull-damage heatmap + structural-risk meter.
##   CHART — the system star chart (mouse pan/zoom).
## Everything here is an instrument you READ. The controls that used to live on
## Tactical — sensor mode, approach/cut, contact locking, and cut-target
## selection — moved to the MFD, so the scope is no longer clickable; it only
## draws. State is shared through GameState, so the MFD driving those intents is
## reflected here automatically.

const TacticalScopeScript := preload("res://scenes/ui/TacticalScope.gd")
const HullHeatmapScript := preload("res://scenes/ui/HullHeatmap.gd")
const RiskMeterScript := preload("res://scenes/ui/RiskMeter.gd")
const StarChartScript := preload("res://scenes/ui/StarChart.gd")
const ButtonTheme := preload("res://scenes/ui/ButtonTheme.gd")

const MODES: Array[String] = ["SCOPE", "CHART"]

@export var accent: Color = Color(1.0, 0.72, 0.2)

var _panels: Dictionary = {}
var _buttons: Dictionary = {}
var _current := ""


func _ready() -> void:
	_build()
	# Mode is shared GameState (TacticalContent is one of possibly several views of
	# it), so a mapped HOTAS button — GameState.cycle_tactical_view — and the tabs
	# stay in agreement. Tabs call the intent; we mirror the resulting state.
	GameState.tactical_view_changed.connect(show_mode)
	show_mode(GameState.tactical_view)


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	outer.add_child(bar)
	var caption := Label.new()
	caption.text = "VIEW"
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", Color(accent, 0.7))
	bar.add_child(caption)
	for mode: String in MODES:
		var btn := Button.new()
		btn.text = mode
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(170, 46)
		btn.add_theme_font_size_override("font_size", 18)
		# Bright, clearly-bordered inactive tab (the old 8%-fill/dark-text style was
		# nearly invisible under the scanline overlay); solid fill when active.
		btn.add_theme_stylebox_override("normal", _tab_style(false, false))
		btn.add_theme_stylebox_override("hover", _tab_style(false, true))
		btn.add_theme_stylebox_override("pressed", _tab_style(true, false))
		btn.add_theme_stylebox_override("hover_pressed", _tab_style(true, false))
		btn.add_theme_color_override("font_color", accent)
		btn.add_theme_color_override("font_hover_color", accent.lightened(0.3))
		btn.add_theme_color_override("font_pressed_color", Color(0.06, 0.04, 0.0))
		btn.add_theme_color_override("font_hover_pressed_color", Color(0.06, 0.04, 0.0))
		btn.pressed.connect(GameState.set_tactical_view.bind(mode))
		bar.add_child(btn)
		_buttons[mode] = btn

	var content := MarginContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(content)
	_panels["SCOPE"] = _build_scope()
	_panels["CHART"] = _build_chart()
	for mode: String in MODES:
		content.add_child(_panels[mode])


func _tab_style(active: bool, hovering: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if active:
		style.bg_color = accent
	else:
		style.bg_color = Color(accent, 0.22 if hovering else 0.14)
	style.border_color = accent
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	return style


func _build_scope() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	# Hull status on the left: heatmap + structural-risk meter.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)

	var heatmap := HullHeatmapScript.new()
	heatmap.accent = accent
	heatmap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	heatmap.size_flags_stretch_ratio = 1.6
	left.add_child(heatmap)

	var risk := RiskMeterScript.new()
	risk.accent = accent
	left.add_child(risk)

	# Scope on the right (the larger pane).
	var scope := TacticalScopeScript.new()
	scope.accent = accent
	scope.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scope.size_flags_stretch_ratio = 1.8
	row.add_child(scope)
	return row


func _build_chart() -> Control:
	var chart := StarChartScript.new()
	# The chart keeps its own cool-blue accent for readability.
	return chart


func show_mode(mode: String) -> void:
	if not _panels.has(mode):
		return
	_current = mode
	for m: String in _panels:
		_panels[m].visible = (m == mode)
	for m: String in _buttons:
		_buttons[m].button_pressed = (m == mode)


func current_mode() -> String:
	return _current
