extends RefCounted
class_name SoundBank
## The one place that maps a logical sound name to a file and a bus.
##
## Nothing else in the project spells an audio path. A renamed or missing clip
## therefore fails in exactly one spot, and AudioSmoke walks this table to catch
## it before a run does.
##
## The BUS column is where "what this sounds like inside a ship in vacuum" is
## actually decided, clip by clip. Outside the pressure hull there is no air, so
## nothing out there radiates sound to you — every clip below arrives by one of
## two paths:
##
##   STRUCTURE — conducted through the frame. Everything bolted to the outside:
##               the legs, the door's leadscrew, the cutting head, the thrusters,
##               the drive. The hull's colouring is applied once, on the bus.
##   CABIN     — the cabin's own air, and the only sounds allowed a top end. The
##               ventilation, the annunciator, the inboard converter, and the
##               hold's air arriving through the bulkhead.
##
## The two hatch air clips are the whole rule in miniature: the door's screw is
## STRUCTURE like every other outside machine, but the air it dumps is CABIN,
## because there is a pressure bulkhead between you and the hold and air is what
## crosses it. The landing gear has no equivalent clip, and that asymmetry is
## deliberate — the legs have nothing between them and vacuum.

const SFX_DIR := "res://assets/generated/sfx/"
const VOICE_DIR := "res://assets/generated/voice/"

## Buses, outermost first. AudioSystem builds these at boot; AudioSmoke asserts
## every name used below exists.
const BUS_MASTER := "Master"
const BUS_CABIN := "CABIN"
const BUS_ALERTS := "ALERTS"
const BUS_SIDETONE := "SIDETONE"
const BUS_STRUCTURE := "STRUCTURE"
const BUS_RADIO := "RADIO"

## name -> { bus, loop }. `loop` marks the continuous sources, which are held on
## a dedicated player and faded rather than fired and forgotten.
const CLIPS: Dictionary = {
	# --- Cabin air: the only machines you hear through atmosphere -------------
	"vent_loop": {"bus": BUS_CABIN, "loop": true},
	"cutter_charge": {"bus": BUS_CABIN, "loop": false},
	"hatch_vent_out": {"bus": BUS_CABIN, "loop": false},
	"hatch_repress": {"bus": BUS_CABIN, "loop": false},

	# --- Conducted through the frame -----------------------------------------
	"gear_travel_loop": {"bus": BUS_STRUCTURE, "loop": true},
	"gear_lock_down": {"bus": BUS_STRUCTURE, "loop": false},
	"gear_lock_up": {"bus": BUS_STRUCTURE, "loop": false},

	"hatch_travel_loop": {"bus": BUS_STRUCTURE, "loop": true},
	"hatch_latch_open": {"bus": BUS_STRUCTURE, "loop": false},
	"hatch_latch_close": {"bus": BUS_STRUCTURE, "loop": false},

	"cutter_ignite": {"bus": BUS_STRUCTURE, "loop": false},
	"cutter_loop": {"bus": BUS_STRUCTURE, "loop": true},
	"cutter_align_loop": {"bus": BUS_STRUCTURE, "loop": true},
	"cutter_stop": {"bus": BUS_STRUCTURE, "loop": false},

	"rcs_pop_a": {"bus": BUS_STRUCTURE, "loop": false},
	"rcs_pop_b": {"bus": BUS_STRUCTURE, "loop": false},
	"rcs_pop_c": {"bus": BUS_STRUCTURE, "loop": false},
	"rcs_hold_loop": {"bus": BUS_STRUCTURE, "loop": true},

	"drive_loop": {"bus": BUS_STRUCTURE, "loop": true},
	"drive_crank_loop": {"bus": BUS_STRUCTURE, "loop": true},
	"drive_catch": {"bus": BUS_STRUCTURE, "loop": false},
	"drive_shutdown": {"bus": BUS_STRUCTURE, "loop": false},

	"impact_soft": {"bus": BUS_STRUCTURE, "loop": false},
	"impact_hard": {"bus": BUS_STRUCTURE, "loop": false},

	# --- The annunciator panel, and the radio --------------------------------
	"alert_warning_loop": {"bus": BUS_ALERTS, "loop": true},
	"alert_caution": {"bus": BUS_ALERTS, "loop": false},
	"alert_note": {"bus": BUS_ALERTS, "loop": false},
	"comms_chirp": {"bus": BUS_ALERTS, "loop": false},
	"squelch_tail": {"bus": BUS_RADIO, "loop": false},
	"mic_click_on": {"bus": BUS_SIDETONE, "loop": false},
	"mic_click_off": {"bus": BUS_SIDETONE, "loop": false},
}

## The RCS pop variants, cycled so holding an axis never machine-guns one sample.
const RCS_POPS: Array[String] = ["rcs_pop_a", "rcs_pop_b", "rcs_pop_c"]

static var _cache: Dictionary = {}


## The stream for a named clip, or null if it is missing. Looping clips have
## their loop mode set here rather than in a committed .import file, so the fact
## that a clip loops lives beside the table that says so.
static func stream(clip: String) -> AudioStream:
	if _cache.has(clip):
		return _cache[clip]
	if not CLIPS.has(clip):
		push_error("SoundBank: no such clip '%s'" % clip)
		return null
	var path := SFX_DIR + clip + ".wav"
	if not ResourceLoader.exists(path):
		push_error("SoundBank: missing file %s" % path)
		_cache[clip] = null
		return null
	var stream_res: AudioStream = load(path)
	if CLIPS[clip]["loop"] and stream_res is AudioStreamWAV:
		# Sample-exact: build_sfx.py filters in the FFT domain, which is circular,
		# so every _loop clip is already periodic over its own length and needs no
		# crossfade. loop_end 0 means "the end of the sample".
		var wav: AudioStreamWAV = stream_res
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = 0
	_cache[clip] = stream_res
	return stream_res


static func bus_of(clip: String) -> String:
	return CLIPS.get(clip, {}).get("bus", BUS_MASTER)


static func loops(clip: String) -> bool:
	return bool(CLIPS.get(clip, {}).get("loop", false))


## Every clip file this bank expects to find. AudioSmoke asserts each resolves.
static func clip_names() -> Array:
	return CLIPS.keys()
