extends Node
## Headless checks for the MFD CHECKLIST page — its catalog, its live reads, and
## the layout budget the instrument pages share with it.
##
##   godot --headless res://tools/ChecklistSmoke.tscn
##
## Three things earn their keep here.
##
## The live-read audit: every auto item is called against real GameState and must
## come back with a status and a value. The whole page is a wall of Callables
## reaching into GameState and the systems, so a renamed field or a removed
## function would otherwise blank one row silently — the reader would see a gap
## where a condition should be and have no way to tell it apart from "not yet".
##
## The tick audit: driving the real intents (set_cargo_hatch, set_landing_gear,
## the power channels) must actually flip the matching rows. A checklist that
## doesn't move when the ship does is worse than no checklist.
##
## The layout audit: the type scale, the footers and the checklist reserves all
## come out of the same vertical budget as the DOCK and SCOOP cone fields.
## Raising one without re-deriving the others collapses the field, and only on a
## screen small enough that nobody sees it until they are flying an approach on
## it. So the arithmetic is asserted rather than eyeballed.

const ChecklistContent := preload("res://scenes/ui/ChecklistContent.gd")
const ChecklistPanelScript := preload("res://scenes/ui/ChecklistPanel.gd")
const Instrument := preload("res://scenes/ui/Instrument.gd")
const DockPanelScript := preload("res://scenes/ui/DockPanel.gd")
const ScoopPanelScript := preload("res://scenes/ui/ScoopPanel.gd")
const AlignPanelScript := preload("res://scenes/ui/AlignPanel.gd")

## The procedures the page is required to carry, by id. These mirror the
## handbook's SECTION 4 chapter ids (checklist-<id>), which PilotManualSmoke
## asserts separately — between them, the page and the paper cannot lose a
## procedure independently of each other.
const REQUIRED_LISTS := ["departure", "arrival", "cutting", "collecting"]

## A unit deliberately smaller than any real MFD, for the layout audit.
const CRAMPED := Vector2(320, 240)

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	_test_catalog()
	_test_live_reads()
	_test_limits_are_read_not_written()
	await _test_ticks()
	await _test_panel()
	await _test_layout_budget()

	if _failures.is_empty():
		print("CHECKLIST SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("CHECKLIST SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


# --- Catalog ----------------------------------------------------------------

func _test_catalog() -> void:
	var lists := ChecklistContent.lists()
	_check(not lists.is_empty(), "the catalog has procedures")

	var seen: Dictionary = {}
	var well_formed := true
	for entry: Dictionary in lists:
		for field in ["id", "title", "items"]:
			if not entry.has(field):
				well_formed = false
		seen[String(entry.get("id", ""))] = true
	_check(well_formed, "every procedure carries id/title/items")

	var missing: PackedStringArray = []
	for id: String in REQUIRED_LISTS:
		if not seen.has(id):
			missing.append(id)
	_check(missing.is_empty(), "required procedures present (missing: %s)"
			% ", ".join(missing))

	for entry: Dictionary in lists:
		var id := String(entry["id"])
		var items: Array = entry["items"]
		_check(not items.is_empty(), "%s: has items" % id)

		var fields_ok := true
		for item: Dictionary in items:
			if String(item.get("label", "")).is_empty() \
					or String(item.get("group", "")).is_empty():
				fields_ok = false
			# A manual item still has to say what it wants; without it the row is
			# a bare label with a box beside it.
			if String(item.get("want", "")).is_empty():
				fields_ok = false
		_check(fields_ok, "%s: every item carries label/want/group" % id)

		# Groups must be contiguous — the row builder emits a heading whenever the
		# group changes, so an item filed out of order prints its section heading
		# a second time further down the list.
		var order: PackedStringArray = []
		var repeated: PackedStringArray = []
		for item: Dictionary in items:
			var group := String(item["group"])
			if not order.is_empty() and order[order.size() - 1] == group:
				continue
			if order.has(group):
				repeated.append(group)
			order.append(group)
		_check(repeated.is_empty(), "%s: sections are contiguous (repeated: %s)"
				% [id, ", ".join(repeated)])


# --- Live reads -------------------------------------------------------------

## Every auto item, called against real state. This is the regression guard: an
## item pointing at a renamed GameState field or a removed system function fails
## the build here instead of quietly blanking a row in flight.
func _test_live_reads() -> void:
	var bad: PackedStringArray = []
	var manual := 0
	var auto := 0
	for entry: Dictionary in ChecklistContent.lists():
		for item: Dictionary in entry["items"]:
			if not item.has("read"):
				manual += 1
				continue
			auto += 1
			var result: Variant = (item["read"] as Callable).call()
			var label := "%s / %s" % [entry["id"], item["label"]]
			if not (result is Dictionary):
				bad.append(label + " (not a Dictionary)")
				continue
			var dict: Dictionary = result
			if not dict.has("status") or not dict.has("value"):
				bad.append(label + " (missing status/value)")
			elif String(dict["value"]).is_empty():
				bad.append(label + " (empty value)")
	_check(bad.is_empty(), "every live read returns a status and a value (bad: %s)"
			% ", ".join(bad))
	_check(auto > 0, "the catalog has items the ship checks itself")
	# The manual items are the two nothing aboard can judge. If this grows, either
	# a real live read was dropped or someone took the easy way out of one.
	_check(manual == 2, "only the unverifiable items are tapped by hand (found %d)"
			% manual)


## No figure is transcribed into the catalog: a row's limit is read from the
## constant that enforces it. Change the constant and these strings must follow —
## if one is hardcoded instead, this fails.
func _test_limits_are_read_not_written() -> void:
	var cutter := _find_read("cutting", "CUTTER ALLOCATION")
	_check(not cutter.is_empty() and String(cutter.get("value", "")).contains(
			"%.2f" % SalvageSystem.MIN_CUTTER_POWER),
			"the cutter row reads MIN_CUTTER_POWER rather than a written number")

	var sensors := _find_read("cutting", "SENSORS ALLOCATION")
	_check(not sensors.is_empty() and String(sensors.get("value", "")).contains(
			"%.2f" % SalvageSystem.MIN_SENSOR_POWER),
			"the sensors row reads MIN_SENSOR_POWER rather than a written number")

	var risk := _find_read("cutting", "STRUCTURAL RISK")
	_check(not risk.is_empty() and String(risk.get("value", "")).contains(
			"%.2f" % ThreatSystem.COLLAPSE_RISK_FLOOR),
			"the risk row reads COLLAPSE_RISK_FLOOR rather than a written number")

	# The scoop rows only report a limit once there is a piece to measure against,
	# so put one in the world first.
	GameState.run_phase = "ON_SITE"
	var piece_id := DriftSystem.spawn_piece(_stub_member(), 1.0)
	var scoop_range := _find_read("collecting", "RANGE")
	_check(not scoop_range.is_empty() and String(scoop_range.get("value", "")).contains(
			"%.1f" % DriftSystem.SCOOP_RANGE),
			"the scoop range row reads SCOOP_RANGE rather than a written number")
	var rel := _find_read("collecting", "RELATIVE VELOCITY")
	_check(not rel.is_empty() and String(rel.get("value", "")).contains(
			"%.2f" % DriftSystem.COLLECT_REL_SPEED),
			"the relative-velocity row reads COLLECT_REL_SPEED rather than a written number")
	GameState.remove_salvage_piece(piece_id)


# --- Ticks follow the ship --------------------------------------------------

func _test_ticks() -> void:
	# The hatch, both ways. It is the single most interlocked thing on the ship —
	# it gates the torch, docking and departure — and it appears on all four
	# procedures, so it is the row most worth proving moves.
	GameState.set_cargo_hatch(false)
	_check(_status("cutting", "CARGO HATCH") == ChecklistContent.Status.PASS,
			"a secured hatch passes the cutting procedure")
	_check(_status("collecting", "CARGO HATCH") == ChecklistContent.Status.FAIL,
			"...and fails the collecting procedure, which needs it open")
	GameState.set_cargo_hatch(true)
	_check(_status("cutting", "CARGO HATCH") == ChecklistContent.Status.FAIL,
			"opening the hatch fails the cutting procedure")
	_check(_status("collecting", "CARGO HATCH") == ChecklistContent.Status.PASS,
			"...and passes the collecting procedure")
	GameState.set_cargo_hatch(false)

	# The gear, through its travel. Three seconds each way is exactly why the row
	# has to report IN TRANSIT rather than just down or up.
	GameState.set_landing_gear(false)
	await get_tree().process_frame
	GameState.gear_position = 0.0
	_check(_status("cutting", "LANDING GEAR") == ChecklistContent.Status.PASS,
			"stowed gear passes the cutting procedure")
	GameState.set_landing_gear(true)
	GameState.gear_position = 0.5
	_check(_status("arrival", "LANDING GEAR") == ChecklistContent.Status.FAIL,
			"gear mid-travel does not yet pass the arrival procedure")
	_check(_read("arrival", "LANDING GEAR").get("value", "") == "IN TRANSIT 50%",
			"...and the row names the travel rather than just failing")
	GameState.gear_position = 1.0
	_check(_status("arrival", "LANDING GEAR") == ChecklistContent.Status.PASS,
			"gear down and locked passes the arrival procedure")

	# A power channel against its interlock threshold.
	GameState.set_power("CUTTER", 0.0)
	_check(_status("cutting", "CUTTER ALLOCATION") == ChecklistContent.Status.FAIL,
			"an unpowered cutter fails the cutting procedure")
	GameState.set_power("CUTTER", SalvageSystem.MIN_CUTTER_POWER)
	_check(_status("cutting", "CUTTER ALLOCATION") == ChecklistContent.Status.PASS,
			"raising CUTTER to the interlock minimum passes it")

	# N/A, not FAIL: with no pattern running there is no pad to be off, and a red
	# row for something that cannot yet be done teaches the reader to ignore red.
	GameState.docking_state = "INACTIVE"
	_check(_status("arrival", "SINK RATE") == ChecklistContent.Status.NA,
			"a touchdown limit reads N/A with no approach running")

	# The exterior lights, both ends of the tour. The two rows deliberately read
	# DIFFERENT things — departure wants them burning, arrival wants the switches
	# off — so both directions are pinned here.
	GameState.set_master_alt(true)
	GameState.set_master_battery(true)
	for group: String in GameState.exterior_lights.keys():
		GameState.set_exterior_light(group, true)
	_check(_status("departure", "EXTERIOR LIGHTS") == ChecklistContent.Status.PASS,
			"a lit ship passes the departure lights item")
	GameState.set_exterior_light("STROBE", false)
	_check(_status("departure", "EXTERIOR LIGHTS") == ChecklistContent.Status.FAIL,
			"one group switched off fails it")
	_check(_read("departure", "EXTERIOR LIGHTS").get("value", "") == "STROBE OFF",
			"...and the row names the group that is out")
	GameState.set_exterior_light("STROBE", true)

	# Selected on but with nothing behind the bus is not "on" — the row states what
	# the pilot could see out of the window, not what the switches are asking for.
	GameState.set_master_alt(false)
	GameState.set_master_battery(false)
	_check(_status("departure", "EXTERIOR LIGHTS") == ChecklistContent.Status.FAIL,
			"lights selected on with a dead bus still fail the departure item")
	_check(_read("departure", "EXTERIOR LIGHTS").get("value", "") == "NO BUS",
			"...and the row says why rather than blaming a switch")
	GameState.set_master_alt(true)
	GameState.set_master_battery(true)

	# The arrival item is N/A until there is a pad under the ship: she is lit for
	# the whole flight by design, and a row red from the claim to touchdown is
	# exactly the red row that trains a pilot to ignore red.
	GameState.docking_state = "INACTIVE"
	var saved_phase := GameState.run_phase
	GameState.run_phase = "ON_SITE"
	_check(_status("arrival", "EXTERIOR LIGHTS") == ChecklistContent.Status.NA,
			"the arrival lights item reads N/A off the pad")
	GameState.run_phase = "DOCKED"
	_check(_status("arrival", "EXTERIOR LIGHTS") == ChecklistContent.Status.FAIL,
			"...and comes live on the pad, with the ship still lit")
	for group: String in GameState.exterior_lights.keys():
		GameState.set_exterior_light(group, false)
	_check(_status("arrival", "EXTERIOR LIGHTS") == ChecklistContent.Status.PASS,
			"switching all three off passes it")
	# Going dark by pulling the masters must NOT tick the item: the switches are
	# what stops the lights coming back with the bus.
	for group: String in GameState.exterior_lights.keys():
		GameState.set_exterior_light(group, true)
	GameState.set_master_alt(false)
	GameState.set_master_battery(false)
	_check(_status("arrival", "EXTERIOR LIGHTS") == ChecklistContent.Status.FAIL,
			"a dark bus does not tick the item for you — the switches do")
	GameState.set_master_alt(true)
	GameState.set_master_battery(true)
	GameState.run_phase = saved_phase


# --- The panel --------------------------------------------------------------

func _test_panel() -> void:
	var panel: Control = ChecklistPanelScript.new()
	add_child(panel)
	_size_to(panel, Vector2(600, 660))
	await get_tree().process_frame

	_check(panel.open_list_id() == "", "the page opens on the procedure index")
	_check(panel._index_buttons.size() == REQUIRED_LISTS.size(),
			"the index offers one button per procedure")
	_check(not panel._footer.visible, "the index has no BACK/RESET footer")

	panel._open_list(2)
	await get_tree().process_frame
	_check(panel.open_list_id() == "cutting", "tapping the index opens that procedure")
	_check(panel._footer.visible, "an open procedure offers its footer")
	_check(not panel._rows.is_empty(), "an open procedure builds rows")

	# Auto rows must not be tappable. A hand-ticked row the ship says is false is
	# exactly the lie this page exists to prevent.
	var auto_tappable := 0
	var manual_rows := 0
	for entry: Dictionary in panel._rows:
		var row: Control = entry["row"]
		if row.manual:
			manual_rows += 1
			continue
		if row.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			auto_tappable += 1
	_check(auto_tappable == 0, "no live row can be ticked by hand")
	_check(manual_rows > 0, "the cutting procedure has a hand-marked item")

	# A manual tick, and RESET clearing it.
	var manual_index := -1
	for entry: Dictionary in panel._rows:
		if (entry["row"] as Control).manual:
			manual_index = int(entry["index"])
			break
	panel._toggle_tick(manual_index)
	_check(panel._ticked.size() == 1, "tapping a hand-marked item ticks it")
	panel._reset_open()
	_check(panel._ticked.is_empty(), "RESET clears the open procedure's ticks")

	# A new run starts a fresh checklist.
	panel._toggle_tick(manual_index)
	GameState.site_reset.emit()
	_check(panel._ticked.is_empty(), "a site reset clears the ticks")

	# The longest procedure runs well past a screen, and drag-scrolling a list is
	# not something you can do while flying — so the footer's own paging has to
	# actually move it.
	await get_tree().process_frame
	_check(panel._scroll.get_v_scroll_bar().max_value > panel._scroll.size.y,
			"the cutting procedure is longer than the screen (so paging matters)")
	panel._scroll_by(1)
	await get_tree().process_frame
	_check(panel._scroll.scroll_vertical > 0, "▼ pages the procedure down")
	panel._scroll_by(-1)
	await get_tree().process_frame
	_check(panel._scroll.scroll_vertical == 0, "▲ pages it back up")

	panel._show_index()
	_check(panel.open_list_id() == "", "BACK returns to the index")

	panel.queue_free()


# --- The shared vertical budget ---------------------------------------------

func _test_layout_budget() -> void:
	# The reserves must actually fit the rows they reserve. Raising the type scale
	# without re-deriving a reserve then fails here rather than overlapping the
	# cone field with the checklist.
	_check(DockPanelScript.CHECKLIST_H >= DockPanelScript.GATE_ROWS * Instrument.ROW_PITCH,
			"the DOCK checklist reserve fits its rows at the current pitch")
	_check(ScoopPanelScript.CHECKLIST_H >= ScoopPanelScript.GATE_ROWS * Instrument.ROW_PITCH
			+ Instrument.ROW_PITCH + Instrument.BAR_H,
			"the SCOOP checklist reserve fits its rows plus the closure line and meter")

	# ...and the pages must survive a unit far smaller than any real MFD. `avail`
	# goes negative once the reserves exceed the height, and the field floor is
	# what has to catch it — otherwise this only shows up on the smallest panel
	# someone actually uses, mid-approach.
	for entry: Dictionary in [
		{"name": "DOCK", "script": DockPanelScript},
		{"name": "SCOOP", "script": ScoopPanelScript},
		{"name": "ALIGN", "script": AlignPanelScript},
	]:
		var panel: Control = (entry["script"] as GDScript).new()
		add_child(panel)
		_size_to(panel, CRAMPED)
		panel.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(is_instance_valid(panel) and panel.size.is_equal_approx(CRAMPED),
				"the %s page draws on a %dx%d unit without falling over"
				% [entry["name"], int(CRAMPED.x), int(CRAMPED.y)])
		panel.queue_free()


## Force a real size onto a page. Each one anchors itself full-rect in _ready(),
## which would otherwise override the assignment (and warn) — leaving the cramped
## check above testing nothing at all.
func _size_to(control: Control, to: Vector2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.size = to


# --- Helpers ----------------------------------------------------------------

func _read(list_id: String, label: String) -> Dictionary:
	return _find_read(list_id, label)


func _status(list_id: String, label: String) -> int:
	var result := _find_read(list_id, label)
	return int(result.get("status", -1))


## The live result for one item, by procedure and label. Returns {} if there is
## no such item — which every caller then fails on, so a renamed label shows up
## as a failure rather than as a silently skipped check.
func _find_read(list_id: String, label: String) -> Dictionary:
	for entry: Dictionary in ChecklistContent.lists():
		if String(entry["id"]) != list_id:
			continue
		for item: Dictionary in entry["items"]:
			if String(item["label"]) != label or not item.has("read"):
				continue
			return (item["read"] as Callable).call()
	return {}


## The minimum a member needs for DriftSystem.spawn_piece to make a piece of it —
## id/name/good/node are read unguarded there, the rest have defaults.
func _stub_member() -> Dictionary:
	return {
		"id": 0, "name": "TEST MEMBER", "good": "ALLOY", "node": "HullFore",
		"center": Vector3.ZERO, "seam": Vector3.UP, "radius": 1.0,
	}


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
