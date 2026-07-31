extends Node
## Maps logical display roles to physical screen indices, persisted per monitor
## setup in user://display_config.cfg.
##
## Persistence is keyed by a "setup signature" (screen count + each screen's
## size/position) so the same rig reuses its saved layout while a different
## monitor arrangement gets its own — virtual-display index order is not
## guaranteed stable across reconnects, so the count/geometry is what we key on.
##
## Roles are data, not code: WindowManager loops over whatever is configured
## here, so adding a fifth display is a config entry + a scene, not a code change.
## When fewer screens are present than roles, the game prompts (see
## needs_setup_prompt) with tools/DisplaySetup so the player assigns roles to
## screens; two roles sharing a screen become a tabbed host.

signal mapping_changed

const CONFIG_PATH := "user://display_config.cfg"

const ROLE_MAIN := "main"
const ROLE_TACTICAL := "tactical"
const ROLE_MFD := "mfd"
const ROLE_CAMERA := "camera"

const ALL_ROLES: Array[String] = [ROLE_MAIN, ROLE_TACTICAL, ROLE_MFD, ROLE_CAMERA]

## Old role names -> current, so a layout saved before the tablet→mfd /
## chart→camera rename keeps its screen assignment instead of re-prompting.
const _ROLE_ALIASES: Dictionary = {"tablet": ROLE_MFD, "chart": ROLE_CAMERA}

var _role_to_screen: Dictionary = {}
## Roles explicitly assigned (loaded from disk or via set_role_screen/commit_all),
## as opposed to back-filled by _fill_defaults(). Only these get persisted, and a
## setup counts as "configured" only once every role is user-set.
var _user_set: Dictionary = {}


func _ready() -> void:
	reload()


## A stable string identifying the current monitor setup: screen count plus each
## screen's size and position. Different arrangements hash to different sections.
func _signature() -> String:
	var parts: PackedStringArray = []
	var n := DisplayServer.get_screen_count()
	parts.append("n%d" % n)
	for i in n:
		var s := DisplayServer.screen_get_size(i)
		var p := DisplayServer.screen_get_position(i)
		parts.append("%dx%d@%d,%d" % [s.x, s.y, p.x, p.y])
	return "|".join(parts)


func _section_for(sig: String) -> String:
	return "layout_%d" % sig.hash()


## Reads the saved layout for the current setup (if any), drops entries that
## point at screens that no longer exist, and fills any missing roles with a
## sensible suggestion across the screens that are present.
func reload() -> void:
	_role_to_screen.clear()
	_user_set.clear()
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		var sig := _signature()
		var section := _section_for(sig)
		# Guard against 32-bit section-hash collisions (or a stale section from a
		# prior arrangement that hashes the same): only trust the saved layout if
		# the stored full signature matches the current setup.
		if cfg.get_value(section, "_sig", "") == sig:
			for role in ALL_ROLES:
				var value: int = cfg.get_value(section, role, -1)
				if value >= 0:
					_role_to_screen[role] = value
					_user_set[role] = true
			# Adopt a pre-rename layout: an old role key fills in for its new name
			# when the new one wasn't itself saved.
			for old_role: String in _ROLE_ALIASES:
				var new_role: String = _ROLE_ALIASES[old_role]
				if not _user_set.get(new_role, false):
					var value: int = cfg.get_value(section, old_role, -1)
					if value >= 0:
						_role_to_screen[new_role] = value
						_user_set[new_role] = true
	_fill_defaults()


func get_screen_for_role(role: String) -> int:
	return _role_to_screen.get(role, 0)


## Roles currently assigned to the given screen (used by the setup chooser and
## by WindowManager to decide which screens need a tabbed host).
func get_roles_for_screen(screen: int) -> Array[String]:
	var roles: Array[String] = []
	for role in ALL_ROLES:
		if _role_to_screen.get(role, -1) == screen:
			roles.append(role)
	return roles


func set_role_screen(role: String, screen: int) -> void:
	_role_to_screen[role] = screen
	_user_set[role] = true
	save()
	mapping_changed.emit()


## Marks the whole current mapping (including back-filled suggestions the player
## accepted as-is) as user-set and persists it — called when the setup chooser
## is confirmed so this setup counts as configured and won't prompt again.
func commit_all() -> void:
	for role in ALL_ROLES:
		_user_set[role] = true
	save()
	mapping_changed.emit()


## True once every role has been explicitly assigned for the current setup.
func has_layout_for_current_setup() -> bool:
	return _user_set.size() == ALL_ROLES.size()


## True when there aren't enough screens for one-role-per-screen and this setup
## hasn't been configured yet — WindowManager shows the chooser in that case.
func needs_setup_prompt() -> bool:
	var screen_count := maxi(DisplayServer.get_screen_count(), 1)
	if screen_count >= ALL_ROLES.size():
		return false
	return not has_layout_for_current_setup()


func save() -> void:
	var cfg := ConfigFile.new()
	# Preserve other setups' sections; we only rewrite the current one. A missing
	# file is fine (first save), but if the file exists and can't be parsed,
	# rewriting it would silently drop every other setup's saved layout — so move
	# the unreadable file aside (recoverable) instead of clobbering it in place.
	var err := cfg.load(CONFIG_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("DisplayConfig: %s unreadable (error %d); moving it to %s.bak before rewrite." % [CONFIG_PATH, err, CONFIG_PATH])
		if FileAccess.file_exists(CONFIG_PATH + ".bak"):
			DirAccess.remove_absolute(CONFIG_PATH + ".bak")
		DirAccess.rename_absolute(CONFIG_PATH, CONFIG_PATH + ".bak")
	var sig := _signature()
	var section := _section_for(sig)
	cfg.set_value(section, "_sig", sig)
	for role in ALL_ROLES:
		if _user_set.get(role, false):
			cfg.set_value(section, role, _role_to_screen[role])
	cfg.save(CONFIG_PATH)


## Suggested placement used both as the chooser's pre-fill and as the no-prompt
## default: MAIN on the primary screen, each other role on the next free screen,
## and any overflow packed onto the last screen so the Main view stays clean.
func _fill_defaults() -> void:
	var screen_count := maxi(DisplayServer.get_screen_count(), 1)
	# Drop stale indices from a previous monitor topology.
	for role in _role_to_screen.keys():
		if _role_to_screen[role] >= screen_count:
			_role_to_screen.erase(role)
	if not _role_to_screen.has(ROLE_MAIN):
		_role_to_screen[ROLE_MAIN] = DisplayServer.get_primary_screen()
	var used: Array = _role_to_screen.values()
	for role in ALL_ROLES:
		if _role_to_screen.has(role):
			continue
		var assigned := -1
		for i in screen_count:
			if not used.has(i):
				assigned = i
				break
		if assigned == -1:
			# Fewer screens than roles: pack overflow onto the last screen
			# (WindowManager makes a shared screen a tabbed host). On a single
			# screen this is the main screen, i.e. the dimmed overlay.
			assigned = screen_count - 1
		_role_to_screen[role] = assigned
		used.append(assigned)
