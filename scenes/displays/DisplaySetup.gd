extends Control
class_name DisplaySetup
## In-game "assign displays" chooser, shown at boot the first time a monitor
## setup with fewer screens than roles is seen (see DisplayConfig.needs_setup_prompt),
## and re-openable anytime with the open_display_setup hotkey.
##
## Factored from tools/ScreenLabeler: every screen gets a numbered overlay window
## whose role buttons assign that role to that screen (DisplayConfig.set_role_screen);
## two or more roles on one screen become a tabbed host (a dimmed overlay on the
## Main screen). The mapping is pre-filled with DisplayConfig's suggestion, so the
## common case is a single confirming click on START.
##
## Emits `confirmed` once the player commits; WindowManager then builds the real
## display windows from the saved mapping.

signal confirmed

const OVERLAY_FRACTION := 0.62

var _overlays: Array[Window] = []
var _assigned_labels: Array[Label] = []
var _summary: Label


## Build the central panel on the Main window plus a labeled overlay on every
## screen. Call after adding this node to the tree.
func start() -> void:
	if DisplayServer.get_name() == "headless":
		# Nothing to choose without a display server; confirm the default.
		DisplayConfig.commit_all()
		confirmed.emit()
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_center()
	for i in DisplayServer.get_screen_count():
		var overlay := _build_overlay(i)
		_overlays.append(overlay)
		add_child(overlay)
	if not DisplayConfig.mapping_changed.is_connected(_refresh):
		DisplayConfig.mapping_changed.connect(_refresh)
	_refresh()


func _build_center() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.03, 0.05, 0.92)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "ASSIGN DISPLAYS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Fewer screens than displays. Each screen shows a card — tap a role\n" \
		+ "to put it on that screen. Two or more roles on one screen share a\n" \
		+ "tabbed panel (a dimmed overlay on the Main screen; F1/F2/F3 or the\n" \
		+ "tabs switch between them). The suggestion below already works —\n" \
		+ "press START to accept it, or reassign first."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
	vbox.add_child(hint)

	_summary = Label.new()
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.add_theme_font_size_override("font_size", 22)
	_summary.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55))
	vbox.add_child(_summary)

	var start_btn := Button.new()
	start_btn.text = "START"
	start_btn.custom_minimum_size = Vector2(220, 64)
	start_btn.focus_mode = Control.FOCUS_NONE
	start_btn.pressed.connect(_confirm)
	var start_center := CenterContainer.new()
	start_center.add_child(start_btn)
	vbox.add_child(start_center)


func _build_overlay(screen: int) -> Window:
	var s_pos := DisplayServer.screen_get_position(screen)
	var s_size := DisplayServer.screen_get_size(screen)

	var w := Window.new()
	w.title = "Assign — Screen %d" % screen
	w.borderless = true
	w.always_on_top = true
	w.size = Vector2i(Vector2(s_size) * OVERLAY_FRACTION)
	w.position = s_pos + (s_size - w.size) / 2
	w.close_requested.connect(_confirm)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.10, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var index_label := Label.new()
	index_label.text = "SCREEN %d" % screen
	index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	index_label.add_theme_font_size_override("font_size", 96)
	vbox.add_child(index_label)

	var res_label := Label.new()
	res_label.text = "%d × %d at (%d, %d)" % [s_size.x, s_size.y, s_pos.x, s_pos.y]
	res_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res_label.add_theme_font_size_override("font_size", 24)
	res_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	vbox.add_child(res_label)

	var assigned := Label.new()
	assigned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	assigned.add_theme_font_size_override("font_size", 30)
	assigned.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55))
	vbox.add_child(assigned)
	_assigned_labels.append(assigned)

	var hint := Label.new()
	hint.text = "put a display on this screen:"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	vbox.add_child(hint)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	vbox.add_child(buttons)
	for role in DisplayConfig.ALL_ROLES:
		var btn := Button.new()
		btn.text = role.to_upper()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(130, 52)
		btn.pressed.connect(DisplayConfig.set_role_screen.bind(role, screen))
		buttons.add_child(btn)

	return w


func _confirm() -> void:
	DisplayConfig.commit_all()
	for w in _overlays:
		if is_instance_valid(w):
			w.queue_free()
	_overlays.clear()
	confirmed.emit()


func _refresh() -> void:
	for screen in _assigned_labels.size():
		var roles := DisplayConfig.get_roles_for_screen(screen)
		var text := "assigned: —"
		if not roles.is_empty():
			text = "assigned: " + ", ".join(roles).to_upper()
		_assigned_labels[screen].text = text
	if _summary:
		var lines: PackedStringArray = []
		for role in DisplayConfig.ALL_ROLES:
			lines.append("%-9s → screen %d" % [role.to_upper(), DisplayConfig.get_screen_for_role(role)])
		_summary.text = "\n".join(lines)
