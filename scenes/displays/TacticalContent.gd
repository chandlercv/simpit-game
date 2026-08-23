extends Control
## Read-only Tactical display: a glass-cockpit instrument band framing one of two
## selectable modes.
##   SCOPE — sensor scope + hull-damage heatmap + structural-risk meter.
##   CHART — the system star chart (mouse pan/zoom).
##
## Everything here is an instrument you READ. There are no buttons: the controls
## that used to live on Tactical — sensor mode, approach/cut, contact locking,
## cut-target selection — moved to the MFD, and the SCOPE/CHART tabs that
## outlasted them are gone too. Mode is stepped with a mapped control
## (tactical_view_cycle), the navigation datum with nav_ref_cycle, and anything
## else these instruments need is on the MFD SETTINGS page. The mode still shows
## on the band's legend — it reports the mode, it does not offer it.
##
## State is shared through GameState, so whatever drives those intents is
## reflected here automatically.

const TacticalScopeScript := preload("res://scenes/ui/TacticalScope.gd")
const HullHeatmapScript := preload("res://scenes/ui/HullHeatmap.gd")
const RiskMeterScript := preload("res://scenes/ui/RiskMeter.gd")
const StarChartScript := preload("res://scenes/ui/StarChart.gd")
const InstrumentBandScript := preload("res://scenes/ui/InstrumentBand.gd")

const MODES: Array[String] = ["SCOPE", "CHART"]

@export var accent: Color = Color(1.0, 0.72, 0.2)

var _panels: Dictionary = {}
var _current := ""
var _band: Control
## The mode panels live in here; its margins are the band's reserves, so hiding
## the band hands the scope the whole display back rather than leaving a hole.
var _content: MarginContainer


func _ready() -> void:
	_build()
	# Mode is shared GameState (TacticalContent is one of possibly several views
	# of it), so a mapped HOTAS button — GameState.cycle_tactical_view — and any
	# other view stay in agreement. We mirror the resulting state.
	GameState.tactical_view_changed.connect(show_mode)
	GameState.tactical_band_changed.connect(_apply_band)
	show_mode(GameState.tactical_view)
	_apply_band(GameState.tactical_band)


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_content = MarginContainer.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	_panels["SCOPE"] = _build_scope()
	_panels["CHART"] = _build_chart()
	for mode: String in MODES:
		# Both modes draw past their own bounds — the chart pans and zooms
		# freely, the scope labels its blips at their edges. That was invisible
		# while a mode had the whole display; with the band framing it, an
		# unclipped panel writes over the instruments.
		_panels[mode].clip_contents = true
		_content.add_child(_panels[mode])

	# The band draws over the panels rather than beside them: it is chrome, it
	# is mouse-transparent, and the margins above are what actually keeps the
	# instruments clear of it.
	_band = InstrumentBandScript.new()
	_band.accent = accent
	_band.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_band)


## Show or hide the band, and give the mode panels back the room either way.
func _apply_band(shown: bool) -> void:
	if _band == null or _content == null:
		return
	_band.visible = shown
	var pad := 6.0
	_content.add_theme_constant_override("margin_left",
			roundi(InstrumentBandScript.FLIGHT_W + pad) if shown else 0)
	_content.add_theme_constant_override("margin_top",
			roundi(InstrumentBandScript.HDG_H + pad) if shown else 0)
	_content.add_theme_constant_override("margin_right", 0)
	_content.add_theme_constant_override("margin_bottom",
			roundi(InstrumentBandScript.BOTTOM_H + pad) if shown else 0)


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
	if _band != null:
		_band.queue_redraw()


func current_mode() -> String:
	return _current
