extends Node
## The ship's and the harbour's voices: how a written comms line becomes a spoken
## one.
##
## Why it works the way it does
## ---------------------------
## Every comms line in the project is a format string with the numbers cut out of
## it — "REDUCE SPEED — %.0f M/S". tools/build_speech.py reads those strings out
## of the source, renders each literal piece between the specifiers as its own
## clip, and leaves a manifest of patterns. This file matches a finished line
## back against those patterns and plays piece, number, piece.
##
## So nothing here contains a script. The lines live in GameState and
## DockingSystem where they always did; change one, rebuild the bank, and the
## spoken form follows. A hand-written script beside the code would have
## disagreed with it inside a week.
##
## Three voices, and they are three different things:
##
##   STATION  someone else, on a radio. Band-limited by the RADIO bus, announced
##            by a chirp, closed by a squelch tail — and it addresses you by your
##            tail number, in full the first time and abbreviated after, which is
##            how a real lane stops a pattern becoming a recital.
##   SHIP     your own annunciator reading a state back to you. It is a machine
##            and it is allowed to sound like one.
##   PILOT    you, transmitting. Heard as sidetone in your own headset, so it
##            never went over the air and keeps its body.
##
## One queue for all three, because you cannot listen to two people at once. The
## queue is short and drops its oldest when it overruns: a backlog of stale
## clearances read out over a wave-off is worse than silence.

const SoundBankScript := preload("res://systems/audio/SoundBank.gd")

const MANIFEST_PATH := "res://assets/generated/voice/manifest.json"
const CLIP_DIR := "res://assets/generated/voice/"

## Gap left between two clips of one utterance. Enough that the words do not run
## together, short enough that a sentence is still a sentence.
const WORD_GAP := 0.06
## Gap after a complete utterance before the queue starts the next.
const UTTERANCE_GAP := 0.2
## How long the call tone runs before the harbour starts speaking. Short: the
## line is already on the instrument the moment it is posted, so every fraction
## of a second here is the voice falling further behind the text the pilot has
## already read. The chirp keeps ringing underneath — this only decides when the
## first word lands on top of it.
const CHIRP_LEAD := 0.3
## How many utterances may be waiting.
const QUEUE_LIMIT := 4
## An utterance still queued this long after it was posted is dropped unspoken.
##
## The text reaches the instrument instantly and the voice cannot; a backlog only
## widens that gap, and reading out a clearance that was superseded ten seconds
## ago is worse than saying nothing. Speech is allowed to fall behind a little
## and then give up, never to queue indefinitely.
const STALE_AFTER := 6.0
## Longest a single utterance may run before the queue gives up on it, seconds.
## Guards against a clip whose length the stream reports as zero.
const UTTERANCE_TIMEOUT := 30.0

signal utterance_started(voice: String, text: String)

var _manifest: Dictionary = {}
var _lines: Array = []
var _patterns: Array[RegEx] = []
var _clip_cache: Dictionary = {}
var _player: AudioStreamPlayer = null

## Queued utterances: { voice, clips: Array[String], text: String }.
var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _clip_index := 0
var _wait := 0.0
var _elapsed := 0.0

## Has the harbour used our full identity yet in this pattern? Reset when a
## pattern ends, so every arrival opens with the tail number in full.
var _addressed := false
var _available := false


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "Voice"
	add_child(_player)
	_load_manifest()
	GameState.comms_posted.connect(_on_comms)
	GameState.docking_changed.connect(_on_docking_state)


func _load_manifest() -> void:
	if not ResourceLoader.exists(MANIFEST_PATH) and not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("Speech: no voice bank at %s — run tools/build_speech.py. "
				% MANIFEST_PATH + "The ship will stay mute; nothing else is affected.")
		return
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Speech: voice manifest is not readable JSON.")
		return
	_manifest = parsed
	_lines = _manifest.get("lines", [])
	# Patterns are pre-sorted most-specific-first by the generator, so a line
	# that is mostly slots can never swallow one that is mostly words.
	for entry: Dictionary in _lines:
		var rx := RegEx.new()
		if rx.compile(String(entry.get("pattern", ""))) != OK:
			rx = null
		_patterns.append(rx)
	_available = not _lines.is_empty()


## True once the bank has loaded. AudioSmoke asserts this rather than listening.
func available() -> bool:
	return _available


## --- Turning a written line into a spoken one -------------------------------


func _on_comms(entry: Dictionary) -> void:
	var source := String(entry.get("source", ""))
	var voice := String(_manifest.get("sources", {}).get(source, "silent"))
	if voice == "silent" or voice.is_empty():
		return
	var clips := _resolve(String(entry.get("text", "")), voice, 0)
	if clips.is_empty():
		return
	_enqueue(voice, clips, String(entry.get("text", "")))


## Match a written line against the manifest and return the clips that say it.
##
## Two passes, because DockingSystem._atc posts an instruction and its reason as
## one line joined by an em dash while the generator saw them as two separate
## literals. Try the whole line first; failing that, try each em-dash split and
## take the first where BOTH halves are sayable. Splitting only on demand is what
## keeps lines that legitimately contain an em dash intact.
func _resolve(text: String, voice: String, depth: int) -> Array[String]:
	var out: Array[String] = []
	if text.is_empty() or depth > 2:
		return out

	var direct := _match_line(text, voice, depth)
	if not direct.is_empty():
		return direct

	var parts := text.split(" — ")
	if parts.size() >= 2:
		for split_at in range(1, parts.size()):
			var head := " — ".join(Array(parts.slice(0, split_at)))
			var tail := " — ".join(Array(parts.slice(split_at)))
			var head_clips := _match_line(head, voice, depth)
			var tail_clips := _match_line(tail, voice, depth)
			if not head_clips.is_empty() and not tail_clips.is_empty():
				out.append_array(head_clips)
				out.append_array(tail_clips)
				return out
	return out


func _match_line(text: String, voice: String, depth: int) -> Array[String]:
	var out: Array[String] = []
	for i in _lines.size():
		var entry: Dictionary = _lines[i]
		if String(entry.get("voice", "")) != voice:
			continue
		var rx: RegEx = _patterns[i]
		if rx == null:
			continue
		var found := rx.search(text)
		if found == null:
			continue
		for part: Dictionary in entry.get("parts", []):
			if part.has("clip"):
				out.append(String(part["clip"]))
			else:
				# A capture group is one-based in Godot's RegEx.
				var value := found.get_string(int(part["slot"]) + 1)
				out.append_array(_speak_value(value.strip_edges(), voice, depth))
		return out
	return out


## Say a slot's value: a callsign, a number, a name we have a clip for, or — for
## something composed out of another line, like a wave-off reason — that line.
##
## Anything else is skipped rather than guessed at. A slot the ship cannot say is
## better silent than wrong: spelling an unknown word letter by letter would turn
## a station name into thirty seconds of alphabet.
func _speak_value(value: String, voice: String, depth: int) -> Array[String]:
	var out: Array[String] = []
	if value.is_empty():
		return out

	var callsign := _callsign_clip(value, voice)
	if not callsign.is_empty():
		out.append(callsign)
		return out

	var words: Dictionary = _manifest.get("words", {}).get(voice, {})
	if words.has(value):
		out.append(String(words[value]))
		return out
	if words.has(value.to_upper()):
		out.append(String(words[value.to_upper()]))
		return out

	if _is_number(value):
		return _speak_number(value, voice)

	# Composed text — a wave-off reason quoted into "GO AROUND — %s", or an
	# instruction quoted into "%s (READBACK)".
	return _resolve(value, voice, depth + 1)


## Our own identity, spoken in full the first time the harbour uses it and
## abbreviated to the last three of the registry after that.
func _callsign_clip(value: String, voice: String) -> String:
	var callsigns: Dictionary = _manifest.get("callsigns", {})
	if not callsigns.has(value):
		return ""
	var forms: Dictionary = callsigns[value].get(voice, {})
	if forms.is_empty():
		return ""
	var short := String(forms.get("short", ""))
	if _addressed and not short.is_empty():
		return short
	_addressed = true
	return String(forms.get("full", short))


func _is_number(value: String) -> bool:
	return value.is_valid_float() or value.is_valid_int()


## Numbers the way a harbour says them: digit by digit, so ONE FIVE cannot be
## heard as FIFTY. Round money is the exception — nobody says "two zero zero
## credits" — so exact hundreds and thousands get their own word.
func _speak_number(value: String, voice: String) -> Array[String]:
	var out: Array[String] = []
	var digits: Array = _manifest.get("digits", {}).get(voice, [])
	var words: Dictionary = _manifest.get("words", {}).get(voice, {})
	if digits.is_empty():
		return out

	var text := value
	if text.begins_with("-"):
		if words.has("MINUS"):
			out.append(String(words["MINUS"]))
		text = text.substr(1)

	var whole := text
	var fraction := ""
	var dot := text.find(".")
	if dot >= 0:
		whole = text.substr(0, dot)
		fraction = text.substr(dot + 1)

	var magnitude := whole.to_int()
	if magnitude >= 1000 and magnitude % 1000 == 0 and magnitude < 10000 \
			and words.has("THOUSAND"):
		out.append(String(digits[magnitude / 1000]))
		out.append(String(words["THOUSAND"]))
	elif magnitude >= 100 and magnitude % 100 == 0 and magnitude < 1000 \
			and words.has("HUNDRED"):
		out.append(String(digits[magnitude / 100]))
		out.append(String(words["HUNDRED"]))
	else:
		for character in whole:
			if character.is_valid_int():
				out.append(String(digits[character.to_int()]))

	if not fraction.is_empty() and words.has("POINT"):
		out.append(String(words["POINT"]))
		for character in fraction:
			if character.is_valid_int():
				out.append(String(digits[character.to_int()]))
	return out


## --- What the pilot transmits -----------------------------------------------


## Speak one of the pilot's own lines. Unlike everything else here these have no
## existing call site to read from — until the ship had a voice, the pilot never
## said anything out loud — so they are the one script that does live in
## data/speech/lines.json.
func transmit(key: String) -> void:
	var template: Array = _manifest.get("pilot", {}).get(key, [])
	if template.is_empty():
		return
	var clips: Array[String] = []
	for part: Dictionary in template:
		if part.has("clip"):
			clips.append(String(part["clip"]))
			continue
		match String(part.get("named", "")):
			"callsign":
				var own := _callsign_clip(GameState.ship_def.display_name, "pilot")
				if not own.is_empty():
					clips.append(own)
			"station":
				var station := String(DockingSystem.status().get("station", ""))
				var words: Dictionary = _manifest.get("words", {}).get("pilot", {})
				if words.has(station):
					clips.append(String(words[station]))
	if not clips.is_empty():
		_enqueue("pilot", clips, key)


## --- The queue --------------------------------------------------------------


func _enqueue(voice: String, clips: Array[String], text: String) -> void:
	if _hushed(voice):
		return
	var now := Time.get_ticks_msec() / 1000.0
	# The ship reports the state it is in, not the history of how it got there.
	# Only one of its lines may be pending: a newer one supersedes whatever had
	# not been said yet, so a burst of changes is answered by the last of them
	# rather than read out as a list a pilot has already flown past.
	if voice != "station":
		var kept: Array[Dictionary] = []
		for pending: Dictionary in _queue:
			if String(pending["voice"]) == "station":
				kept.append(pending)
		_queue = kept
	_queue.append({"voice": voice, "clips": clips, "text": text, "posted": now})
	while _queue.size() > QUEUE_LIMIT:
		_queue.pop_front()


## The ship's own voice stands down while the torch is live.
##
## Aligning and cutting are the two things in the game the pilot is actually
## concentrating on, and an annunciator that narrates over them is the exact
## behaviour a real one is built to avoid. The harbour is not hushed — that is
## someone else talking, on a radio, and it is never chatter. Neither are the
## warning tones, which are not speech and are the one thing worth interrupting
## for.
func _hushed(voice: String) -> bool:
	if not _manifest.get("hush_while_cutting", []).has(voice):
		return false
	return GameState.wreck.get("cutting_id", -1) != -1 \
			or GameState.align_state == "ALIGNING"


func _on_docking_state(state: String) -> void:
	# Leaving the pattern ends the exchange, so the next arrival is greeted in
	# full again rather than picking up mid-conversation.
	if state == "INACTIVE":
		_addressed = false


func _process(delta: float) -> void:
	if not _available:
		return
	_wait = maxf(_wait - delta, 0.0)
	if not _current.is_empty():
		_elapsed += delta
		if _elapsed > UTTERANCE_TIMEOUT:
			_finish_utterance()
			return
	if _wait > 0.0 or _player.playing:
		return

	if _current.is_empty():
		# Drop anything that has been waiting long enough to be out of date. The
		# text was on the instrument the instant it was posted; speaking it now
		# would be reporting a state the ship has already left.
		var now := Time.get_ticks_msec() / 1000.0
		while not _queue.is_empty() \
				and now - float(_queue[0].get("posted", now)) > STALE_AFTER:
			_queue.pop_front()
		if _queue.is_empty():
			return
		_current = _queue.pop_front()
		_clip_index = 0
		_elapsed = 0.0
		var voice := String(_current["voice"])
		# The harbour announces itself before it speaks, and the ship prepends
		# nothing — an annunciator that chimed before every readout would be
		# unbearable within one approach.
		if String(_manifest.get("voices", {}).get(voice, {}).get("bus", "")) \
				== SoundBankScript.BUS_RADIO:
			AudioSystem.play("comms_chirp", 0.5)
			_wait = CHIRP_LEAD
		utterance_started.emit(voice, String(_current["text"]))
		return

	var clips: Array = _current["clips"]
	if _clip_index >= clips.size():
		_finish_utterance()
		return
	_play_clip(String(clips[_clip_index]), String(_current["voice"]))
	_clip_index += 1


func _finish_utterance() -> void:
	var voice := String(_current.get("voice", ""))
	if bool(_manifest.get("voices", {}).get(voice, {}).get("squelch", false)):
		# The carrier dropping at the end of somebody else's transmission.
		AudioSystem.play("squelch_tail", 0.5)
	_current = {}
	_clip_index = 0
	_elapsed = 0.0
	_wait = UTTERANCE_GAP


func _play_clip(clip: String, voice: String) -> void:
	var stream := _stream(clip)
	if stream == null:
		return
	_player.stream = stream
	_player.bus = String(_manifest.get("voices", {}).get(voice, {}).get(
			"bus", SoundBankScript.BUS_MASTER))
	_player.play()
	_wait = WORD_GAP


func _stream(clip: String) -> AudioStream:
	if _clip_cache.has(clip):
		return _clip_cache[clip]
	var path := CLIP_DIR + clip + ".ogg"
	var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_clip_cache[clip] = stream
	return stream


## --- For the smoke test -----------------------------------------------------


## Which clips a written line would be spoken as, without playing anything.
## AudioSmoke uses this to prove the bank still covers the lines the code writes.
func clips_for(text: String, voice: String) -> Array[String]:
	return _resolve(text, voice, 0)


## Spell a number the way the harbour would, as clip ids.
func number_clips(value: String, voice := "station") -> Array[String]:
	return _speak_number(value, voice)


## The words behind a list of clip ids — what the ship would actually be heard
## to say. Only the manifest knows this; the clips themselves are opaque.
func words_for(clips: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var table: Dictionary = _manifest.get("clips", {})
	for clip: String in clips:
		out.append(String(table.get(clip, {}).get("text", "?")))
	return out


## Reset the "has the harbour used our full identity yet" flag, for tests that
## want to see first contact twice.
func forget_callsign() -> void:
	_addressed = false


## Which voice speaks for each comms source, as the bank was built. AudioSmoke
## asks so it can check the same lines the runtime would.
func manifest_sources() -> Dictionary:
	return _manifest.get("sources", {})


## Every clip in the bank: id -> { voice, text }. AudioSmoke walks this to prove
## each id is the hash of its own content and each file is a plausible length for
## the words it claims — the two things that would have caught a bank serving the
## right file for the wrong entry.
func manifest_clips() -> Dictionary:
	return _manifest.get("clips", {})


## The stream behind one clip id, for callers that want to measure it rather than
## play it.
func stream_for(clip: String) -> AudioStream:
	return _stream(clip)


## Would this voice be heard right now, or is it standing down? See _hushed.
func would_speak(voice: String) -> bool:
	return not _hushed(voice)
