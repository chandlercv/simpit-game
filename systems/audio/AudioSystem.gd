extends Node
## Everything the pilot hears, and the one place that decides when.
##
## Registered LAST in project.godot's autoload list, after NavReference: audio
## reports on settled state and must never be the reason a system ran early. It
## is an autoload rather than a node in any window because audio is
## process-global — the project runs one native OS window per monitor
## (`embed_subwindows=false`), so a per-window player would be wrong four times
## over.
##
## The design rule, stated once and then obeyed everywhere:
##
##   Outside the pressure hull there is no air, so nothing out there radiates
##   sound to you. What you hear is either CONDUCTED through the frame, or it is
##   the cabin's own air. The buses below apply that difference; SoundBank
##   decides which path each clip took.
##
## What follows from it is the best thing in here: the ventilation is the only
## continuous airborne machine on the ship, so when the LIFE channel dies the
## room goes silent and a gear clunk still comes through the frame. Nothing else
## sells vacuum half as well, and it costs one line of gain.
##
## Two kinds of source, and they are handled differently:
##
##   ONE-SHOT   fired and forgotten, from a small round-robin pool. Events.
##   HELD       a dedicated player per continuous machine, faded toward a target
##              gain every frame by _hold(). States, not events.
##
## Cut start, cut abort and the thruster axes are POLLED rather than signalled.
## They need a per-frame parameter pass regardless — a cut has a progress, a
## thruster has a magnitude — so reading the edge off the same poll costs
## nothing and leaves SalvageSystem and ShipMotion untouched. This is what
## CuttingBeam.gd already does with the same state.

const SoundBankScript := preload("res://systems/audio/SoundBank.gd")
const SpeechScript := preload("res://systems/audio/Speech.gd")

## Where the mixer settings live, beside the display and input configs.
const CONFIG_PATH := "user://audio.cfg"

## One-shot voices. Twelve is comfortably past the worst honest pile-up (three
## staggered gear clunks over a running drive, a cutter, and an alert).
const POOL_SIZE := 12

## How quickly a held loop reaches a new target gain, in units per second. Fast
## enough that a thruster feels immediate, slow enough that nothing zippers.
const FADE_RATE := 8.0

## Below this linear gain a held loop is stopped outright rather than left
## running at an inaudible level burning a voice.
const SILENCE := 0.001

## Shortest gap between two RCS pops, seconds. Without it, an axis held against
## its stop retriggers every frame and the valves sound like a sewing machine.
const RCS_REPEAT := 0.06

## The buses, and why each exists. Volumes are the pilot's, set on the MFD
## SETTINGS page and persisted; the EFFECTS are the physics and are not adjustable.
const BUSES: Array[Dictionary] = [
	{"name": SoundBankScript.BUS_CABIN, "send": "Master"},
	{"name": SoundBankScript.BUS_ALERTS, "send": SoundBankScript.BUS_CABIN},
	{"name": SoundBankScript.BUS_SIDETONE, "send": SoundBankScript.BUS_CABIN},
	{"name": SoundBankScript.BUS_STRUCTURE, "send": "Master"},
	{"name": SoundBankScript.BUS_RADIO, "send": "Master"},
]

## Buses the pilot can set a level for, in the order the SETTINGS page shows them.
const MIXER_BUSES: Array[String] = [
	"Master",
	SoundBankScript.BUS_CABIN,
	SoundBankScript.BUS_STRUCTURE,
	SoundBankScript.BUS_RADIO,
	SoundBankScript.BUS_ALERTS,
]

signal mixer_changed()

var _pool: Array[AudioStreamPlayer] = []
var _next_voice := 0
## clip name -> held player, and clip name -> its current linear gain.
var _held: Dictionary = {}
var _gain: Dictionary = {}
var _levels: Dictionary = {}
var _muted := false
var _speech: Node = null

# --- Edge-detection state for the polled machines -----------------------------
var _was_cutting := false
var _was_aligning := false
## The voice the capacitor charge went to, so the contactor can cut it short.
var _charge_player: AudioStreamPlayer = null
var _was_drive_live := false
var _was_drive_starting := false
var _axis_active: Array[bool] = [false, false, false, false, false, false]
var _rcs_cooldown := 0.0
var _pop_index := 0
## True while the part is on a stop, so the arrival clunk fires once per travel
## rather than every frame the position sits at 0.0 or 1.0.
var _gear_settled := true
var _hatch_settled := true
## Set while DockingSystem teleports the gear onto a berth, so the spawn does not
## sound like a gear cycle that never happened.
var _suppress_gear_until := 0.0


func _ready() -> void:
	_build_buses()
	_build_pool()
	_speech = SpeechScript.new()
	_speech.name = "Speech"
	add_child(_speech)
	_load_mixer()
	_connect_signals()


## --- Buses ------------------------------------------------------------------


## Built in code rather than loaded from a bus layout resource so that every
## filter figure sits beside the reason it has that value. A hand-edited .tres
## would be a second, silent copy of numbers the handbook quotes.
func _build_buses() -> void:
	for spec: Dictionary in BUSES:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, spec["name"])
		AudioServer.set_bus_send(idx, spec["send"])

	# STRUCTURE — the hull itself. A sound that reached you through the frame has
	# lost its top end and picked up the frame's ring on the way, so it is
	# lowpassed hard and given a short, dense, metallic tail. Doing this ONCE
	# here is what lets build_sfx.py author every mechanical clip clean: change
	# the cabin's acoustic state and you tilt one bus, not thirty files.
	var structure := AudioServer.get_bus_index(SoundBankScript.BUS_STRUCTURE)
	var conducted := AudioEffectLowPassFilter.new()
	conducted.cutoff_hz = 900.0
	conducted.resonance = 0.2
	AudioServer.add_bus_effect(structure, conducted)
	var frame := AudioEffectReverb.new()
	frame.room_size = 0.35     # a compartment, not a hall
	frame.damping = 0.7
	frame.spread = 0.4
	frame.wet = 0.22
	frame.dry = 1.0
	frame.predelay_msec = 6.0  # the frame answers almost immediately
	AudioServer.add_bus_effect(structure, frame)

	# RADIO — somebody else's voice, arriving over a channel that is 300–3400 Hz
	# and nothing else. The band is the reason a radio sounds like a radio; the
	# compressor is the reason every station is the same loudness however far off
	# it is.
	var radio := AudioServer.get_bus_index(SoundBankScript.BUS_RADIO)
	var low_cut := AudioEffectHighPassFilter.new()
	low_cut.cutoff_hz = 300.0
	AudioServer.add_bus_effect(radio, low_cut)
	var high_cut := AudioEffectLowPassFilter.new()
	high_cut.cutoff_hz = 3400.0
	AudioServer.add_bus_effect(radio, high_cut)
	var grit := AudioEffectDistortion.new()
	grit.mode = AudioEffectDistortion.MODE_CLIP
	grit.pre_gain = 4.0
	grit.drive = 0.18
	grit.post_gain = -5.0
	AudioServer.add_bus_effect(radio, grit)
	var leveller := AudioEffectCompressor.new()
	leveller.threshold = -18.0
	leveller.ratio = 6.0
	leveller.attack_us = 2000.0
	leveller.release_ms = 120.0
	leveller.gain = 6.0
	AudioServer.add_bus_effect(radio, leveller)

	# SIDETONE — your own transmission, in your own headset. It never went over
	# the air, so it keeps its body: a gentle low cut and nothing else.
	var sidetone := AudioServer.get_bus_index(SoundBankScript.BUS_SIDETONE)
	var thin := AudioEffectHighPassFilter.new()
	thin.cutoff_hz = 180.0
	AudioServer.add_bus_effect(sidetone, thin)

	# CABIN and ALERTS get no effects at all. They are the air you are sitting
	# in, heard directly, and the annunciator is deliberately the only unfiltered
	# thing on the ship — that is what makes it cut through everything else.


func _build_pool() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "OneShot%d" % i
		add_child(player)
		_pool.append(player)


## --- Mixer ------------------------------------------------------------------


func _load_mixer() -> void:
	for bus: String in MIXER_BUSES:
		_levels[bus] = 1.0
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		for bus: String in MIXER_BUSES:
			_levels[bus] = clampf(float(cfg.get_value("mixer", bus, 1.0)), 0.0, 1.0)
		_muted = bool(cfg.get_value("mixer", "muted", false))
	_apply_mixer()


func _apply_mixer() -> void:
	for bus: String in MIXER_BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var level: float = _levels[bus]
		# linear_to_db of 0 is -inf; mute the bus outright instead so the mixer's
		# bottom position is silence rather than a very quiet sound.
		AudioServer.set_bus_mute(idx, level <= 0.0 or (_muted and bus == "Master"))
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(level, 0.0001)))
	mixer_changed.emit()


func _save_mixer() -> void:
	var cfg := ConfigFile.new()
	for bus: String in MIXER_BUSES:
		cfg.set_value("mixer", bus, _levels[bus])
	cfg.set_value("mixer", "muted", _muted)
	cfg.save(CONFIG_PATH)


## Set one bus's level, 0..1. The MFD SETTINGS page calls this.
func set_level(bus: String, level: float) -> void:
	if not _levels.has(bus):
		return
	_levels[bus] = clampf(level, 0.0, 1.0)
	_apply_mixer()
	_save_mixer()


func level(bus: String) -> float:
	return float(_levels.get(bus, 1.0))


func muted() -> bool:
	return _muted


## Master mute. A simpit runs at odd hours; this has to be reachable by touch.
func set_muted(on: bool) -> void:
	_muted = on
	_apply_mixer()
	_save_mixer()
	GameState.post_comms("SYSTEM", "AUDIO %s" % ("MUTED" if on else "RESTORED"))


func toggle_mute() -> void:
	set_muted(not _muted)


## --- Playback primitives ----------------------------------------------------


## Fire a clip once from the pool. `gain` is linear, `pitch` a ratio.
##
## Returns the voice it went to, for the rare caller that needs to cut a long
## one-shot short — the capacitor charge, when the contactor closes before the
## bank has finished filling. Ignore it otherwise.
func play(clip: String, gain := 1.0, pitch := 1.0) -> AudioStreamPlayer:
	var stream := SoundBankScript.stream(clip)
	if stream == null or gain <= SILENCE:
		return null
	var player := _pool[_next_voice]
	_next_voice = (_next_voice + 1) % POOL_SIZE
	player.stream = stream
	player.bus = SoundBankScript.bus_of(clip)
	player.volume_db = linear_to_db(clampf(gain, SILENCE, 4.0))
	player.pitch_scale = clampf(pitch, 0.05, 4.0)
	player.play()
	return player


## Hold a looping clip at a target gain. Starts it when it first becomes
## audible, stops it when it fades out, and glides between the two — so every
## continuous machine on the ship is one call per frame and no state of its own.
func _hold(clip: String, target: float, delta: float, pitch := 1.0) -> void:
	var current: float = _gain.get(clip, 0.0)
	current = move_toward(current, clampf(target, 0.0, 4.0), FADE_RATE * delta)
	_gain[clip] = current

	var player: AudioStreamPlayer = _held.get(clip)
	if current <= SILENCE:
		if player != null and player.playing:
			player.stop()
		return
	if player == null:
		var stream := SoundBankScript.stream(clip)
		if stream == null:
			return
		player = AudioStreamPlayer.new()
		player.name = "Held_" + clip
		player.stream = stream
		player.bus = SoundBankScript.bus_of(clip)
		add_child(player)
		_held[clip] = player
	if not player.playing:
		player.play()
	player.volume_db = linear_to_db(current)
	player.pitch_scale = clampf(pitch, 0.05, 4.0)


## --- Signals ----------------------------------------------------------------


func _connect_signals() -> void:
	GameState.landing_gear_changed.connect(_on_gear_lever)
	GameState.cargo_hatch_changed.connect(_on_hatch_lever)
	GameState.hull_impact.connect(_on_hull_impact)
	GameState.ship_contact.connect(_on_ship_contact)
	GameState.rival_cut_fired.connect(_on_rival_cut)
	GameState.drive_mode_changed.connect(_on_drive_mode)
	AlertSystem.alert_raised.connect(_on_alert_raised)


## The lever moving is the pilot's decision; the travel and the stops are the
## machine's answer, and those are driven from position in _update_gear.
func _on_gear_lever(_down: bool) -> void:
	pass


func _on_hatch_lever(open: bool) -> void:
	# The hold's air crosses the bulkhead the moment the door cracks, not when it
	# finishes travelling — so this one hangs off the lever, unlike the latches.
	play("hatch_vent_out" if open else "hatch_repress", 0.8)


func _on_hull_impact(_section: String, amount: float) -> void:
	play("impact_hard", clampf(0.5 + amount * 2.0, 0.5, 1.0))


func _on_ship_contact(_body: String, closing: float) -> void:
	# Anything hard enough to damage the hull already sounded through
	# hull_impact; this is the scrape that did not.
	if closing < 0.5:
		return
	play("impact_soft", clampf(closing / 6.0, 0.2, 1.0), randf_range(0.92, 1.08))


func _on_rival_cut(_from: Vector3, _to: Vector3) -> void:
	# Someone else's torch, at distance, through nothing. You get the contactor
	# and none of the work.
	play("cutter_ignite", 0.25, 0.8)


func _on_drive_mode(mode: String) -> void:
	if mode == "OFF":
		return
	# Selecting a detent is a switch under your hand, not a machine outside.
	play("mic_click_on", 0.3, 0.7)


func _on_alert_raised(_id: String, level: String) -> void:
	match level:
		AlertSystem.CAUTION:
			play("alert_caution", 0.8)
		AlertSystem.NOTE:
			play("alert_note", 0.7)
		# WARNING is held, not fired — see _update_alerts.


## --- The per-frame parameter pass -------------------------------------------


func _process(delta: float) -> void:
	_update_ventilation(delta)
	_update_gear(delta)
	_update_hatch(delta)
	_update_cutter(delta)
	_update_drive(delta)
	_update_thrusters(delta)
	_update_alerts(delta)


## The bed. Level and brightness follow the LIFE channel actually delivered, so
## starving the bus or opening it takes the room down with it. The pitch drop is
## the fan losing revs, not a filter — a fan on a sagging bus runs slower.
func _update_ventilation(delta: float) -> void:
	var supply := 0.0
	if GameState.bus_live():
		supply = clampf(GameState.power("LIFE") * GameState.delivery_fraction(), 0.0, 1.0)
	_hold("vent_loop", 0.55 * supply, delta, 0.85 + 0.15 * supply)


## Three legs winding out, and three arriving. The stops are taken off POSITION
## rather than the lever, because the lever is a decision and the downlock is an
## event three seconds later.
func _update_gear(delta: float) -> void:
	var pos := GameState.gear_position
	var travelling := pos > 0.0 and pos < 1.0
	_hold("gear_travel_loop", 0.5 if travelling else 0.0, delta)

	if Time.get_ticks_msec() / 1000.0 < _suppress_gear_until:
		return
	if travelling:
		_gear_settled = false
	elif not _gear_settled:
		_gear_settled = true
		play("gear_lock_down" if pos >= 1.0 else "gear_lock_up", 0.9)



## The leadscrew, and the door reaching its stop. The air is elsewhere — it goes
## through the bulkhead on the lever, in _on_hatch_lever.
func _update_hatch(delta: float) -> void:
	var pos := GameState.hatch_position
	var travelling := pos > 0.0 and pos < 1.0
	_hold("hatch_travel_loop", 0.5 if travelling else 0.0, delta)

	if travelling:
		_hatch_settled = false
	elif not _hatch_settled:
		_hatch_settled = true
		play("hatch_latch_open" if pos >= 1.0 else "hatch_latch_close", 0.9)



## The torch, polled. Firing in vacuum is a sequence — charge, contactor, work,
## and a pump that runs on after you let go — so the clips are sequenced off the
## same state CuttingBeam.gd draws the beam from.
func _update_cutter(delta: float) -> void:
	var cutting: bool = GameState.wreck.get("cutting_id", -1) != -1
	var aligning := GameState.align_state == "ALIGNING"

	# Pressing the trigger starts the bank charging and opens the alignment
	# together, so the spool runs underneath the aim rather than ahead of it.
	if aligning and not _was_aligning:
		_charge_player = play("cutter_charge", 0.55)
	_was_aligning = aligning

	if cutting and not _was_cutting:
		# The contactor closing ends the charge, whether or not the bank had
		# finished filling. A commit on a short alignment must not leave the
		# spool whining on underneath the cut.
		_stop_charge()
		play("cutter_ignite", 0.9)
	elif _was_cutting and not cutting:
		play("cutter_stop", 0.8)
	_was_cutting = cutting

	# An abandoned alignment lets the bank down too — nothing is going to be
	# fired with it, so the spool stops rather than finishing to a ready note.
	if not aligning and not cutting:
		_stop_charge()

	# The targeting beam holds while you line up, and gives way to the work.
	var align_quality: float = GameState.align.get("quality", 0.0) if aligning else 0.0
	_hold("cutter_align_loop", 0.0 if cutting else (0.45 * (0.5 + 0.5 * align_quality)),
			delta, 0.95 + 0.1 * align_quality)

	# Cutting: the crackle thickens as the cut bites deeper into the member.
	var progress: float = GameState.wreck.get("cut_progress", 0.0) if cutting else 0.0
	_hold("cutter_loop", 0.75 if cutting else 0.0, delta, 0.92 + 0.16 * progress)


## Let the capacitor bank down, if it is still spooling.
##
## The charge is a one-shot from the shared pool, and the pool round-robins: over
## three and a half seconds a dozen other sounds can come and go, and the voice
## the charge started on may since have been handed to a gear clunk. So check
## what is actually on that voice before stopping it — otherwise committing a cut
## silences whatever unrelated sound happened to inherit the slot.
func _stop_charge() -> void:
	if _charge_player == null:
		return
	if _charge_player.playing \
			and _charge_player.stream == SoundBankScript.stream("cutter_charge"):
		_charge_player.stop()
	_charge_player = null


## The drive: a ten-second crank that rises, the moment it catches, and then a
## rumble that follows how hard it is being worked. drive_start_time is the
## ship's figure, so a hull that cranks longer sounds like it.
func _update_drive(delta: float) -> void:
	var starting := GameState.drive_starting()
	var served := 0.0
	if GameState.ship_def.drive_start_time > 0.0:
		served = clampf(GameState.drive_start_progress()
				/ GameState.ship_def.drive_start_time, 0.0, 1.0)
	# One short loop played at a rising pitch, rather than a ten-second file.
	_hold("drive_crank_loop", 0.6 if starting else 0.0, delta, 0.55 + 0.45 * served)
	if _was_drive_starting and not starting and served >= 1.0:
		play("drive_catch", 0.85)
	_was_drive_starting = starting

	var live := GameState.drive_live()
	if _was_drive_live and not live:
		play("drive_shutdown", 0.8)
	_was_drive_live = live

	if not live:
		_hold("drive_loop", 0.0, delta)
		return
	# Idling stages still turn; load is what you hear on top of them.
	var load := ShipMotion.drive_load()
	var stages := GameState.thrust_fraction()
	var gain := 0.22 + 0.55 * load * maxf(stages, 0.2)
	if GameState.boosting():
		gain *= 1.25
	_hold("drive_loop", gain, delta, 0.88 + 0.22 * load)


## RCS: a valve cracking per axis, then the reaction load through the mounts
## while it fires. The plume is silent — it is in vacuum — so a pop and a rumble
## is the whole of it.
func _update_thrusters(delta: float) -> void:
	_rcs_cooldown = maxf(_rcs_cooldown - delta, 0.0)
	var thrust := ShipMotion.command_thrust()
	var rot := ShipMotion.command_rotation()
	var axes: Array[float] = [thrust.x, thrust.y, thrust.z, rot.x, rot.y, rot.z]

	var held := 0.0
	for i in axes.size():
		var amount: float = absf(axes[i])
		var active := amount > ShipMotion.CMD_DEADBAND
		held = maxf(held, amount if active else 0.0)
		if active and not _axis_active[i] and _rcs_cooldown <= 0.0:
			# Round-robin the variants: one sample retriggering reads as a fault,
			# not as a thruster.
			play(SoundBankScript.RCS_POPS[_pop_index], clampf(0.35 + amount * 0.5, 0.3, 0.9),
					randf_range(0.94, 1.06))
			_pop_index = (_pop_index + 1) % SoundBankScript.RCS_POPS.size()
			_rcs_cooldown = RCS_REPEAT
		_axis_active[i] = active

	# The main drive already carries the throttle; this is the manoeuvring load
	# only, so it fades out as the drive note comes up.
	_hold("rcs_hold_loop", 0.30 * held, delta, 0.9 + 0.2 * held)


## WARNING is the only held alert: it repeats for as long as the condition
## applies and stops when it clears, which is the entire point of latching them.
## CAUTION and NOTE fire once, in _on_alert_raised.
func _update_alerts(delta: float) -> void:
	_hold("alert_warning_loop", 0.7 if AlertSystem.has_warning() else 0.0, delta)


## --- Radio ------------------------------------------------------------------


## Suppress the gear cycle a berth spawn would otherwise fake, for one second.
## DockingSystem sets gear_position directly when it puts the ship on a pad; the
## legs did not travel and must not be heard to.
func suppress_gear_cycle() -> void:
	_suppress_gear_until = Time.get_ticks_msec() / 1000.0 + 1.0
	_gear_settled = true


## The speech layer, for callers that want to say something explicitly.
func speech() -> Node:
	return _speech


## Key the mic and say one of the pilot's own lines (data/speech/lines.json).
## Every other voice in the game is read off a comms line that some system had
## already written; these are the only ones the pilot originates, so they are the
## only ones a call site has to ask for by name.
func transmit(key: String) -> void:
	play("mic_click_on", 0.4)
	if _speech != null:
		_speech.transmit(key)
