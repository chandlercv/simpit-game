extends Control
## Power allocation panel for the tablet: one touch slider per channel plus a
## reactor budget readout that goes red when the summed allocation exceeds
## the ship's power budget. Sliders call the set_power intent; Phase 4 systems
## read the allocations: THRUST gates approach speed, CUTTER gates cutting,
## SENSORS gates structural-scan speed.

@export var accent: Color = Color(0.3, 0.9, 0.78)

const OVER_BUDGET := Color(1.0, 0.35, 0.25)
const TouchSliderScript := preload("res://scenes/ui/TouchSlider.gd")

var _sliders: Dictionary = {}

@onready var _header: Label = %Header
@onready var _row: HBoxContainer = %Row


func _ready() -> void:
	_header.add_theme_font_size_override("font_size", 15)
	for channel in GameState.POWER_CHANNELS:
		var slider: Control = TouchSliderScript.new()
		slider.accent = accent
		slider.label = channel
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slider.user_changed_value.connect(
				func(v: float) -> void: GameState.set_power(channel, v))
		_row.add_child(slider)
		_sliders[channel] = slider
	GameState.power_changed.connect(_sync)
	_sync()


func _sync() -> void:
	var power: Dictionary = GameState.local_ship()["power"]
	for channel: String in _sliders:
		# Setting .value doesn't re-emit user_changed_value, so no feedback loop.
		_sliders[channel].value = power[channel]
	var total := GameState.power_total()
	var over := total > GameState.power_budget()
	_header.text = "POWER  %.1f / %.1f%s" % [
		total, GameState.power_budget(), "  — REACTOR OVERDRAW" if over else ""]
	_header.add_theme_color_override("font_color", OVER_BUDGET if over else accent)
