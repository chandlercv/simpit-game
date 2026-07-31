extends Control
class_name MfdUnit
## One MFD screen: a top-level MENU home plus swappable pages, shown one at a
## time. Two of these sit side by side in MfdWindow (each independently paged).
##
## Navigation is a home menu, not a cycle: the MENU grid taps straight to any
## page, and the bezel MENU button returns home — so no tabbing through pages you
## don't want. Mapped controls (InputRouter, Phase 5) call go_home() and
## page_step() to give the HOTAS the same reach.
##
## Every page is an existing reusable widget (PowerSliders, InventoryGrid,
## MarketPanel+CommsLog, SalvagePanel, ContactList) — this unit only hosts and
## switches them; all state lives in GameState.

const ButtonTheme := preload("res://scenes/ui/ButtonTheme.gd")
const PowerSlidersScene := preload("res://scenes/ui/PowerSliders.tscn")
const InventoryGridScene := preload("res://scenes/ui/InventoryGrid.tscn")
const MarketPanelScene := preload("res://scenes/ui/MarketPanel.tscn")
const CommsLogScene := preload("res://scenes/ui/CommsLog.tscn")
const ContactListScript := preload("res://scenes/ui/ContactList.gd")
const SalvagePanelScript := preload("res://scenes/ui/SalvagePanel.gd")

## Page order (also the menu grid order). Empty string = the MENU home.
const PAGES: Array[String] = ["POWER", "CARGO", "SALVAGE", "MARKET", "CONTACTS"]

@export var accent: Color = Color(0.3, 0.9, 0.78)
@export var background: Color = Color(0.012, 0.038, 0.038)
## Page shown on start; "" or "MENU" starts on the home menu.
@export var default_page: String = ""
## Which MFD unit this is ("A"/"B") — mapped controls (InputRouter) target a unit
## by this id through the "mfd_unit" group.
@export var unit_id: String = "A"

## "" == the MENU home; otherwise one of PAGES.
var _current := ""
var _pages: Dictionary = {}   # page name -> Control
var _menu: Control
var _content: MarginContainer
var _title: Label
var _menu_button: Button


func _ready() -> void:
	add_to_group("mfd_unit")
	_build()
	if default_page != "" and default_page.to_upper() != "MENU" \
			and PAGES.has(default_page.to_upper()):
		show_page(default_page.to_upper())
	else:
		go_home()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = background
	add_child(bg)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	# Bezel: MENU button + current page title.
	var bezel := HBoxContainer.new()
	bezel.add_theme_constant_override("separation", 8)
	outer.add_child(bezel)
	_menu_button = ButtonTheme.make_button(accent, 8)
	_menu_button.text = "☰ MENU"
	_menu_button.pressed.connect(go_home)
	bezel.add_child(_menu_button)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", accent)
	bezel.add_child(_title)

	# Content area: holds the menu grid + every page, one visible at a time.
	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		_content.add_theme_constant_override(m, 4)
	outer.add_child(_content)

	_build_menu()
	for page: String in PAGES:
		var panel := _build_page(page)
		panel.visible = false
		_content.add_child(panel)
		_pages[page] = panel


## The MENU home: a grid of big page buttons.
func _build_menu() -> void:
	_menu = CenterContainer.new()
	_content.add_child(_menu)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_menu.add_child(grid)
	for page: String in PAGES:
		var btn := ButtonTheme.make_button(accent, 20)
		btn.text = page
		btn.custom_minimum_size = Vector2(200, 88)
		btn.add_theme_font_size_override("font_size", 22)
		btn.pressed.connect(show_page.bind(page))
		grid.add_child(btn)


func _build_page(page: String) -> Control:
	match page:
		"POWER":
			return PowerSlidersScene.instantiate()
		"CARGO":
			return InventoryGridScene.instantiate()
		"SALVAGE":
			var salvage := SalvagePanelScript.new()
			salvage.accent = accent
			return salvage
		"MARKET":
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 8)
			var market := MarketPanelScene.instantiate()
			market.size_flags_vertical = Control.SIZE_EXPAND_FILL
			col.add_child(market)
			var comms := CommsLogScene.instantiate()
			comms.size_flags_vertical = Control.SIZE_EXPAND_FILL
			comms.size_flags_stretch_ratio = 0.8
			col.add_child(comms)
			return col
		"CONTACTS":
			var scroll := ScrollContainer.new()
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			var contacts := ContactListScript.new()
			contacts.accent = accent
			contacts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.add_child(contacts)
			return scroll
	return Control.new()


# --- Public navigation (touch buttons + mapped controls) -------------------

## The current page name, or "" while on the MENU home.
func current_page() -> String:
	return _current


func go_home() -> void:
	_current = ""
	for page: String in _pages:
		_pages[page].visible = false
	_menu.visible = true
	_menu_button.visible = false
	_title.text = "MENU"


func show_page(page: String) -> void:
	if not _pages.has(page):
		return
	_current = page
	_menu.visible = false
	for p: String in _pages:
		_pages[p].visible = (p == page)
	_menu_button.visible = true
	_title.text = page


## Step through pages (mapped page-next/prev). From the MENU home, +1 opens the
## first page and −1 the last; stepping past the ends returns to the MENU.
func page_step(delta: int) -> void:
	if _current == "":
		show_page(PAGES[0] if delta >= 0 else PAGES[PAGES.size() - 1])
		return
	var idx := PAGES.find(_current) + delta
	if idx < 0 or idx >= PAGES.size():
		go_home()
	else:
		show_page(PAGES[idx])
