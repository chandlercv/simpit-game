extends RefCounted
## The four operating procedures, as items the ship can check itself against —
## the same catalog-not-branches shape as MfdUnit.PAGES and
## PilotManualContent.CHAPTERS.
##
## These mirror SECTION 4 of the pilot's handbook (checklist-departure, -arrival,
## -cutting, -collecting) item for item and in the same order, so the page and the
## paper agree. The handbook remains the prose of record: it carries the reasons,
## the warnings and the cautions. This carries only what a row needs to state its
## own condition.
##
## TWO RULES HOLD THIS FILE TOGETHER.
##
## No figure is written here. Every limit in a value string is read from the
## constant that enforces it — SalvageSystem.MIN_CUTTER_POWER,
## DriftSystem.SCOOP_RANGE, DockingSystem.TILT_LIMIT_DEG — so a row cannot drift
## away from the rule the way a transcribed number would. If you cannot point at
## the constant, the row does not state the number.
##
## The evaluation belongs to the systems. A `read` calls DockingSystem.status(),
## DriftSystem.collection_status() or GameState directly — the same evaluations
## the interlocks themselves test — so a green row and a refused intent cannot
## disagree. Nothing here re-derives a rule.
##
## An item with no `read` is one nothing aboard can verify ("HOLD — DISPOSED OF",
## "ATTITUDE — PILOT"): the pilot marks it off by hand. Every other item is
## evaluated live and is NOT tappable, so a green tick always means the ship
## agrees.

enum Status { PASS, FAIL, NA }

## Item fields:
##   "label" — the item, as the handbook names it
##   "want"  — the condition it must be in
##   "group" — section heading; a new value starts a new group
##   "read"  — Callable() -> {"status": Status, "value": String}; absent on a
##             manual item

## Built on demand rather than held in a `const`, because a const Array cannot
## hold Callables. The panel calls this once and caches it.
static func lists() -> Array[Dictionary]:
	return [
		{"id": "departure", "title": "DEPARTURE", "items": _departure()},
		{"id": "arrival", "title": "ARRIVAL", "items": _arrival()},
		{"id": "cutting", "title": "CUTTING", "items": _cutting()},
		{"id": "collecting", "title": "COLLECTING", "items": _collecting()},
	]


# --- Result builders --------------------------------------------------------

static func _gate(ok: bool, value: String) -> Dictionary:
	return {"status": Status.PASS if ok else Status.FAIL, "value": value}


## An item that does not apply yet — the touchdown limits before there is a pad
## under you, the gear stow before the bay is cleared. Dim, not failed: a red row
## for something you could not possibly have done yet trains you to ignore red.
static func _na(value: String) -> Dictionary:
	return {"status": Status.NA, "value": value}


## Shared rows. The hatch and the torch are tested by three of the four
## procedures, and by several interlocks each, so they are written once.
static func _hatch_secured() -> Dictionary:
	return _gate(not GameState.cargo_hatch_open,
			"OPEN" if GameState.cargo_hatch_open else "SECURED")


static func _torch_idle() -> Dictionary:
	var cutting: bool = GameState.wreck.get("cutting_id", -1) != -1
	var aligning := GameState.align_state == "ALIGNING"
	if cutting:
		return _gate(false, "CUTTING %d%%" % roundi(
				float(GameState.wreck.get("cut_progress", 0.0)) * 100.0))
	return _gate(not aligning, "ALIGNING" if aligning else "IDLE")


## The exterior fit on departure, as the pilot can SEE it rather than as the
## switches are set: a group selected on with no bus behind it is not burning, and
## saying "NO BUS" is more use than a green tick on a ship nobody can see. This is
## also why the item sits after MASTER SWITCHES in the procedure.
static func _lights_lit() -> Dictionary:
	if not GameState.bus_live():
		return _gate(false, "NO BUS")
	var out: Array[String] = []
	for group: String in GameState.exterior_lights:
		if not GameState.exterior_lights[group]:
			out.append(group)
	if out.is_empty():
		return _gate(true, "NAV · BEACON · STROBE")
	return _gate(false, "%s OFF" % " · ".join(out))


## The same fit at the other end of a tour. This one reads the SWITCHES, not what
## is burning — the opposite of _lights_lit, and deliberately. Going dark on the
## pad is something the pilot does; a green tick earned because the masters
## happened to be off already would let the item be skipped, and the lights would
## come straight back on with the bus.
static func _lights_dark() -> Dictionary:
	var on: Array[String] = []
	for group: String in GameState.exterior_lights:
		if GameState.exterior_lights[group]:
			on.append(group)
	if on.is_empty():
		return _gate(true, "DARK")
	return _gate(false, "%s ON" % " · ".join(on))


static func _gear_down() -> Dictionary:
	if GameState.gear_locked_down():
		return _gate(true, "DOWN & LOCKED")
	if GameState.gear_position > 0.0:
		return _gate(false, "IN TRANSIT %d%%" % roundi(GameState.gear_position * 100.0))
	return _gate(false, "UP")


static func _gear_stowed() -> Dictionary:
	if GameState.gear_stowed():
		return _gate(true, "STOWED")
	if GameState.gear_position < 1.0:
		return _gate(false, "IN TRANSIT %d%%" % roundi(GameState.gear_position * 100.0))
	return _gate(false, "DOWN")


## The primary MFD presents DOCK for as long as a pattern is being flown — the
## same condition MfdUnit._auto_page is wired to — so this item reports that
## rather than asking the pilot to confirm something the ship did for them.
static func _dock_page() -> Dictionary:
	var active := GameState.docking_state != "INACTIVE"
	return _gate(active, "PRESENTED" if active else "NO PATTERN RUNNING")


## Live compliance with whatever the berth is currently enforcing. The rules are
## the harbour's and are published in the TERMINAL PROCEDURES; what this reports
## is only whether the ship is inside them right now, read from the same
## status() the wave-off itself tests.
static func _berth_compliance() -> Dictionary:
	var st := DockingSystem.status()
	if st.is_empty():
		return _na("NO PATTERN RUNNING")
	if not st["speed_ok"]:
		return _gate(false, "OVER SPEED %.0f / %.0f M/S" % [st["speed"], st["speed_limit"]])
	if not st["lane_ok"]:
		return _gate(false, "OUTSIDE LANE %.0f / %.0f M" % [
			st["lane_deviation"], st["lane_limit"]])
	return _gate(true, "%s  %d M" % [st["gate_name"], roundi(float(st["range"]))])


# --- DEPARTURE --------------------------------------------------------------

static func _departure() -> Array[Dictionary]:
	return [
		{
			# First, so the lever is known to agree with the ship standing on its
			# legs before anything else is touched.
			"group": "BEFORE DEPARTURE", "label": "LANDING GEAR", "want": "DOWN",
			"read": func() -> Dictionary: return _gear_down(),
		},
		{
			"group": "BEFORE DEPARTURE", "label": "MASTER SWITCHES", "want": "ON",
			"read": func() -> Dictionary:
				var on := GameState.master_bat and GameState.master_alt
				return _gate(on, "BAT %s · ALT %s" % [
					"ON" if GameState.master_bat else "OFF",
					"ON" if GameState.master_alt else "OFF"]),
		},
		{
			# After the masters, because the lights are on the bus and will not
			# light without one. The beacon is lit before the drive is started.
			"group": "BEFORE DEPARTURE", "label": "EXTERIOR LIGHTS", "want": "ON",
			"read": func() -> Dictionary: return _lights_lit(),
		},
		{
			"group": "BEFORE DEPARTURE", "label": "BATTERY", "want": "CHARGING",
			"read": func() -> Dictionary:
				var flow := GameState.battery_flow()
				var charge := "%d%%" % roundi(GameState.battery_fraction() * 100.0)
				if GameState.battery_fraction() >= 1.0:
					return _gate(GameState.master_alt, "%s · FULL" % charge)
				return _gate(flow > 0.0, "%s · %s" % [charge,
					"CHG %.1f" % flow if flow > 0.0
					else ("DISCH %.1f" % -flow if flow < 0.0 else "STATIC")]),
		},
		{
			"group": "BEFORE DEPARTURE", "label": "POWER CHANNELS", "want": "SET",
			"read": func() -> Dictionary:
				return _gate(GameState.power("THRUST") > 0.0, "THRUST %.2f · SENSORS %.2f"
						% [GameState.power("THRUST"), GameState.power("SENSORS")]),
		},
		{
			"group": "BEFORE DEPARTURE", "label": "CARGO HATCH", "want": "SECURED",
			"read": func() -> Dictionary: return _hatch_secured(),
		},
		{
			# The starter needs the bus, which is why it sits after the masters.
			# It counts only while the selector is actually at START.
			"group": "STARTING", "label": "DRIVE SELECTOR", "want": "START, 10 S",
			"read": func() -> Dictionary:
				if GameState.drive_live():
					return _gate(true, "STARTED")
				if GameState.drive_mode != "START":
					return _gate(false, GameState.drive_mode)
				return _gate(false, "%.0f / %.0f S" % [
					GameState.drive_start_progress(),
					GameState.ship_def.drive_start_time]),
		},
		{
			"group": "STARTING", "label": "DRIVE SELECTOR", "want": "RUNNING POSITION",
			"read": func() -> Dictionary:
				if not GameState.drive_live():
					return _gate(false, GameState.drive_mode)
				return _gate(GameState.thrust_fraction() > 0.0, "%s · %d%% THRUST" % [
					GameState.drive_mode,
					roundi(GameState.thrust_fraction() * 100.0)]),
		},
		{
			"group": "LEAVING THE BERTH", "label": "UNDOCK", "want": "COMMANDED",
			"read": func() -> Dictionary:
				return _gate(GameState.run_phase != "DOCKED", GameState.run_phase),
		},
		{
			"group": "LEAVING THE BERTH", "label": "DOCK PAGE", "want": "SELECTED",
			"read": func() -> Dictionary: return _dock_page(),
		},
		{
			"group": "LEAVING THE BERTH", "label": "BERTH PROCEDURE", "want": "COMPLY",
			"read": func() -> Dictionary: return _berth_compliance(),
		},
		{
			"group": "LEAVING THE BERTH", "label": "LANDING GEAR",
			"want": "STOWED BEFORE RELEASE",
			"read": func() -> Dictionary:
				# There is no longer a point on the way out at which the gear must
				# still be down, so this applies for the whole outbound run: raise
				# it whenever the pad is clear, and it has to be up before ATC will
				# release the ship for the jump.
				var st := DockingSystem.status()
				if st.is_empty() or not st["outbound"]:
					return _na("NOT OUTBOUND")
				return _gear_stowed(),
		},
	]


# --- ARRIVAL ----------------------------------------------------------------

static func _arrival() -> Array[Dictionary]:
	return [
		{
			"group": "BEFORE LEAVING THE CLAIM", "label": "CUTTING TORCH", "want": "IDLE",
			"read": func() -> Dictionary: return _torch_idle(),
		},
		{
			"group": "BEFORE LEAVING THE CLAIM", "label": "ADRIFT PIECES",
			"want": "RECOVERED",
			"read": func() -> Dictionary:
				var adrift: int = GameState.salvage_pieces.size()
				return _gate(adrift == 0, "NONE" if adrift == 0 else "%d ADRIFT" % adrift),
		},
		{
			"group": "BEFORE LEAVING THE CLAIM", "label": "CARGO HATCH", "want": "SECURED",
			"read": func() -> Dictionary: return _hatch_secured(),
		},
		{
			"group": "BEFORE LEAVING THE CLAIM", "label": "OPERATOR", "want": "SELECTED",
			"read": func() -> Dictionary:
				return _gate(GameState.run_phase != "ON_SITE", GameState.run_phase),
		},
		{
			"group": "INBOUND", "label": "DOCK PAGE", "want": "SELECTED",
			"read": func() -> Dictionary: return _dock_page(),
		},
		{
			"group": "INBOUND", "label": "BERTH PROCEDURE", "want": "COMPLY",
			"read": func() -> Dictionary: return _berth_compliance(),
		},
		{
			"group": "BEFORE FINAL", "label": "LANDING GEAR", "want": "DOWN AND LOCKED",
			"read": func() -> Dictionary: return _gear_down(),
		},
		{
			"group": "BEFORE FINAL", "label": "CARGO HATCH", "want": "SECURED",
			"read": func() -> Dictionary: return _hatch_secured(),
		},
		{
			"group": "BEFORE FINAL", "label": "CAMERA", "want": "BELLY",
			"read": func() -> Dictionary:
				return _gate(GameState.external_view == "BELLY", GameState.external_view),
		},
		{
			"group": "TOUCHDOWN", "label": "ON THE MARKINGS", "want": "WITHIN THE PAD",
			"read": func() -> Dictionary:
				var st := DockingSystem.status()
				if st.is_empty():
					return _na("NO PATTERN RUNNING")
				return _gate(st["on_pad"], "%.1f / %.1f M" % [
					st["lateral"], DockingSystem.PAD_RADIUS]),
		},
		{
			"group": "TOUCHDOWN", "label": "ATTITUDE", "want": "LEVEL",
			"read": func() -> Dictionary:
				var st := DockingSystem.status()
				if st.is_empty():
					return _na("NO PATTERN RUNNING")
				return _gate(st["level"], "%d° / %d°" % [
					roundi(float(st["tilt"])), roundi(DockingSystem.TILT_LIMIT_DEG)]),
		},
		{
			"group": "TOUCHDOWN", "label": "LATERAL DRIFT", "want": "NULLED",
			"read": func() -> Dictionary:
				var st := DockingSystem.status()
				if st.is_empty():
					return _na("NO PATTERN RUNNING")
				var drift: float = (st["drift"] as Vector2).length()
				return _gate(drift <= DockingSystem.TOUCHDOWN_DRIFT, "%.1f / %.1f M/S" % [
					drift, DockingSystem.TOUCHDOWN_DRIFT]),
		},
		{
			"group": "TOUCHDOWN", "label": "SINK RATE", "want": "UNDER THE LEGS' LIMIT",
			"read": func() -> Dictionary:
				var st := DockingSystem.status()
				if st.is_empty():
					return _na("NO PATTERN RUNNING")
				# Green only below the no-wear rate: the crash rate is what breaks
				# the legs, but arriving between the two still costs hull, and a
				# row that goes green at "survivable" would be teaching the wrong
				# number.
				var rate: float = maxf(float(st["descent"]), 0.0)
				return _gate(rate <= DockingSystem.FIRM_RATE, "%.1f / %.1f M/S" % [
					rate, DockingSystem.FIRM_RATE]),
		},
		{
			# Shut the drive down before the ship is opened up. Selecting OFF costs
			# a full start to undo, which is what makes it a decision rather than a
			# reflex — see the DEPARTURE procedure.
			"group": "AFTER LANDING", "label": "DRIVE SELECTOR", "want": "OFF",
			"read": func() -> Dictionary:
				if GameState.docking_state != "LANDED" and GameState.run_phase != "DOCKED":
					return _na("NOT ON A PAD")
				return _gate(GameState.drive_mode == "OFF", GameState.drive_mode),
		},
		{
			"group": "AFTER LANDING", "label": "CARGO HATCH", "want": "OPEN",
			"read": func() -> Dictionary:
				if GameState.docking_state != "LANDED" and GameState.run_phase != "DOCKED":
					return _na("NOT ON A PAD")
				# The hold discharges through the hatch, so this is the item that
				# lets the berth take the cargo — not a formality.
				return _gate(GameState.cargo_hatch_open,
					"OPEN" if GameState.cargo_hatch_open else "SECURED"),
		},
		{
			# The ship goes dark before the bus is opened, so the last thing done
			# to her is the same thing the next departure undoes first.
			"group": "AFTER LANDING", "label": "EXTERIOR LIGHTS", "want": "OFF",
			"read": func() -> Dictionary:
				if GameState.docking_state != "LANDED" and GameState.run_phase != "DOCKED":
					return _na("ON")
				return _lights_dark(),
		},
		{
			"group": "AFTER LANDING", "label": "MASTER ALT", "want": "OFF",
			"read": func() -> Dictionary:
				if GameState.docking_state != "LANDED" and GameState.run_phase != "DOCKED":
					return _na("NOT ON A PAD")
				return _gate(not GameState.master_alt,
					"ON" if GameState.master_alt else "OFF"),
		},
		{
			"group": "AFTER LANDING", "label": "MASTER BAT", "want": "OFF",
			"read": func() -> Dictionary:
				if GameState.docking_state != "LANDED" and GameState.run_phase != "DOCKED":
					return _na("NOT ON A PAD")
				return _gate(not GameState.master_bat,
					"ON" if GameState.master_bat else "OFF"),
		},
	]


# --- CUTTING ----------------------------------------------------------------

static func _cutting() -> Array[Dictionary]:
	return [
		{
			"group": "SURVEY", "label": "SENSORS ALLOCATION", "want": "AT THE MINIMUM",
			"read": func() -> Dictionary:
				return _gate(GameState.power("SENSORS") >= SalvageSystem.MIN_SENSOR_POWER,
						"%.2f / %.2f" % [GameState.power("SENSORS"),
								SalvageSystem.MIN_SENSOR_POWER]),
		},
		{
			"group": "SURVEY", "label": "SENSOR MODE", "want": "STRUCT",
			"read": func() -> Dictionary:
				return _gate(GameState.sensor_mode == "STRUCT", GameState.sensor_mode),
		},
		{
			"group": "SURVEY", "label": "RANGE", "want": "INSIDE SCAN RANGE",
			"read": func() -> Dictionary:
				var d := SalvageSystem.wreck_distance()
				return _gate(d <= SalvageSystem.SCAN_RANGE, "%d / %d U" % [
					roundi(d), roundi(SalvageSystem.SCAN_RANGE)]),
		},
		{
			"group": "SURVEY", "label": "STRUCTURAL SCAN", "want": "COMPLETE",
			"read": func() -> Dictionary:
				var done: bool = GameState.wreck.get("scanned", false)
				return _gate(done, "COMPLETE" if done else "%d%%" % roundi(
						float(GameState.wreck.get("scan_progress", 0.0)) * 100.0)),
		},
		{
			"group": "TARGET", "label": "CUT TARGET", "want": "SELECTED",
			"read": func() -> Dictionary:
				var member := GameState.get_member(GameState.selected_member_id)
				return _gate(not member.is_empty(),
						String(member.get("name", "NONE SELECTED"))),
		},
		{
			# The autopilot flies on the drive, and it is refused outright when the
			# drive is not making thrust — so the drive is checked before the
			# throttle, in the order the refusals actually fire.
			"group": "APPROACH", "label": "DRIVE", "want": "MAKING THRUST",
			"read": func() -> Dictionary:
				return _gate(GameState.thrust_fraction() > 0.0, "%s · %d%%" % [
					GameState.drive_mode,
					roundi(GameState.thrust_fraction() * 100.0)]),
		},
		{
			# It flies on the THRUST channel as well, and the drive row above cannot
			# see that: the stages keep turning on a bus that has stopped supplying
			# them. Delivered rather than set, because that is the figure it flies on,
			# and against the autopilot's own floor rather than zero, so this row goes
			# amber exactly where the engagement is refused.
			"group": "APPROACH", "label": "THRUST ALLOCATION", "want": "DELIVERING",
			"read": func() -> Dictionary:
				return _gate(GameState.power("THRUST") >= SalvageSystem.MIN_APPROACH_POWER,
					"%.2f OF %.2f SET" % [
						GameState.power("THRUST"),
						GameState.power_target("THRUST")]),
		},
		{
			"group": "APPROACH", "label": "THROTTLE", "want": "INSIDE THE ARMING BAND",
			"read": func() -> Dictionary:
				var t := SalvageSystem.throttle_command()
				return _gate(t <= SalvageSystem.APPROACH_ARM_THROTTLE_MAX, "%d%% / %d%%" % [
					roundi(t * 100.0),
					roundi(SalvageSystem.APPROACH_ARM_THROTTLE_MAX * 100.0)]),
		},
		{
			"group": "APPROACH", "label": "APPROACH", "want": "ENGAGED",
			"read": func() -> Dictionary:
				return _gate(GameState.approach_state != "HOLDING",
						GameState.approach_state),
		},
		{
			"group": "APPROACH", "label": "ATTITUDE", "want": "PILOT",
			# The autopilot translates only; keeping the member in view is hand
			# flying, and nothing aboard can judge whether you are doing it.
		},
		{
			"group": "APPROACH", "label": "APPROACH STATE", "want": "MATCHED",
			"read": func() -> Dictionary:
				return _gate(GameState.approach_state == "MATCHED",
						GameState.approach_state),
		},
		{
			"group": "BEFORE FIRING", "label": "CUTTER ALLOCATION", "want": "AT THE MINIMUM",
			"read": func() -> Dictionary:
				return _gate(GameState.power("CUTTER") >= SalvageSystem.MIN_CUTTER_POWER,
						"%.2f / %.2f" % [GameState.power("CUTTER"),
								SalvageSystem.MIN_CUTTER_POWER]),
		},
		{
			"group": "BEFORE FIRING", "label": "CARGO HATCH", "want": "SECURED",
			"read": func() -> Dictionary: return _hatch_secured(),
		},
		{
			"group": "BEFORE FIRING", "label": "LANDING GEAR", "want": "STOWED",
			"read": func() -> Dictionary: return _gear_stowed(),
		},
		{
			"group": "CUT", "label": "TRIGGER", "want": "ALIGNMENT OPEN",
			"read": func() -> Dictionary:
				if GameState.wreck.get("cutting_id", -1) != -1:
					return _gate(true, "COMMITTED")
				var aligning := GameState.align_state == "ALIGNING"
				return _gate(aligning, "ALIGNING" if aligning else "NOT FIRED"),
		},
		{
			"group": "CUT", "label": "SEAM", "want": "TRACKED",
			"read": func() -> Dictionary:
				if GameState.align_state != "ALIGNING" or GameState.align.is_empty():
					return _na("NO ALIGNMENT RUNNING")
				var lock := float(GameState.align["lock"])
				return _gate(lock > 0.0, "LOCK %d%% · SLIP %d%%" % [
					roundi(lock * 100.0),
					roundi(float(GameState.align["slip"]) * 100.0)]),
		},
		{
			"group": "CUT", "label": "COMMIT", "want": "CUT RUNNING",
			"read": func() -> Dictionary:
				if GameState.wreck.get("cutting_id", -1) == -1:
					return _na("NO CUT RUNNING")
				return _gate(true, "%d%%" % roundi(
						float(GameState.wreck.get("cut_progress", 0.0)) * 100.0)),
		},
		{
			"group": "CUT", "label": "STRUCTURAL RISK", "want": "BELOW THE FLOOR",
			"read": func() -> Dictionary:
				return _gate(GameState.structural_risk <= ThreatSystem.COLLAPSE_RISK_FLOOR,
						"%.2f / %.2f" % [GameState.structural_risk,
								ThreatSystem.COLLAPSE_RISK_FLOOR]),
		},
		{
			"group": "CUT", "label": "SEVERED PIECE", "want": "ADRIFT",
			"read": func() -> Dictionary:
				var adrift: int = GameState.salvage_pieces.size()
				return _gate(adrift > 0, "NONE" if adrift == 0 else "%d ADRIFT" % adrift),
		},
	]


# --- COLLECTING -------------------------------------------------------------

static func _collecting() -> Array[Dictionary]:
	return [
		{
			"group": "BEFORE OPENING", "label": "CUTTING TORCH", "want": "IDLE",
			"read": func() -> Dictionary: return _torch_idle(),
		},
		{
			"group": "BEFORE OPENING", "label": "HOLD", "want": "CAPACITY CHECKED",
			"read": func() -> Dictionary:
				var ship: Dictionary = GameState.local_ship()
				var mass := CargoSystem.cargo_mass()
				var vol := CargoSystem.cargo_volume()
				var room := mass <= float(ship["cargo_mass_limit_t"]) \
						and vol <= float(ship["cargo_vol_limit_m3"])
				return _gate(room, "%.1f / %.1f T · %.1f / %.1f M³" % [
					mass, float(ship["cargo_mass_limit_t"]),
					vol, float(ship["cargo_vol_limit_m3"])]),
		},
		{
			"group": "RECOVERY", "label": "CARGO HATCH", "want": "OPEN",
			"read": func() -> Dictionary:
				return _gate(GameState.cargo_hatch_open,
						"OPEN" if GameState.cargo_hatch_open else "SECURED"),
		},
		{
			"group": "RECOVERY", "label": "PIECE", "want": "IDENTIFIED",
			"read": func() -> Dictionary:
				if not DriftSystem.is_collecting():
					return _na("COLLECTION SUSPENDED")
				var piece := DriftSystem.nearest_piece()
				if piece.is_empty():
					return _gate(false, "NONE ADRIFT")
				return _gate(true, String(piece["name"])),
		},
		{
			"group": "RECOVERY", "label": "RANGE", "want": "INSIDE SCOOP RANGE",
			"read": func() -> Dictionary:
				var st := _collect_status()
				if st.is_empty():
					return _na("NO PIECE ADRIFT")
				return _gate(st["in_range"], "%.1f / %.1f M" % [
					maxf(float(st["gap"]), 0.0), DriftSystem.SCOOP_RANGE]),
		},
		{
			"group": "RECOVERY", "label": "RELATIVE VELOCITY", "want": "NULLED",
			"read": func() -> Dictionary:
				var st := _collect_status()
				if st.is_empty():
					return _na("NO PIECE ADRIFT")
				return _gate(st["speed_ok"], "%.2f / %.2f M/S" % [
					st["rel_speed"], DriftSystem.COLLECT_REL_SPEED]),
		},
		{
			"group": "RECOVERY", "label": "BEARING", "want": "INSIDE THE CONE",
			"read": func() -> Dictionary:
				var st := _collect_status()
				if st.is_empty():
					return _na("NO PIECE ADRIFT")
				return _gate(st["in_cone"], "%d° / %d°" % [
					roundi(float(st["off_axis"])), roundi(DriftSystem.COLLECT_CONE_DEG)]),
		},
		{
			"group": "RECOVERY", "label": "ALL FOUR CONDITIONS", "want": "HELD",
			"read": func() -> Dictionary:
				var st := _collect_status()
				if st.is_empty():
					return _na("NO PIECE ADRIFT")
				return _gate(st["gated"], "SCOOP %d%%" % roundi(float(st["scoop"]) * 100.0)),
		},
		{
			"group": "RECOVERY", "label": "STOWAGE", "want": "CONFIRM",
			# Stowage is annunciated in the log and the piece leaves the world, so
			# by the time this could be evaluated there is nothing left to evaluate.
		},
		{
			"group": "ON COMPLETION", "label": "REMAINING PIECES", "want": "NONE ADRIFT",
			"read": func() -> Dictionary:
				var adrift: int = GameState.salvage_pieces.size()
				return _gate(adrift == 0, "NONE" if adrift == 0 else "%d ADRIFT" % adrift),
		},
		{
			"group": "ON COMPLETION", "label": "CARGO HATCH", "want": "SECURED",
			"read": func() -> Dictionary: return _hatch_secured(),
		},
	]


## The live collection evaluation for the piece being worked, or {} when there
## is none. Same dictionary the scoop itself gates on.
static func _collect_status() -> Dictionary:
	if not DriftSystem.is_collecting():
		return {}
	var piece := DriftSystem.nearest_piece()
	if piece.is_empty():
		return {}
	return DriftSystem.collection_status(piece)
