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

## When true the slider ignores input and dims. Nothing in the power model sets
## this today — a starved bus is shown with `delivered`, not by locking the
## control, because the setting stays the pilot's either way.
var disabled := false:
	set(v):
		disabled = v
		if v:
			_mouse_dragging = false
			_touch_index = -1
		queue_redraw()

## What is actually being DELIVERED against `value`, or a negative number when
## there is no separate figure to show. Drawn as a second, brighter fill inside
## the handle's own so a starved channel reads as "you asked for this much and
## are getting this much" rather than as a setting that moved on its own.
var delivered: float = -1.0:
	set(v):
		delivered = v
		queue_redraw()

var _mouse_dragging := false
## Index of the finger currently driving the slider, or -1 when none. Tracking
## the specific touch means a second finger lifting off doesn't cancel the drag
## the still-held finger owns.
var _touch_index := -1


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index == -1:
				_touch_index = event.index
				_apply(event.position)
		elif event.index == _touch_index:
			_touch_index = -1
		accept_event()
	elif event is InputEventScreenDrag and event.index == _touch_index:
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
	# Dim everything to read as inert while a master switch locks the mix.
	var tint := accent.darkened(0.5) if disabled else accent
	var track := _track_rect()
	draw_rect(track, Color(tint, 0.4), false, 1.0)
	for i in range(1, 4):
		var y := track.position.y + track.size.y * float(i) / 4.0
		draw_line(Vector2(track.position.x - 5, y),
				Vector2(track.position.x, y), Color(tint, 0.4), 1.0)
	var fill_h := (track.size.y - 4.0) * value
	# The setting, drawn faint when delivery is falling short of it, so the solid
	# bar is always the power the ship is really making.
	var starved := delivered >= 0.0 and delivered < value - 0.005
	draw_rect(Rect2(track.position.x + 2.0, track.end.y - 2.0 - fill_h,
			track.size.x - 4.0, fill_h), Color(tint, 0.3 if starved else 0.75))
	if starved:
		var got_h := (track.size.y - 4.0) * delivered
		draw_rect(Rect2(track.position.x + 2.0, track.end.y - 2.0 - got_h,
				track.size.x - 4.0, got_h), Color(tint, 0.85))
	var readout := "%d%%" % roundi(value * 100.0)
	if starved:
		readout = "%d→%d%%" % [roundi(value * 100.0), roundi(delivered * 100.0)]
	draw_string(font, Vector2(0, 18), readout,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, tint)
	draw_string(font, Vector2(0, size.y - 10), label,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(tint, 0.8))
