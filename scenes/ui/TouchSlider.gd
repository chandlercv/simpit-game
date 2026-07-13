extends Control
## Vertical slider that answers both raw touch and mouse events. Needed
## because both touch emulations are off project-wide (plan Phase 3), so
## stock Range controls would be mouse-only on the tablet. Tap anywhere on
## the track to set the value directly — tap-to-set suits spacedesk's ~30fps
## + latency better than requiring a precise grab — and drags also work.

signal user_changed_value(value: float)

@export var accent: Color = Color(0.3, 0.9, 0.78)
@export var label: String = ""

var value: float = 0.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()

var _mouse_dragging := false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_apply(event.position)
		accept_event()
	elif event is InputEventScreenDrag:
		_apply(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_dragging = event.pressed
		if event.pressed:
			_apply(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _mouse_dragging:
		_apply(event.position)
		accept_event()


func _apply(pos: Vector2) -> void:
	var track := _track_rect()
	value = 1.0 - clampf((pos.y - track.position.y) / track.size.y, 0.0, 1.0)
	user_changed_value.emit(value)


func _track_rect() -> Rect2:
	# Room for the percent readout above and the channel label below.
	return Rect2(size.x / 2.0 - 11.0, 28.0, 22.0, maxf(size.y - 28.0 - 34.0, 10.0))


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var track := _track_rect()
	draw_rect(track, Color(accent, 0.4), false, 1.0)
	for i in range(1, 4):
		var y := track.position.y + track.size.y * float(i) / 4.0
		draw_line(Vector2(track.position.x - 5, y),
				Vector2(track.position.x, y), Color(accent, 0.4), 1.0)
	var fill_h := (track.size.y - 4.0) * value
	draw_rect(Rect2(track.position.x + 2.0, track.end.y - 2.0 - fill_h,
			track.size.x - 4.0, fill_h), Color(accent, 0.75))
	draw_string(font, Vector2(0, 18), "%d%%" % roundi(value * 100.0),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, accent)
	draw_string(font, Vector2(0, size.y - 10), label,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(accent, 0.8))
