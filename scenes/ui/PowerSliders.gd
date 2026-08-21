extends Control
## Power allocation panel for the MFD POWER page: one touch slider per channel,
## a bus readout (demand against the alternator's output, plus the battery and
## which way it is going), and the drive selector's position with both propellant
## tanks. Sliders call the set_power intent; Phase 4 systems read the delivered
## allocations: THRUST gates approach speed, CUTTER gates cutting, SENSORS gates
## structural-scan speed.
##
## The page shows SETTINGS and DELIVERY as two different things, because they are.
## A master switch off, or a load the alternator cannot carry, starves delivery
## and leaves every allocation exactly where the pilot put it.

@export var accent: Color = Color(0.3, 0.9, 0.78)

const OVER_BUDGET := Color(1.0, 0.35, 0.25)
const TouchSliderScript := preload("res://scenes/ui/TouchSlider.gd")

var _sliders: Dictionary = {}

@onready var _header: Label = %Header
@onready var _row: HBoxContainer = %Row
@onready var _propellant: Label = %Propellant


func _ready() -> void:
	_header.add_theme_font_size_override("font_size", 15)
	_propellant.add_theme_font_size_override("font_size", 15)
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
	GameState.battery_changed.connect(func(_f: float) -> void: _sync())
	GameState.propellant_changed.connect(_sync_propellant)
	GameState.drive_mode_changed.connect(func(_m: String) -> void: _sync())
	_sync()
	_sync_propellant()


## Sliders show the SETTING at the handle and the delivered figure inside it. A
## starved bus never moves a handle: the allocation is what the pilot asked for
## and only the ship's ability to honour it changes.
func _sync() -> void:
	var power: Dictionary = GameState.local_ship()["power"]
	for channel: String in _sliders:
		# Setting .value doesn't re-emit user_changed_value, so no feedback loop.
		_sliders[channel].value = GameState.power_target(channel)
		_sliders[channel].delivered = power[channel]
	var demand := GameState.electrical_demand()
	var supply := GameState.electrical_supply()
	var flow := GameState.battery_flow()
	var short := demand > supply
	# What the bus is doing, in the order that matters to a pilot reading it: dead
	# first, then unbuffered, then which way the battery is going.
	var note := ""
	if supply <= 0.0 and (not GameState.master_bat or GameState.battery_charge <= 0.0):
		note = "  — SHIP DARK"
	elif supply <= 0.0:
		note = "  — ON BATTERY"
	elif not GameState.master_bat:
		note = "  — NO BUFFER" + ("  (SHEDDING)" if short else "")
	elif flow < -0.001:
		note = "  — DISCH %.1f" % -flow
	elif flow > 0.001:
		note = "  — CHG %.1f" % flow
	_header.text = "POWER  %.1f / %.1f   BAT %d%%%s" % [
			demand, GameState.power_budget(),
			roundi(GameState.battery_fraction() * 100.0), note]
	_header.add_theme_color_override("font_color", OVER_BUDGET if short else accent)


## The propellant readout under the sliders. LH2 is the fusion reactor's working
## fluid as well as the drive's, so the tanks belong on the ship's systems page
## rather than on a page of their own.
func _sync_propellant() -> void:
	var boost := "  BOOST" if GameState.boosting() else ""
	_propellant.text = "DRIVE %s     LH2 %d%%     LOX %d%%%s" % [
			GameState.drive_mode,
			roundi(GameState.lh2_fraction() * 100.0),
			roundi(GameState.lox_fraction() * 100.0), boost]
	# The dry-hydrogen case is the one that costs thrust AND raises the draw, so
	# it gets the same red the overdraw does.
	_propellant.add_theme_color_override("font_color",
			OVER_BUDGET if GameState.lh2_fuel <= 0.0 else accent)
