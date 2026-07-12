extends Control
## Dev utility: shows a borderless overlay on every screen DisplayServer can
## see, labeled with that screen's index, and lets you assign a display role to
## each screen with one click. Assignments are written straight into
## user://display_config.cfg via DisplayConfig.
##
## Run it the moment spacedesk is connected — virtual-display index order isn't
## guaranteed stable across reconnects:
##   godot --path . res://tools/ScreenLabeler.tscn
## (or open the scene in the editor and press F6). Esc quits.

const OVERLAY_FRACTION := 0.6

var _assigned_labels: Array[Label] = []

@onready var _summary: Label = %SummaryLabel


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	win.title = "Screen Labeler — Esc quits"
	win.size = Vector2i(640, 420)
	win.always_on_top = true
	win.current_screen = DisplayServer.get_primary_screen()
	win.move_to_center()
	_print_screens()
	for i in DisplayServer.get_screen_count():
		add_child(_build_overlay(i))
	DisplayConfig.mapping_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _print_screens() -> void:
	print("=== ScreenLabeler: %d screen(s) detected ===" % DisplayServer.get_screen_count())
	for i in DisplayServer.get_screen_count():
		var pos := DisplayServer.screen_get_position(i)
		var size := DisplayServer.screen_get_size(i)
		var primary := " (primary)" if i == DisplayServer.get_primary_screen() else ""
		print("  screen %d: %d x %d at (%d, %d)%s" % [i, size.x, size.y, pos.x, pos.y, primary])


func _build_overlay(screen: int) -> Window:
	var s_pos := DisplayServer.screen_get_position(screen)
	var s_size := DisplayServer.screen_get_size(screen)

	var w := Window.new()
	w.borderless = true
	w.always_on_top = true
	w.size = Vector2i(Vector2(s_size) * OVERLAY_FRACTION)
	w.position = s_pos + (s_size - w.size) / 2
	w.window_input.connect(_on_overlay_input)
	w.close_requested.connect(get_tree().quit)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	var index_label := Label.new()
	index_label.text = "SCREEN %d" % screen
	index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	index_label.add_theme_font_size_override("font_size", 120)
	vbox.add_child(index_label)

	var res_label := Label.new()
	res_label.text = "%d × %d at (%d, %d)" % [s_size.x, s_size.y, s_pos.x, s_pos.y]
	res_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res_label.add_theme_font_size_override("font_size", 26)
	res_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	vbox.add_child(res_label)

	var assigned := Label.new()
	assigned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	assigned.add_theme_font_size_override("font_size", 32)
	assigned.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55))
	vbox.add_child(assigned)
	_assigned_labels.append(assigned)

	var hint := Label.new()
	hint.text = "assign a role to this screen:"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 20)
	vbox.add_child(hint)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	vbox.add_child(buttons)
	for role in DisplayConfig.ALL_ROLES:
		var btn := Button.new()
		btn.text = role.to_upper()
		btn.custom_minimum_size = Vector2(140, 56)
		btn.pressed.connect(func() -> void: DisplayConfig.set_role_screen(role, screen))
		buttons.add_child(btn)

	return w


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _refresh() -> void:
	for screen in _assigned_labels.size():
		var roles := DisplayConfig.get_roles_for_screen(screen)
		var text := "assigned: —"
		if not roles.is_empty():
			text = "assigned: " + ", ".join(roles).to_upper()
		_assigned_labels[screen].text = text
	var lines: PackedStringArray = []
	for role in DisplayConfig.ALL_ROLES:
		lines.append("%-10s ->  screen %d" % [role, DisplayConfig.get_screen_for_role(role)])
	_summary.text = "\n".join(lines)
