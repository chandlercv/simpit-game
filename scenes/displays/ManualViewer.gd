extends Control
class_name ManualViewer
## Reader for the ship's paper documents, opened from the launch title card. It is
## a viewer, not a document: `configure()` supplies which one to show, so the two
## the ship carries share one implementation —
##
##   PilotManualContent          — the builder's handbook for the SV Kestrel
##   TerminalProceduresContent   — the harbour's procedures and local notices
##
## A contents list on the left, one chapter at a time on the right. This script
## holds no prose, so a document grows by adding a catalog entry to its content
## script. Grouped headings in the list follow the same idiom as ControlsSetup's
## binding groups.
##
## Steps name the LIVE binding for each control rather than a key the content
## assumed: _resolve() substitutes the content's {{...}} placeholders through
## BindingLabel, which reads the Input Map that InputRouter binds. Substitution
## happens on show, not at build, so reopening after an F7 remap is enough to see
## the new bindings.
##
## Hosted by TitleCard on its own CanvasLayer (see TitleCard._open_document) at a
## layer BELOW the display chooser and the remapper, so a global F5/F6/F7 press
## still draws over the reader and uncovers it again on close.

signal closed

const ButtonThemeScript := preload("res://scenes/ui/ButtonTheme.gd")
const BindingLabelScript := preload("res://scenes/ui/BindingLabel.gd")

const ACCENT := Color(0.35, 0.95, 0.55)
const SETUP_ACCENT := Color(0.4, 0.8, 1.0)
const DIM := Color(0.65, 0.72, 0.82)
const FAINT := Color(0.55, 0.62, 0.72)
const INK := Color(0.02, 0.03, 0.05)

## Hex of ACCENT, for wrapping a resolved binding so every one reads the same
## without the content having to colour them itself.
const BIND_COLOR := "#59f28c"
## ...and amber for a control with nothing assigned to it. Green is the manual's
## "this is the required condition" colour, so a green NOT ASSIGNED read as
## though the step were satisfied. A missing assignment is a defect the pilot has
## to go and correct.
const UNBOUND_COLOR := "#f2bf59"

## Contents column width. Wide enough for the longest chapter title AND the
## longest part heading at their sizes without wrapping (a wrapped heading eats
## the spacing that separates the parts), narrow enough to leave the page the
## screen.
const LIST_WIDTH := 280.0
## Height of a contents entry. Sized so the whole contents list — every chapter
## plus its three part headings — fits without scrolling on a 1080-high display,
## which is the smallest the Main display is expected to be. It still scrolls if
## it has to (see _build_contents).
const LIST_ROW_HEIGHT := 30.0

var _chapter_buttons: Dictionary = {}  # chapter id -> Button
var _body: RichTextLabel
var _scroll: ScrollContainer
var _close_button: Button
var _current := ""

## The document on the reader: its chapter catalog and its masthead. Set by
## configure() before start().
var _chapters: Array = []
var _doc_title := ""
var _doc_subtitle := ""


## Load a document. Call before start(). `chapters` is a content script's CHAPTERS;
## `title` and `subtitle` are its masthead — for a document not issued by the
## ship's builder, the subtitle is where the issuing authority is named.
func configure(chapters: Array, title: String, subtitle: String) -> void:
	_chapters = chapters
	_doc_title = title
	_doc_subtitle = subtitle


## Build the reader and show its first chapter. Call after adding this node to
## the tree.
func start() -> void:
	# Parented to a CanvasLayer, not a Control, so anchors alone don't stretch us
	# to the viewport — set offsets too and re-fit on resize, else the backdrop and
	# columns collapse to the top-left (the bug TitleCard and ControlsSetup both
	# carry the same note about).
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_build_ui()
	if not _chapters.is_empty():
		show_chapter(String(_chapters[0]["id"]))
	_close_button.grab_focus.call_deferred()


func _fit_to_viewport() -> void:
	# Offsets as well as anchors: parented to a CanvasLayer the anchors resolve
	# against the viewport rect, but a preset that leaves the offsets alone
	# collapses the backdrop to the top-left. FULL_RECT zeroes them, which is the
	# whole fix — don't also assign `size`, since with full-rect anchors the
	# anchors own it and Godot warns that the assignment will be overridden.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# --- UI construction -------------------------------------------------------

func _build_ui() -> void:
	# Fully opaque, unlike the title card underneath it (which is deliberately
	# translucent so you launch into a world you can see). This is a page of small
	# text: the card's own title and buttons showing through it just made it
	# harder to read, so nothing shows through.
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.03, 0.05, 1.0)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	vbox.add_child(_make_label(_doc_title, 34, SETUP_ACCENT))
	vbox.add_child(_make_label("%s        Controls are named as currently assigned; "
			% _doc_subtitle
			+ "re-assign at CONTROLS (F7). Esc or CLOSE to return.", 16, FAINT))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(columns)
	columns.add_child(_build_contents())
	columns.add_child(_build_page())

	var actions := HBoxContainer.new()
	vbox.add_child(actions)
	_close_button = ButtonThemeScript.make_button(SETUP_ACCENT, 12)
	_close_button.text = "CLOSE"
	_close_button.custom_minimum_size = Vector2(160, 48)
	# make_button hands back FOCUS_NONE (the MFDs are touch-first); the manual is
	# read at a keyboard, so its controls have to be reachable by Tab and arrows.
	_close_button.focus_mode = Control.FOCUS_ALL
	_close_button.pressed.connect(func() -> void: closed.emit())
	actions.add_child(_close_button)


## The contents column: one button per chapter, under a heading whenever the
## group changes (same shape as ControlsSetup._maybe_group_header).
func _build_contents() -> Control:
	# The list is short enough to fit today, but a chapter or two more would push
	# it off a 720p screen with no way to reach the last entry — so it scrolls,
	# and follow_focus keeps keyboard navigation inside the visible part.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true

	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	var last_group := ""
	for chapter: Dictionary in _chapters:
		var group := String(chapter.get("group", ""))
		if group != last_group:
			var header := _make_label(group, 14, SETUP_ACCENT)
			# Breathing room above every heading but the first, so the parts read as
			# blocks rather than one run of buttons.
			if not last_group.is_empty():
				header.custom_minimum_size = Vector2(0, 30)
				header.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			list.add_child(header)
			last_group = group
		var id := String(chapter["id"])
		var btn := Button.new()
		btn.text = String(chapter["title"])
		btn.custom_minimum_size = Vector2(LIST_WIDTH, LIST_ROW_HEIGHT)
		btn.focus_mode = Control.FOCUS_ALL
		btn.pressed.connect(show_chapter.bind(id))
		list.add_child(btn)
		_chapter_buttons[id] = btn
	return scroll


func _build_page() -> Control:
	# Rows scroll inside an EXPAND_FILL ScrollContainer: giving it an expanding
	# height (it fills the column) rather than letting it size to its content is
	# what avoids the zero-height collapse ControlsSetup documents.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	# fit_content + EXPAND_FILL width: the label grows to whatever the chapter
	# needs and the scroll takes up the overflow.
	_body.fit_content = true
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.selection_enabled = true
	# RichTextLabel sizes its text through normal/bold_font_size, NOT font_size —
	# a plain font_size override on it does nothing (see CommsLog).
	_body.add_theme_font_size_override("normal_font_size", 17)
	_body.add_theme_font_size_override("bold_font_size", 17)
	_body.add_theme_font_size_override("italics_font_size", 17)
	_body.add_theme_color_override("default_color", DIM)
	_body.add_theme_constant_override("line_separation", 3)
	_scroll.add_child(_body)
	return _scroll


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


# --- Chapters --------------------------------------------------------------

## Show a chapter by id, resolving its live bindings. No-op for an unknown id, so
## a stale link can't blank the page.
func show_chapter(id: String) -> void:
	var chapter := _chapter_def(id)
	if chapter.is_empty():
		return
	_current = id
	_body.text = "[b][color=#66ccff]%s[/color][/b]\n\n%s" % [
			String(chapter["title"]), _resolve(String(chapter["body"]))]
	# A chapter always opens at its top: leaving the previous chapter's scroll
	# offset would drop the reader into the middle of a checklist.
	_scroll.set_deferred("scroll_vertical", 0)
	for other: String in _chapter_buttons:
		_style_chapter_button(_chapter_buttons[other], other == id)


## The id of the chapter currently on the page.
func current_chapter() -> String:
	return _current


func _chapter_def(id: String) -> Dictionary:
	for chapter: Dictionary in _chapters:
		if String(chapter["id"]) == id:
			return chapter
	return {}


func _style_chapter_button(btn: Button, active: bool) -> void:
	for state in ["normal", "hover", "pressed"]:
		btn.add_theme_stylebox_override(state, ButtonThemeScript.make_toggle_stylebox(
				SETUP_ACCENT, active, state != "normal", 6))
	btn.add_theme_color_override("font_color", INK if active else SETUP_ACCENT)
	btn.add_theme_color_override("font_hover_color",
			INK if active else SETUP_ACCENT.lightened(0.2))


# --- Binding substitution --------------------------------------------------

## Replace the content's {{...}} placeholders with the live binding for each, all
## wrapped in one colour so bindings read as bindings wherever they appear.
##
## An unknown placeholder is left verbatim rather than silently blanked: it shows
## up on the page, and PilotManualSmoke fails on it, so a typo can't quietly turn
## a checklist step into a gap.
func _resolve(body: String) -> String:
	var out := ""
	var rest := body
	while true:
		var open := rest.find("{{")
		if open == -1:
			return out + rest
		var close := rest.find("}}", open)
		if close == -1:
			return out + rest
		out += rest.substr(0, open)
		var token := rest.substr(open + 2, close - open - 2)
		var text := _binding_text(token)
		if text.is_empty():
			out += "{{%s}}" % token
		else:
			var color := UNBOUND_COLOR if text.contains(BindingLabelScript.UNBOUND) \
					else BIND_COLOR
			out += "[b][color=%s]%s[/color][/b]" % [color, text]
		rest = rest.substr(close + 2)
	return out


## One placeholder's replacement, or "" when the token isn't one we know (which
## _resolve leaves in place as a visible defect).
func _binding_text(token: String) -> String:
	if token == "throttle":
		return BindingLabelScript.for_throttle()
	var split := token.split(":", true, 1)
	if split.size() != 2:
		return ""
	var arg := split[1]
	match split[0]:
		"act":
			return BindingLabelScript.for_action(arg)
		"axis":
			var pair := arg.split(",", true, 1)
			if pair.size() != 2:
				return ""
			return BindingLabelScript.for_axis(pair[0], pair[1])
		"sw":
			return BindingLabelScript.for_switch(arg)
		"pwsw":
			return BindingLabelScript.for_power_switch(arg)
	return ""


# --- Input -----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# Swallowed, or it reaches InputRouter's quit-on-Esc and takes the game down
	# instead of closing the manual (the same guard ControlsSetup carries).
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()
