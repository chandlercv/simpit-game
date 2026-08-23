extends Control
class_name RoleTabHost
## Hosts one or more secondary-display role panels and shows one at a time,
## switched by an on-screen tab strip and by hotkeys.
##
## This is the fallback, not the usual case: WindowManager tiles the roles
## sharing a screen so they are all visible at once, and only falls back here
## when ScreenLayout finds the region too small to tile legibly. One component,
## two modes, matching the two regions that can be too small:
##
##  - overlay (dimmed): lives in a CanvasLayer over the live Main view, for a
##    Main screen too short to carry a panel strip under the flight view. A MAIN
##    tab hides the panel so the hull-cam is unobstructed; the panel floats over
##    a dimmed backdrop.
##  - opaque: fills its own borderless window on a spare screen whose tiles would
##    be too small. Solid backdrop, no MAIN tab, always showing a panel.
##
## Panels are the reused Root content of the standalone display windows,
## reparented in by WindowManager, so the UI and its input handling are
## identical to the dedicated-window case. Content instances persist (hidden),
## so per-panel state survives switching.

const OVERLAY_MARGIN := 64
const TAB_MIN_SIZE := Vector2(150, 44)

var _opaque := false
var _roles: Array[String] = []
var _panels: Dictionary = {}   # role -> Control
var _buttons: Dictionary = {}  # role -> Button
var _active := ""

var _scrim: ColorRect
var _holder: MarginContainer
var _tabs: HBoxContainer
var _main_button: Button


## Build the shared structure. Call once before add_role(); `opaque` picks the
## spare-screen look (solid, no MAIN tab) vs the dimmed Main-screen overlay.
func configure(opaque: bool) -> void:
	_opaque = opaque
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# The root passes clicks through where nothing is drawn so the Main view /
	# HUD stay interactive around an open overlay panel.
	mouse_filter = Control.MOUSE_FILTER_IGNORE if not opaque else Control.MOUSE_FILTER_STOP

	_scrim = ColorRect.new()
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.color = Color(0.02, 0.03, 0.05, 1.0) if opaque else Color(0, 0, 0, 0.62)
	# The scrim blocks click-through only while a panel is up (overlay) or always
	# (opaque). It's toggled with the panel in overlay mode.
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	_holder = MarginContainer.new()
	_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	if not opaque:
		for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			_holder.add_theme_constant_override(m, OVERLAY_MARGIN)
		_holder.add_theme_constant_override("margin_top", OVERLAY_MARGIN + 52)
	add_child(_holder)

	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("margin_top", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(center)

	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	center.add_child(_tabs)

	if not opaque:
		_main_button = _make_tab_button("MAIN")
		_main_button.pressed.connect(show_main)
		_tabs.add_child(_main_button)


## Add a role and its (already-detached) content panel. Panels start hidden.
func add_role(role: String, content: Control) -> void:
	_roles.append(role)
	content.visible = false
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_holder.add_child(content)
	_panels[role] = content

	var btn := _make_tab_button(role.to_upper())
	btn.pressed.connect(_select.bind(role))
	_tabs.add_child(btn)
	_buttons[role] = btn


## Pick the initial view once every role is added: opaque shows the first role;
## overlay starts clean (Main visible, panel hidden).
func finish() -> void:
	if _opaque and not _roles.is_empty():
		_select(_roles[0])
	else:
		show_main()


func show_main() -> void:
	if _opaque:
		return
	_active = ""
	_holder.visible = false
	_scrim.visible = false
	_update_buttons()


func _select(role: String) -> void:
	if not _panels.has(role):
		return
	for r in _roles:
		_panels[r].visible = (r == role)
	_active = role
	_holder.visible = true
	_scrim.visible = true
	_update_buttons()


func _select_index(i: int) -> bool:
	if i >= 0 and i < _roles.size():
		_select(_roles[i])
		return true
	return false


func _toggle() -> bool:
	if _roles.is_empty():
		return false
	if _active == "":
		_select(_roles[0])
	else:
		show_main()
	return true


func _cycle() -> bool:
	if _roles.is_empty():
		return false
	var idx := _roles.find(_active)
	_select(_roles[(idx + 1) % _roles.size()])
	return true


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var handled := false
	match event.keycode:
		KEY_F1:
			handled = _select_index(0)
		KEY_F2:
			handled = _select_index(1)
		KEY_F3:
			handled = _select_index(2)
		KEY_TAB:
			handled = _cycle()
		KEY_QUOTELEFT:
			if not _opaque:
				handled = _toggle()
	if handled:
		accept_event()


func _update_buttons() -> void:
	if _main_button:
		_main_button.button_pressed = (_active == "")
	for role in _buttons:
		_buttons[role].button_pressed = (role == _active)


func _make_tab_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = TAB_MIN_SIZE
	return btn
