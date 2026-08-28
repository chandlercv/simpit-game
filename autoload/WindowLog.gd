extends Node
## A written record of where the OS put our windows and where input went
## afterwards, mirrored to user://window_log.txt (path printed at boot).
##
## It exists for the one class of simpit fault that can't be diagnosed by
## looking at the game: the windows land on the right screens, the ship flies on
## HOTAS — which is polled process-globally and needs no window focus at all —
## and yet the Main window takes neither a click nor a keystroke, or the pointer
## can no longer be dragged off the screen it sits on. Every in-game symptom of
## that is normal; the fault is on the other side of the DisplayServer, in the
## OS focus stack and the cursor clip rect, neither of which Godot exposes.
##
## So this logs the observable facts on both sides of that boundary and lets the
## log say which side is lying:
##
##  - what mode, screen and rect each window was ASKED for, and what the
##    DisplayServer reads back once the OS has had its say;
##  - which window the OS reports as focused, every time that changes — plus
##    whether the app has focus at all, and which Control Godot thinks is
##    focused inside each window (a focused button in an unfocused window is
##    exactly the reported symptom);
##  - how many real input events each window has received, counted per window,
##    which separates "the Main window is dead" from "the binding is wrong";
##  - the mouse mode, and every screen the pointer has managed to reach since
##    the last focus change — a pointer that stops crossing a screen boundary
##    at a particular moment is a clip rect, not a coincidence.
##
## Nothing we set is logged as if it took: every value is read back from the
## DisplayServer, because the failures worth catching here are the ones where
## the OS quietly ignored or undid a request.
##
## Lines are only written when something CHANGES, so a healthy session costs a
## page and the interesting one is all signal. F8 stamps a full dump on demand
## — that is how a player marks the moment the thing they are reporting
## happened, which is the hard part of reading someone else's log.

## Truncated at each launch, for the same reason the comms log is: a log you
## have to scroll to the end of to find the current run is barely better than a
## photograph of the screen.
const LOG_PATH := "user://window_log.txt"

## The session before this one, kept because the faults this log is for are
## reported by someone who has already restarted the game to see whether it
## sticks. Truncating on launch and keeping nothing would destroy the evidence
## in the act of confirming it. One generation is enough: the run that broke is
## the run before the one you are reading.
const PREV_LOG_PATH := "user://window_log.prev.txt"

## Stop writing after this many lines — a hard ceiling of roughly 2 MB per
## session, and 4 MB on disk once the previous session is counted. Focus
## flapping frame after frame is one of the shapes this fault could take, and an
## overnight session must not be able to fill a disk with it.
const LINE_BUDGET := 20000

## The size at which a log that cannot be rotated stops being appended to (see
## _open_log). Well clear of the 2 MB a single session can reach, so only a file
## that has been accumulating sessions ever meets it.
const APPEND_CEILING_BYTES := 8 << 20

## How often the log says it is still running (see _heartbeat). Two lines a
## minute is legible at a glance and spends the budget slowly enough that a
## long session still records the end of itself.
const HEARTBEAT_SECONDS := 30.0

## Window geometry is compared by rebuilding its description, which is the one
## poll here expensive enough to be worth throttling. Nothing it watches for —
## a window minimising itself, a mode the OS undid — needs finding within a
## frame, and five times a second still times it well enough to read against
## the focus lines around it.
const GEOMETRY_POLL_SECONDS := 0.2

const MODE_NAMES: Dictionary = {
	Window.MODE_WINDOWED: "windowed",
	Window.MODE_MINIMIZED: "minimized",
	Window.MODE_MAXIMIZED: "maximized",
	Window.MODE_FULLSCREEN: "fullscreen",
	Window.MODE_EXCLUSIVE_FULLSCREEN: "exclusive_fullscreen",
}

const MOUSE_MODE_NAMES: Dictionary = {
	DisplayServer.MOUSE_MODE_VISIBLE: "visible",
	DisplayServer.MOUSE_MODE_HIDDEN: "hidden",
	DisplayServer.MOUSE_MODE_CAPTURED: "captured",
	DisplayServer.MOUSE_MODE_CONFINED: "confined",
	DisplayServer.MOUSE_MODE_CONFINED_HIDDEN: "confined_hidden",
}

## Window flags worth naming in a placement line. NO_FOCUS and MOUSE_PASSTHROUGH
## would each produce precisely the reported symptom on their own, so they are
## logged whether we ever set them or not.
const FLAG_NAMES: Dictionary = {
	DisplayServer.WINDOW_FLAG_BORDERLESS: "borderless",
	DisplayServer.WINDOW_FLAG_RESIZE_DISABLED: "unresizable",
	DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP: "always_on_top",
	DisplayServer.WINDOW_FLAG_NO_FOCUS: "no_focus",
	DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH: "mouse_passthrough",
	DisplayServer.WINDOW_FLAG_POPUP: "popup",
	DisplayServer.WINDOW_FLAG_TRANSPARENT: "transparent",
}

## Event classes counted per window. Kept as named buckets rather than a total:
## "motion but no buttons" and "nothing at all" are different faults.
const EVENT_KINDS: Array[String] = ["key", "button", "motion", "touch", "joypad", "other"]

var _enabled := false
var _file: FileAccess = null
var _lines := 0

## One entry per window we know about: {win, label, counts}.
var _watched: Array[Dictionary] = []
## The main window's entry, counted from _input() rather than from window_input
## (see watch()).
var _main_entry: Dictionary = {}

## Last logged state, so only changes are written.
var _focused: Dictionary = {}
var _geometry: Dictionary = {}
var _mouse_mode := -1

## Where the pointer has been able to go since the last mark. -2 is "not sampled
## yet", which is distinct from -1, "off every screen".
var _pointer_screen := -2
var _pointer_span := Rect2i()
var _pointer_span_valid := false
var _pointer_screens: Dictionary = {}
## Screen rects, cached so the per-frame pointer sample is arithmetic rather
## than two DisplayServer calls per screen. Refreshed on the geometry tick, so a
## monitor that appears or moves is picked up within a fifth of a second.
var _screen_rects: Array[Rect2i] = []

var _since_heartbeat := 0.0
var _since_geometry := 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_enabled = true
	# Same reason WindowManager runs always: the title card pauses the tree, and
	# the windows this log is about are placed while the card is still up.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_screen_rects()
	var rolled := _roll_previous()
	_open_log(rolled == OK)
	note("boot", "Salvager window log — %s" % Time.get_datetime_string_from_system())
	if rolled != OK:
		note("boot", ("could NOT move the previous session to %s (error %d), so this run was "
				+ "APPENDED rather than written over it — everything above this line is an "
				+ "older session") % [PREV_LOG_PATH, rolled])
	_log_environment()
	watch(get_window(), "main")
	snapshot("boot")


# --- Writing ---------------------------------------------------------------

## Move last session's log aside before this one is written. Renamed rather than
## copied so a large file costs nothing, and the older generation is dropped
## first because rename won't overwrite on every platform.
##
## Returns the rename's error, OK also meaning "there was nothing to move". The
## caller must respect a failure: opening the log for writing anyway would
## truncate the very evidence the roll exists to keep, and the read-only file or
## the lock that stopped the rename says nothing about the file we would then
## destroy.
func _roll_previous() -> Error:
	if not FileAccess.file_exists(LOG_PATH):
		return OK
	# A failure here is not itself fatal — on Windows rename removes the target
	# anyway — so it is the rename's verdict that decides.
	if FileAccess.file_exists(PREV_LOG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREV_LOG_PATH))
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(LOG_PATH),
			ProjectSettings.globalize_path(PREV_LOG_PATH))


## Open this session's log: truncating when the previous one was safely moved
## aside, appending when it could not be. Preservation beats tidiness — a log
## with two sessions in it is readable, and a log that overwrote the run being
## reported is not.
##
## Appending cannot be allowed to grow without limit, though: a permanently
## unrollable file (read-only, or held open by something else) would otherwise
## gain a session every launch forever. Past APPEND_CEILING_BYTES this session
## keeps its stdout output and writes no file, which loses the cheaper half —
## and says so, naming the file to clear.
func _open_log(fresh: bool) -> void:
	if fresh:
		_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	else:
		_file = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
		if _file and _file.get_length() >= APPEND_CEILING_BYTES:
			_file = null
			push_warning(("WindowLog: %s is over %d MB and cannot be rotated — logging to "
					+ "stdout only. Delete or move that file.")
					% [ProjectSettings.globalize_path(LOG_PATH), APPEND_CEILING_BYTES >> 20])
			return
		if _file:
			_file.seek_end()
	if _file == null:
		push_warning("WindowLog: could not open %s for writing (error %d) — logging to stdout only"
				% [LOG_PATH, FileAccess.get_open_error()])
		return
	print("window log: ", ProjectSettings.globalize_path(LOG_PATH))

## One timestamped line, to the log file and to stdout. `category` is a short
## tag so the file can be grepped by concern (focus, pointer, layout, input).
func note(category: String, text: String) -> void:
	if not _enabled or _lines > LINE_BUDGET:
		return
	_lines += 1
	if _lines > LINE_BUDGET:
		text = "line budget (%d) reached — nothing further will be logged" % LINE_BUDGET
		category = "budget"
	var line := "[%9.3f] %-8s %s" % [Time.get_ticks_msec() / 1000.0, category, text]
	print(line)
	if _file:
		_file.store_line(line)
		_file.flush()


## Everything about a window that the OS gets the last word on. Deliberately
## excludes focus, which changes on its own schedule and is logged separately —
## otherwise every focus change would reprint the geometry and vice versa.
func describe(win: Window) -> String:
	if not _enabled or not is_instance_valid(win):
		return "(no window)"
	var id := win.get_window_id()
	if id < 0:
		return "(not yet created)"
	var server_mode: int = DisplayServer.window_get_mode(id)
	var parts: PackedStringArray = []
	parts.append("id=%d" % id)
	parts.append("screen=%d" % DisplayServer.window_get_current_screen(id))
	parts.append("mode=%s" % MODE_NAMES.get(server_mode, str(server_mode)))
	# The Window node caches what we asked for; the DisplayServer reports what
	# the window actually is. A disagreement is a finding, not noise.
	if win.mode != server_mode:
		parts.append("asked_for=%s(!)" % MODE_NAMES.get(win.mode, str(win.mode)))
	# str(), not %v: %v prints an integer vector with six decimal places.
	parts.append("pos=%s" % str(DisplayServer.window_get_position(id)))
	parts.append("size=%s" % str(DisplayServer.window_get_size(id)))
	parts.append("visible=%s" % win.visible)
	var flags: PackedStringArray = []
	for flag: int in FLAG_NAMES:
		if DisplayServer.window_get_flag(flag, id):
			flags.append(FLAG_NAMES[flag])
	parts.append("flags=[%s]" % " ".join(flags))
	return " ".join(parts)


# --- Watching a window -----------------------------------------------------

## Start following a window: its focus, its geometry, and the input it receives.
## Called by WindowManager for the Main window and for every tile it spawns.
func watch(win: Window, label: String) -> void:
	if not _enabled or not is_instance_valid(win):
		return
	var counts: Dictionary = {}
	for kind in EVENT_KINDS:
		counts[kind] = 0
	var entry := {"win": win, "label": label, "counts": counts}
	_watched.append(entry)
	win.focus_entered.connect(_on_focus_signal.bind(label, true))
	win.focus_exited.connect(_on_focus_signal.bind(label, false))
	if win == get_window():
		# The root window's events are pushed straight into the root viewport by
		# SceneTree and never reach `window_input`, so the main window is counted
		# from this autoload's own _input() — which sees the root viewport and
		# nothing else. The secondaries are the other way round: their events
		# never reach an autoload's _input at all.
		_main_entry = entry
	else:
		win.window_input.connect(_count_event.bind(entry))
	note("window", "watching %s — %s" % [label, describe(win)])


## Stop following windows that have been closed (WindowManager tears the tiles
## down and rebuilds them on every F5 / re-assign).
func forget_closed() -> void:
	var kept: Array[Dictionary] = []
	for entry in _watched:
		var win: Window = entry["win"]
		# Callers free their windows with queue_free, so a closing window is still
		# a valid instance at the moment we are told about it.
		if is_instance_valid(win) and not win.is_queued_for_deletion():
			kept.append(entry)
	_watched = kept
	# Window ids are recycled, so a rebuilt tile can inherit a closed one's id and
	# read as "unchanged" against its predecessor's last state. Drop both caches
	# and let the next poll re-establish them.
	_focused.clear()
	_geometry.clear()
	if not is_instance_valid(_main_entry.get("win")):
		_main_entry = {}


func _count_event(event: InputEvent, entry: Dictionary) -> void:
	var kind := "other"
	if event is InputEventKey:
		kind = "key"
	elif event is InputEventMouseButton:
		kind = "button"
	elif event is InputEventMouseMotion:
		kind = "motion"
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		kind = "touch"
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		kind = "joypad"
	var counts: Dictionary = entry["counts"]
	var first: bool = counts[kind] == 0
	counts[kind] = counts[kind] + 1
	# The first of each class per window is the fact that matters: a Main window
	# that has never seen a mouse button says so in one line, and the absence of
	# that line for one window while its neighbours have it is the whole report.
	if first and kind != "motion" and kind != "joypad":
		note("input", "%s received its FIRST %s event — %s"
				% [entry["label"], kind, event.as_text()])


func _input(event: InputEvent) -> void:
	if not _main_entry.is_empty():
		_count_event(event, _main_entry)


func _on_focus_signal(label: String, gained: bool) -> void:
	note("focus", "%s window %s focus (Godot signal)"
			% [label, "gained" if gained else "lost"])


# --- Polling ---------------------------------------------------------------

## Polled rather than driven by signals alone: a mode the OS changes behind our
## back, a clip rect, and a focus change that never reaches Godot are precisely
## the things no signal fires for.
func _process(delta: float) -> void:
	if not _enabled:
		return
	# Mouse first: a focus change reports where the pointer has been able to
	# reach, and on the frame focus arrives that record must already include
	# this frame's position.
	_poll_mouse()
	_poll_focus()
	_since_geometry += delta
	if _since_geometry >= GEOMETRY_POLL_SECONDS:
		_since_geometry = 0.0
		_refresh_screen_rects()
		_poll_geometry()
	_heartbeat(delta)
	if Input.is_action_just_pressed("dump_window_log"):
		snapshot("F8 — dump requested")


## One line every HEARTBEAT_SECONDS, whether or not anything changed. A log that
## goes quiet is ambiguous — a dead window and a dead logger read the same — and
## this is also the line that shows the fault plainly: the tiles' event counts
## climbing while the Main window's stay at zero.
func _heartbeat(delta: float) -> void:
	_since_heartbeat += delta
	if _since_heartbeat < HEARTBEAT_SECONDS:
		return
	_since_heartbeat = 0.0
	var focused: PackedStringArray = []
	for entry in _watched:
		var win: Window = entry["win"]
		if is_instance_valid(win) and win.is_inside_tree() and win.get_window_id() >= 0 \
				and DisplayServer.window_is_focused(win.get_window_id()):
			focused.append(entry["label"])
	note("alive", "focused=[%s] pointer on screen %d — %s"
			% [" ".join(focused), _pointer_screen, _counts_line()])


func _poll_focus() -> void:
	var changed := false
	for entry in _watched:
		var win: Window = entry["win"]
		if not is_instance_valid(win) or not win.is_inside_tree():
			continue
		var id := win.get_window_id()
		if id < 0:
			continue
		var focused := DisplayServer.window_is_focused(id)
		if _focused.get(id) != focused:
			_focused[id] = focused
			changed = true
			note("focus", "%s (id %d) %s OS focus" % [
					entry["label"], id, "GAINED" if focused else "lost"])
	if changed:
		note("focus", "keyboard focus screen=%d  input so far: %s"
				% [DisplayServer.get_keyboard_focus_screen(), _counts_line()])
		# Reset the pointer's travel record on each focus change, so the log can
		# answer "where could the pointer go AFTER I clicked into that window".
		_mark_pointer_travel("focus change")


func _poll_geometry() -> void:
	for entry in _watched:
		var win: Window = entry["win"]
		if not is_instance_valid(win) or not win.is_inside_tree():
			continue
		var id := win.get_window_id()
		if id < 0:
			continue
		var desc := describe(win)
		if _geometry.get(id, "") != desc:
			_geometry[id] = desc
			note("window", "%s — %s" % [entry["label"], desc])


func _poll_mouse() -> void:
	var mode := DisplayServer.mouse_get_mode()
	if mode != _mouse_mode:
		note("mouse", "mode %s → %s" % [
				MOUSE_MODE_NAMES.get(_mouse_mode, "unset"),
				MOUSE_MODE_NAMES.get(mode, str(mode))])
		_mouse_mode = mode
	# The pointer's reachable area is the only evidence available for a clip
	# rect: Godot cannot read one, but it can watch the pointer fail to leave.
	var pos := DisplayServer.mouse_get_position()
	_pointer_span = _pointer_span.expand(pos) if _pointer_span_valid \
			else Rect2i(pos, Vector2i.ZERO)
	_pointer_span_valid = true
	var screen := _screen_at(pos)
	_pointer_screens[screen] = true
	if screen != _pointer_screen:
		if _pointer_screen != -2:
			note("pointer", "crossed from screen %d to screen %d at %s"
					% [_pointer_screen, screen, str(pos)])
		_pointer_screen = screen


## Report and reset what the pointer has been able to reach. Called on every
## focus change and on every dump, so each report answers "since when".
func _mark_pointer_travel(reason: String) -> void:
	if not _pointer_span_valid:
		return
	var screens: Array = _pointer_screens.keys()
	screens.sort()
	note("pointer", "reached screen(s) %s within %s since the last mark (%s)"
			% [str(screens), str(_pointer_span), reason])
	_pointer_span_valid = false
	_pointer_screens.clear()


func _screen_at(pos: Vector2i) -> int:
	for i in _screen_rects.size():
		if _screen_rects[i].has_point(pos):
			return i
	return -1


func _refresh_screen_rects() -> void:
	var n := DisplayServer.get_screen_count()
	_screen_rects.resize(n)
	for i in n:
		_screen_rects[i] = Rect2i(DisplayServer.screen_get_position(i),
				DisplayServer.screen_get_size(i))


# --- Dumps -----------------------------------------------------------------

## The whole picture at one instant, with `reason` naming what prompted it.
func snapshot(reason: String) -> void:
	if not _enabled:
		return
	note("dump", "======== %s ========" % reason)
	log_screens()
	log_roles()
	var focused: PackedStringArray = []
	for entry in _watched:
		var win: Window = entry["win"]
		if not is_instance_valid(win):
			note("dump", "  %s: window is gone" % entry["label"])
			continue
		var id := win.get_window_id()
		var has_focus: bool = id >= 0 and DisplayServer.window_is_focused(id)
		if has_focus:
			focused.append(entry["label"])
		var focus_owner := win.gui_get_focus_owner()
		note("dump", "  %s: %s" % [entry["label"], describe(win)])
		# A Control holding Godot's GUI focus inside a window the OS has NOT
		# focused is the reported symptom exactly: the button looks live and
		# answers nothing.
		note("dump", "    os_focused=%s  gui_focus=%s" % [
				has_focus, focus_owner.name if focus_owner else "none"])
	# The headline fact, on one line, because it is the question every report of
	# this kind is really asking.
	note("dump", "  OS focus is on: %s" % ("no window of ours" if focused.is_empty()
			else " ".join(focused)))
	note("dump", "  OS window ids: %s" % str(DisplayServer.get_window_list()))
	note("dump", "  keyboard focus screen=%d" % DisplayServer.get_keyboard_focus_screen())
	var pos := DisplayServer.mouse_get_position()
	note("dump", "  pointer at %s (screen %d), mouse mode=%s" % [
			str(pos), _screen_at(pos),
			MOUSE_MODE_NAMES.get(DisplayServer.mouse_get_mode(), "unknown")])
	note("dump", "  input received: %s" % _counts_line())
	_mark_pointer_travel(reason)


## The monitor topology as the DisplayServer currently sees it — re-logged on
## every F5, since a re-detect exists precisely because this can change.
func log_screens() -> void:
	if not _enabled:
		return
	_refresh_screen_rects()
	var n := DisplayServer.get_screen_count()
	note("screens", "%d screen(s), primary=%d" % [n, DisplayServer.get_primary_screen()])
	for i in n:
		note("screens", "  screen %d: pos=%s size=%s usable=%s scale=%.2f dpi=%d refresh=%.1fHz"
				% [i, str(DisplayServer.screen_get_position(i)),
				str(DisplayServer.screen_get_size(i)),
				str(DisplayServer.screen_get_usable_rect(i)), DisplayServer.screen_get_scale(i),
				DisplayServer.screen_get_dpi(i), DisplayServer.screen_get_refresh_rate(i)])


func log_roles() -> void:
	if not _enabled:
		return
	var parts: PackedStringArray = []
	for role: String in DisplayConfig.ALL_ROLES:
		parts.append("%s→%d" % [role.to_upper(), DisplayConfig.get_screen_for_role(role)])
	note("roles", "%s (this setup configured=%s)"
			% [" ".join(parts), DisplayConfig.has_layout_for_current_setup()])


## How many DELIBERATE input events every window has received between them —
## keys, mouse buttons and taps. Pointer motion and joypad traffic are left out
## on purpose: neither means anyone touched anything (a stick at rest still
## reports, and the pointer crosses a window by being nearby). WindowManager
## reads this to know when to stop insisting on focus at launch.
func deliberate_input_count() -> int:
	var total := 0
	for entry in _watched:
		var counts: Dictionary = entry["counts"]
		total += int(counts["key"]) + int(counts["button"]) + int(counts["touch"])
	return total


func _counts_line() -> String:
	var parts: PackedStringArray = []
	for entry in _watched:
		if not is_instance_valid(entry["win"]):
			continue
		var counts: Dictionary = entry["counts"]
		var bits: PackedStringArray = []
		for kind: String in EVENT_KINDS:
			bits.append("%s=%d" % [kind, counts[kind]])
		parts.append("%s[%s]" % [entry["label"], " ".join(bits)])
	return "  ".join(parts)


func _log_environment() -> void:
	var v := Engine.get_version_info()
	note("env", "godot %s  os=%s  renderer=%s  pid=%d  debug_build=%s" % [
			v.get("string", "?"), OS.get_name(),
			ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"),
			OS.get_process_id(), OS.is_debug_build()])
	note("env", "display server=%s  embed_subwindows=%s  cmdline=%s" % [
			DisplayServer.get_name(),
			ProjectSettings.get_setting("display/window/subwindows/embed_subwindows", true),
			str(OS.get_cmdline_args())])


func _notification(what: int) -> void:
	# Window- and application-level focus as the engine reports it, alongside the
	# polled DisplayServer view. The two disagreeing is itself worth knowing.
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN:
			note("focus", "application FOCUS IN")
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			note("focus", "application FOCUS OUT")
		NOTIFICATION_WM_WINDOW_FOCUS_IN:
			note("focus", "main window focus IN (engine notification)")
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			note("focus", "main window focus OUT (engine notification)")
		NOTIFICATION_WM_MOUSE_ENTER:
			note("mouse", "pointer entered the main window")
		NOTIFICATION_WM_MOUSE_EXIT:
			note("mouse", "pointer left the main window")
