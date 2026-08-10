extends Control
class_name MfdUnit
## One MFD screen: a top-level MENU home plus swappable pages, shown one at a
## time. Two of these sit side by side in MfdWindow (each independently paged).
##
## Navigation is a home menu, not a cycle: the MENU grid taps straight to any
## page, and the bezel MENU button returns home from anywhere — so reaching a
## page is one hop, never tabbing through pages you don't want. page_step() is
## there for a HOTAS rocker and wraps through the PAGES alone; the MENU home is
## not in that cycle, so paging can't strand you on it. Mapped controls
## (InputRouter, Phase 5) call go_home() and page_step() for the same reach.
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
const AlignPanelScript := preload("res://scenes/ui/AlignPanel.gd")
const ScoopPanelScript := preload("res://scenes/ui/ScoopPanel.gd")
const DockPanelScript := preload("res://scenes/ui/DockPanel.gd")

## Page order (also the menu grid order). Empty string = the MENU home.
## ALIGN and SCOOP sit together: they're the two halves of a salvage run (cut
## the member free, then go collect it). DOCK follows MARKET, which is where
## an approach is started from.
const PAGES: Array[String] = ["POWER", "CARGO", "SALVAGE", "ALIGN", "SCOOP",
		"MARKET", "DOCK", "CONTACTS"]

@export var accent: Color = Color(0.3, 0.9, 0.78)
@export var background: Color = Color(0.012, 0.038, 0.038)
## Page shown on start; "" or "MENU" starts on the home menu.
@export var default_page: String = ""
## Which MFD unit this is ("A"/"B") — mapped controls (InputRouter) target a unit
## by this id through the "mfd_unit" group.
@export var unit_id: String = "A"

## "" == the MENU home; otherwise one of PAGES.
var _current := ""
## Last non-mini-game page a mini-game took the screen away from, restored once
## every mini-game has ended (primary unit only). "" = MENU home.
var _page_before_auto := ""
## Mini-game pages currently auto-displayed, oldest first. Mini-games can overlap
## (open the hatch mid-alignment), and they don't have to end in the order they
## started, so this is a set-with-order rather than a plain "previous page":
## whichever auto page is still live when another ends is what we fall back to.
var _auto_pages: Array[String] = []
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
	GameState.align_changed.connect(
			func(state: String) -> void: _auto_page("ALIGN", state == "ALIGNING"))
	GameState.cargo_hatch_changed.connect(
			func(open: bool) -> void: _auto_page("SCOOP", open))
	# The docking pattern is a mini-game like the other two, so it takes the
	# primary MFD while it runs and gives it back when the ship is berthed or
	# away — including through a go-around, which never leaves the pattern.
	GameState.docking_changed.connect(
			func(state: String) -> void: _auto_page("DOCK", state != "INACTIVE"))


## Surface a mini-game's instrument page on the primary MFD while that mini-game
## is live, then hand the screen back to whatever was up when it ends. Only unit
## A auto-switches, so the other MFD stays free for power/cargo throughout.
## Shared by the two halves of a salvage run: ALIGN while lining up a cut, and
## SCOOP while the cargo hatch is open to collect (opening the hatch is a
## deliberate "I'm going to collect now", so it's the right trigger).
##
## Overlapping mini-games nest: opening the hatch mid-alignment stacks SCOOP on
## top of ALIGN, and ending either one falls back to the other if it's still
## live, only reaching the pre-mini-game page once none are. Restoring is skipped
## when the player has since paged away by hand — their choice outranks ours.
func _auto_page(page: String, active: bool) -> void:
	if unit_id != "A":
		return
	if active:
		# Capture the page to come back to whenever a mini-game takes over one
		# the player is really on: the first one, and any later one that
		# interrupts a page they've since chosen by hand. A page that is itself
		# a live mini-game is never captured — that would restore one of our own
		# pages — which is also what stops a repeated trigger (already showing
		# its own page) from re-capturing over the real fallback.
		if not _auto_pages.has(_current):
			_page_before_auto = _current
		if not _auto_pages.has(page):
			_auto_pages.append(page)
		show_page(page)
		return
	_auto_pages.erase(page)
	if _current != page:
		return
	if not _auto_pages.is_empty():
		show_page(_auto_pages[_auto_pages.size() - 1])
	elif _page_before_auto == "":
		go_home()
	else:
		show_page(_page_before_auto)


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
		"ALIGN":
			var align := AlignPanelScript.new()
			align.accent = accent
			return align
		"SCOOP":
			var scoop := ScoopPanelScript.new()
			scoop.accent = accent
			return scoop
		"DOCK":
			var dock := DockPanelScript.new()
			dock.accent = accent
			return dock
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


## Step through the pages (mapped page-next/prev), wrapping at both ends. The
## MENU home is deliberately NOT in this cycle: it's reached by its own bezel
## button / mapped MFD-menu action, from which you tap straight to the page you
## want. Paging therefore stays on the working pages and can never dump you onto
## the menu mid-cycle. From the MENU home (nothing paged yet) +1 opens the first
## page and −1 the last, so a rocker still gets you in.
func page_step(delta: int) -> void:
	if _current == "":
		show_page(PAGES[0] if delta >= 0 else PAGES[PAGES.size() - 1])
		return
	var step := 1 if delta >= 0 else -1
	show_page(PAGES[(PAGES.find(_current) + step + PAGES.size()) % PAGES.size()])
