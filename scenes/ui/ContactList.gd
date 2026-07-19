extends VBoxContainer
## Target lock list for the Tactical display: every sensor contact with live
## bearing/range, click a row to lock it (same intent as clicking a scope
## blip). The complete, omnidirectional list belongs here, not on the main
## HUD (plan Phase 2 rule of thumb).

@export var accent: Color = Color(1.0, 0.72, 0.2)

var _rows: Dictionary = {}


func _ready() -> void:
	GameState.contacts_changed.connect(_rebuild)
	GameState.tracked_contact_changed.connect(func(_id: int) -> void: _refresh())
	GameState.tick_changed.connect(func(_tick: int) -> void: _refresh())
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_rows.clear()
	var header := Label.new()
	header.text = "CONTACTS — LOCK LIST"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", accent)
	add_child(header)
	for contact in GameState.contacts:
		var row := Button.new()
		row.flat = true
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.focus_mode = Control.FOCUS_NONE
		row.add_theme_font_size_override("font_size", 13)
		row.pressed.connect(GameState.set_tracked_contact.bind(contact["id"]))
		add_child(row)
		_rows[contact["id"]] = row
	_refresh()


func _refresh() -> void:
	var ship_pos: Vector3 = GameState.local_ship()["transform"].origin
	for contact in GameState.contacts:
		if not _rows.has(contact["id"]):
			continue
		var row: Button = _rows[contact["id"]]
		var rel: Vector3 = contact["position"] - ship_pos
		var bearing := fposmod(rad_to_deg(atan2(rel.x, -rel.z)), 360.0)
		var is_tracked: bool = contact["id"] == GameState.tracked_contact_id
		row.text = "%s%s%s — BRG %03d — %d M" % [
			"► " if is_tracked else "   ",
			"! " if contact["threat"] else "",
			contact["name"], roundi(bearing), roundi(rel.length())]
		var color := accent if is_tracked else Color(accent, 0.55)
		if contact["threat"]:
			color = Color(1.0, 0.42, 0.15, 1.0 if is_tracked else 0.7)
		row.add_theme_color_override("font_color", color)
		row.add_theme_color_override("font_hover_color", color.lightened(0.2))
		row.add_theme_color_override("font_pressed_color", color)
