extends Node
## User-authored HOTAS binding profiles, one JSON file per device GUID under
## user://input_profiles/. These OVERRIDE InputRouter's shipped BUILTIN_PROFILES
## (matched by GUID) or add support for a device the game has never seen — so a
## tester can map an arbitrary stick (e.g. a Thrustmaster T.16000M) without the
## dev owning that hardware or anyone editing GDScript.
##
## The on-disk schema mirrors InputRouter.BUILTIN_PROFILES entry-for-entry so the
## two are interchangeable — a loaded profile is fed straight into _bind_hotas():
##   {
##     "name": "Thrustmaster T.16000M",     # label only
##     "guid": "03...",                      # match key (Input.get_joy_guid)
##     "axes":    [{"axis":1,"neg":"pitch_down","pos":"pitch_up"}],
##     "buttons": [{"button":0,"action":"ops_cut"}],
##     "throttle": {"axis":2,"idle":1.0,"full":-1.0},   # optional
##     "hid_axes":[{"source":"x52_mouse_x","neg":"yaw_left","pos":"yaw_right"}], # optional
##     "reserved_buttons": []                # documentation only
##   }
##
## JSON (not ConfigFile like DisplayConfig) because the payload is nested arrays
## of dicts that a human edits by hand and a tester mails back; ConfigFile is for
## flat key=value. We keep DisplayConfig's discipline though: guard every read,
## and never let one unreadable file take out the others.

signal profiles_changed

const PROFILE_DIR := "user://input_profiles"

## The remapper and file loader both write/read here. Keys are lowercase GUIDs.


func _ready() -> void:
	_ensure_dir()


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(PROFILE_DIR):
		DirAccess.make_dir_recursive_absolute(PROFILE_DIR)


func _path_for(guid: String) -> String:
	return "%s/%s.json" % [PROFILE_DIR, guid]


## Every valid user profile on disk, newest-mtime order irrelevant (InputRouter
## keys them by GUID). A file that won't parse or lacks a GUID is skipped with a
## warning, never fatal — one bad file must not block the others.
func get_user_profiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(PROFILE_DIR)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var profile := _load_file(PROFILE_DIR + "/" + file_name)
		if not profile.is_empty():
			out.append(profile)
	return out


func _load_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_warning("InputConfig: %s empty or unreadable — skipped" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("InputConfig: %s is not a JSON object — skipped" % path)
		return {}
	var profile: Dictionary = parsed
	if String(profile.get("guid", "")).is_empty():
		push_warning("InputConfig: %s has no \"guid\" — skipped" % path)
		return {}
	return profile


## Write one device's profile; overwrites the file for that GUID. Emits
## profiles_changed so InputRouter rebinds live (same path as a replug).
func save_profile(profile: Dictionary) -> void:
	var guid := String(profile.get("guid", ""))
	if guid.is_empty():
		push_warning("InputConfig.save_profile: profile has no guid; not saved")
		return
	_ensure_dir()
	var file := FileAccess.open(_path_for(guid), FileAccess.WRITE)
	if file == null:
		push_warning("InputConfig.save_profile: cannot write %s" % _path_for(guid))
		return
	file.store_string(JSON.stringify(profile, "\t"))
	file.close()
	profiles_changed.emit()


func delete_profile(guid: String) -> void:
	var path := _path_for(guid)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		profiles_changed.emit()
