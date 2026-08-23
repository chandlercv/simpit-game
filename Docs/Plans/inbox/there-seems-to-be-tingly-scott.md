# Rival cutter & patrol — visible ships, and a standard exterior light fit

## Context

The rival cutter and the claim-holder's patrol are fully simulated — they close on
the wreck, strip members, retrieve their own pieces, enforce the claim, and they
are solid enough to ram — but they have **no 3D body**. `systems/ThreatSystem.gd`
registers each one as a sensor contact and nothing more:

```gdscript
_rival_contact_id = GameState.register_contact(
        "RIVAL CUTTER", spawn, true, SHIP_CONTACT_RADIUS)
```

So a rival today is a bracket on the HUD, a blip on the Tactical scope, a row on
the MFD CONTACTS page, and an invisible collision sphere. Look out of the window
at the bearing the scope gives you and there is nothing there.

Two other gaps get closed in the same pass, because they are the same work:

- The contact record carries `position` only — no facing and no kind — so there is
  nothing for a view node to point a mesh along, and no way to tell a rival from
  the derelict without string-matching a display name.
- The switch panel already decodes **BEACON** and **STROBE** and posts them to the
  comms log, but nothing is wired to them (`README.md:539`). Giving the AI ships a
  proper light fit and not giving the Kestrel the same one would be the wrong way
  round, so the same fit goes on all three hulls and those two switches finally
  drive something.

Outcome: you can see the rival working the hull from across the volume — including
its torch firing when it severs a member — and every ship in the world carries the
standard exterior lighting a pilot would expect to identify one by. The Kestrel's
own fit becomes a real system rather than a decoration: it sits on the bus, it
costs a little of the signature that keeps the patrol off you, and it appears in
the departure and arrival procedures where a pilot would look for it.

## Decisions already taken

| Decision | Choice |
| --- | --- |
| Model source | New `tools/build_ships.py` Blender generator (Blender 4.5 is at `C:\Program Files\Blender Foundation\Blender 4.5\blender.exe`) |
| Scale | Peers of the Kestrel — hulls ~3 m, and `SHIP_CONTACT_RADIUS` drops 4.0 → 2.0 |
| Lighting | Standard fit on **all three** hulls: red port / green starboard / white tail, white strobes on the wingtips and tail, flashing red beacons dorsal and ventral. The patrol gets no special livery lighting. |
| Lights & the bus | A token draw; dead when there is no source (both masters off, or ALT off on a flat battery) |
| Lights & signature | A lit ship is more visible: ×0.95 per group extinguished, so a blacked-out fit ≈ 0.857 — far below a master's 0.5, and below where an active emitter should sit |
| Torch | The rival's torch fires visibly on the strip it already announces to comms |

---

## 1. `tools/build_ships.py` — the two hulls

New Blender generator, third alongside `build_hull.py` and `build_station.py`,
writing to a new `assets/cc0/ships/` directory:

- `rival_cutter.glb` — a working salvage boat. Blunt bow, a torch boom slung under
  the nose (so the flash in step 7 has somewhere to come from), an open cargo
  cradle aft. Scuffed working-boat tint.
- `patrol_cutter.glb` — leaner and faster-looking. Slim fuselage, swept wings, a
  large drive at the tail. Colder authority-grey tint.

Follow the existing generators exactly:

- **Author in Godot space, at the origin, facing Godot forward (−z)** — the same
  convention `build_station.py`'s traffic ships use, and each vertex is emitted to
  Blender as `(gx, -gz, gy)`.
- **Copy the primitive helpers rather than extracting a shared module.**
  `build_hull.py` and `build_station.py` each carry their own `add_box`,
  `_finalize` and `export`; that duplication is the established convention here
  and the generators stay self-contained. Do not refactor them into a common file.
- **Assert the fit at build time.** Mirror `build_station.py`'s `check_clear` /
  `_violations` discipline: refuse to write a mesh with any vertex further than
  `SHIP_CONTACT_RADIUS` (2.0) from the origin, and print what overflowed. This is
  the same principle as the lane clearance check and as `build_gear_leg`'s tie to
  `GEAR_HEIGHT` — the model cannot outgrow the sphere the game collides against.

Sizing reference: the Kestrel bakes to a capsule 2.6 m long × 0.7 m across
(`data/ships/kestrel.tres`), and `craft_miner` is 1.8 m wide. A ~3.0 m × 1.9 m ×
0.9 m hull circumscribes to a sphere of radius ~1.9, which is what sets the 2.0
below.

## 2. Contact record gains `kind` and `heading`

`autoload/GameState.gd` — extend the record documented at `GameState.gd:243-251`
and `register_contact()` at `:501`:

- New trailing optional parameter `kind := ""`. Every existing caller (`Wreck.gd`,
  `DebrisField.gd`, `DockingSystem._spawn_traffic`) is unchanged.
- Store `"kind": kind` and `"heading": Vector3.ZERO` on the record.

This mirrors how `GameState.traffic` already carries `entry["kind"]` for
`StationTraffic.gd` to key its mesh off — the reason that node needs no name
matching. Both new fields are replication-friendly types, per the comment on
`GameState.ships`.

`systems/ThreatSystem.gd` — pass `"RIVAL"` / `"PATROL"` at both `register_contact`
calls, and write `contact["heading"]` at every point it already writes
`contact["position"]`:

| State | Heading |
| --- | --- |
| `_update_rival_approach` | toward the wreck |
| `_update_rival_cut` | toward the wreck (station-keeping, nose on the work) |
| `_update_rival_collect` | toward the piece |
| `_update_rival_depart` | along `away` |
| `_update_patrol` | toward the ship, both while closing and while holding at enforce range |

Every one of those directions is already computed on the line above; this is
storing a normalised vector that exists anyway. Deriving facing from frame-to-frame
position deltas instead was rejected — it gives nothing during CUT and enforcement
hold, when the ship is stationary and is exactly when you are looking at it.

## 3. `SHIP_CONTACT_RADIUS` 4.0 → 2.0

`systems/ThreatSystem.gd:20`. The constant is referenced in exactly three places,
all in that file, and no smoke test asserts on it — verified by grep.

This is a real gameplay change: the rival and patrol become smaller, harder-to-ram
targets and the ~4 m standoff a collision currently gives you halves. Update the
constant's comment to say the number is the circumscribing sphere of the hulls
`tools/build_ships.py` builds, so the two stay tied.

No document figure moves — the terminal procedures' **RIVAL CUTTERS** chapter
(`scenes/displays/TerminalProceduresContent.gd:212`) quotes 45–90 s, 180 m, 25 s,
6 m and 2 s, none of which change.

## 4. `scenes/world/ShipLights.gd` — the standard fit, written once

New `Node3D` script. One hull-extents table drives nine lights so the Kestrel and
both AI ships carry an identical scheme rather than three hand-placed copies:

| Group | Lights | Behaviour |
| --- | --- | --- |
| `NAV` | red port wingtip, green starboard wingtip, white tail | steady |
| `STROBE` | port wingtip, starboard wingtip, tail | white, ~1 Hz |
| `BEACON` | dorsal, ventral | red, ~0.75 Hz short flash |

Key points:

- **Mount points are measured, not transcribed.** `build(host: Node3D)` merges the
  AABBs of every `MeshInstance3D` under `host` into host-local space and places the
  lights on that box's extremes — the same technique `tools/ShipColliderBake.gd`
  uses to fit the ship capsule, and it handles the Kestrel's offset `Hull` node
  (positioned at `(-2.0, -1.05, -1.5)` in `Ship.tscn`) for free. No hull dimension
  gets written down twice.
- **Each light is an additive unshaded billboard `QuadMesh`**, so it reads as a
  source at range and blooms against the environment's `glow_hdr_threshold = 1.4`.
  Copy the material block from `scenes/world/CuttingBeam.gd:43-48` — unshaded,
  alpha, additive, cull disabled — which is the idiom already used for the torch
  and the dust particles.
- `OmniLight3D` only on the **player's** nav pair and beacons, preserving the
  hull-lighting look `Ship.tscn` has today. Distant AI ships get billboards alone;
  an omni on a contact 150 m away buys nothing.
- **Random phase offset per ship**, so three ships never flash in lockstep.
- Public `set_group(role: String, on: bool)`; AI ships just leave everything on.

## 5. Light state, the bus, and the signature

### 5a. State moves into `GameState`, and BEACON / STROBE get wired

The Kestrel's lights are currently read straight off `GameState.panel_switches` by
`Ship.gd:97`, under the "cosmetic switches may be read directly" licence at
`GameState.gd:371-374`. **That will not survive step 8.** With no switch panel
connected `panel_switches` is empty, so a checklist row keyed to it would report
FAIL on a ship whose lights are in fact on — the default-on comes from `Ship.tscn`,
not from any state anyone can read.

So promote the three groups from cosmetic to real state, which is what the bridge's
own documented distinction (`SwitchPanelBridge.gd:116`) calls for once a switch has
a systemic effect:

- `autoload/GameState.gd` — `var exterior_lights := {"NAV": true, "BEACON": true,
  "STROBE": true}`, a `set_exterior_light(group, on)` setter and an
  `exterior_lights_changed` signal. Default on: the ship is lit unless a switch
  says otherwise, which preserves today's behaviour for keyboard players.
- `systems/hardware/SwitchPanelBridge.gd` — route `"NAV"`, `"BEACON"`, `"STROBE"`
  through `_route_intent` to that setter, alongside `COWL` and the masters.
  `LANDING` stays cosmetic and panel-only; it is not in any checklist and moving it
  buys nothing.
- `scenes/world/Ship.tscn` — delete the hand-placed `NavLightL` / `NavLightR`;
  they are replaced by the built fit. `ThrusterGlow`, `LandingLight`,
  `HullCameraRig` and `CuttingBeam` are untouched.
- `scenes/world/Ship.gd` — add `_build_lights()` beside `_build_gear()`, run
  against `$Hull`, and drive the groups from `exterior_lights_changed`. The
  `LANDING` case in `_on_panel_switch` stays as it is.

No new keybinds — the panel is the only control for lights today and that stays
true, so the Controls tables need no new rows.

### 5b. A token draw, and dead with the bus

`autoload/GameState.gd`:

- `const LIGHT_GROUP_DRAW := 0.02` — added to `electrical_demand()` (`:798`) for
  each **lit** group. All three lit is 0.06: about 2.4% of the Kestrel's 2.5 power
  budget, and a tenth of a channel's `power_low` of 0.2. It can never starve the
  bus; it shows as a marginally slower battery charge and slightly shorter
  endurance on a battery-only ship. Genuinely token, as asked.
- `func bus_live() -> bool` — `electrical_supply() > 0.0 or (master_bat and
  battery_charge > 0.0)`. The lights go out when it is false.

**Gate on a source existing, not on `delivery_fraction()`.** Gating on delivery
would be circular: the lights draw starves the bus → lights out → demand drops →
bus recovers → lights on, oscillating every tick. `bus_live()` has no such loop.

It also gives the behaviour asked for and slightly more: both masters off kills
them, and so does a **flat battery with ALT off** — which is the "runs on the
battery until that's flat, then goes quiet" case `set_master_alt`'s own comment
already describes. Lights that survived a dead ship would be the odd case.

Not a fifth power channel. That would drag in the MFD POWER page sliders, a switch
mapping, `CHANNEL_SWITCHES`, both documents and the checklists, for a load two
orders of magnitude below the others.

### 5c. Lit ships are more visible

`passive_signature()` (`:900`) currently reads only the two masters — **`sensor_mode`
never enters it, so running ACTIVE costs nothing today.** There is no existing
emissions term to match the lights against.

Add one reductive term: **×0.95 per group extinguished**, all three off ≈ 0.857.

```
fully lit, both masters on   1.00   -> patrol enforces at 60 m
blacked out, masters on      0.857  -> 51 m
blacked out, one master off  0.43   -> 26 m
blacked out, both off        0.21   -> 13 m
```

**Keep 1.0 meaning "fully lit."** A lit ship being more visible than a dark one is
the requested behaviour either way; where the baseline sits is what decides how
much else has to move. Raising signature *above* 1.0 for lights would push the
patrol's reach past the **60 m** the terminal procedures publish as the base
(`TerminalProceduresContent.gd:222`) and falsify the handbook's "one switch off
gives one half, both give one quarter" (`PilotManualContent.gd:231`), plus all
three `PowerSmoke.gd:125-129` assertions. Making lights-off a third reductive term
leaves every published figure and every existing assertion true.

**Magnitude — deliberately far below a master, and this is the right call.** A
master halves the signature; a whole blacked-out light fit costs about a seventh.
Physically an active emitter is detected by a passive listener at roughly twice the
range it can detect that listener (one-way path loss against the echo's two-way
loss), which is why going active is treated as announcing yourself; navigation
lights are a few watts of incoherent, unmodulated light. Strobes are the most
detectable of the three groups, but still nowhere near an emitter. The ordering
that falls out is masters ≫ active sensors ≫ lights, and 0.95 per group puts the
lights at the bottom of it where they belong.

Emit `signature_changed` from `set_exterior_light`, as the two master setters do.
Nothing in `scenes/` consumes that signal today — `ThreatSystem:225` is the only
reader of `passive_signature()` — so there is no HUD readout to update.

⚠ **Watch the hull camera.** No camera in the project sets a `cull_mask`, so the
pilot's own wingtip strobes and dorsal beacon will be in frame from
`HullCameraRig`. If a 1 Hz white flash intrudes on the main flight view, put the
player's own billboards on a dedicated `VisualInstance3D.layers` bit and clear that
bit from the hull camera's `cull_mask` — the external camera keeps it, so the ship
still looks right from outside. Judge it with the screenshot tool, not by guessing.

## 6. `scenes/world/ThreatShips.gd` — the view node

New `Node3D`, added to `scenes/world/DebrisField.tscn` as a sibling of
`SalvagePieces`. Modelled directly on `scenes/world/StationTraffic.gd`, which is
the cleanest existing example of this pattern:

```gdscript
const SHIP_DIR := "res://assets/cc0/ships/"
const MESHES := {"RIVAL": "rival_cutter.glb", "PATROL": "patrol_cutter.glb"}
var _visuals: Dictionary = {}   # contact id -> Node3D
```

- `_ready()` connects `GameState.contacts_changed` and calls `_sync()` once, so a
  window opened late still back-fills (the reason `SalvagePieces.gd` replays
  existing pieces on ready).
- `_sync()` diffs live contacts whose `kind` is a key of `MESHES` against
  `_visuals`, `queue_free()`s orphans, spawns the rest. Keying on explicit kinds is
  what keeps the station's traffic contacts — which already have their own visuals
  via `StationTraffic` — from being rendered twice.
- `_process()` sets `global_transform` from `position` and
  `Basis.looking_at(heading, Vector3.UP)`, guarded for a zero or near-vertical
  heading by keeping the current basis. `DockingSystem._route_pose()` is the
  reference for this.
- `_spawn()` loads the `.glb`, `add_child`s it, then attaches `ShipLights`. Warn
  and skip on a missing asset, matching `StationTraffic.gd:60`'s
  `"… — run tools/build_station.py"` phrasing.

Presence gating falls out for free: ThreatSystem only spawns these contacts
`ON_SITE` and removes them on depart and on `reset_run()`, so no `run_phase`
handling is needed here.

**View-only, mutates nothing** — the convention stated in `SalvagePieces.gd:9-12`
and `StationTraffic.gd:3-5`. The rules stay headless.

## 7. The rival's torch flash

- `autoload/GameState.gd` — new `signal rival_cut_fired(from: Vector3, to: Vector3)`,
  alongside the other world signals.
- `systems/ThreatSystem.gd:150` — emit it in `_update_rival_cut` on the same line
  that already posts `"RIVAL CUTTER FLARE — %s STRIPPED BY RIVAL"`. The far end is
  the severed piece's origin, which is where the torch was working:
  `GameState.get_salvage_piece(result["piece_id"])["transform"].origin`. No new
  data is needed from `SalvageSystem`.
- **Factor the beam.** `scenes/world/CuttingBeam.gd` is hard-wired to the player
  (its `EMITTER_LOCAL` hardpoint, `GameState.align_state`, `wreck.cutting_id`), so
  it cannot be reused as-is — but its mesh construction, material block and the
  stretch-a-cylinder-between-two-points math in `_orient()` (`:100-120`) are
  exactly what the rival needs. Extract those into a new
  `scenes/world/TorchBeam.gd` base and make `CuttingBeam.gd extends TorchBeam`,
  keeping its own `_process`, `_cut_point` and colour constants so the player's
  beam behaves identically. The rival's beam is a second, much smaller subclass
  that shows for a fixed duration after the signal and hides itself.

## 8. The lights in the departure and arrival procedures

Each procedure exists in **two** places that must agree item for item and in the
same order — the handbook prose (`scenes/displays/PilotManualContent.gd`) and the
MFD rows (`scenes/ui/ChecklistContent.gd`). Nothing asserts that agreement
automatically; it is held by hand, so edit both in the same pass.

**Departure** — one new item in `BEFORE DEPARTURE`, inserted after
`MASTER SWITCHES` (the lights want the bus) and before `BATTERY`, then renumber
items 3–11 in the handbook body:

> **3  EXTERIOR LIGHTS** — NAV, BEACON AND STROBE **ON** · `{{sw:NAV}}`,
> `{{sw:BEACON}}`, `{{sw:STROBE}}`
> NOTE — The beacon is lit before the drive is started.
> CAUTION — The lights are on the bus. They will not light before item 2.

MFD row: `{"group": "BEFORE DEPARTURE", "label": "EXTERIOR LIGHTS", "want": "ON"}`,
reading all three groups out of `GameState.exterior_lights` and reporting which are
out, e.g. `"NAV · BEACON · STROBE"` or `"STROBE OFF"`. It must also fail on a dead
bus with all three selected on — report `"NO BUS"` — so the row states what the
pilot can actually see out of the window, not what the switches are asking for.
That ordering is why the item sits after `MASTER SWITCHES`.

**Arrival** — one new item in `AFTER LANDING`, between `CARGO HATCH — OPEN`
(item 12) and `{{sw:MASTER_ALT}} — OFF`, then renumber 13–14 → 14–15:

> **13 EXTERIOR LIGHTS** — **OFF** · `{{sw:NAV}}`, `{{sw:BEACON}}`, `{{sw:STROBE}}`
> The ship goes dark on the pad before the bus is opened.

This closes the loop the existing closing note already implies — *"Both are the
first items of the next departure"* — and matches the departure item rather than
inventing a second idiom.

**The arrival row must be `_na()`, not FAIL, until the ship is on the pad.** Lights
are on for the whole flight by design, and a row that sits red from the claim to
touchdown is exactly what `ChecklistContent._na`'s comment warns against — *"a red
row for something you could not possibly have done yet trains you to ignore red."*
Gate on `GameState.run_phase == "DOCKED"`, the same shape as the touchdown-limit
rows (`ChecklistSmoke.gd:235` asserts `arrival / SINK RATE == Status.NA`).

Both rows carry a live `read`, so they stay auto-evaluated and non-tappable and the
`manual == 2` assertion at `ChecklistSmoke.gd:151` is undisturbed. Neither row
states a figure, so `_test_limits_are_read_not_written` has nothing to catch.

The DOCK/SCOOP vertical-budget assertion is **not** in play — it covers those
pages' own embedded gate reserves (`DockPanelScript.GATE_ROWS`), not these lists,
and `ChecklistPanel` scrolls (`ROW_H`, `SCROLL_ROWS`).

## 9. Documentation

Required by `CLAUDE.md`, both directions of the two-document split:

**`README.md`**
- Switch panel table (`:530`) — add **BEACON** and **STROBE** rows, and say on all
  three light rows that the group is a token bus load and that extinguishing it
  cuts the ship's passive signature.
- The **running dark** paragraph at `:469` currently explains signature purely in
  terms of the masters. Add the lights as the third term so it stays complete.
- The line at `:539` saying "PANEL, BEACON, STROBE and TAXI … have no gameplay
  effect yet" is now **false**. Reword it to name PANEL and TAXI only — per
  `CLAUDE.md`, fix the false line rather than appending a second one.
- **Handy tool scenes** table — a row for `build_ships.py`, and for the new smoke
  scene and the `rival` screenshot flag from step 9.
- Wherever the rival and patrol are described as contacts (`:88`, `:144`, `:312`),
  make sure nothing now reads as though they are sensor-only.

**`scenes/displays/PilotManualContent.gd`** — two edits:

- A new `"lighting"` chapter in `SECTION 2 — SYSTEMS` (the catalog runs
  `… collision, nav, displays, risk`; place it after `collision`). It states the
  fit, which switch commands each group, that the groups are on the bus and will
  not light without it, and what the fit costs in signature. Flat, declarative,
  addressed to the operator. Use `{{sw:NAV}}`, `{{sw:BEACON}}`, `{{sw:STROBE}}`
  so the switch names resolve live. Quote the 0.95-per-group figure from the
  constant, not from this plan — *if you cannot point at the constant, do not write
  the number.*
- The **Electrical & power** chapter already states the signature rule at `:231`
  ("Each master switch turned off halves the ship's signature…"). Extend that
  sentence to name the lights as the third term, and point at the lighting chapter
  for the detail. That chapter is also where `CLAUDE.md` says a power-model change
  belongs.

The "fitted but has no effect" idiom no longer applies to these lights — they draw
and they emit — so do **not** write the "no bearing on any other system" wording
the plan originally carried.

Nothing in `TerminalProceduresContent.gd` changes. No harbour rule, charge, limit
or quoted ThreatSystem figure moves, the 60 m base is untouched, and its existing
NOTE — *"How a vessel reduces its signature is a matter for its own handbook"* —
already points the right way across the split.

## 10. Tests

**New `tools/ThreatShipsSmoke.gd` + `.tscn`**, following the standard skeleton
(`_failures`, `_check`, `Engine.time_scale = 10.0`, `InputRouter.set_process(false)`
and the same for its children, quit 0/1). `tools/DockSmoke.gd:504-516` is the
precedent for asserting on the real world scene headless — meshes import and
AABBs are measurable without a DisplayServer. Assert:

- Registering a `RIVAL` contact produces exactly one visual under `ThreatShips`,
  and removing it frees the visual.
- The visual's `global_position` tracks the contact's `position`, and its `-z`
  points along `heading`.
- Every vertex of both `.glb`s lies within `ThreatSystem.SHIP_CONTACT_RADIUS` of
  the model origin — the runtime half of the generator's build-time assertion, so
  a re-exported model that outgrew its sphere fails here too.
- `ShipLights.build()` produces the nine lights on a stand-in mesh, and
  `set_group` toggles each group.
- A station traffic contact does **not** get a `ThreatShips` visual (the
  double-render guard).

**Extend `tools/ScreenshotCheck.gd`** with a `rival` flag next to `close` and
`berth`: force the rival and patrol to spawn immediately, park the ship looking at
them, and render. This is the only way to actually eyeball the models, the light
fit and the torch flash short of a playtest, and it is how the hull-camera strobe
question in step 5 gets settled.

**Add to `tools/ChecklistSmoke.gd`**, following its existing per-row pattern: the
departure lights row flips with `GameState.set_exterior_light`, fails with `NO BUS`
when both masters are off, and the arrival row reads `NA` off the pad and gates on
all three being off once `run_phase` is `DOCKED`.

**Add to `tools/PowerSmoke.gd`**, beside the three signature assertions at
`:125-129` it already carries:

- Signature is still exactly 1.0 fully lit with both masters on — the existing
  assertion must keep passing unchanged.
- Each group extinguished lowers it, all three land on the product, and a master
  still dominates the whole fit.
- Lit groups raise `electrical_demand()`; the rise is small enough that
  `delivery_fraction()` stays 1.0 on a healthy bus.
- `bus_live()` false — both masters off, and separately ALT off with a flat
  battery — puts the lights out with the switches still selected on, and they come
  back on restoration. This is the same "an electrical condition changes what is
  delivered and never what is set" rule the file exists to pin down.

Verified in advance: every `electrical_demand()` assertion in `PowerSmoke` and
`PropellantSmoke` is **relative** (before/after comparisons, `<` and `>`), never an
exact equality against a computed sum, so adding a constant to demand shifts both
sides and none of them break.

**Re-run** `DriftSmoke` (rival strip/collect parity), `CollisionSmoke`,
`ChecklistSmoke` (catalog contiguity, the `manual == 2` count, the layout budget)
and `PilotManualSmoke` (which will fail if the new chapter breaks section
contiguity, publishes harbour material, or names a switch that does not exist).

---

## Verification

```powershell
# 1. Build the models (Blender is not on PATH)
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" --background --python tools/build_ships.py

# 2. Headless assertions
godot --headless res://tools/ThreatShipsSmoke.tscn
godot --headless res://tools/PowerSmoke.tscn
godot --headless res://tools/PropellantSmoke.tscn
godot --headless res://tools/ChecklistSmoke.tscn
godot --headless res://tools/DriftSmoke.tscn
godot --headless res://tools/CollisionSmoke.tscn
godot --headless res://tools/PilotManualSmoke.tscn
godot --headless res://tools/DisplayLoadCheck.tscn

# 3. Eyeball the models, lights and torch flash
godot --path . res://tools/ScreenshotCheck.tscn ++ rival.png rival

# 4. Proof the new manual chapter on paper
pwsh tools/build_manuals.ps1
```

Then fly it: launch the game, sit at the claim, and confirm the rival arrives as a
lit ship on the bearing the scope gives, that its torch fires on the strip that
posts `RIVAL CUTTER FLARE`, that the patrol is visible on intercept, and that the
Kestrel's own beacon and strobes respond to the panel switches without washing out
the main flight view.

Also shoot the MFD checklist pages, since step 8 changes them:

```powershell
godot --path . res://tools/ScreenshotCheck.tscn ++ dep.png mfd CHECKLIST departure
godot --path . res://tools/ScreenshotCheck.tscn ++ arr.png mfd CHECKLIST arrival
```

## Deliberately not included

- **TAXI.** Still decoded and logged with no effect; only BEACON and STROBE get
  wired here.
- **A signature cost for running ACTIVE sensors.** The research above says an
  active emitter should cost far *more* than lights and currently costs nothing —
  `sensor_mode` never enters `passive_signature()`. Adding it is the obvious next
  move, but it is a separate gameplay decision: it changes the value of ACTIVE and
  STRUCT, and it touches the handbook's **Sensors** chapter and the terminal
  procedures' enforcement chapter. Worth doing on its own, not folded in here.
