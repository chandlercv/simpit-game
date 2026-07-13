extends Label
## Thin diagnostic footer on every secondary display: role, actual screen
## index, window size, and the shared GameState tick. Replaces Phase 1's
## full-screen RolePanel — the non-drifting tick stays visible because it's
## the cheapest way to spot a stalled window over spacedesk.

@export var role_name: String = "ROLE"
@export var accent: Color = Color(0.9, 0.9, 0.9)


func _ready() -> void:
	add_theme_color_override("font_color", accent.darkened(0.45))
	add_theme_font_size_override("font_size", 13)
	GameState.tick_changed.connect(_refresh)
	_refresh(GameState.tick)


func _refresh(current_tick: int) -> void:
	var win := get_window()
	if win == null:
		return
	text = "%s — SCREEN %d — %d × %d — TICK %06d" % [
		role_name, win.current_screen, win.size.x, win.size.y, current_tick]
