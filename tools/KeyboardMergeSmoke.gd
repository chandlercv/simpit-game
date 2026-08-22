extends Node
## Headless checks for InputRouter._merge_keyboard: a user keyboard.json overrides
## the shipped layout key for key, but must not swallow an action that postdates
## the file. Regression guard for the softlock where a profile saved before the
## masters and the drive selector arrived left a keyboard pilot with no way to
## switch the bus back on or start the drive — sprung by following the AFTER
## LANDING checklist, which calls for all three OFF.
##
##   godot --headless res://tools/KeyboardMergeSmoke.tscn

var _failures: Array[String] = []


func _ready() -> void:
	_check_rules()
	_check_shipped_layout()

	if _failures.is_empty():
		print("KEYBOARD MERGE SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("KEYBOARD MERGE SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


## The merge rules, on a synthetic two-key built-in so the assertions don't move
## every time the shipped layout does.
func _check_rules() -> void:
	var builtin := {
		"guid": "keyboard",
		"keys": [
			{"key": KEY_9, "action": "master_bat"},
			{"key": KEY_C, "action": "ops_cut"},
		],
	}

	# A file with no `known_actions` predates the field: every unbound shipped
	# default comes back. This is the case that repairs the profiles on disk.
	var legacy := _merge(builtin, {"guid": "keyboard", "keys": [
		{"key": KEY_X, "action": "ops_cut"},
	]})
	_check(legacy.get("master_bat", -1) == KEY_9,
			"legacy file (no known_actions) gets the missing default back")
	_check(legacy.get("ops_cut", -1) == KEY_X,
			"legacy file keeps its own bind for an action it did bind")
	_check(legacy.size() == 2, "legacy merge adds nothing else")

	# The action was offered and left unbound: the pilot cleared it, and it stays
	# cleared. This is what stops the merge from resurrecting deliberate clears.
	var cleared := _merge(builtin, {"guid": "keyboard", "keys": [],
			"known_actions": ["master_bat", "ops_cut"]})
	_check(cleared.is_empty(), "an offered-but-unbound action stays cleared")

	# Offered, and one of them bound elsewhere: the pilot's key wins, and the
	# untouched-but-offered one is still not resurrected.
	var rebound := _merge(builtin, {"guid": "keyboard", "keys": [
		{"key": KEY_B, "action": "master_bat"},
	], "known_actions": ["master_bat", "ops_cut"]})
	_check(rebound.get("master_bat", -1) == KEY_B and rebound.size() == 1,
			"a user bind wins and is not duplicated by its default")

	# A default whose KEY the pilot reassigned to something else is left out rather
	# than bound twice — two actions on one key is worse than one unbound row.
	var collision := _merge(builtin, {"guid": "keyboard", "keys": [
		{"key": KEY_9, "action": "ops_approach"},
	]})
	_check(not collision.has("master_bat"),
			"a default whose key was reassigned is skipped, not double-bound")
	_check(collision.get("ops_approach", -1) == KEY_9 and collision.get("ops_cut", -1) == KEY_C,
			"the free default still lands alongside the reassigned key")

	# JSON numbers parse as floats; the merge must still see the collision and the
	# bound action, not treat 67.0 and 67 as different keys.
	var floaty := _merge(builtin, {"guid": "keyboard", "keys": [
		{"key": 67.0, "action": "ops_approach"},
	]})
	_check(not floaty.has("ops_cut"), "a float keycode from JSON still collides")


## The real shipped layout against a real-shaped legacy file: the actions added
## after the last schema change must come back, or the ship is unflyable from the
## keyboard once the arrival checklist has been run.
func _check_shipped_layout() -> void:
	var builtin := {}
	for profile: Dictionary in InputRouter.BUILTIN_PROFILES:
		if String(profile.get("guid", "")) == InputRouter.KEYBOARD_GUID:
			builtin = profile
	_check(not builtin.is_empty(), "the shipped keyboard profile exists")
	if builtin.is_empty():
		return

	# What a keyboard.json written before commit 3ad7088 looks like: a plain `keys`
	# array, no `known_actions`, and nothing for the electrical or drive controls.
	var stale: Array = []
	for spec: Dictionary in builtin.get("keys", []):
		if not (spec["action"] as String) in _POST_DATED:
			stale.append(spec.duplicate())
	var merged := _merge(builtin, {"guid": "keyboard", "keys": stale})
	for action: String in _POST_DATED:
		_check(merged.has(action), "%s is reachable again after the merge" % action)
	_check(merged.size() == (builtin["keys"] as Array).size(),
			"the merged layout is the whole shipped layout, no more")


## The actions a pre-3ad7088 keyboard.json cannot contain. Kept literal (not read
## off the built-in) so the guard keeps asserting these exact controls even if the
## layout is rearranged around them.
const _POST_DATED: Array[String] = [
	"master_bat", "master_alt", "drive_mode_prev", "drive_mode_next", "drive_boost",
]


## action -> keycode of a merge result, which is the shape the assertions care
## about (the merge returns a whole profile).
func _merge(builtin: Dictionary, user: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for spec: Dictionary in InputRouter._merge_keyboard(builtin, user).get("keys", []):
		out[String(spec["action"])] = int(spec["key"])
	return out


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
