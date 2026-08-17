extends Node
## Headless checks for the ship's two documents: their chapter catalogs, the
## live-binding substitution their procedures depend on, and the reader itself.
##
##   godot --headless res://tools/PilotManualSmoke.tscn
##
## Two checks earn their keep here.
##
## The placeholder audit: every {{act:...}} in either document must name a real
## Input Map action. Rename or drop an action and this fails, instead of a
## procedure quietly printing a gap where a control's name should be — which is
## the failure mode a document embedded in code has.
##
## The boundary audit: the handbook is the builder's and the terminal procedures
## are the harbour's, and the whole reason they are separate publications is that
## nobody can state the other's business. The lane markers are the test case —
## they are the harbour's geometry, they were once written into the handbook's
## arrival checklist, and putting them back is exactly the regression this
## catches.

const ManualContentScript := preload("res://scenes/displays/PilotManualContent.gd")
const TerminalContentScript := preload("res://scenes/displays/TerminalProceduresContent.gd")
const ViewerScript := preload("res://scenes/displays/ManualViewer.gd")
const TitleCardScript := preload("res://scenes/displays/TitleCard.gd")
const BindingLabelScript := preload("res://scenes/ui/BindingLabel.gd")

## The procedures the handbook is required to carry, by chapter id.
const REQUIRED_CHECKLISTS := [
	"checklist-departure", "checklist-arrival",
	"checklist-cutting", "checklist-collecting",
]

## The procedures the harbour's document is required to carry.
const REQUIRED_TERMINAL := ["arrival-procedure", "departure-procedure"]

## Harbour geometry, by the names only the harbour publishes. None of these may
## appear in the builder's handbook: the ship is the same ship at every berth,
## and a marker name is true of one station only.
const HARBOUR_ONLY := ["ALPHA", "BRAVO", "CHARLIE", "DELTA"]

## ...and the mirror of it. These are properties of the airframe, and the harbour
## does not restate them — it assesses arrivals, it does not certify airframes.
const BUILDER_ONLY := ["45°/s", "4.0 m/s²", "manual_accel", "0.35 of a member"]

var _failures: Array[String] = []
## Signal probe. A member, not a lambda-captured local: a GDScript lambda captures
## by VALUE, so a counter local to the test would never see the increment.
var _closed_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	_test_catalog()
	_test_placeholders()
	_test_binding_labels()
	await _test_screen()
	await _test_card_wiring()

	if _failures.is_empty():
		print("PILOT MANUAL SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("PILOT MANUAL SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


func _test_catalog() -> void:
	_check_catalog(ManualContentScript.CHAPTERS, "handbook", REQUIRED_CHECKLISTS)
	_check_catalog(TerminalContentScript.CHAPTERS, "terminal procedures", REQUIRED_TERMINAL)
	_test_boundary()


## Shape checks common to both documents.
func _check_catalog(chapters: Array, label: String, required: Array) -> void:
	_check(not chapters.is_empty(), "%s: has chapters" % label)
	var well_formed := true
	var seen: Dictionary = {}
	var unique := true
	for chapter: Dictionary in chapters:
		for field in ["id", "group", "title", "body"]:
			if String(chapter.get(field, "")).is_empty():
				well_formed = false
		var id := String(chapter.get("id", ""))
		if seen.has(id):
			unique = false
		seen[id] = true
	_check(well_formed, "%s: every chapter carries id/group/title/body" % label)
	_check(unique, "%s: chapter ids are unique" % label)

	var missing: PackedStringArray = []
	for id: String in required:
		if not seen.has(id):
			missing.append(id)
	_check(missing.is_empty(), "%s: required chapters present (missing: %s)"
			% [label, ", ".join(missing)])

	# Each section must be contiguous. The contents list emits a heading whenever
	# the group changes, so a chapter filed out of order would print a second copy
	# of its section heading further down the list.
	var order: PackedStringArray = []
	var repeated: PackedStringArray = []
	for chapter: Dictionary in chapters:
		var group := String(chapter.get("group", ""))
		if not order.is_empty() and order[order.size() - 1] == group:
			continue
		if order.has(group):
			repeated.append(group)
		order.append(group)
	_check(repeated.is_empty(), "%s: each section is contiguous (split: %s)"
			% [label, ", ".join(repeated)])


## The reason the two documents exist separately: neither publisher may state the
## other's business. Asserted on the material each is uniquely able to publish.
func _test_boundary() -> void:
	var leaked: PackedStringArray = []
	for chapter: Dictionary in ManualContentScript.CHAPTERS:
		var body := String(chapter["body"])
		for marker: String in HARBOUR_ONLY:
			if body.contains(marker):
				leaked.append("%s names %s" % [chapter["id"], marker])
	_check(leaked.is_empty(),
			"the handbook publishes no harbour geometry (%s)" % ", ".join(leaked))

	var restated: PackedStringArray = []
	for chapter: Dictionary in TerminalContentScript.CHAPTERS:
		var body := String(chapter["body"])
		for figure: String in BUILDER_ONLY:
			if body.contains(figure):
				restated.append("%s quotes %s" % [chapter["id"], figure])
	_check(restated.is_empty(),
			"the terminal procedures restate no airframe figures (%s)" % ", ".join(restated))

	# Each terminal chapter names the office that issued it, at the head. That
	# masthead IS the attribution — there is no disclaimer to look for.
	var unsourced: PackedStringArray = []
	for chapter: Dictionary in TerminalContentScript.CHAPTERS:
		var body := String(chapter["body"])
		var sourced := body.contains(TerminalContentScript.HARBOUR) \
				or body.contains(TerminalContentScript.CLAIM_OFFICE) \
				or body.contains(TerminalContentScript.AGENT) \
				or body.contains("SYSTEM CHART")
		if not sourced:
			unsourced.append(String(chapter["id"]))
	_check(unsourced.is_empty(), "every terminal chapter names its issuing office (%s)"
			% ", ".join(unsourced))


## Every {{...}} in the content must be a token the manual knows how to resolve,
## and every action it names must exist. A typo here is a hole in a checklist.
func _test_placeholders() -> void:
	var manual: Control = ViewerScript.new()
	var bad_tokens: PackedStringArray = []
	var bad_actions: PackedStringArray = []
	# Both documents: the harbour's procedures name controls too.
	var every: Array = []
	every.append_array(ManualContentScript.CHAPTERS)
	every.append_array(TerminalContentScript.CHAPTERS)
	for chapter: Dictionary in every:
		for token: String in _tokens(String(chapter["body"])):
			if manual._binding_text(token).is_empty():
				bad_tokens.append("%s: {{%s}}" % [chapter["id"], token])
			# Action-shaped tokens are checked against the Input Map itself, so a
			# renamed action fails here rather than resolving to "unbound".
			for action in _actions_in(token):
				if not InputMap.has_action(action):
					bad_actions.append("%s: %s" % [chapter["id"], action])
	manual.free()
	_check(bad_tokens.is_empty(), "every placeholder resolves (bad: %s)"
			% ", ".join(bad_tokens))
	_check(bad_actions.is_empty(), "every placeholder names a real action (bad: %s)"
			% ", ".join(bad_actions))


## The {{...}} tokens in a body, without their braces.
func _tokens(body: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var rest := body
	while true:
		var open := rest.find("{{")
		if open == -1:
			return found
		var close := rest.find("}}", open)
		if close == -1:
			return found
		found.append(rest.substr(open + 2, close - open - 2))
		rest = rest.substr(close + 2)
	return found


## The action names a token refers to ({} for switch tokens, which name panel
## legends rather than actions).
func _actions_in(token: String) -> PackedStringArray:
	var split := token.split(":", true, 1)
	if split.size() != 2:
		return []
	match split[0]:
		"act":
			return [split[1]]
		"axis":
			return split[1].split(",", true, 1)
	return []


## The resolver must agree with whatever is ACTUALLY bound, so the expectations
## here are derived from the effective profiles rather than from the shipped
## defaults. A developer machine carrying a saved user profile replaces those
## defaults wholesale (that is the documented override rule), so asserting "C
## fires the cutter" would test the machine, not the code.
func _test_binding_labels() -> void:
	var keyboard := InputRouter.profile_for_guid("keyboard")
	var keys: Array = keyboard.get("keys", [])
	_check(not keys.is_empty(), "there is an effective keyboard profile to check")
	var wrong_keys: PackedStringArray = []
	for spec: Dictionary in keys:
		var action := String(spec.get("action", ""))
		var key_name := OS.get_keycode_string(int(spec.get("key", 0)) as Key)
		if not BindingLabelScript.for_action(action).contains(key_name):
			wrong_keys.append("%s→%s" % [action, key_name])
	_check(wrong_keys.is_empty(), "every bound key is reported on its action (%s)"
			% ", ".join(wrong_keys))

	# An action with nothing bound must say so in the one agreed way, rather than
	# rendering as an empty gap in the middle of a checklist step.
	# A GAME action specifically: Godot's own ui_* actions are always present and
	# would make this pass without exercising anything the manual depends on.
	var unbound := ""
	for action: StringName in InputMap.get_actions():
		if not String(action).begins_with("ui_") \
				and InputMap.action_get_events(action).is_empty():
			unbound = String(action)
			break
	_check(not unbound.is_empty(), "there is an unbound action to check")
	if not unbound.is_empty():
		_check(BindingLabelScript.for_action(unbound) == BindingLabelScript.UNBOUND,
				"an unbound action reports UNBOUND (%s)" % unbound)
	_check(BindingLabelScript.for_action("not_an_action") == BindingLabelScript.UNBOUND,
			"an unknown action reports UNBOUND rather than erroring")
	# Nothing may resolve to an empty string — that would render as a hole.
	var empties: PackedStringArray = []
	for action: StringName in InputMap.get_actions():
		if BindingLabelScript.for_action(String(action)).is_empty():
			empties.append(String(action))
	_check(empties.is_empty(), "no action resolves to an empty label (%s)"
			% ", ".join(empties))

	# An analog axis binds to BOTH directions of a pair, so it must be named once,
	# not twice. Checked against whatever axis pair the profiles actually carry.
	var pair := _bound_axis_pair()
	if pair.is_empty():
		print("  -- no analog axis pair bound; skipping the shared-axis check")
	else:
		var text: String = BindingLabelScript.for_axis(pair[0], pair[1])
		_check(text.count("Axis") == 1,
				"one analog axis on a pair is named once, not per direction (%s)" % text)

	# Switch legends are static — the panel silkscreen — and the power ones derive
	# from GameState.CHANNEL_SWITCHES so the pairing is defined in exactly one place.
	_check(BindingLabelScript.for_power_switch("CUTTER") == "DE-ICE",
			"the CUTTER channel resolves to its panel switch")
	_check(BindingLabelScript.for_power_switch("THRUST") == "FUEL PUMP",
			"the THRUST channel resolves to its panel switch")
	_check(BindingLabelScript.for_power_switch("SENSORS") == "AVIONICS",
			"the SENSORS channel resolves to its panel switch")
	_check(BindingLabelScript.for_switch("COWL") == "COWL",
			"the cargo hatch switch resolves to its legend")
	_check(BindingLabelScript.for_switch("GEAR_DOWN") == "GEAR DOWN",
			"the gear lever resolves to its legend")


## The first direction pair (from the manual's own axis placeholders) that a
## connected device drives with one analog axis, or [] if none does.
func _bound_axis_pair() -> Array:
	for chapter: Dictionary in ManualContentScript.CHAPTERS:
		for token: String in _tokens(String(chapter["body"])):
			var split := token.split(":", true, 1)
			if split.size() != 2 or split[0] != "axis":
				continue
			var pair := split[1].split(",", true, 1)
			if pair.size() == 2 \
					and BindingLabelScript.for_axis(pair[0], pair[1]).contains("Axis"):
				return [pair[0], pair[1]]
	return []


func _test_screen() -> void:
	# The reader is document-agnostic, so it is exercised against BOTH — a viewer
	# that only ever renders the handbook would pass while the harbour's document
	# was unopenable.
	await _check_screen(ManualContentScript.CHAPTERS, "handbook")
	await _check_screen(TerminalContentScript.CHAPTERS, "terminal procedures")


func _check_screen(chapters: Array, label: String) -> void:
	var manual: Control = ViewerScript.new()
	manual.configure(chapters, "TEST — %s" % label, "SUBTITLE")
	add_child(manual)
	manual.start()
	await get_tree().process_frame

	_check(manual._chapter_buttons.size() == chapters.size(),
			"%s: one contents button per chapter" % label)
	_check(manual.current_chapter() == String(chapters[0]["id"]),
			"%s: opens on its first chapter" % label)

	# Every chapter renders, and none leaves an unsubstituted placeholder on the
	# page — the visible half of the audit in _test_placeholders.
	var leftovers: PackedStringArray = []
	var blanks: PackedStringArray = []
	for chapter: Dictionary in chapters:
		var id := String(chapter["id"])
		manual.show_chapter(id)
		if manual._body.text.contains("{{"):
			leftovers.append(id)
		# get_parsed_text is the text AFTER bbcode is stripped: a chapter whose
		# markup swallowed its own content would still pass a length check on the
		# raw string.
		if manual._body.get_parsed_text().strip_edges().length() < 200:
			blanks.append(id)
	_check(leftovers.is_empty(), "%s: no unresolved placeholder on any page (%s)"
			% [label, ", ".join(leftovers)])
	_check(blanks.is_empty(), "%s: every chapter renders real text (%s)"
			% [label, ", ".join(blanks)])

	# Selecting a chapter actually swaps the page.
	var last := String(chapters[chapters.size() - 1]["id"])
	manual.show_chapter(String(chapters[0]["id"]))
	var first_text: String = manual._body.text
	manual.show_chapter(last)
	_check(manual.current_chapter() == last and manual._body.text != first_text,
			"%s: picking a chapter swaps the page" % label)

	# An unknown id must not blank the page.
	manual.show_chapter("no-such-chapter")
	_check(manual.current_chapter() == last, "%s: an unknown chapter id is ignored" % label)

	_closed_count = 0
	manual.closed.connect(_on_closed)
	manual._close_button.pressed.emit()
	_check(_closed_count == 1, "%s: CLOSE asks to be closed" % label)
	manual.closed.disconnect(_on_closed)
	manual.queue_free()


func _on_closed() -> void:
	_closed_count += 1


## The card side: both documents are reachable from the launch screen, only one
## is on the reader at a time, a document hides for a full-screen setup step, and
## closing hands focus back to LAUNCH.
func _test_card_wiring() -> void:
	var card: Control = TitleCardScript.new()
	add_child(card)
	card.start()
	await get_tree().process_frame

	_check(not card.manual_open(), "no document starts open")
	# The card offers a row per document, and each opens the one it names.
	_check(card.DOCUMENTS.size() == 2, "the card offers both documents")
	for document: Dictionary in card.DOCUMENTS:
		var id := String(document["id"])
		card._open_document(id)
		await get_tree().process_frame
		_check(card.open_document() == id, "the card opens %s" % id)
		_check(card._manual_ui._chapters.size() == card._document_chapters(id).size(),
				"%s opens with its own chapters" % id)
		card._close_manual()
		await get_tree().process_frame

	card._open_document("manual")
	await get_tree().process_frame
	_check(card._manual_layer.layer > 15 and card._manual_layer.layer < 20,
			"a document sits above the card but below the chooser and remapper")
	_check(card._manual_layer.process_mode == Node.PROCESS_MODE_ALWAYS,
			"a document runs while the card holds the tree paused")

	# A second press on the SAME row must not stack a second copy over the first.
	var layer: CanvasLayer = card._manual_layer
	card._open_document("manual")
	_check(card._manual_layer == layer, "re-opening the same document is a no-op")

	# ...but the other row swaps to it rather than stacking on top of it.
	card._open_document("terminal")
	await get_tree().process_frame
	_check(card.open_document() == "terminal" and card._manual_layer != layer,
			"the other document replaces the one on the reader")
	_check(not is_instance_valid(layer), "swapping documents frees the first one")

	# Stepping out to the display chooser must not leave a document over it.
	card.suspend()
	_check(not card._manual_layer.visible, "the document hides with the card")
	card.resume()
	_check(card._manual_layer.visible, "the document comes back with the card")

	card._close_manual()
	await get_tree().process_frame
	_check(not card.manual_open(), "closing tears the document down")
	_check(card.open_document().is_empty(), "closing clears the open-document id")
	_check(card._launch_button.has_focus(), "closing returns focus to LAUNCH")

	# The layer is a child of the card, so LAUNCH freeing the card must take any
	# open document with it rather than leaving a page over the running game.
	card._open_document("manual")
	await get_tree().process_frame
	var orphan: CanvasLayer = card._manual_layer
	card.free()
	_check(not is_instance_valid(orphan), "freeing the card frees an open document")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
