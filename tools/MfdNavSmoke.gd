extends Node
## Headless checks for MFD page navigation: the MENU home is a hub you jump TO
## and tap out of, not a stop in the paging cycle. Paging wraps through the
## pages alone, so a rocker can lap the MFD without ever being dumped back onto
## the menu, while the bezel MENU button / mapped MFD-menu action still reaches
## the home grid from anywhere for a direct jump to any page.
##
##   godot --headless res://tools/MfdNavSmoke.tscn

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var unit := MfdUnit.new()
	# Not "A": the primary unit auto-opens ALIGN/SCOOP off gameplay signals, and
	# this is a test of navigation alone.
	unit.unit_id = "TEST"
	add_child(unit)
	await get_tree().process_frame

	var pages: Array[String] = MfdUnit.PAGES
	var first: String = pages[0]
	var last: String = pages[pages.size() - 1]
	_check(pages.has("SCOOP"), "the SCOOP page is registered")
	_check(unit.current_page() == "", "starts on the MENU home")

	# From the home a rocker still gets you onto the pages, at either end.
	unit.page_step(1)
	_check(unit.current_page() == first, "step + from the MENU opens the first page")
	unit.go_home()
	unit.page_step(-1)
	_check(unit.current_page() == last, "step − from the MENU opens the last page")

	# The wrap: paging past either end lands on the other end, never the MENU.
	unit.show_page(last)
	unit.page_step(1)
	_check(unit.current_page() == first,
			"paging past the last page wraps to the first, not the MENU")
	unit.show_page(first)
	unit.page_step(-1)
	_check(unit.current_page() == last,
			"paging back off the first page wraps to the last, not the MENU")

	# A full lap: every page once, and the MENU never among them.
	unit.show_page(first)
	var seen: Dictionary = {}
	var never_menu := true
	for _i in pages.size():
		seen[unit.current_page()] = true
		never_menu = never_menu and unit.current_page() != ""
		unit.page_step(1)
	_check(never_menu and seen.size() == pages.size(),
			"a full lap visits every page once and never lands on the MENU")
	_check(unit.current_page() == first, "a full lap comes back around to the start")

	# The MENU stays reachable on demand — what the bezel button and the mapped
	# MFD-menu action call — and tapping the grid jumps straight to a page.
	unit.show_page("SCOOP")
	unit.go_home()
	_check(unit.current_page() == "", "go_home returns to the MENU from a page")
	unit.show_page("MARKET")
	_check(unit.current_page() == "MARKET", "the MENU jumps straight to any page")
	_check(unit._menu_button.visible, "the MENU button is offered while on a page")
	unit.go_home()
	_check(not unit._menu_button.visible, "the MENU button hides on the home grid itself")

	if _failures.is_empty():
		print("MFD NAV SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("MFD NAV SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
