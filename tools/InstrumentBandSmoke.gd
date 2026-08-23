extends Node
## Headless checks for the Tactical instrument band and the navigation datum it
## reads from.
##
##   godot --headless res://tools/InstrumentBandSmoke.tscn
##
## Four things earn their keep here.
##
## The SIGN audit. Every reading on this band is a signed quantity whose sign is
## the instrument — nose-up has to fill the ball with sky, a right wing down has
## to tilt the horizon the way the world tilts, a climb has to point the trend
## arrow up. Every one of those is a single character in the source and none of
## them is visible in a screenshot taken while the ship is level, so they are
## asserted rather than eyeballed.
##
## The AGREEMENT audit. The band's ALT under the platform datum must equal
## DockingSystem's own altitude, and its heading under the inertial datum must
## equal the flight HUD's formula. Two instruments disagreeing about the same
## number on short final is worse than one instrument fewer, and the only reason
## they agree is that this test says so.
##
## The DATUM audit. Every datum has to resolve to a real orthonormal frame, AUTO
## has to pick the right one for the phase being flown, and a pinned datum that
## has lost its fix has to report the fallback it is holding rather than reading
## from an origin that is not there.
##
## The LAYOUT audit. The band's reserves come out of the same 1280x720 canvas
## the mode panels do, and TacticalContent sets its margins from those same
## consts — so the arithmetic is checked here rather than discovered on the
## physical panel.

const InstrumentBandScript := preload("res://scenes/ui/InstrumentBand.gd")
const TailPlateScript := preload("res://scenes/ui/TailPlate.gd")
const SettingsPanelScript := preload("res://scenes/ui/SettingsPanel.gd")
const TacticalContentScript := preload("res://scenes/displays/TacticalContent.gd")
const MfdUnitScript := preload("res://scenes/ui/MfdUnit.gd")
const ManualContentScript := preload("res://scenes/displays/PilotManualContent.gd")

## The Tactical window's virtual canvas, less TacticalWindow.tscn's margins.
const CONTENT := Vector2(1252, 676)
## The scope still has to be worth looking at with the band up.
const MIN_PANE := Vector2(560, 380)
## A unit deliberately smaller than any real display, for the layout audit.
const CRAMPED := Vector2(320, 240)

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	_test_layout()
	_test_datums()
	_test_auto()
	_test_fallback()
	_test_heading()
	_test_attitude()
	_test_rates()
	_test_altitude()
	_test_propellant()
	_test_plate()
	await _test_panels()

	if _failures.is_empty():
		print("INSTRUMENT BAND SMOKE: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		printerr("INSTRUMENT BAND SMOKE: %d CHECK(S) FAILED" % _failures.size())
		get_tree().quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)


## --- Layout ------------------------------------------------------------------

func _test_layout() -> void:
	var band := InstrumentBandScript
	_check(band.FLIGHT_W == band.SPD_W + band.ADI_W + band.ALT_W,
			"the flight block's width is the sum of its three instruments")
	_check(band.FLIGHT_W + MIN_PANE.x <= CONTENT.x,
			"the flight block leaves a usable mode pane across the canvas")
	_check(band.HDG_H + band.BOTTOM_H + MIN_PANE.y <= CONTENT.y,
			"the heading tape and bottom band leave a usable mode pane down it")
	_check(band.HDG_TAPE_H < band.HDG_H,
			"the heading reserve has room for the datum legend under the tape")


## --- The datum ---------------------------------------------------------------

## Every datum must come back with a real orthonormal frame. A skewed or
## degenerate one would not fail loudly — it would put a plausible, wrong number
## on every readout at once.
func _test_datums() -> void:
	var ids: PackedStringArray = []
	for entry: Dictionary in NavReference.DATUMS:
		ids.append(String(entry["id"]))
	_check(ids == PackedStringArray(GameState.NAV_REFERENCES),
			"the datum catalogue and the selectable list are the same list")

	_stand_up_wreck()
	for id: String in GameState.NAV_REFERENCES:
		GameState.set_nav_reference(id)
		var d: Dictionary = NavReference.datum()
		var up: Vector3 = d["up"]
		var north: Vector3 = d["north"]
		var east: Vector3 = d["east"]
		var label := "%s resolves to an orthonormal frame" % id
		_check(is_equal_approx(up.length(), 1.0) and is_equal_approx(north.length(), 1.0)
				and absf(up.dot(north)) < 0.0001
				and east.is_equal_approx(north.cross(up)), label)
		_check(d["id"] != "AUTO", "%s resolves to a concrete datum, never AUTO" % id)


## AUTO's whole job is to be the datum the pilot would have picked: the approach
## while one is being flown, the piece being cut while one is selected.
func _test_auto() -> void:
	GameState.set_nav_reference("AUTO")
	_clear_site()
	_check(NavReference.datum()["id"] == "INERTIAL",
			"AUTO holds inertial with nothing on site")

	_stand_up_wreck()
	_check(NavReference.datum()["id"] == "WRECK",
			"AUTO takes the derelict once there is one")

	SalvageSystem.select_member(_first_member_id())
	_check(NavReference.datum()["id"] == "TARGET",
			"AUTO prefers the selected cut target to the hull it is on")

	DockingSystem.begin_approach(0)
	_check(DockingSystem.is_active(), "an approach can be started for the phase check")
	_check(NavReference.datum()["id"] == "PAD",
			"AUTO takes the landing platform for as long as an approach is flown")
	DockingSystem.abort_approach()


## A pinned datum that loses its fix must say so. Silently reading an altitude
## from somewhere the pilot did not choose is the one failure this instrument
## cannot be allowed to have.
func _test_fallback() -> void:
	_clear_site()
	GameState.set_nav_reference("WRECK")
	var d: Dictionary = NavReference.datum()
	_check(d["fallback"], "a pinned datum with no fix reports that it fell back")
	_check(d["reason"] != "", "...and says why")
	_check(d["id"] == "INERTIAL", "...and holds what AUTO would have picked")
	_check(is_finite(NavReference.altitude()) and is_finite(NavReference.heading()),
			"...and every reading stays a real number through it")

	_stand_up_wreck()
	_check(not NavReference.datum()["fallback"],
			"the pinned datum comes back the moment it has a fix again")

	# A target pinned with nothing designated is the everyday version of the
	# same failure, and needs no site teardown to reach.
	GameState.set_nav_reference("TARGET")
	SalvageSystem.select_member(-1)
	GameState.tracked_contact_id = -1
	_check(NavReference.datum()["fallback"],
			"a pinned target with nothing designated falls back too")
	GameState.set_nav_reference("AUTO")


## --- Heading ------------------------------------------------------------------

## The datum heading must be a GENERALISATION of the flight HUD's formula, not a
## second convention: under the inertial datum the two are the same number, so a
## pilot reading HDG on the band and HDG on the HUD is reading one thing.
func _test_heading() -> void:
	GameState.set_nav_reference("INERTIAL")
	for yaw_deg in [0.0, 37.0, 90.0, 180.0, 271.0, 359.0]:
		_park(Basis.from_euler(Vector3(0, deg_to_rad(-yaw_deg), 0)))
		var fwd: Vector3 = -(GameState.local_ship()["transform"] as Transform3D).basis.z
		var hud := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
		_check(absf(wrapf(NavReference.heading() - hud, -180.0, 180.0)) < 0.01,
				"heading matches the flight HUD's formula at yaw %d" % roundi(yaw_deg))
	_park(Basis.IDENTITY)
	_check(absf(wrapf(NavReference.heading() - 0.0, -180.0, 180.0)) < 0.01,
			"a ship on the inertial datum's north reads 000")
	GameState.set_nav_reference("AUTO")


## --- Attitude -----------------------------------------------------------------

## The signs ARE the instrument. Nose up has to fill the ball with sky; a right
## wing down has to tilt the horizon the way the world tilts.
func _test_attitude() -> void:
	var band := InstrumentBandScript.new()
	add_child(band)
	GameState.set_nav_reference("INERTIAL")

	_park(Basis.IDENTITY)
	var level := NavReference.attitude()
	_check(absf(level.x) < 0.01 and absf(level.y) < 0.01,
			"a level ship reads P 0 R 0 against its datum")
	_check(is_equal_approx(band.horizon_offset(0.0), 0.0),
			"...and its horizon sits on the waterline")

	# Nose up: pitch is a rotation about the body's right axis, +X.
	_park(Basis(Vector3.RIGHT, deg_to_rad(10.0)))
	_check(absf(NavReference.attitude().x - 10.0) < 0.5,
			"pitching the nose up 10 degrees reads P +10")
	_check(band.horizon_offset(10.0) > 0.0,
			"...and drops the horizon below the waterline, filling the ball with sky")
	_park(Basis(Vector3.RIGHT, deg_to_rad(-10.0)))
	_check(absf(NavReference.attitude().x + 10.0) < 0.5,
			"pitching the nose down 10 degrees reads P -10")
	_check(band.horizon_offset(-10.0) < 0.0,
			"...and raises it, filling the ball with ground")
	_check(band.horizon_offset(20.0) > band.horizon_offset(10.0),
			"the horizon moves monotonically with pitch")

	# Roll right-wing-down is a rotation about the body's own nose axis, -Z.
	_park(Basis(Vector3.FORWARD, deg_to_rad(14.0)))
	_check(absf(NavReference.attitude().y - 14.0) < 0.5,
			"dropping the right wing 14 degrees reads R +14")
	_park(Basis(Vector3.FORWARD, deg_to_rad(-14.0)))
	_check(absf(NavReference.attitude().y + 14.0) < 0.5,
			"dropping the left wing 14 degrees reads R -14")

	# The ball has to hold a reading at any pitch, and say when it has run out.
	var half := 500.0 / 2.0
	_check(absf(band.horizon_offset(30.0)) < half,
			"30 degrees of pitch still lands the horizon inside the ball")
	_check(absf(band.horizon_offset(60.0)) > absf(band.horizon_offset(30.0)),
			"...and 60 takes it further, which is what the off-scale chevron is for")

	# "Level" means level with the SELECTED datum, and a tilted platform is
	# exactly where that stops being the same as level with the world.
	var tilted := Transform3D(Basis(Vector3.FORWARD, deg_to_rad(20.0)), Vector3(0, 0, 900))
	DockingSystem.register_station(tilted)
	GameState.set_nav_reference("PAD")
	_park(tilted.basis)
	var on_plane := NavReference.attitude()
	_check(absf(on_plane.x) < 0.5 and absf(on_plane.y) < 0.5,
			"a ship square to a tilted platform reads level against IT, not the world")
	DockingSystem.register_station(Transform3D(Basis.IDENTITY,
			DockingSystem.DEFAULT_STATION_ORIGIN))
	GameState.set_nav_reference("AUTO")
	_park(Basis.IDENTITY)
	band.queue_free()


## --- Rates --------------------------------------------------------------------

## The ribbons must read the same way round as the horizon above them. Two of the
## three are deliberately flipped against the raw command axes to get there.
func _test_rates() -> void:
	_park(Basis.IDENTITY)
	var ship: Dictionary = GameState.local_ship()

	ship["omega"] = Vector3(deg_to_rad(12.0), 0, 0)
	var pitch_rate := NavReference.body_rates()
	_check(absf(pitch_rate.x - 12.0) < 0.1 and absf(pitch_rate.y) < 0.1
			and absf(pitch_rate.z) < 0.1,
			"a pure nose-up rate reads +12 on pitch and zero on the others")

	# Yawing nose-RIGHT is a negative rotation about the body's up axis.
	ship["omega"] = Vector3(0, deg_to_rad(-9.0), 0)
	_check(absf(NavReference.body_rates().y - 9.0) < 0.1,
			"a nose-right yaw rate reads positive, the way the heading tape moves")

	# Rolling right-wing-DOWN is a negative rotation about the body's +Z (aft).
	ship["omega"] = Vector3(0, 0, deg_to_rad(-7.0))
	_check(absf(NavReference.body_rates().z - 7.0) < 0.1,
			"a right-wing-down roll rate reads positive, the way the horizon tilts")

	ship["omega"] = Vector3.ZERO
	_check(NavReference.body_rates().is_equal_approx(Vector3.ZERO),
			"a ship with no spin reads zero on all three")

	_check(is_equal_approx(GameState.rate_scale_deg(), GameState.ship_def.rotation_rate_deg),
			"the RATED ribbon scale is the ship's own full-deflection rate")
	GameState.set_rate_scale("FINE")
	_check(GameState.rate_scale_deg() < GameState.ship_def.rotation_rate_deg,
			"FINE expands the scale for nulling a slow tumble")
	GameState.set_rate_scale("RATED")


## --- Altitude -----------------------------------------------------------------

## The band and the HUD's landing ladder must be reading one number.
func _test_altitude() -> void:
	DockingSystem.begin_approach(0)
	GameState.set_nav_reference("PAD")
	var up := DockingSystem.pad_up()
	var pad := DockingSystem.pad_world()
	ShipMotion.seize(Transform3D(Basis.IDENTITY, pad + up * 24.0), Vector3.ZERO)
	var status: Dictionary = DockingSystem.status()
	_check(not status.is_empty(), "the docking status is live for the altitude check")
	_check(absf(NavReference.altitude() - float(status["altitude"])) < 0.01,
			"ALT on the platform datum is the same number DockingSystem reports")
	_check(absf(NavReference.range_to() - 24.0) < 0.01,
			"RNG is the distance to the datum's origin")

	# Climb positive, sink negative — the trend arrow points where the tape goes.
	ShipMotion.seize(Transform3D(Basis.IDENTITY, pad + up * 24.0), up * 3.0)
	_check(NavReference.vertical_speed() > 0.0, "a climb reads a positive vertical speed")
	_check(absf(NavReference.vertical_speed() + float(status["descent"])) >= 0.0,
			"...and DockingSystem's descent is the same reading negated")
	ShipMotion.seize(Transform3D(Basis.IDENTITY, pad + up * 24.0), -up * 3.0)
	_check(NavReference.vertical_speed() < 0.0, "a sink reads a negative vertical speed")

	DockingSystem.abort_approach()
	GameState.set_nav_reference("AUTO")
	ShipMotion.seize(Transform3D.IDENTITY, Vector3.ZERO)


func _test_propellant() -> void:
	GameState.lh2_fuel = GameState.ship_def.lh2_capacity
	_check(is_equal_approx(GameState.lh2_fraction(), 1.0), "a full LH2 tank reads 1.0")
	GameState.lh2_fuel = 0.0
	_check(is_equal_approx(GameState.lh2_fraction(), 0.0),
			"a dry LH2 tank reads 0.0, which is the tape's red state")
	_check(GameState.lh2_fraction() < InstrumentBandScript.TANK_LOW,
			"...and is under the low-level threshold the tape ambers at")
	GameState.lh2_fuel = GameState.ship_def.lh2_capacity


## The plate is the ship's identity, and it must come from the ship's data — a
## second hull gets its own plate by being a different .tres, not a code change.
func _test_plate() -> void:
	var plate := TailPlateScript.new()
	add_child(plate)
	var rows := plate.rows()
	var joined := " | ".join(rows)
	_check(GameState.ship_def.registry != "", "the ship carries a registry")
	_check(joined.contains(GameState.ship_def.registry),
			"the plate stamps the registry it is given")
	_check(joined.contains(GameState.ship_def.hull_serial),
			"the plate stamps the hull serial")
	_check(joined.contains(str(GameState.ship_def.build_year)),
			"the plate stamps the build year")
	plate.queue_free()

	# The handbook's leading particulars are a second copy of the same identity,
	# quoted the way every other figure in that chapter is. A hull renamed in its
	# .tres and not on paper is exactly the drift the two-documents rule exists
	# to catch, so the copy is checked rather than trusted.
	var ship: ShipDefinition = GameState.ship_def
	var chapter := ""
	for entry: Dictionary in ManualContentScript.CHAPTERS:
		if entry["id"] == "ship":
			chapter = String(entry["body"])
	_check(chapter != "", "the handbook carries a Description chapter")
	for figure: String in [ship.display_name, ship.registry, ship.hull_serial,
			ship.builder, str(ship.build_year)]:
		_check(chapter.contains(figure),
				"the handbook's particulars quote the ship's own '%s'" % figure)


## --- The panels themselves ----------------------------------------------------

## Every instrument here draws itself; a division by a zero size or a nil datum
## shows up as a broken frame, not an exception, so the panels are actually
## instantiated and made to paint at a size nothing sensible would use.
func _test_panels() -> void:
	_check(MfdUnitScript.PAGES.has("SETTINGS"),
			"SETTINGS is a page the MFD can reach")

	for entry: Dictionary in [
		{"name": "InstrumentBand", "script": InstrumentBandScript},
		{"name": "TailPlate", "script": TailPlateScript},
		{"name": "SettingsPanel", "script": SettingsPanelScript},
		{"name": "TacticalContent", "script": TacticalContentScript},
	]:
		var panel: Control = (entry["script"] as GDScript).new()
		add_child(panel)
		_size_to(panel, CRAMPED)
		panel.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(is_instance_valid(panel) and panel.size.is_equal_approx(CRAMPED),
				"%s draws at a size smaller than any real display" % entry["name"])
		panel.queue_free()

	# Hiding the band has to give the mode panels the room back, or the toggle
	# buys the scope nothing and there was no point fitting it.
	var content: Control = TacticalContentScript.new()
	add_child(content)
	_size_to(content, CONTENT)
	await get_tree().process_frame
	GameState.set_tactical_band(false)
	await get_tree().process_frame
	_check(content._content.get_theme_constant("margin_left") == 0,
			"hiding the band returns the mode pane's full width")
	GameState.set_tactical_band(true)
	await get_tree().process_frame
	_check(content._content.get_theme_constant("margin_left")
			>= int(InstrumentBandScript.FLIGHT_W),
			"showing it clears the mode pane of the flight block again")
	content.queue_free()


## Force a real size onto a panel. Each one anchors itself full-rect in _ready(),
## which would otherwise override the assignment (and warn) — leaving the cramped
## check above testing nothing at all.
func _size_to(control: Control, to: Vector2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.size = to


## --- Fixtures -----------------------------------------------------------------

## Park the ship at a known attitude at the origin, without running the flight
## pipeline — seize() is the one sanctioned way to overwrite motion state.
func _park(basis: Basis) -> void:
	ShipMotion.seize(Transform3D(basis, Vector3.ZERO), Vector3.ZERO)


## A site with a scanned graph, which is the state a cut target can be selected
## from. Marking the scan done directly is the fixture idiom DisplayLoadCheck
## already uses — the alternative is waiting out a real STRUCT scan.
func _stand_up_wreck() -> void:
	SalvageSystem.reset_site()
	GameState.wreck["scanned"] = true


## The empty-site state, which production only sees between boot and the first
## reset_site. ALWAYS restore it with _stand_up_wreck() before anything draws or
## ticks: the running systems read the wreck's keys directly, and an empty
## dictionary under them is not a state they are written for.
func _clear_site() -> void:
	GameState.wreck = {}
	GameState.selected_member_id = -1
	GameState.tracked_contact_id = -1
	GameState.contacts.clear()


func _first_member_id() -> int:
	var members: Array = GameState.wreck.get("members", [])
	return int(members[0]["id"]) if not members.is_empty() else -1
