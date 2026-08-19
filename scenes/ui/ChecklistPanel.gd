extends Control
## MFD CHECKLIST page: the ship's four operating procedures, marked off against
## live state.
##
## The procedures are carried on paper in the pilot's handbook (SECTION 4), which
## is readable only from the launch card — before the run, and never during it.
## But every condition those checklists describe is already being evaluated
## somewhere aboard: DockingSystem.status() is what waves you off, the scoop gates
## are what DriftSystem stows on, request_cut()'s ladder is what refuses the
## torch. This page puts that evaluation on the glass, item by item, so a pilot
## mid-run can ask "what have I not done yet?" and get an answer rather than a
## recollection.
##
##   * an INDEX of the four procedures, each showing how far through it you are;
##   * inside a procedure, one ROW PER ITEM — what it is, what it must be, what it
##     is right now, and a mark;
##   * items the ship cannot judge (attitude flown by hand, stowage seen in the
##     log) are TAPPED off. Everything else is read live and is deliberately NOT
##     tappable, so a green tick always means the ship agrees, never that someone
##     ticked it hopefully.
##
## Read-only but for those taps: the rows call nothing and change nothing. The
## catalog and every live read live in ChecklistContent.

const ButtonTheme := preload("res://scenes/ui/ButtonTheme.gd")
const Instrument := preload("res://scenes/ui/Instrument.gd")
const ChecklistContent := preload("res://scenes/ui/ChecklistContent.gd")

@export var accent: Color = Color(0.3, 0.9, 0.78)

## Reserve for the footer button row.
const FOOTER_H := 76.0
## One item row. A fingertip's worth, because the manual items are tapped — and
## uniform across auto rows too, since a list of mixed heights is harder to scan
## than a slightly taller one.
const ROW_H := ButtonTheme.TOUCH_MIN_H
## A group heading between sections of a procedure.
const HEADER_ROW_H := 34.0
## Rows moved per press of the scroll buttons. The longest procedure is well over
## a screen, and a ScrollContainer's drag-scroll is not something you can rely on
## reaching from a footer button, so paging is explicit.
const SCROLL_ROWS := 3

var _lists: Array[Dictionary] = []
## Manual ticks, keyed "<list id>/<item index>". Not on the item dictionaries —
## those are rebuilt from the catalog and carry no per-run state.
var _ticked: Dictionary = {}
## Index of the open procedure in _lists, or -1 on the index screen.
var _open := -1

var _index: VBoxContainer
var _index_buttons: Array[Button] = []
var _list_root: VBoxContainer
var _title: Label
var _scroll: ScrollContainer
var _rows_box: VBoxContainer
var _rows: Array = []
var _footer: HBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_lists = ChecklistContent.lists()
	_build()
	_show_index()
	# A status list, not a flying instrument: the shared 10 Hz tick is fast enough
	# to watch a gate flip, and leaves the per-frame budget to the pages that
	# actually need it (ALIGN, SCOOP, DOCK).
	GameState.tick_changed.connect(func(_t: int) -> void: _refresh())
	# A new run is a fresh checklist — a tick carried over from the last one is
	# worse than no tick at all.
	GameState.site_reset.connect(_clear_ticks)


func _build() -> void:
	var body := MarginContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_bottom = -FOOTER_H
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		body.add_theme_constant_override(m, 4)
	add_child(body)

	# --- The index: one button per procedure ---------------------------------
	_index = VBoxContainer.new()
	_index.alignment = BoxContainer.ALIGNMENT_CENTER
	_index.add_theme_constant_override("separation", ButtonTheme.TOUCH_SEP)
	body.add_child(_index)
	for i in _lists.size():
		var btn := ButtonTheme.make_touch_button(accent)
		btn.custom_minimum_size = Vector2(0, 96)
		btn.add_theme_font_size_override("font_size", 22)
		btn.pressed.connect(_open_list.bind(i))
		_index.add_child(btn)
		_index_buttons.append(btn)

	# --- An open procedure ---------------------------------------------------
	_list_root = VBoxContainer.new()
	_list_root.add_theme_constant_override("separation", 4)
	body.add_child(_list_root)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", Instrument.HEADING)
	_title.add_theme_color_override("font_color", accent)
	_list_root.add_child(_title)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_root.add_child(_scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 0)
	_scroll.add_child(_rows_box)

	# --- Footer --------------------------------------------------------------
	_footer = HBoxContainer.new()
	_footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_footer.offset_top = -(FOOTER_H - 8.0)
	_footer.offset_left = 8
	_footer.offset_right = -8
	_footer.offset_bottom = -8
	_footer.add_theme_constant_override("separation", ButtonTheme.TOUCH_SEP)
	add_child(_footer)
	_add_footer_button("BACK", accent, _show_index)
	_add_footer_button("▲", accent, _scroll_by.bind(-1))
	_add_footer_button("▼", accent, _scroll_by.bind(1))
	_add_footer_button("RESET", Color(1.0, 0.72, 0.35), _reset_open)


func _add_footer_button(text: String, color: Color, action: Callable) -> void:
	var btn := ButtonTheme.make_touch_button(color)
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(action)
	_footer.add_child(btn)


# --- Navigation -------------------------------------------------------------

## The index screen, and where BACK returns to.
func _show_index() -> void:
	_open = -1
	_index.visible = true
	_list_root.visible = false
	_footer.visible = false
	_refresh()


func _open_list(which: int) -> void:
	if which < 0 or which >= _lists.size():
		return
	_open = which
	_index.visible = false
	_list_root.visible = true
	_footer.visible = true
	_title.text = String(_lists[which]["title"])
	_build_rows()
	_scroll.set_deferred("scroll_vertical", 0)
	_refresh()


## Which procedure is open, or "" on the index. For the smoke test.
func open_list_id() -> String:
	return "" if _open < 0 else String(_lists[_open]["id"])


func _scroll_by(direction: int) -> void:
	_scroll.scroll_vertical += direction * SCROLL_ROWS * int(ROW_H)


# --- Rows -------------------------------------------------------------------

func _build_rows() -> void:
	for row in _rows_box.get_children():
		row.queue_free()
	_rows.clear()
	var items: Array = _lists[_open]["items"]
	var group := ""
	for i in items.size():
		var item: Dictionary = items[i]
		var item_group := String(item.get("group", ""))
		if item_group != group:
			group = item_group
			var heading := Row.new()
			heading.accent = accent
			heading.heading = true
			heading.label = group
			heading.custom_minimum_size = Vector2(0, HEADER_ROW_H)
			heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_rows_box.add_child(heading)
		var row := Row.new()
		row.accent = accent
		row.label = String(item["label"])
		row.want = String(item.get("want", ""))
		row.manual = not item.has("read")
		row.custom_minimum_size = Vector2(0, ROW_H)
		# An auto row must not be tappable: a hand-ticked row that the ship says
		# is false would be exactly the lie this page exists to prevent.
		row.mouse_filter = Control.MOUSE_FILTER_STOP if row.manual \
				else Control.MOUSE_FILTER_IGNORE
		if row.manual:
			row.tapped.connect(_toggle_tick.bind(i))
		_rows_box.add_child(row)
		_rows.append({"row": row, "item": item, "index": i})


func _toggle_tick(index: int) -> void:
	var key := _tick_key(_open, index)
	if _ticked.has(key):
		_ticked.erase(key)
	else:
		_ticked[key] = true
	_refresh()


func _tick_key(list_index: int, item_index: int) -> String:
	return "%s/%d" % [String(_lists[list_index]["id"]), item_index]


## Clear the manual ticks on the open procedure only — RESET is about the list in
## front of you, not the other three.
func _reset_open() -> void:
	if _open < 0:
		return
	for entry: Dictionary in _rows:
		_ticked.erase(_tick_key(_open, int(entry["index"])))
	_refresh()


func _clear_ticks() -> void:
	_ticked.clear()
	_refresh()


# --- Live refresh -----------------------------------------------------------

func _refresh() -> void:
	if _open < 0:
		for i in _lists.size():
			var tally := _tally(i)
			_index_buttons[i].text = "%s          %d / %d" % [
				String(_lists[i]["title"]), tally.x, tally.y]
		return
	for entry: Dictionary in _rows:
		var item: Dictionary = entry["item"]
		var row: Row = entry["row"]
		if row.manual:
			var ticked := _ticked.has(_tick_key(_open, int(entry["index"])))
			row.mark = "☑" if ticked else "☐"
			row.mark_color = Instrument.GOOD if ticked else Color(accent, 0.7)
			row.queue_redraw()
			continue
		var result: Dictionary = (item["read"] as Callable).call()
		row.value = String(result["value"])
		match int(result["status"]):
			ChecklistContent.Status.PASS:
				row.mark = "OK"
				row.mark_color = Instrument.GOOD
			ChecklistContent.Status.FAIL:
				row.mark = "✗"
				row.mark_color = Instrument.WARN
			_:
				# N/A: dim, not red. A red row for something you could not
				# possibly have done yet trains you to ignore red.
				row.mark = "—"
				row.mark_color = Color(accent, 0.45)
		row.queue_redraw()


## Items satisfied, and items that apply. An item reading N/A is left out of both:
## counting "you have not landed yet" as outstanding would make every list look
## half-failed for most of a run.
func _tally(which: int) -> Vector2i:
	var items: Array = _lists[which]["items"]
	var done := 0
	var applicable := 0
	for i in items.size():
		var item: Dictionary = items[i]
		if not item.has("read"):
			applicable += 1
			if _ticked.has(_tick_key(which, i)):
				done += 1
			continue
		var result: Dictionary = (item["read"] as Callable).call()
		var status := int(result["status"])
		if status == ChecklistContent.Status.NA:
			continue
		applicable += 1
		if status == ChecklistContent.Status.PASS:
			done += 1
	return Vector2i(done, applicable)


## One line of the procedure. Draws itself rather than composing Labels, so it
## shares the instruments' type scale and reads as part of the same family as the
## DOCK and SCOOP gate checklists.
class Row:
	extends Control

	signal tapped

	var accent: Color = Color(0.3, 0.9, 0.78)
	var label := ""
	var want := ""
	var value := ""
	## Pass mark and its colour, decided by the panel — the row draws, it does not
	## judge.
	var mark := ""
	var mark_color: Color = Color(0.3, 0.9, 0.78)
	var manual := false
	var heading := false     ## a group heading rather than an item

	func _gui_input(event: InputEvent) -> void:
		var touch_tap: bool = event is InputEventScreenTouch and event.pressed
		var click: bool = event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT
		if touch_tap or click:
			tapped.emit()
			accept_event()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		if heading:
			draw_string(font, Vector2(Instrument.INSET, size.y - 10.0), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, Instrument.ROW,
					Color(accent.lightened(0.25), 0.9))
			draw_line(Vector2(Instrument.INSET, size.y - 4.0),
					Vector2(size.x - Instrument.INSET, size.y - 4.0),
					Color(accent, 0.25), 1.0)
			return

		# Left/right alignment rather than a measured column: the value strings
		# here run much longer than a gate row's, and a fixed column that fits
		# them on a wide unit would collide on a narrow one.
		draw_string(font, Vector2(Instrument.INSET, 22.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, Instrument.ROW, Color(accent, 0.85))
		draw_string(font, Vector2(-Instrument.INSET, 22.0), mark,
				HORIZONTAL_ALIGNMENT_RIGHT, size.x, Instrument.ROW, mark_color)
		draw_string(font, Vector2(Instrument.INSET, 42.0), want,
				HORIZONTAL_ALIGNMENT_LEFT, -1, Instrument.TAG, Color(accent, 0.5))
		if not manual:
			draw_string(font, Vector2(-Instrument.INSET, 42.0), value,
					HORIZONTAL_ALIGNMENT_RIGHT, size.x, Instrument.ANNOT, mark_color)
