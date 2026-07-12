extends Node
## Maps logical display roles to physical screen indices, persisted in
## user://display_config.cfg.
##
## Screen indices come from tools/ScreenLabeler.tscn — run it whenever spacedesk
## reconnects, because virtual-display index order is not guaranteed stable
## across reconnects. Roles are data, not code: WindowManager loops over
## whatever is configured here, so adding a fifth display is a config entry +
## a scene, not a code change.

signal mapping_changed

const CONFIG_PATH := "user://display_config.cfg"
const SECTION := "roles"

const ROLE_MAIN := "main"
const ROLE_TACTICAL := "tactical"
const ROLE_TABLET := "tablet"
const ROLE_CHART := "chart"

const ALL_ROLES: Array[String] = [ROLE_MAIN, ROLE_TACTICAL, ROLE_TABLET, ROLE_CHART]

var _role_to_screen: Dictionary = {}


func _ready() -> void:
	reload()


## Reads the config file, drops entries that point at screens that no longer
## exist (e.g. spacedesk not connected), and fills any missing roles with
## sensible defaults across the screens that are present.
func reload() -> void:
	_role_to_screen.clear()
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		for role in ALL_ROLES:
			var value: int = cfg.get_value(SECTION, role, -1)
			if value >= 0:
				_role_to_screen[role] = value
	_fill_defaults()


func get_screen_for_role(role: String) -> int:
	return _role_to_screen.get(role, 0)


## Roles currently assigned to the given screen (used by the ScreenLabeler).
func get_roles_for_screen(screen: int) -> Array[String]:
	var roles: Array[String] = []
	for role in ALL_ROLES:
		if _role_to_screen.get(role, -1) == screen:
			roles.append(role)
	return roles


func set_role_screen(role: String, screen: int) -> void:
	_role_to_screen[role] = screen
	save()
	mapping_changed.emit()


func save() -> void:
	var cfg := ConfigFile.new()
	for role in ALL_ROLES:
		cfg.set_value(SECTION, role, _role_to_screen.get(role, 0))
	cfg.save(CONFIG_PATH)


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
			# Fewer screens than roles: double up on the main screen.
			# WindowManager cascades shared-screen windows so nothing is buried.
			assigned = _role_to_screen[ROLE_MAIN]
		_role_to_screen[role] = assigned
		used.append(assigned)
