extends Node
## Headless checks for the ship's sound and speech:
##  - every clip SoundBank names resolves to a file, and every bus it names
##    exists on the mixer;
##  - the voice bank still covers the lines the CODE writes — driven by real
##    intents, not by transcribed strings, so editing a comms line without
##    rebuilding the bank fails here rather than going quiet in flight;
##  - numbers are spoken the way a harbour speaks them;
##  - the harbour uses the full tail number on first contact and abbreviates
##    after, and starts again at the next pattern;
##  - alerts LATCH: a condition held across a threshold raises exactly once,
##    which is the whole reason AlertSystem exists;
##  - the cargo door travels rather than teleporting, and its two predicates
##    disagree while it is moving.
##
##   godot --headless res://tools/AudioSmoke.tscn
##
## Nothing here listens. Headless Godot runs a dummy audio driver, so playback
## is silent and every assertion below is state: which clips WOULD be played,
## which conditions ARE standing. That is also why the speech checks call
## Speech.clips_for() instead of waiting on the queue, which runs in real time
## and would make this test thirty seconds long for no extra confidence.

const SoundBankScript := preload("res://systems/audio/SoundBank.gd")

var _failures: Array[String] = []
var _speech: Node = null


func _ready() -> void:
	Engine.time_scale = 10.0
	Engine.physics_ticks_per_second = roundi(60.0 * Engine.time_scale)
	InputRouter.set_process(false)
	# A live switch panel on a dev box would otherwise work the COWL and GEAR
	# levers out from under the travel checks below.
	for child in InputRouter.get_children():
		child.set_process(false)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	_speech = AudioSystem.speech()

	_test_bank()
	_test_buses()
	_test_bank_integrity()
	await _test_hatch_travel()
	await _test_lines_are_sayable()
	_test_hush_while_cutting()
	_test_numbers()
	_test_callsign()
	await _test_alerts_latch()
	_test_mixer()

	if _failures.is_empty():
		print("AUDIO SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("AUDIO SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


# --- The bank ---------------------------------------------------------------

## Every name in the table resolves. This is the check that catches a renamed or
## deleted clip, which is otherwise completely silent at runtime.
func _test_bank() -> void:
	var missing: Array[String] = []
	for clip: String in SoundBankScript.clip_names():
		if SoundBankScript.stream(clip) == null:
			missing.append(clip)
	_check(missing.is_empty(), "every SoundBank clip resolves (missing: %s)"
			% (", ".join(missing) if not missing.is_empty() else "none"))
	_check(SoundBankScript.clip_names().size() >= 25,
			"the bank is populated (%d clips)" % SoundBankScript.clip_names().size())

	# Looping clips must actually be marked looping, or a held machine stops
	# after one pass and the ship goes quiet mid-travel.
	var unlooped: Array[String] = []
	for clip: String in SoundBankScript.clip_names():
		if not SoundBankScript.loops(clip):
			continue
		var stream := SoundBankScript.stream(clip)
		if stream is AudioStreamWAV \
				and (stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
			unlooped.append(clip)
	_check(unlooped.is_empty(), "every looping clip is set to loop (%s)"
			% (", ".join(unlooped) if not unlooped.is_empty() else "all set"))


func _test_buses() -> void:
	var wanted: Array[String] = []
	for clip: String in SoundBankScript.clip_names():
		var bus := SoundBankScript.bus_of(clip)
		if not wanted.has(bus):
			wanted.append(bus)
	for bus: String in wanted:
		_check(AudioServer.get_bus_index(bus) >= 0, "bus %s exists on the mixer" % bus)

	# The structure bus is where "conducted through the hull" actually lives. If
	# its effects are gone, every mechanical sound is wrong and nothing else says so.
	var structure := AudioServer.get_bus_index(SoundBankScript.BUS_STRUCTURE)
	_check(structure >= 0 and AudioServer.get_bus_effect_count(structure) >= 2,
			"the STRUCTURE bus carries its hull colouring")
	var radio := AudioServer.get_bus_index(SoundBankScript.BUS_RADIO)
	_check(radio >= 0 and AudioServer.get_bus_effect_count(radio) >= 2,
			"the RADIO bus carries its channel band")


# --- The voice bank says what it claims to say -------------------------------

## Two checks, both added after a bug that every other test in this file sailed
## past. Clip ids were once assigned sequentially in discovery order, so trimming
## one entry from the catalogue renumbered everything after it — while the raw
## renders cached on disk under the old numbers stayed where they were. The bank
## then served the right FILE for the wrong ENTRY: the four-second full callsign
## came out as a one-second clip of something else, and numbers were spoken in a
## different voice from the sentence around them.
##
## Nothing threw. Every assertion here passed, because they all read the
## manifest's own metadata and never the audio it points at. These two do.
func _test_bank_integrity() -> void:
	if _speech == null or not _speech.available():
		return
	var clips: Dictionary = _speech.manifest_clips()
	_check(clips.size() >= 100, "the voice bank is populated (%d clips)" % clips.size())

	# 1. Every id is the hash of its own content. An id that names what it says
	#    cannot be reused for something else, however the catalogue is edited.
	var misnamed: Array[String] = []
	for cid: String in clips:
		var meta: Dictionary = clips[cid]
		# The generator joins the two with a UNIT SEPARATOR before hashing (see
		#    SEPARATOR in tools/build_speech.py) - a character that cannot occur
		#    in a comms line, so no two entries can collide by concatenation.
		var joined := "%s\u001f%s" % [meta["voice"], meta["text"]]
		var expected := "c" + joined.sha1_text().substr(0, 12)
		if expected != cid:
			misnamed.append(cid)
	_check(misnamed.is_empty(), "every clip id is the hash of its own content (%s)"
			% ("all %d" % clips.size() if misnamed.is_empty()
					else "%d wrong, e.g. %s" % [misnamed.size(), misnamed[0]]))

	# 2. The audio is a plausible length for the words it claims. This is the one
	#    that catches a stale file: a clip claiming a sentence cannot be a fifth
	#    of a second long, whatever the manifest says about it.
	var impossible: Array[String] = []
	var missing := 0
	for cid: String in clips:
		var meta: Dictionary = clips[cid]
		var stream: AudioStream = _speech.stream_for(cid)
		if stream == null:
			missing += 1
			continue
		var seconds := stream.get_length()
		var characters: int = maxi(String(meta["text"]).length(), 1)
		var rate := float(characters) / maxf(seconds, 0.001)
		# Measured across the real bank: median 13.5 characters a second, spread
		# 2.7 to 23.7. A single spoken letter is legitimately slow once its
		# padding is counted, so only texts long enough to carry the signal get
		# the lower bound; everything is capped above, which is the direction a
		# stale clip fails in — too many words for the time available.
		var floor_rate := 5.0 if characters >= 12 else 1.0
		var ceiling_rate := 30.0 if characters >= 12 else 40.0
		if rate < floor_rate or rate > ceiling_rate:
			impossible.append("%s %dch/%.2fs" % [String(meta["text"]).substr(0, 24),
					characters, seconds])
	_check(missing == 0, "every manifest clip has a file (%d missing)" % missing)
	_check(impossible.is_empty(),
			"every clip is a plausible length for its words (%s)"
					% ("all sane" if impossible.is_empty()
							else "%d off, e.g. %s" % [impossible.size(), impossible[0]]))


# --- The cargo door travels --------------------------------------------------

## The door is the reason this feature touched gameplay at all, so prove it moves
## and that its two predicates disagree while it is moving. Both waits are read
## from the constant that sets the travel, never transcribed.
func _test_hatch_travel() -> void:
	GameState.set_cargo_hatch(false)
	await _wait(GameState.HATCH_TRAVEL_TIME * 1.5)
	_check(GameState.hatch_secured(), "the door starts secured")

	GameState.set_cargo_hatch(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not GameState.hatch_open_locked(),
			"selecting open does not open the door instantly")
	_check(not GameState.hatch_secured(),
			"...and a door under way no longer counts as secured either")
	_check(GameState.hatch_position > 0.0 and GameState.hatch_position < 1.0,
			"...it is mid-travel (%.2f)" % GameState.hatch_position)

	await _wait(GameState.HATCH_TRAVEL_TIME * 1.5)
	_check(GameState.hatch_open_locked(),
			"the door reaches its stop after HATCH_TRAVEL_TIME")

	GameState.set_cargo_hatch(false)
	await _wait(GameState.HATCH_TRAVEL_TIME * 1.5)
	_check(GameState.hatch_secured(), "and travels back to secured")


# --- The voice bank still covers the code ------------------------------------

## Drive REAL intents and check the lines they produce can be spoken.
##
## This is the drift check. The bank is generated by reading the format strings
## out of the source, so a comms line edited without a rebuild leaves a pattern
## that no longer matches — and the only symptom in flight is a voice that stops
## saying one thing. Here it is a failure.
func _test_lines_are_sayable() -> void:
	if _speech == null or not _speech.available():
		_check(false, "the voice bank is present (run tools/build_speech.py)")
		return

	var probes: Array[Dictionary] = []

	var before := GameState.comms.size()
	GameState.set_landing_gear(true)
	await _wait(GameState.GEAR_TRAVEL_TIME * 1.5)
	probes.append_array(_comms_since(before, "OPS"))

	before = GameState.comms.size()
	GameState.set_landing_gear(false)
	await _wait(GameState.GEAR_TRAVEL_TIME * 1.5)
	probes.append_array(_comms_since(before, "OPS"))

	before = GameState.comms.size()
	await _set_hatch(true)
	probes.append_array(_comms_since(before, "OPS"))

	# A refusal, which is the shape most of the ship's talking takes.
	before = GameState.comms.size()
	SalvageSystem.request_cut()
	await get_tree().process_frame
	probes.append_array(_comms_since(before, "OPS"))
	await _set_hatch(false)


	_check(probes.size() >= 4, "the probes produced comms to say (%d)" % probes.size())
	var mute: Array[String] = []
	for entry: Dictionary in probes:
		var voice: String = _voice_for(String(entry["source"]))
		if voice.is_empty():
			continue
		if _speech.clips_for(String(entry["text"]), voice).is_empty():
			mute.append(String(entry["text"]))
	_check(mute.is_empty(),
			"every line the ship just wrote can be spoken (mute: %s)"
					% (" | ".join(mute) if not mute.is_empty() else "none"))

	# An ATC line with a number in it, taken from the constant that sets it, so
	# the slot machinery is exercised and not just the fixed text.
	var atc := "REDUCE SPEED — %.0f M/S" % DockingSystem.SPEED_CLEARED
	_check(not _speech.clips_for(atc, "station").is_empty(),
			"a numbered ATC line resolves: \"%s\"" % atc)


func _comms_since(from_index: int, source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(from_index, GameState.comms.size()):
		var entry: Dictionary = GameState.comms[i]
		if String(entry.get("source", "")) == source:
			out.append(entry)
	return out


func _voice_for(source: String) -> String:
	var voice := String(_speech.manifest_sources().get(source, "silent"))
	return "" if voice == "silent" else voice


# --- The ship knows when to shut up ------------------------------------------

## Aligning and cutting are the two things the pilot is actually concentrating
## on, and the ship's own voice stands down for both. The harbour does not — it
## is someone else talking, on a radio, and it is never chatter.
func _test_hush_while_cutting() -> void:
	if _speech == null or not _speech.available():
		return
	var was_align := GameState.align_state
	var was_cut: int = GameState.wreck.get("cutting_id", -1)

	_check(_speech.would_speak("ship"), "the ship speaks with the torch idle")

	GameState.align_state = "ALIGNING"
	_check(not _speech.would_speak("ship"), "the ship stands down while aligning")
	_check(_speech.would_speak("station"), "...but the harbour is not hushed")

	GameState.align_state = "IDLE"
	GameState.wreck["cutting_id"] = 0
	_check(not _speech.would_speak("ship"), "the ship stands down while cutting")

	GameState.wreck["cutting_id"] = -1
	_check(_speech.would_speak("ship"), "and speaks again once the torch is out")

	GameState.align_state = was_align
	GameState.wreck["cutting_id"] = was_cut

	# Boot banners and settings echoes are dropped at build time, so they are not
	# in the bank at all — the strongest form of "never spoken".
	#
	# The two flight-control lines are settings echoes and belong here, not in the
	# sayable probes above: they read back a control the pilot has their hand on,
	# which is exactly the noise never_speak exists to prevent. That a law change
	# MATTERS is said by the annunciator and the alert, not by reading the switch
	# out loud. Renaming either line without carrying its never_speak pattern
	# across would start the ship announcing them, so both are pinned here.
	for line: String in ["DISPLAY NETWORK ONLINE — SV KESTREL",
			"SWEEP MODE PASSIVE", "THROTTLE — COMBINED COMMAND",
			"FLIGHT CONTROL — DIRECT LAW"]:
		_check(_speech.clips_for(line, "ship").is_empty(),
				"never spoken: \"%s\"" % line)


# --- Numbers -----------------------------------------------------------------

## Digit by digit, the way a lane says them — ONE FIVE cannot be misheard as
## FIFTY. Round money is the exception, because nobody says "two zero zero
## credits".
func _test_numbers() -> void:
	if _speech == null or not _speech.available():
		return
	var cases := [
		{"value": "25", "want": ["TWO", "FIVE"]},
		{"value": "200", "want": ["TWO", "HUNDRED"]},
		{"value": "1.5", "want": ["ONE", "POINT", "FIVE"]},
		{"value": "9", "want": ["NINER"]},
	]
	for case: Dictionary in cases:
		var said: PackedStringArray = _speech.words_for(_speech.number_clips(String(case["value"])))
		_check(Array(said) == case["want"], "%s is spoken as %s (got %s)" % [
			case["value"], " ".join(PackedStringArray(case["want"])), " ".join(said)])


# --- The tail number ----------------------------------------------------------

## Full identity on first contact, the last three of the registry after that,
## and full again next pattern. Both forms are quoted from the ShipDefinition, so
## this also proves a second hull would answer to its own.
func _test_callsign() -> void:
	if _speech == null or not _speech.available():
		return
	var name: String = GameState.ship_def.display_name
	var registry: String = GameState.ship_def.registry
	var line := "%s CLEAR OF THE PATTERN — GOOD HUNTING." % name

	_speech.forget_callsign()
	var first: PackedStringArray = _speech.words_for(_speech.clips_for(line, "station"))
	_check(not Array(first).is_empty(), "the first-contact line resolves")
	var opening := String(first[0]) if not Array(first).is_empty() else ""
	_check(opening.contains("KESTREL"),
			"first contact says the ship's name (got \"%s\")" % opening)
	_check(opening.to_upper().contains("LIMA") and opening.to_upper().contains("KILO"),
			"first contact spells the registry %s (got \"%s\")" % [registry, opening])

	var second: PackedStringArray = _speech.words_for(_speech.clips_for(line, "station"))
	var later := String(second[0]) if not Array(second).is_empty() else ""
	_check(later != opening and not later.is_empty(),
			"the next call abbreviates (got \"%s\")" % later)
	_check(later.to_upper().contains("KILO"),
			"...to the last of the registry (got \"%s\")" % later)

	# Leaving the pattern ends the exchange; the next arrival is greeted in full.
	GameState.docking_changed.emit("INACTIVE")
	await get_tree().process_frame
	var again: PackedStringArray = _speech.words_for(_speech.clips_for(line, "station"))
	_check(not Array(again).is_empty() and String(again[0]) == opening,
			"a new pattern is opened with the full identity again")


# --- Alerts latch -------------------------------------------------------------

## The point of the whole file. Hold a condition across its threshold and it must
## raise ONCE — the failure this replaces was an alarm sounding every frame.
func _test_alerts_latch() -> void:
	# A Dictionary, not two ints: GDScript lambdas capture locals BY VALUE, so
	# incrementing a captured int only ever increments the lambda's own copy and
	# the count stays stubbornly at zero. A Dictionary is a reference.
	var tally := {"raised": 0, "cleared": 0}
	var counter := func(id: String, _level: String) -> void:
		if id == "BUS_DEAD":
			tally["raised"] += 1
	var clearer := func(id: String) -> void:
		if id == "BUS_DEAD":
			tally["cleared"] += 1
	AlertSystem.alert_raised.connect(counter)
	AlertSystem.alert_cleared.connect(clearer)

	# Open the bus: nothing is delivered, so BUS_DEAD stands.
	var battery_was := GameState.master_bat
	var alternator_was := GameState.master_alt
	GameState.set_master_battery(false)
	GameState.set_master_alt(false)
	await _wait(1.0)
	_check(AlertSystem.is_active("BUS_DEAD"), "opening the bus raises BUS_DEAD")
	_check(AlertSystem.has_warning(), "...and a WARNING is standing")
	var after_raise: int = tally["raised"]

	# Hold it there. Sixty frames of a standing condition, one alarm.
	await _wait(2.0)
	_check(tally["raised"] == after_raise and tally["raised"] == 1,
			"a held condition raises exactly once (raised %d times)" % tally["raised"])

	GameState.set_master_battery(battery_was)
	GameState.set_master_alt(alternator_was)
	await _wait(1.0)
	_check(not AlertSystem.is_active("BUS_DEAD"), "restoring the bus clears it")
	_check(tally["cleared"] == 1, "...exactly once (cleared %d times)" % tally["cleared"])

	AlertSystem.alert_raised.disconnect(counter)
	AlertSystem.alert_cleared.disconnect(clearer)

	# Every declared predicate must still be wired to functions that exist. This
	# is what catches an alert whose condition was renamed out from under it.
	for id: String in AlertSystem.condition_ids():
		AlertSystem.test_raise(id)
	_check(AlertSystem.condition_ids().size() >= 8,
			"the conditions are declared (%d)" % AlertSystem.condition_ids().size())
	for level: String in AlertSystem.LEVELS:
		_check(not level.is_empty(), "the handbook's %s level is declared" % level)


# --- The mixer ---------------------------------------------------------------

func _test_mixer() -> void:
	for bus: String in AudioSystem.MIXER_BUSES:
		_check(AudioServer.get_bus_index(bus) >= 0, "mixer row %s names a real bus" % bus)
	var was := AudioSystem.level("Master")
	AudioSystem.set_level("Master", 0.5)
	_check(is_equal_approx(AudioSystem.level("Master"), 0.5), "a level survives being set")
	AudioSystem.set_level("Master", was)


# --- Helpers -----------------------------------------------------------------

func _wait(game_seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < game_seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _set_hatch(open: bool) -> void:
	GameState.set_cargo_hatch(open)
	var elapsed := 0.0
	while elapsed < GameState.HATCH_TRAVEL_TIME * 2.0:
		var arrived := GameState.hatch_open_locked() if open else GameState.hatch_secured()
		if arrived:
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
