extends VBoxContainer
## MFD SALVAGE page: the salvage workflow in one place — sensor-mode selector,
## approach/cut ops, and the cut-target list. Picking the cut point is a list
## selection here (tap a member), not a click on the Tactical scope, which is now
## a read-only instrument. Rows mirror the ContactList pattern: a Button per
## structural member whose `pressed` calls the SalvageSystem.select_member intent;
## GameState.selected_member_id stays the single source of truth, so OpsBar and
## the scope react identically no matter where the selection came from.

const ButtonTheme := preload("res://scenes/ui/ButtonTheme.gd")
const SensorModeBarScript := preload("res://scenes/ui/SensorModeBar.gd")
const OpsBarScript := preload("res://scenes/ui/OpsBar.gd")

@export var accent: Color = Color(0.3, 0.9, 0.78)

var _list: VBoxContainer
var _rows: Dictionary = {}   # member id -> Button
var _empty: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)

	var sensors := SensorModeBarScript.new()
	sensors.accent = accent
	sensors.add_theme_constant_override("separation", 8)
	add_child(sensors)

	var ops := OpsBarScript.new()
	ops.accent = accent
	ops.add_theme_constant_override("separation", 8)
	add_child(ops)

	var header := Label.new()
	header.text = "CUT TARGETS — TAP TO SELECT"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", accent)
	add_child(header)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	_empty = Label.new()
	_empty.add_theme_font_size_override("font_size", 13)
	_empty.add_theme_color_override("font_color", Color(accent, 0.55))
	_list.add_child(_empty)

	GameState.wreck_scanned.connect(_rebuild)
	GameState.wreck_member_cut.connect(func(_id: int) -> void: _rebuild())
	GameState.wreck_members_lost.connect(_rebuild)
	GameState.site_reset.connect(_rebuild)
	GameState.selected_member_changed.connect(func(_id: int) -> void: _refresh())
	_rebuild()


func _rebuild() -> void:
	for id: int in _rows:
		_rows[id].queue_free()
	_rows.clear()
	var members: Array = GameState.wreck.get("members", [])
	if not GameState.wreck.get("scanned", false) or members.is_empty():
		_empty.text = "NO STRUCTURAL DATA — SCAN THE WRECK (STRUCT MODE)"
		_empty.visible = true
		return
	_empty.visible = false
	for member: Dictionary in members:
		var row := Button.new()
		row.flat = true
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.focus_mode = Control.FOCUS_NONE
		row.add_theme_font_size_override("font_size", 13)
		var gone: bool = member["cut"] or member["destroyed"]
		row.disabled = gone
		if not gone:
			row.pressed.connect(SalvageSystem.select_member.bind(member["id"]))
		_list.add_child(row)
		_rows[member["id"]] = row
	_refresh()


func _refresh() -> void:
	for member: Dictionary in GameState.wreck.get("members", []):
		var id: int = member["id"]
		if not _rows.has(id):
			continue
		var row: Button = _rows[id]
		var is_selected: bool = id == GameState.selected_member_id
		var suffix := ""
		if member["destroyed"]:
			suffix = " (LOST)"
		elif member["cut"]:
			suffix = " (CUT)"
		row.text = "%s%s — %s — RISK +%d%%%s" % [
			"► " if is_selected else "   ",
			member["name"], SalvageSystem.load_class(member),
			roundi(SalvageSystem.predicted_spike(member) * 100.0), suffix]
		var color := Color(accent, 0.4) if (member["cut"] or member["destroyed"]) \
				else (accent if is_selected else Color(accent, 0.7))
		if SalvageSystem.load_class(member) == "HIGH" and not is_selected \
				and not (member["cut"] or member["destroyed"]):
			color = Color(1.0, 0.5, 0.2, 0.8)
		row.add_theme_color_override("font_color", color)
		row.add_theme_color_override("font_hover_color", color.lightened(0.2))
		row.add_theme_color_override("font_pressed_color", color)
