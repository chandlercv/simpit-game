# Docking / landing mini-game

## Context

Docking is currently the one part of the loop the player doesn't fly. `MarketSystem.request_dock()`
(`systems/MarketSystem.gd:78`) is a button press, a 3-second `await`, and a phase flip to `DOCKED` —
no piloting, no station, no place. Everything else in the game is hands-on: the approach autopilot
hands control back the moment you touch the stick, the pre-cut alignment is a tracked crosshair, the
post-cut scoop is a four-gate rendezvous you fly. The end of a run falls off a cliff by comparison.

This adds a **piloted arrival**: a station with a gated approach lane through its structure, live
traffic working the same volume, an ATC clearance you have to earn and obey, landing gear that takes
time to travel, and a scored touchdown on a berth pad. It reuses the shapes the game already has —
a system that owns the rules, a read-only `status()` the instruments share, an MFD instrument page,
HUD markers, a headless smoke test — so it reads as more of the same game rather than a bolt-on.

**Requested scope:** lots of piloting, a new MFD page, tight quarters, avoiding ship traffic,
deploying landing gear, following ATC instructions, and new assets for the scene.

## Work already on disk

Drafted in a cloud session that stalled at the decisions below and never committed; recovered from
that session's transcript and committed on `docking-recovered` (`b4499de`). Both files compile and
the existing smoke scenes pass with them loaded.

- `autoload/GameState.gd` — modified (+139 lines): `APPROACH` run phase, `FLIGHT_PHASES`,
  `DOCK_STATES`, gear state + travel in `_process`, `docking`/`traffic` state, signals, intents.
- `systems/DockingSystem.gd` — new file, complete first draft (1005 lines): lane data, ATC state
  machine, traffic routes, corridor/gate rules, wave-offs, touchdown scoring. **Not registered as an
  autoload yet**, so nothing calls into it and the game is unchanged.

Both need a review pass against the decisions below.

## Design

### Run phase

Add `APPROACH` between `TRANSIT` and `DOCKED` in `GameState.RUN_PHASES`, plus
`GameState.flight_active()` (`ON_SITE` or `APPROACH`) — the gate for "the pilot is hand-flying a real
ship in a real volume".

- `systems/SalvageSystem.gd:485` `_process` — run `_update_manual_flight` during `APPROACH`
  (scan/approach/align/cut stay `ON_SITE`-only).
- `systems/CollisionSystem.gd:61` — test collisions during `APPROACH` too. This is what makes tight
  quarters bite; no other change needed, its bounding-sphere broadphase already rejects distant bodies.
- `ThreatSystem` / `DriftSystem` stay `ON_SITE`-only (no rival, no salvage at the station).
- Consumers needing an `APPROACH` branch: `scenes/ui/MarketPanel.gd:56`, `scenes/ui/OpsBar.gd:32`,
  `scenes/ui/HUDOverlay.gd:132`.

### `systems/DockingSystem.gd` (new autoload, after `DriftSystem`, before `CollisionSystem`)

Owns lane geometry, ATC, traffic and the landing. Geometry is **station-local constant data** here,
and `Station.gd` builds its 3D gate rings and traffic meshes *from* that data, so what you fly and
what you see cannot drift apart — the same trick `SalvageSystem.register_wreck_position()` uses.
`register_station(xform)` supplies the real world transform; a default keeps every rule testable
headless with no 3D scene (mirrors `SalvageSystem.DEFAULT_WRECK_POS`).

**Lane** — four gates doglegging inward, each with a ring radius you must fly *through* and a
corridor radius for the leg leading to it:

| Gate | Local position | Ring | Corridor |
|---|---|---|---|
| ALPHA (hold) | `(0, 0, 190)` | 14 | free flight |
| BRAVO | `(0, 10, 120)` | 12 | 22 |
| CHARLIE | `(-30, 10, 66)` | 9 | 15 — the slot between two hab drums |
| DELTA | `(-30, 16, 14)` | 6.5 | 10 |
| PAD | `(-30, 0, 14)` | 7 (markings) | 6 — down between the berth walls |

~200 m of lane, flown at a 12 m/s ATC limit. Entry at `(0, 0, 246)`.

**States** (`GameState.docking_state`): `INACTIVE → INBOUND → HOLD → CLEARED → FINAL → LANDED`.
Wave-off returns to `INBOUND`.

**ATC instructions** — a standing instruction dict (`text` / `detail` / `urgent`) held in
`GameState.docking["atc"]` so an instrument can display it as long as it applies, *and* posted to the
comms log via `GameState.post_comms("ATC", …)`. Rules the player must comply with:
1. Proceed to ALPHA and stop (under 3 m/s) — clearance refused while moving.
2. Sequencing delay + no traffic fouling the lane before clearance is granted; the refusal names
   which. ATC calls the clearance itself once both clear, or the pilot requests it.
3. Speed limit per state (22 inbound / 12 cleared / 6 final / 3 holding), warning then go-around
   after 2.5 s over.
4. Stay in the leg's corridor — warning, then go-around after 1.2 s outside.
5. Fly through each ring in order; crossing a gate's plane outside its ring is a missed marker.
6. Mid-approach "HOLD POSITION — TRAFFIC CROSSING" when a ship fouls the lane ahead, released when
   it clears.
7. Gear down and locked (and cargo hatch secured) at the final gate, and all the way down.

**Traffic** — three ships on parametric routes in station-local space: a lane tug crossing the
BRAVO→CHARLIE leg square on (the one you get sequenced behind), a shuttle on the ring circuit, a slow
ore barge on the outer transit past the hold. Registered as `GameState.contacts` with a radius, so
`CollisionSystem` already treats them as solid and the Tactical scope already plots them. Ladder:
advisory call inside 8 m hull-to-hull, go-around for loss of separation, go-around on any actual
contact (via the existing `GameState.hull_impact` signal).

**Landing gear** — `GameState.gear_down` (the lever) + `gear_position` 0..1 travelling over 3 s in
`GameState._process`, so "gear down before the final gate" is a call you act on early. Flying over
the 18 m/s gear limit with it extended wears the DRIVE section. It interlocks the cutter (a leg sits
in the torch's arc) the same way the cargo hatch does, which gives it a cost at the claim too.

**Touchdown** — evaluated the moment the legs reach deck height: gear locked, inside the pad
markings, level within 20°, lateral drift under 2 m/s, sink rate under 5 m/s. Anything the legs
can't take bounces the ship and sends it around; anything they can is scored (sink rate 50%,
accuracy 30%, attitude 20%) into `greased / firm / hard`, with hull wear over 3 m/s and a small
faction standing change either way. Then `MarketSystem.complete_dock(faction)` books the berth.

**`status()`** — one read-only evaluation returning next-gate range and off-nose `aim` (degrees,
screen convention), corridor deviation, speed vs limit, the gate checklist, and the final-approach
numbers (altitude, sink, lateral offset, tilt) plus nearest-first traffic. Deliberately the same
pattern as `DriftSystem.collection_status()` (`systems/DriftSystem.gd:166`), so the DOCK page and the
HUD read exactly the numbers the rules test.

### `MarketSystem` handoff

`request_dock()` keeps its interlocks and transit burn, then hands to `DockingSystem.begin_approach()`
and sets phase `APPROACH`. New `complete_dock(faction)` (berth booked, prices rerolled → `DOCKED`)
and `abort_dock()` (back to the claim). Ship placement on jump-back is a fixed claim entry pose.

### MFD `DOCK` page — `scenes/ui/DockPanel.gd`

Registered in `MfdUnit.PAGES` (`scenes/ui/MfdUnit.gd:30`) and auto-surfaced on the primary MFD while
docking is live, via the existing `_auto_page()` mechanism that already handles ALIGN and SCOOP —
including the nesting behaviour, no changes needed there. Modelled on `ScoopPanel.gd`:

- **ATC instruction banner** — the standing clearance, urgent ones flashing.
- **Cone field** — next gate placed by true off-nose angle with its ring as the tolerance circle and
  an edge arrow when it's off the field; traffic drawn as small crosses on the same field.
- **On final, the field becomes a pad view** — top-down pad markings, your lateral offset, a sink-rate
  tape and altitude.
- **Gate checklist** — SPEED / LANE / GEAR / HATCH / CLEARANCE against live values, so a refused
  clearance or an imminent go-around always names itself.
- **Footer** — REQUEST/ACK, GEAR, ABORT (touch equivalents of the mapped controls).

### HUD — `scenes/ui/HUDOverlay.gd`

Reusing its existing `_draw_diamond` / `_draw_offscreen_marker` / `_draw_scoop_ring` helpers:
next-gate marker with name and range (edge arrow when off-screen), the ATC line in the same slot the
align/cut banner uses, a gear indicator beside the existing cargo-hatch one, and on final a landing
ladder (altitude + sink rate). VEL readout goes red over the ATC limit.

### Controls

Two new actions in `project.godot` `[input]`, wired the standard three ways:
- `landing_gear` — keyboard **X**, plus the switch panel's **GEAR** lever
  (`systems/hardware/SwitchPanelBridge.gd:117` `_route_intent`; `GEAR_UP`/`GEAR_DOWN` are already
  decoded and currently unused).
- `dock_request` — keyboard **Z** — request clearance / read back the standing instruction.
- Abort reuses the existing `market_depart` action while on approach — no new binding.

Defaults go in the `keyboard` profile in `InputRouter.BUILTIN_PROFILES`, dispatch in
`InputRouter._process_panel_commands()`, and rows in a new `DOCKING` group in
`ControlsSetup.BUTTON_TARGETS` (`scenes/displays/ControlsSetup.gd:42`).

### Scene + assets

- `scenes/world/Station.tscn` / `Station.gd` — places gate rings and the pad from
  `DockingSystem.GATES`/`PAD_LOCAL`, registers its world transform, and registers its solid
  structures as collision hulls using the same per-mesh convex-hull bake `DebrisField.gd:102`
  `_mesh_body()` already does. Gate rings and the pad deck are deliberately **not** solid.
- `scenes/world/StationTraffic.gd` — view-only mirror of `GameState.traffic`, exactly like
  `SalvagePieces.gd` mirrors `salvage_pieces`.
- Landing gear meshes on `scenes/world/Ship.tscn`, extended/retracted from `gear_position`.
- Both hung off `scenes/world/DebrisField.tscn` (the world root) at a station origin well clear of
  the claim.

### Test + docs

- `tools/DockSmoke.tscn` / `.gd` — headless, matching the `DriftSmoke`/`AlignSmoke` house style
  (`Engine.time_scale`, `InputRouter.set_process(false)` plus its HID children, `_check`/`_wait_until`):
  arrival places the ship and starts `INBOUND`; the hold gates the clearance on stopping and on
  traffic; gates must be flown in order; corridor departure and sustained overspeed wave off; gear
  up at the final gate waves off; gear travel takes real time; a hot touchdown bounces and a clean
  one books the berth; the cutter is interlocked while the gear is extended.
- `README.md` per `CLAUDE.md`: **Core gameplay loop** (docking is now flown), **Controls** tables
  (keyboard + switch-panel GEAR row, which currently says gear has no gameplay effect), **The four
  displays** (DOCK page), **The Main flight HUD** (gate marker, ATC line, gear, landing ladder),
  **Handy tool scenes** (`DockSmoke`, and the asset generator if one is added).
- `CREDITS.md` if any third-party art is used.

## Decisions (settled 2026-08-09)

1. **Station art — a Blender script**, `tools/build_station.py`, run exactly like `build_hull.py`
   (`blender --background --python tools/build_station.py`). Blender 4.5.10 LTS is installed
   (`C:\Program Files\Blender Foundation\Blender 4.5\blender.exe`, not on PATH), so the script is
   run and its output verified here and the generated `.glb` files are committed.
2. **Auto-berth is kept** as an alternative to flying the pattern — see below.
3. **Departure is flown too**, not abstracted — see below.

### Auto-berth (decision 2)

ATC will fly you in on request, so a run can be wrapped up without the mini-game. It is a *worse*
deal than flying it, never a shortcut past a hard landing:

- `DockingSystem.request_auto_berth()`, offered from the DOCK page footer and the MARKET panel while
  an approach is live. Refused on `FINAL` — once you are over the pad it is your landing.
- Costs a **handling fee** (credits, scaled by the berth's faction) and a **standing hit** of
  `REP_AUTO_BERTH`, against the `REP_PER_LANDING * quality` a flown arrival *earns*. Flying it well
  is the profitable path; the fee is the price of skipping it.
- Books the berth through the same `MarketSystem.complete_dock(faction)` as a touchdown, with
  `docking["quality"] = 0.0` and an `auto` flag, so there is still exactly one door into `DOCKED`.

### Piloted departure (decision 3)

`DOCK_STATES` gains `DEPART_HOLD` and `DEPARTING`, and the pattern runs outbound in reverse:

- Undocking puts the ship on the pad in `DEPART_HOLD` (run phase back to `APPROACH`) awaiting a
  departure clearance, which ATC sequences around the same traffic that gates an arrival.
- `DEPARTING` flies the lane in reverse — DELTA, CHARLIE, BRAVO, ALPHA — under the same corridor and
  speed rules `_check_corridor` / `_update_speed` already enforce.
- **The gear must stay down until DELTA is behind you** (a leg is still in the bay); stowing it early
  is a violation, and it must be stowed before the jump.
- Departure violations are **reprimands, not go-arounds** — a standing cost and an urgent ATC call,
  not a forced return to the pad, which would trap a bad pilot at the station. Collisions still cost
  hull through `CollisionSystem` as everywhere else.
- Past ALPHA outbound, ATC releases the ship and `MarketSystem` runs the existing jump back to the
  claim.

This keeps one lane definition, one corridor test and one speed test serving both directions; only
the gate ordering and the failure consequence differ.

## Verification

Godot 4.7 and Blender 4.5 are both available here, so all of this is verifiable:
`godot --headless res://tools/DockSmoke.tscn`
plus the existing smoke scenes (`Phase4Smoke`, `DriftSmoke`, `MfdNavSmoke`, `CollisionSmoke`) to
confirm the `APPROACH` phase and gear interlock didn't disturb the salvage loop; then an interactive
run — dock from the MARKET page, fly the pattern, and check the DOCK page, HUD markers and switch
panel behave together. `tools/ScreenshotCheck.tscn` can capture the Main view for the README image.
