extends Control
## Thin HUD overlaid on the hull-camera feed — reads as markings on a camera
## feed, not dashboard chrome. Rule of thumb (plan Phase 2): if it's tied to
## what's currently in the camera's view it can live here; omnidirectional or
## historical readouts (full radar sweep, complete contact list, risk-over-time)
## belong on the Tactical window.
##
## Draws: nose reticle (marks where the hull points, slides off-centre while
## glancing), velocity-vector brackets (direction of travel), velocity/heading
## readout, lock brackets + distance on the tracked contact when it's in frame,
## pulsing threat brackets + proximity warning for threat contacts in frame.
## Contacts behind the camera or outside the frame draw nothing — that's
## Tactical's job.

## Set by MainViewWindow.gd at runtime (a .tscn NodePath can't reach inside the
## instanced world scene). Unprojected coordinates match this Control 1:1
## because the SubViewportContainer stretches the SubViewport to window size.
var camera: Camera3D

const HUD_COLOR := Color(0.75, 0.88, 0.95, 0.85)
const THREAT_COLOR := Color(1.0, 0.35, 0.25, 0.9)
## Adrift salvage piece markers — amber, greening up (same green as a matched
## cut target) while its scoop meter is actively filling.
const SALVAGE_COLOR := Color(1.0, 0.7, 0.25, 0.9)
const SALVAGE_LOCKED_COLOR := Color(0.5, 1.0, 0.6, 0.95)

## Threat contacts closer than this (meters) get the proximity warning.
const PROXIMITY_RANGE := 25.0

## Keeps the nose reticle / velocity marker off the very edge when clamped.
const EDGE_MARGIN := 24.0

## At/below this speed the ship is effectively stationary; hide the resting marker.
const VEL_EPSILON := 0.05

## Drift-marker sensitivity: screen offset per (m/s) of lateral velocity, as a
## fraction of viewport height. At 0.04, ~10 m/s of drift pushes the brackets
## ~40% of the way to the screen edge before the margin clamp catches them.
const VEL_MARKER_SCALE := 0.04

var _time := 0.0

@onready var _vel_label: Label = %VelLabel
@onready var _hdg_label: Label = %HdgLabel
@onready var _tgt_label: Label = %TargetLabel


func _ready() -> void:
	for label in [_vel_label, _hdg_label, _tgt_label]:
		label.add_theme_color_override("font_color", HUD_COLOR)
	GameState.tick_changed.connect(_on_tick_changed)
	_update_readouts()


## The readout labels only need shared-tick resolution; the brackets drawn in
## _draw() need every frame since their screen position tracks the camera,
## which keeps moving between ticks.
func _on_tick_changed(_tick: int) -> void:
	_update_readouts()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _update_readouts() -> void:
	var ship: Dictionary = GameState.local_ship()
	var velocity: Vector3 = ship.get("velocity", Vector3.ZERO)
	var speed := velocity.length()
	var vel_text := "VEL %5.1f M/S" % speed
	# Which reaction stage is burning, so spending propellant is never silent.
	# Quantity stays off the HUD (it is on the MFD POWER page) — this is only the
	# fact that a tank is going down.
	if GameState.boosting():
		vel_text += "  BOOST"
	elif GameState.thermal_stage_running():
		vel_text += "  IMPULSE"
	if GameState.approach_state != "HOLDING":
		vel_text += "  — %s" % GameState.approach_state
	# In the pattern the speed you were given is an instruction, so the readout
	# carries it — and goes red the moment you're over it, which is the same
	# moment ATC starts counting toward a go-around.
	var docking: Dictionary = DockingSystem.status()
	if not docking.is_empty():
		var limit: float = docking["speed_limit"]
		vel_text = "VEL %5.1f / %.0f M/S" % [speed, limit]
		_vel_label.add_theme_color_override("font_color",
				HUD_COLOR if docking["speed_ok"] else THREAT_COLOR)
	else:
		_vel_label.remove_theme_color_override("font_color")
	_vel_label.text = vel_text
	if camera == null:
		return
	var fwd := -camera.global_transform.basis.z
	var azimuth := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	var elevation := rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
	_hdg_label.text = "HDG %03d  EL %+03d" % [roundi(azimuth), roundi(elevation)]
	var tracked := GameState.get_contact(GameState.tracked_contact_id)
	if tracked.is_empty():
		_tgt_label.text = ""
	else:
		var dist := camera.global_position.distance_to(tracked["position"])
		_tgt_label.text = "TGT %s — %d M" % [tracked["name"], roundi(dist)]


func _draw() -> void:
	_draw_reticle()
	_draw_velocity_vector()
	_draw_target_member()
	_draw_salvage_pieces()
	_draw_align()
	_draw_docking()
	_draw_ops_state()
	_draw_hatch_indicator()
	_draw_gear_indicator()
	_draw_assist_indicator()
	_draw_drive_indicator()
	if camera == null:
		return
	var frame := Rect2(Vector2.ZERO, size)
	var font := ThemeDB.fallback_font
	for contact in GameState.contacts:
		var pos: Vector3 = contact["position"]
		# Contextual only: nothing is drawn for contacts out of frame.
		if camera.is_position_behind(pos):
			continue
		var screen_pos := camera.unproject_position(pos)
		if not frame.has_point(screen_pos):
			continue
		var is_tracked: bool = contact["id"] == GameState.tracked_contact_id
		var is_threat: bool = contact["threat"]
		var color := THREAT_COLOR if is_threat else HUD_COLOR
		if is_threat:
			color.a = 0.55 + 0.45 * sin(_time * TAU * 1.5)
		var radius := 28.0 if is_tracked else 18.0
		var width := 2.0 if is_tracked else 1.2
		_draw_corner_brackets(screen_pos, radius, color, width)
		var dist := camera.global_position.distance_to(pos)
		var label: String = contact["name"]
		if is_tracked:
			label += "  %d M" % roundi(dist)
		draw_string(font, screen_pos + Vector2(-radius, radius + 18), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		if is_threat and dist < PROXIMITY_RANGE:
			draw_string(font, screen_pos + Vector2(-radius, -radius - 10),
					"PROXIMITY", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)


## Camera-feed-tied ops readouts: cutter progress while the torch is live,
## and a phase banner when the feed isn't showing the claim at all.
func _draw_ops_state() -> void:
	var font := ThemeDB.fallback_font
	var c := size / 2.0
	# The docking pattern is flown, so it gets the full flight HUD rather than a
	# banner — only the phases where the ship is parked get one.
	if not GameState.flight_active():
		var banner := "IN TRANSIT" if GameState.run_phase == "TRANSIT" \
				else "DOCKED — %s" % GameState.market_factions[GameState.docked_faction]
		draw_string(font, Vector2(0, c.y + 70), banner,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, HUD_COLOR)
		return
	if GameState.align_state == "ALIGNING" and not GameState.align.is_empty():
		var member := GameState.get_member(GameState.selected_member_id)
		draw_string(font, Vector2(0, c.y + 70),
				"ALIGNING %s — LOCK %d%%" % [member.get("name", "TARGET"),
					roundi(float(GameState.align["lock"]) * 100.0)],
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, HUD_COLOR)
		return
	var cutting_id: int = GameState.wreck.get("cutting_id", -1)
	if cutting_id != -1:
		var member := GameState.get_member(cutting_id)
		draw_string(font, Vector2(0, c.y + 70),
				"CUTTING %s — %d%%" % [member["name"],
					roundi(GameState.wreck["cut_progress"] * 100.0)],
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, THREAT_COLOR)


## Docking: the next gate as a marker you fly at (edge arrow when it's off
## frame, exactly like a tracked contact), ATC's standing instruction in the
## same slot the align/cut banner uses, and on final a landing ladder.
##
## Everything comes from DockingSystem.status() — the same evaluation the rules
## test — so the marker cannot point somewhere ATC isn't measuring.
func _draw_docking() -> void:
	var st: Dictionary = DockingSystem.status()
	if st.is_empty() or camera == null:
		return
	var font := ThemeDB.fallback_font
	var target: Vector3 = st["gate_position"]
	var color := HUD_COLOR
	if not bool(st["lane_ok"]) or not bool(st["speed_ok"]):
		color = THREAT_COLOR
	var label := "%s  %d M" % [st["gate_name"], roundi(float(st["range"]))]
	if camera.is_position_behind(target):
		_draw_offscreen_marker(target, label, color)
	else:
		var at := camera.unproject_position(target)
		if Rect2(Vector2.ZERO, size).has_point(at):
			_draw_diamond(at, 14.0, color, 2.0)
			# The gate's ring at the size it actually subtends, so "am I lined up"
			# is a question about this circle rather than a guess.
			var subtend: float = _gate_screen_radius(target, float(st["gate_radius"]))
			if subtend > 4.0:
				draw_arc(at, subtend, 0.0, TAU, 48, Color(color, 0.55), 1.5, true)
			draw_string(font, at + Vector2(18, 5), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		else:
			_draw_offscreen_marker(target, label, color)

	var atc: Dictionary = st.get("atc", {})
	if not atc.is_empty():
		var c := size / 2.0
		var atc_color := HUD_COLOR
		if bool(atc.get("urgent", false)):
			atc_color = Color(THREAT_COLOR, 0.55 + 0.45 * sin(_time * TAU * 1.5))
		draw_string(font, Vector2(0, c.y + 70), String(atc.get("text", "")),
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, atc_color)

	if st["state"] == "FINAL":
		_draw_landing_ladder(font, st)


## Screen radius of a gate ring at its current range — the projection of a point
## one ring-radius off the gate centre, so perspective is handled by the camera
## rather than approximated here.
func _gate_screen_radius(target: Vector3, radius: float) -> float:
	if camera == null:
		return 0.0
	var edge: Vector3 = target + camera.global_transform.basis.x * radius
	if camera.is_position_behind(edge):
		return 0.0
	return camera.unproject_position(target).distance_to(camera.unproject_position(edge))


## The last 16 m: altitude, sink rate against what the legs will take, and how
## far off the pad's markings you are. Sat under the reticle where the eye
## already is on final.
func _draw_landing_ladder(font: Font, st: Dictionary) -> void:
	var c := size / 2.0
	var descent: float = st["descent"]
	var rate_color := HUD_COLOR
	if descent > DockingSystem.HARD_RATE:
		rate_color = THREAT_COLOR
	elif descent > DockingSystem.FIRM_RATE:
		rate_color = SALVAGE_COLOR
	draw_string(font, Vector2(0, c.y + 96),
			"ALT %.1f    SINK %.1f M/S    OFF %.1f M" % [
				maxf(float(st["altitude"]), 0.0), descent, float(st["lateral"])],
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, rate_color)
	if not bool(st["on_pad"]):
		draw_string(font, Vector2(0, c.y + 116), "OFF THE PAD MARKINGS",
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, THREAT_COLOR)


## Gear state, beside the cargo-hatch indicator. Shown whenever the gear isn't
## stowed, because an extended leg is both a landing requirement and a thing
## that wears out over GEAR_LIMIT_SPEED — either way the pilot needs to know.
func _draw_gear_indicator() -> void:
	if GameState.gear_stowed():
		return
	var font := ThemeDB.fallback_font
	var locked := GameState.gear_locked_down()
	var text := "GEAR DOWN" if locked else "GEAR IN TRANSIT %d%%" % roundi(
			GameState.gear_position * 100.0)
	var color := SALVAGE_LOCKED_COLOR if locked else SALVAGE_COLOR
	# World (inertial) speed — see GameState.ships on the frame. The legs are
	# rated against speed through space, so nothing is subtracted here.
	var speed: float = (GameState.local_ship().get("velocity", Vector3.ZERO) as Vector3).length()
	if speed > GameState.GEAR_LIMIT_SPEED:
		text = "GEAR OVERSPEED %d / %d" % [roundi(speed), roundi(GameState.GEAR_LIMIT_SPEED)]
		color = Color(THREAT_COLOR, 0.55 + 0.45 * sin(_time * TAU * 1.5))
	draw_string(font, Vector2(size.x - 190, 48), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)


## Persistent reminder that the cutter and jump/dock are both interlocked off
## right now (SalvageSystem.request_cut, MarketSystem) — pulses so an open
## hatch left open by accident still catches the eye.
func _draw_hatch_indicator() -> void:
	if GameState.hatch_secured():
		return
	# Mid-travel is its own state, and worth naming: the door is neither shut
	# enough to cut over nor open enough to take a piece.
	var text := "CARGO HATCH OPEN"
	if not GameState.hatch_open_locked():
		text = "CARGO HATCH IN TRANSIT %d%%" % roundi(GameState.hatch_position * 100.0)
	var a := 0.55 + 0.45 * sin(_time * TAU * 1.2)
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 190, 28), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(SALVAGE_COLOR, a))


## Stability-augmentation state, stacked under the hatch/gear annunciators.
## Silent while nominal: an annunciator that is always lit says nothing. Shown
## switched OFF (a pilot's choice, steady) or DEGRADED (authority below rated —
## pulsing red once it is too low to open an alignment, since that is the point
## at which it starts costing salvage).
func _draw_assist_indicator() -> void:
	var engaged: bool = ShipMotion.fbw_engaged()
	var auth: float = ShipMotion.authority()
	if engaged and auth >= 0.99:
		return
	var text := "ASSIST OFF" if not engaged else "ASSIST DEGRADED %d%%" % roundi(auth * 100.0)
	var color := SALVAGE_COLOR
	if engaged and auth < SalvageSystem.MIN_ALIGN_AUTHORITY:
		color = Color(THREAT_COLOR, 0.55 + 0.45 * sin(_time * TAU * 1.5))
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 190, 68), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)


## Drive state, stacked under the assist annunciator. Silent while the drive is
## making its rated thrust. There are three quite different ways to end up with no
## thrust — the selector at OFF, the THRUST channel delivering nothing, or the
## thermal stage starved of hydrogen — and a pilot has to be able to tell them
## apart, so each says which it is instead of a shared "no thrust" light. The
## electrical case is read from what is DELIVERED, not from the drive: the stages
## keep turning on a dead bus, so nothing else here would show it. It is ranked
## above the tank because it is the one that leaves no thrust at all. LH2 DEPLETED
## pulses because it is the one that arrives without being asked for and costs
## most of the ship's acceleration.
func _draw_drive_indicator() -> void:
	var text := ""
	var color := SALVAGE_COLOR
	if not GameState.drive_live():
		text = "DRIVE %s" % ("STARTING" if GameState.drive_starting() else GameState.drive_mode)
	elif GameState.power("THRUST") <= 0.0:
		text = "THRUST UNPOWERED"
		color = THREAT_COLOR
	elif GameState.lh2_fuel <= 0.0:
		text = "LH2 DEPLETED"
		color = Color(THREAT_COLOR, 0.55 + 0.45 * sin(_time * TAU * 1.5))
	elif GameState.thrust_fraction() < 1.0:
		text = "DRIVE %s — %d%% THRUST" % [
			GameState.drive_mode, roundi(GameState.thrust_fraction() * 100.0)]
	if text.is_empty():
		return
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 190, 88), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)


## Pre-cut alignment crosshair, anchored over the member you're cutting so the
## drifting seam ⊕ sits on the actual hull in view (not floating in screen-space).
## Steering the pilot reticle ✛ onto the seam reads as lining the cutting head up
## with a point on the member (the torch beam itself is drawn in 3D from the ship's
## wing — see CuttingBeam.gd). Coords are the align dict's -1..1 mapped to a field
## around that anchor.
func _draw_align() -> void:
	if GameState.align_state != "ALIGNING" or GameState.align.is_empty():
		return
	var align: Dictionary = GameState.align
	var field := 120.0
	var center := _align_field_center(field)
	var tol: float = SalvageSystem.ALIGN_LOCK_RADIUS * field
	var target := center + Vector2(align["target"]) * field
	var reticle := center + Vector2(align["reticle"]) * field
	var lock := float(align["lock"])
	var slip := float(align["slip"])
	var err: float = Vector2(align["reticle"]).distance_to(align["target"])
	var on: bool = err <= SalvageSystem.ALIGN_LOCK_RADIUS
	# Field boundary, and the lock-progress ring that fills as you hold on-seam.
	draw_arc(center, field, 0.0, TAU, 64, Color(HUD_COLOR, 0.3), 1.0, true)
	if lock > 0.0:
		draw_arc(center, field, -PI / 2.0, -PI / 2.0 + TAU * lock, 64,
				Color(HUD_COLOR, 0.9), 2.5, true)
	# Seam target ⊕ with its tolerance ring; greens up while the reticle is inside.
	var tgt_col := Color(0.45, 1.0, 0.55, 0.9) if on else Color(HUD_COLOR, 0.8)
	draw_arc(target, tol, 0.0, TAU, 32, tgt_col, 1.5, true)
	draw_line(target - Vector2(9, 0), target + Vector2(9, 0), tgt_col, 1.5)
	draw_line(target - Vector2(0, 9), target + Vector2(0, 9), tgt_col, 1.5)
	# Pilot reticle ✛ (rotated cross so it reads apart from the target).
	var rc := Color(1.0, 0.9, 0.4, 0.95)
	for d: Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(reticle - d * 8.0, reticle + d * 8.0, rc, 2.0)
	# Slip warning as the torch wanders toward a hard-fail.
	if slip > 0.35:
		var a := 0.4 + 0.6 * sin(_time * TAU * 3.0)
		draw_string(ThemeDB.fallback_font, center + Vector2(-26, -field - 12),
				"SLIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(THREAT_COLOR, a))


## Anchor the alignment field on the selected member's on-screen position, so the
## seam sits on the actual hull you're cutting. Clamped to keep the field on-screen,
## and falls back to the nose reticle if the member has no projectable centre
## (headless / behind the camera).
func _align_field_center(field: float) -> Vector2:
	var member := GameState.get_member(GameState.selected_member_id)
	if camera != null and member.has("center") and not camera.is_position_behind(member["center"]):
		var pad := field + 16.0
		return camera.unproject_position(member["center"]).clamp(
				Vector2(pad, pad), size - Vector2(pad, pad))
	return _nose_center()


## Marks the selected cut target on its world-space centroid (published into the
## graph by Wreck.gd), so the pilot can see which member they picked and fly to it.
## In view: a diamond + name + range, greening to a FIRE-TO-ALIGN cue once MATCHED
## on it. Out of frame: an edge arrow pointing the way to turn to bring it into
## view. Nothing to draw before scan (no member is selectable) or headless (no
## baked centre) — hence the has("center") guard.
func _draw_target_member() -> void:
	if camera == null or GameState.run_phase != "ON_SITE":
		return
	# While aligning, the crosshair field itself sits on the member (see _draw_align),
	# so the separate marker would just clutter the same spot.
	if GameState.align_state == "ALIGNING":
		return
	var member := GameState.get_member(GameState.selected_member_id)
	if member.is_empty() or member.get("cut", false) or member.get("destroyed", false):
		return
	if not member.has("center"):
		return
	# During the cut, mark the seam the beam actually bites (a real hull vertex) —
	# a member's centroid can sit in empty space (hollow corridors / ring spine).
	# Before the cut, the centroid is the right locator to fly the approach to.
	var cutting_here: bool = GameState.wreck.get("cutting_id", -1) == member["id"]
	var pos: Vector3 = member["seam"] if (cutting_here and member.has("seam")) else member["center"]
	var font := ThemeDB.fallback_font
	var matched: bool = GameState.approach_state == "MATCHED" \
			and GameState.matched_member_id == member["id"]
	var color := Color(0.5, 1.0, 0.6, 0.95) if matched else Color(1.0, 0.85, 0.4, 0.9)
	var dist := roundi(camera.global_position.distance_to(pos))
	var frame := Rect2(Vector2.ZERO, size)
	# In front and inside the frame: full marker. Otherwise an edge arrow.
	if not camera.is_position_behind(pos):
		var screen := camera.unproject_position(pos)
		if frame.has_point(screen):
			_draw_diamond(screen, 11.0, color, 2.0)
			draw_string(font, screen + Vector2(16, 5), "%s — %d M" % [member["name"], dist],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
			# Prompt the cut only once you're MATCHED and not already aligning/cutting.
			if matched and GameState.align_state != "ALIGNING" \
					and GameState.wreck.get("cutting_id", -1) == -1:
				draw_string(font, screen + Vector2(16, 23), "MATCHED — FIRE TO ALIGN",
						HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
			return
	# Off-screen: point an arrow the short way round to the target.
	_draw_offscreen_marker(pos, "%s  %d M" % [member["name"], dist], color)


## Adrift salvage pieces (DriftSystem): a diamond + name + range like the cut
## target marker, greening up while the scoop meter is filling and gaining a
## progress ring, plus a live relative-speed readout once the hatch is open —
## the number the pilot is actually flying to zero out to collect.
func _draw_salvage_pieces() -> void:
	# Off the claim, pieces left adrift are frozen but still listed
	# (DriftSystem.is_collecting) — no markers or gate cues for those.
	if camera == null or not DriftSystem.is_collecting():
		return
	var frame := Rect2(Vector2.ZERO, size)
	var font := ThemeDB.fallback_font
	for piece: Dictionary in GameState.salvage_pieces:
		var pos: Vector3 = (piece["transform"] as Transform3D).origin
		# The same evaluation the scoop itself runs (and the MFD SCOOP page
		# draws), so the cue here can't disagree with either.
		var st := DriftSystem.collection_status(piece)
		var scoop: float = st["scoop"]
		var color := SALVAGE_LOCKED_COLOR if scoop > 0.0 else SALVAGE_COLOR
		var label := "%s — %d M" % [piece["name"], roundi(float(st["range"]))]
		if camera.is_position_behind(pos):
			_draw_offscreen_marker(pos, label, color)
			continue
		var screen := camera.unproject_position(pos)
		if not frame.has_point(screen):
			_draw_offscreen_marker(pos, label, color)
			continue
		_draw_diamond(screen, 9.0, color, 1.5)
		draw_string(font, screen + Vector2(14, 5), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
		# Once the hatch is open, name the gate that's actually blocking the
		# scoop rather than just printing a number — the SCOOP page has the full
		# instrument, this is the glance version.
		if GameState.hatch_open_locked():
			draw_string(font, screen + Vector2(14, 21), _scoop_cue(st),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
		if scoop > 0.0:
			_draw_scoop_ring(screen, 16.0, scoop, color)


## The one thing to fix right now to get this piece aboard, worst gate first:
## get in range, then point at it, then kill the relative drift.
func _scoop_cue(st: Dictionary) -> String:
	if not st["in_range"]:
		return "CLOSE IN — %.0f M" % maxf(float(st["gap"]), 0.0)
	if not st["in_cone"]:
		return "OFF-AXIS %d°" % roundi(float(st["off_axis"]))
	if not st["speed_ok"]:
		return "MATCH SPEED — REL %.1f M/S" % st["rel_speed"]
	return "SCOOPING"


## Progress ring for a piece's scoop meter — same visual idiom as the
## alignment mini-game's lock ring (_draw_align), so "holding something
## steady fills a ring" reads as one consistent HUD language.
func _draw_scoop_ring(center: Vector2, radius: float, progress: float, color: Color) -> void:
	draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * progress, 32, color, 2.0, true)


func _draw_diamond(c: Vector2, r: float, color: Color, width: float) -> void:
	draw_polyline(PackedVector2Array([
			c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r),
			c + Vector2(-r, 0), c + Vector2(0, -r)]), color, width, true)


func _draw_arrowhead(tip: Vector2, dir: Vector2, r: float, color: Color) -> void:
	var d := dir.normalized()
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([
			tip, tip - d * r * 1.7 + n * r * 0.8, tip - d * r * 1.7 - n * r * 0.8]), color)


## Off-screen indicator shared by the target-member and salvage-piece markers:
## an edge arrow pointing the short way round toward `pos`, with a label. Behind
## the camera the perspective mapping inverts, so the screen direction flips
## there — same math _draw_target_member used inline before this was factored
## out for the salvage-piece markers to share.
func _draw_offscreen_marker(pos: Vector3, label: String, color: Color) -> void:
	var b := camera.global_transform.basis
	var dir := pos - camera.global_position
	var v := Vector2(dir.dot(b.x), -dir.dot(b.y))
	if dir.dot(-b.z) < 0.0:
		v = -v
	v = v.normalized() if v.length() > 0.001 else Vector2.DOWN
	var edge := (size / 2.0 + v * size.length()).clamp(
			Vector2(EDGE_MARGIN + 16.0, EDGE_MARGIN + 16.0),
			size - Vector2(EDGE_MARGIN + 16.0, EDGE_MARGIN + 16.0))
	_draw_arrowhead(edge, v, 12.0, color)
	draw_string(ThemeDB.fallback_font, edge - Vector2(30, 16), label,
			HORIZONTAL_ALIGNMENT_CENTER, 60, 12, color)


## Screen point for a world-space direction from the camera eyepoint, clamped
## into the frame (minus a margin) so out-of-fov directions pin to the nearest
## edge. Returns null when the direction is behind the camera.
func _project_direction(dir: Vector3) -> Variant:
	var world_point := camera.global_position + dir.normalized() * 1000.0
	if camera.is_position_behind(world_point):
		return null
	var p := camera.unproject_position(world_point)
	return p.clamp(Vector2(EDGE_MARGIN, EDGE_MARGIN), size - Vector2(EDGE_MARGIN, EDGE_MARGIN))


## The nose reticle, and the drift marker's anchor, both live here: the ship's
## *nose* projected to screen (glance rotates only the camera gimbal, so the nose
## slides off-centre as you look around). Falls back to screen centre when the
## nose is behind the camera or the camera isn't wired up yet.
func _nose_center() -> Vector2:
	if camera == null:
		return size / 2.0
	var xform: Transform3D = GameState.local_ship()["transform"]
	var p = _project_direction(-xform.basis.z)
	return p if p != null else size / 2.0


## The reticle marks the ship's *nose*, not the view centre: glance rotates only
## the camera gimbal, so the nose slides off-centre as you look around. At rest
## (no glance) the nose projects to screen centre, matching the old fixed glyph.
func _draw_reticle() -> void:
	var c := _nose_center()
	draw_arc(c, 14.0, 0.0, TAU, 48, HUD_COLOR, 1.5, true)
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + dir * 22.0, c + dir * 34.0, HUD_COLOR, 1.5)


## Drift marker: a pair of vertical brackets [ ] offset from the nose reticle by
## the ship's *lateral* velocity — the component perpendicular to the nose;
## forward speed shows in the VEL readout, not here. The offset scales with drift
## *magnitude* (not just direction), so the brackets rest on the reticle when you
## fly straight and slide smoothly back onto it as you counter-thrust to null,
## instead of pinning to the screen edge the moment travel goes off-axis.
func _draw_velocity_vector() -> void:
	if camera == null:
		return
	var vel: Vector3 = GameState.local_ship().get("velocity", Vector3.ZERO)
	if vel.length() < VEL_EPSILON:
		return
	var nose := -(GameState.local_ship()["transform"] as Transform3D).basis.z
	var drift := vel - nose * vel.dot(nose)
	var cam_basis := camera.global_transform.basis
	var px_per_ms := size.y * VEL_MARKER_SCALE
	var offset := Vector2(drift.dot(cam_basis.x), -drift.dot(cam_basis.y)) * px_per_ms
	var center := (_nose_center() + offset).clamp(
			Vector2(EDGE_MARGIN, EDGE_MARGIN), size - Vector2(EDGE_MARGIN, EDGE_MARGIN))
	_draw_flanking_brackets(center, 18.0, HUD_COLOR, 1.5)


func _draw_flanking_brackets(center: Vector2, r: float, color: Color, width: float) -> void:
	var arm := r * 0.5
	for s: float in [-1.0, 1.0]:
		var x := center.x + s * r
		var top := Vector2(x, center.y - r)
		var bot := Vector2(x, center.y + r)
		draw_line(top, bot, color, width)  # spine
		draw_line(top, top + Vector2(-s * arm, 0), color, width)  # top serif (toward center)
		draw_line(bot, bot + Vector2(-s * arm, 0), color, width)  # bottom serif


func _draw_corner_brackets(center: Vector2, r: float, color: Color, width: float) -> void:
	var arm := r * 0.45
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var p := center + corner * r
		draw_line(p, p + Vector2(-corner.x * arm, 0), color, width)
		draw_line(p, p + Vector2(0, -corner.y * arm), color, width)
