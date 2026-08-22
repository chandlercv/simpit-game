extends Control
class_name TitleCard
## The launch screen — the first thing the game shows, on the Main window, before
## any display window exists and while WindowManager holds the tree paused (so
## the world isn't already running behind the card you haven't launched yet).
##
## It hosts the three things a player sets before flying — the latter two being
## the same surfaces their in-game hotkeys open:
##  - SCENARIO — which run to fly, from GameState.SCENARIOS. Adding a run is a
##    catalog entry there, not a branch here: the buttons are built from the list.
##  - DISPLAYS — the same chooser F6 opens (DisplaySetup). WindowManager runs it
##    as a step you come back from (the card hides, then returns), and the row
##    reads back the resulting screen assignment.
##  - CONTROLS — the same remapper F7 opens (ControlsSetup). That overlay is owned
##    by InputRouter on a HIGHER CanvasLayer, so it simply draws over this card
##    and reveals it again on close — no hide/show handshake needed. The row reads
##    back which sticks are connected.
##
## ...plus the PILOT'S MANUAL (PilotManual), which this card owns outright — it is
## the only thing that opens it, so the layer lives here rather than on a system.
##
## LAUNCH commits the scenario (GameState.launch_scenario) and hands back to
## WindowManager, which builds the display windows and lets the world run.

## LAUNCH was pressed and the scenario is committed — build the displays.
signal launched
## The DISPLAYS button was pressed; WindowManager owns the chooser (and this
## card), so it runs that step and shows us again afterwards.
signal display_setup_requested

const ButtonThemeScript := preload("res://scenes/ui/ButtonTheme.gd")
const ManualViewerScript := preload("res://scenes/displays/ManualViewer.gd")
const PilotManualContentScript := preload("res://scenes/displays/PilotManualContent.gd")
const TerminalProceduresContentScript := preload("res://scenes/displays/TerminalProceduresContent.gd")

## The two documents the ship carries, each a row on the card. They are separate
## publications because they have separate publishers — the handbook is the
## builder's and describes the ship; the terminal procedures are the harbour's
## and bind the pilot — so neither can be folded into the other.
##   "title"/"subtitle" — the masthead ManualViewer prints
##   "status"           — the card's own line describing what's inside
const DOCUMENTS := [
	{
		"id": "manual",
		"button": "PILOT'S MANUAL",
		"title": "PILOT'S MANUAL — %s",
		"subtitle": "SALVAGE CUTTER · OPERATING INSTRUCTIONS AND PROCEDURES",
		"status": "the ship, her systems and her limits, and the checklists for\n"
			+ "departure · arrival · cutting · collecting",
	},
	{
		"id": "terminal",
		"button": "TERMINAL PROCEDURES",
		"title": "TERMINAL PROCEDURES",
		"subtitle": "ISSUED BY HARBOUR CONTROL · NOT A BUILDER PUBLICATION",
		"status": "the approach lane and its plate, clearance and traffic rules,\n"
			+ "charges, claim conditions and the schedule of prices",
	},
]

## CanvasLayer a document is raised on. Above this card (WindowManager puts it on
## 15) so it covers it, and deliberately BELOW the display chooser (20) and the
## remapper (25): F5/F6/F7 are polled globally and still fire while a document is
## up, so those surfaces have to draw over it rather than under it.
const MANUAL_LAYER := 18

const ACCENT := Color(0.35, 0.95, 0.55)
const SETUP_ACCENT := Color(0.4, 0.8, 1.0)
const DIM := Color(0.65, 0.72, 0.82)
const WARN := Color(0.95, 0.75, 0.35)
const INK := Color(0.02, 0.03, 0.05)

var _scenario_buttons: Dictionary = {}  # scenario id -> Button
var _blurb: Label
var _display_status: Label
var _controls_status: Label
var _launch_button: Button
var _manual_layer: CanvasLayer = null
var _manual_ui: Control = null
## DOCUMENTS id currently on the reader, "" when none is.
var _open_document_id := ""


## Build the card and start tracking the state it reports. Call after adding this
## node to the tree.
func start() -> void:
	# Anchors AND offsets: parented to a CanvasLayer the anchors resolve against
	# the viewport rect, but a preset that leaves the offsets alone collapses the
	# backdrop to the top-left (the bug ControlsSetup carries the same note about).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	# Everything the two setup rows report can change while the card is up: the
	# chooser rewrites the mapping, the remapper saves a profile, a stick is
	# plugged in. Re-read on each rather than snapshotting at build time.
	DisplayConfig.mapping_changed.connect(refresh)
	InputConfig.profiles_changed.connect(refresh)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	GameState.scenario_changed.connect(_on_scenario_changed)
	refresh()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	refresh()


func _on_scenario_changed(_id: String) -> void:
	refresh()


# --- UI construction -------------------------------------------------------

func _build_ui() -> void:
	# Not fully opaque: the hull-cam view sits frozen behind the card (the tree is
	# paused, but rendering isn't), which is the point — you launch into the scene
	# you can already see.
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.03, 0.05, 0.88)
	add_child(bg)

	# A CenterContainer alone centres the column at its own minimum size, so on a
	# viewport smaller than the card it offsets NEGATIVELY and pushes LAUNCH/QUIT
	# off-screen with no way to reach them (measured: below roughly 800×620). The
	# scroll is purely that safety net — the centre fills it whenever there's room,
	# so at any normal size the layout is identical and no scrollbar appears.
	# follow_focus keeps Tab/arrow navigation inside the visible area when it does.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.follow_focus = true
	add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	_add_title(vbox)
	_add_scenario_section(vbox)
	_add_setup_rows(vbox)
	_add_actions(vbox)

	var footer := _make_label(
		"F5 re-detect monitors  ·  F6 displays  ·  F7 controls  ·  Esc quits",
		15, Color(0.45, 0.52, 0.62))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(footer)


func _add_title(vbox: VBoxContainer) -> void:
	var title := _make_label("S A L V A G E R", 64, ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var tagline := _make_label(
		"cyberpunk mercenary salvage — one hull, four displays", 19, DIM)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tagline)


func _add_scenario_section(vbox: VBoxContainer) -> void:
	vbox.add_child(_make_label("SCENARIO", 20, SETUP_ACCENT))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	vbox.add_child(buttons)
	for entry: Dictionary in GameState.SCENARIOS:
		var id: String = entry["id"]
		var btn := Button.new()
		btn.text = "%s\n%s" % [entry["name"], entry["subtitle"]]
		btn.custom_minimum_size = Vector2(340, 68)
		btn.pressed.connect(GameState.set_scenario.bind(id))
		buttons.add_child(btn)
		_scenario_buttons[id] = btn

	_blurb = _make_label("", 16, DIM)
	_blurb.custom_minimum_size = Vector2(700, 0)
	vbox.add_child(_blurb)


## The two setup rows: a button that opens the surface, and a status line that
## reports what it's currently set to, so the common case is reading the line and
## pressing LAUNCH.
func _add_setup_rows(vbox: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid)

	var displays := _make_setup_button("SET UP DISPLAYS   (F6)")
	displays.pressed.connect(func() -> void: display_setup_requested.emit())
	grid.add_child(displays)
	_display_status = _make_label("", 16, DIM)
	_display_status.custom_minimum_size = Vector2(520, 0)
	grid.add_child(_display_status)

	var controls := _make_setup_button("SET UP CONTROLS   (F7)")
	# The remapper belongs to InputRouter (it owns the live bindings and its own
	# overlay layer); we just ask for it, exactly as the F7 hotkey does.
	controls.pressed.connect(InputRouter.open_controls_setup)
	grid.add_child(controls)
	_controls_status = _make_label("", 16, DIM)
	_controls_status.custom_minimum_size = Vector2(520, 0)
	grid.add_child(_controls_status)

	# No hotkey suffix, unlike the two rows above: the documents are read before you
	# fly, so they're reachable from here and nowhere else. Their status lines are
	# fixed — there's no live state to report, just what's inside each.
	for document: Dictionary in DOCUMENTS:
		var open := _make_setup_button(String(document["button"]))
		open.pressed.connect(_open_document.bind(document["id"]))
		grid.add_child(open)
		var status := _make_label(String(document["status"]), 16, DIM)
		status.custom_minimum_size = Vector2(520, 0)
		grid.add_child(status)


func _add_actions(vbox: VBoxContainer) -> void:
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	vbox.add_child(actions)

	_launch_button = ButtonThemeScript.make_button(ACCENT, 14)
	_launch_button.text = "L A U N C H"
	_launch_button.custom_minimum_size = Vector2(280, 64)
	_launch_button.focus_mode = Control.FOCUS_ALL
	_launch_button.pressed.connect(_launch)
	actions.add_child(_launch_button)
	# Focused so Enter/Space launches straight away and arrow keys reach the other
	# buttons — the launch screen is the one place you may not have a hand on the
	# mouse yet.
	_launch_button.grab_focus.call_deferred()

	var quit := ButtonThemeScript.make_button(Color(0.9, 0.45, 0.45), 14)
	quit.text = "QUIT"
	quit.custom_minimum_size = Vector2(140, 64)
	quit.focus_mode = Control.FOCUS_ALL
	quit.pressed.connect(func() -> void: get_tree().quit())
	actions.add_child(quit)


func _make_setup_button(text: String) -> Button:
	var btn := ButtonThemeScript.make_button(SETUP_ACCENT, 12)
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 52)
	btn.focus_mode = Control.FOCUS_ALL
	return btn


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


# --- The ship's documents --------------------------------------------------

## The chapter catalog for a DOCUMENTS id. Kept here rather than in the catalog
## itself because a const Array can't hold a preloaded script reference.
func _document_chapters(id: String) -> Array:
	return (TerminalProceduresContentScript.CHAPTERS if id == "terminal"
			else PilotManualContentScript.CHAPTERS)


## Raise a document on its own CanvasLayer. Parented to THIS node rather than the
## window, so LAUNCH freeing the card takes the document with it instead of
## leaving a page floating over the run. Opening one while another is up swaps
## them, so the two can never stack.
func _open_document(id: String) -> void:
	if is_instance_valid(_manual_ui):
		if _open_document_id == id:
			return
		_close_manual()
	var document := _document_def(id)
	if document.is_empty():
		return
	_open_document_id = id
	_manual_layer = CanvasLayer.new()
	_manual_layer.layer = MANUAL_LAYER
	# ALWAYS so the document's buttons and its Esc still work while this card holds
	# the tree paused — a paused Control receives no input at all.
	_manual_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_manual_layer)
	_manual_ui = ManualViewerScript.new()
	_manual_ui.closed.connect(_close_manual)
	_manual_layer.add_child(_manual_ui)
	# The handbook's masthead carries the ship's name; the harbour's does not, so
	# the format string is only substituted when it asks for one.
	var title := String(document["title"])
	if title.contains("%s"):
		title = title % GameState.ship_def.display_name
	_manual_ui.configure(_document_chapters(id), title, String(document["subtitle"]))
	_manual_ui.start()


func _document_def(id: String) -> Dictionary:
	for document: Dictionary in DOCUMENTS:
		if document["id"] == id:
			return document
	return {}


func _close_manual() -> void:
	if is_instance_valid(_manual_ui):
		_manual_ui.queue_free()
	_manual_ui = null
	if is_instance_valid(_manual_layer):
		_manual_layer.queue_free()
	_manual_layer = null
	_open_document_id = ""
	_launch_button.grab_focus()


## True while a document is up — the smoke test's handle on it, and what
## suspend/resume restore.
func manual_open() -> bool:
	return is_instance_valid(_manual_ui)


## Which document is open, "" when none is.
func open_document() -> String:
	return _open_document_id if manual_open() else ""


# --- Stepping out and back -------------------------------------------------

## Step away to a setup surface that covers the whole screen (the display
## chooser). The card keeps its state and its signal wiring — it's hidden, not
## torn down — so returning is instant.
func suspend() -> void:
	visible = false
	# A CanvasLayer is not a CanvasItem, so it does NOT inherit this node's
	# visibility: without hiding it explicitly the manual would keep drawing over
	# a chooser that F6 opened from underneath it.
	if is_instance_valid(_manual_layer):
		_manual_layer.visible = false


## Come back from that step: re-read what it changed and take focus again, since
## hiding dropped it.
func resume() -> void:
	visible = true
	if is_instance_valid(_manual_layer):
		_manual_layer.visible = true
	refresh()
	_launch_button.grab_focus()


# --- State readback --------------------------------------------------------

## Re-read everything the card reports (selected scenario, screen assignment,
## connected sticks). Safe to call before the UI exists — WindowManager also
## calls it when a setup step hands the card back.
func refresh() -> void:
	if _blurb == null:
		return
	for id: String in _scenario_buttons:
		_style_scenario_button(_scenario_buttons[id], id == GameState.scenario)
	_blurb.text = String(GameState.scenario_def(GameState.scenario).get("blurb", ""))
	_display_status.text = _display_status_text()
	_display_status.add_theme_color_override("font_color",
			WARN if DisplayConfig.needs_setup_prompt() else DIM)
	_controls_status.text = _controls_status_text()


func _style_scenario_button(btn: Button, active: bool) -> void:
	for state in ["normal", "hover", "pressed"]:
		btn.add_theme_stylebox_override(state, ButtonThemeScript.make_toggle_stylebox(
				ACCENT, active, state != "normal", 12))
	btn.add_theme_color_override("font_color", INK if active else ACCENT)
	btn.add_theme_color_override("font_hover_color", INK if active else ACCENT.lightened(0.2))


func _display_status_text() -> String:
	var count := maxi(DisplayServer.get_screen_count(), 1)
	var parts: PackedStringArray = []
	for role in DisplayConfig.ALL_ROLES:
		parts.append("%s→%d" % [role.to_upper(), DisplayConfig.get_screen_for_role(role)])
	var lines: PackedStringArray = [
		"%d screen%s   %s" % [count, "" if count == 1 else "s", "  ".join(parts)]]
	if DisplayConfig.needs_setup_prompt():
		lines.append("not assigned for this monitor setup yet — LAUNCH asks first")
	elif _has_shared_screen():
		lines.append(_sharing_status())
	return "\n".join(lines)


## True if two or more roles are assigned to the same physical screen. Checked
## directly against the role→screen assignments rather than by comparing
## screen count to role count — assignment is manual, so a rig with enough
## screens for one role each can still have the player put two roles on one
## screen and leave another spare.
func _has_shared_screen() -> bool:
	var seen: Dictionary = {}
	for role in DisplayConfig.ALL_ROLES:
		var screen: int = DisplayConfig.get_screen_for_role(role)
		if seen.has(screen):
			return true
		seen[screen] = true
	return false


## What LAUNCH will actually do with a screen that carries more than one role:
## tile them side by side, or — where tiling would shrink a panel past legible
## size — fall back to a tabbed host. Reads WindowManager's own layout plan
## rather than assuming tiling always fits, so this can't say "tiled" for an
## arrangement that's really landing in the tabbed fallback.
func _sharing_status() -> String:
	var plans := WindowManager.screen_plans()
	for screen: int in plans:
		if plans[screen]["tabbed"]:
			return "displays sharing a screen are too tight to tile — LAUNCH tabs them instead"
	return "displays sharing a screen are tiled side by side"


func _controls_status_text() -> String:
	var names: PackedStringArray = []
	for device in Input.get_connected_joypads():
		names.append(Input.get_joy_name(device))
	if names.is_empty():
		return "no stick detected — flying on the keyboard mapping\n" \
			+ "(WASD thrust/strafe, IJKL aim, V approach, C cut)"
	return "%s\nkeyboard mapping stays live alongside" % ", ".join(names)


func _launch() -> void:
	GameState.launch_scenario()
	launched.emit()
