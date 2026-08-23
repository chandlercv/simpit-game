# Glass-cockpit instrument band on the Tactical display

## Context

The Tactical display is the ship's read-only instrument panel, but today it
carries only three instruments in SCOPE mode (sensor scope, hull heatmap,
structural-risk meter) plus a star CHART. Everything a pilot actually flies
by — speed, heading, altitude, attitude, rates, propellant — is either squeezed
onto the thin Main HUD (which is deliberately camera-feed markings, not
dashboard chrome) or does not exist anywhere.

This adds a permanent glass-cockpit instrument band framing the Tactical
display: heading, speed, altitude, attitude, rotation rates and LH2/LOX, drawn
as tapes wherever a tape reads better than a dial, plus a builder's plate
carrying the ship's tail number.

The band's readouts need a **datum** to be measured against — there is no
"altitude" in space without one. So the change also introduces a selectable
**navigation reference**: one datum that supplies the reference plane and the
zero-bearing direction for altitude, heading, range *and* attitude together.
AUTO follows the run — the landing platform on an approach, the salvage target
on site — and it can be pinned by hand.

Two rules from the user shape the design:

- **No clickable buttons on Tactical.** That includes the SCOPE/CHART tabs that
  are there today — they go, leaving a passive mode legend. Mode already has
  full HOTAS/keyboard coverage.
- **Settings live on HOTAS or a new MFD SETTINGS page**, never on Tactical.

---

## Design

### The navigation reference (new concept)

A datum resolves to an origin plus an orthonormal frame:

| Field | Meaning | Feeds |
| --- | --- | --- |
| `origin` | world point | RNG readout, the altitude plane's position |
| `up` | plane normal | ALT tape, vertical speed, attitude horizon |
| `north` | zero bearing in the plane | HDG tape, attitude yaw |
| `east` | `north.cross(up)` | heading sign |

`east = north.cross(up)` is the correct handedness for Godot's Y-up/−Z-forward
world: with `up = +Y`, `north = -Z`, it yields `+X`. That makes the datum
heading formula `atan2(fwd.dot(east), fwd.dot(north))` a strict generalisation of
the existing HUD formula `atan2(fwd.x, -fwd.z)` at [HUDOverlay.gd:96](scenes/ui/HUDOverlay.gd#L96) — a
smoke test asserts the two agree under the INERTIAL datum.

The catalogue:

| Id | Label | `origin` | Frame | Valid when |
| --- | --- | --- | --- | --- |
| `AUTO` | AUTO | *(resolves to one below)* | | always |
| `PAD` | LANDING PLATFORM | `DockingSystem.pad_world()` | `pad_up()` / `pad_forward()` | always — `_station_xform` has a headless default ([DockingSystem.gd:234](systems/DockingSystem.gd#L234)) |
| `WRECK` | DERELICT | `GameState.wreck["position"]` | station frame | a wreck is registered |
| `TARGET` | CUT TARGET | selected member's centre, else tracked contact | station frame | either exists |
| `INERTIAL` | INERTIAL | `Vector3.ZERO` | world `+Y` / `-Z` | always |

`WRECK` and `TARGET` deliberately borrow the **station's** up/north rather than
the object's own basis: a derelict tumbles, and an attitude horizon pinned to a
tumbling body is unusable. What the object supplies is the origin — so ALT reads
height above a level plane through the wreck, and RNG reads distance to it.

`AUTO` resolves: `PAD` while `DockingSystem.is_active()` → else `TARGET` if
valid → else `WRECK` if valid → else `INERTIAL`. A hand-pinned datum that goes
invalid keeps the selection but falls back the same way, and the legend says so
(`REF DERELICT — NO DATUM, HOLDING INERTIAL`).

**ALT must agree with the HUD landing ladder.** Under the `PAD` datum, subtract
`DockingSystem.GEAR_HEIGHT` so `NavReference.altitude()` equals
`DockingSystem.status()["altitude"]` exactly ([DockingSystem.gd:438](systems/DockingSystem.gd#L438)) — two
instruments disagreeing on final is worse than one fewer instrument. Asserted by
test.

### Band layout

Tactical canvas is 1280×720; after the window's margins the content area is
**1252 × 676** ([TacticalWindow.tscn](scenes/displays/TacticalWindow.tscn)). Reserves, as public consts on the band
script so the layout margins and the smoke test read the same numbers (the
idiom `DockPanel.gd` already uses for `HEADER_H`/`FOOTER_H`/`CHECKLIST_H`):

```
HDG_H = 56   SPD_W = 96   ADI_W = 340   ALT_W = 104   BOTTOM_H = 120
                                        (96 + 340 + 104 + 712 = 1252)
```

**VEL | ADI | ALT form one flight block** on the left, in PFD reading order,
with the tactical picture outboard on the right. The attitude indicator is the
centre of that block, at its full 340 × 500 — larger than a real 3-inch
instrument — because it is the one reading that has to be legible in peripheral
vision.

```
┌──────────────────────────────────────────────────────────────┐
│ ···340····350····000····010····020···          ▼        HDG  │ HDG_H
│ REF LANDING PLATFORM (AUTO) — RNG 412 M               SCOPE  │
├─────┬──────────────────────┬──────┬──────────────────────────┤
│ 24  │  20 10  ·  10 20     │ 120  │                          │
│ 22  │    ╲▼                │ 110  │                          │
│     │   ──20─────          │      │                          │
│▶20.4│  ╲       ──20──      │▶104.6│    SCOPE  or  CHART      │ 500
│ 18  │   ──10────           │ 100  │                          │
│ 16  │ ────┤ ▪ ├───         │  90  │                          │
│ 14  │ ░░░░░╲═══════        │  80  │                          │
│ VEL │  P +08    R −14      │ ALT  │                          │
├─────┴──────────────────────┴──────┴──────────────────────────┤
│ ┌────────────┐   ṗ ──|──      LH2 ▓▓▓▓▓░ 78%                 │
│ │ SV KESTREL │   ẏ ──|──      LOX ▓▓░░░░ 31%                 │ BOTTOM_H
│ │ LU‑4471‑K  │   ṙ ──|──                                     │
│ └────────────┘                                               │
└──────────────────────────────────────────────────────────────┘
  96          340            104              712
```

- **HDG tape** (top, horizontal) — ticks every 5°, `%03d` labels every 10°,
  lubber line at centre, plus a **bearing bug** marking the datum origin's
  azimuth. That bug is why the datum does not need to redefine north per target.
- **VEL tape** (left, vertical) — m/s, boxed pointer at the live value.
  `GameState.speed_ceiling()` draws the top limit band; `GEAR_LIMIT_SPEED`
  (18 m/s) adds an amber band whenever the gear is not stowed; a live approach
  adds ATC's `speed_limit` as a bug.
- **ADI** (centre of the flight block) — see the next section.
- **ALT tape** (right of the ADI, vertical) — metres above the datum plane,
  signed, with a vertical-speed trend arrow (`velocity.dot(up)`) and a ground
  band at zero when the datum is `PAD`.
- **Rate ribbons** (bottom) — three centre-zero horizontal tapes, pitch/yaw/roll
  body rates in °/s, full scale from `ship_def.rotation_rate_deg` (45°/s) or the
  FINE setting (±15°/s).
- **Propellant** (bottom right) — two vertical tank tapes, `GameState.lh2_fraction()`
  / `lox_fraction()`. Amber below 25%, red at zero, wording matching the HUD's
  existing `LH2 DEPLETED` annunciator.
- **Tail plate** (bottom left) — see below.
- **Mode legend** — passive `SCOPE` / `CHART` text where the tabs used to be.

Cost: the scope's radius drops from ≈283 px to ≈207 px. The band toggle (HOTAS +
SETTINGS) gives it back on demand — that is the mitigation, and it is why the
toggle exists.

### The attitude indicator

Everything here exists to answer two questions without reading a number:
*am I pitched up or down*, and *are my wings level*.

**Fixed waterline symbol** `─┤ ▪ ├─` at the ADI's geometric centre. It never
moves. Every other element moves behind it, which turns both questions into
coincidence judgements rather than estimations.

**Sky and ground fields, split by the horizon line.** Sky above in a dark
slate; ground below stippled rather than solid, because the datum's "ground" is
a reference plane and not terrain. Nose up → the horizon drops *below* the
waterline and sky fills the box; nose down → it rises and the stipple fills it.
This is the cue that reads in peripheral vision, and it is the one my earlier
sketch was missing.

**The ground field carries the datum label** (`PLATFORM PLANE`, `DERELICT PLANE`,
`INERTIAL`) — "level" means level with the *selected* datum, and that changes
under the pilot's feet when AUTO switches. The instrument says which.

**Pitch ladder** — bars every 5°, labelled every 10°, **solid above the horizon
and dashed below** (the standard which-side-am-I-on cue), each bar shorter than
the one below it so the taper alone tells you how far from the horizon you are.
Scaled so ±30° fills the box; past that the ladder keeps sliding.

**Roll** — an arc across the top marked at 10 / 20 / 30 / 45 / 60°, a fixed
index triangle at zero, and a moving pointer riding the arc. Wings are level
when the pointer sits on the index — and, redundantly, when the horizon line
is flat.

**Horizon-off-scale chevron** — when pitch takes the horizon out of the box
entirely, a chevron at the box edge points the short way back to level, so the
instrument never goes blank.

**Numerics** `P +08   R −14` beneath the ball, for the exact figure.

*Not* fitted: a slip/skid ball. There is no lateral-acceleration concept in the
flight model, and lateral *translation* is already the HUD's drift brackets —
putting it under a roll pointer would conflate two different things.

### Redraw cadence

Follow the project rule for spacedesk-streamed secondary windows
([TacticalScope.gd:42-44](scenes/ui/TacticalScope.gd#L42-L44)): the band redraws on `GameState.tick_changed`
(10 Hz) only. Nothing in it animates continuously, so no `_process`.

---

## Files

### New

**`systems/NavReference.gd`** — autoload (registered after `DockingSystem` in
`project.godot`, since it reads the station frame). Read-only; mutates nothing.

```gdscript
const DATUMS: Array[Dictionary]        # id + label, the table above
func datum() -> Dictionary             # {id,label,auto,origin,up,north,east,valid,reason}
func altitude() -> float               # (ship.origin - origin).dot(up); −GEAR_HEIGHT on PAD
func vertical_speed() -> float         # velocity.dot(up), positive up
func heading() -> float                # 0..360 of the hull nose in the datum plane
func range_to() -> float
func attitude() -> Vector2             # (pitch°, roll°) in the datum frame
func body_rates() -> Vector3           # (pitch, yaw, roll) °/s from ship["omega"]
```

Attitude: build `ref := Basis(east, up, -north)`, take `rel := ref.transposed() * ship.basis`
(orthonormal, so transpose is the inverse), then pitch/roll off `rel`. Rates:
`ship.basis.inverse() * omega`, `rad_to_deg`, components mapping to
(pitch, yaw, roll) per the command convention at [ShipMotion.gd:56](systems/ShipMotion.gd#L56). Both sign
conventions are pinned by test rather than by inspection.

**`scenes/ui/InstrumentBand.gd`** — one full-rect `Control`,
`mouse_filter = IGNORE`, drawn as a sibling over the mode panels. All band
elements in a flat list of named `_draw_*` sub-draws, the idiom at
[HUDOverlay.gd:107-118](scenes/ui/HUDOverlay.gd#L107-L118). Exports `accent` like every other tactical
instrument (amber `Color(1, 0.72, 0.2)`).

The ADI's geometry goes through two **pure, public** helpers rather than being
computed inline, so the smoke test can assert the symbology instead of eyeballing
pixels:

```gdscript
func horizon_offset(pitch_deg: float) -> float   # px the horizon sits below centre
func tape_offset(value: float, per_unit: float) -> float
```

`horizon_offset` must be monotonic and **positive for nose-up** — that sign is
the whole "more sky means pitched up" cue, and it is the easiest thing in this
change to get backwards.

**`scenes/ui/TailPlate.gd`** — small `Control` drawing an etched builder's
plate: `display_name`, registry, hull serial, builder and build year, on a
bevelled dark field. Separate from the band so it can later go on the title
card. Static — redraws only on `_ready()`.

**`scenes/ui/SettingsPanel.gd`** — the MFD SETTINGS page. Touch buttons via
`ButtonTheme.make_touch_button(accent)` (touch sizing is correct *here* — the
no-buttons rule is Tactical's). Three rows:

1. **NAV REFERENCE** — one button per datum; shows what AUTO resolved to and
   greys unavailable datums with the reason.
2. **TACTICAL BAND** — SHOW / HIDE.
3. **RATE SCALE** — RATED (±45°/s) / FINE (±15°/s).

**`tools/InstrumentBandSmoke.gd` + `.tscn`** — standard harness shape
(`_failures` array, `_check()`, `quit(0/1)`), modelled on
[tools/ChecklistSmoke.gd:363-399](tools/ChecklistSmoke.gd#L363-L399) including its `CRAMPED := Vector2(320, 240)`
layout audit and `_size_to()` helper.

### Modified

| File | Change |
| --- | --- |
| [scenes/displays/TacticalContent.gd](scenes/displays/TacticalContent.gd) | Delete the tab bar and `_tab_style()`; add the band + tail plate; wrap the mode panels in a `MarginContainer` whose margins are the band's reserve consts; keep the `tactical_view_changed` mirror |
| [autoload/GameState.gd](autoload/GameState.gd) | `NAV_REFERENCES` const, `nav_reference` var, `nav_reference_changed` signal, `set_nav_reference`/`cycle_nav_reference` intents — mirroring `tactical_view` at [:114](autoload/GameState.gd#L114), [:294](autoload/GameState.gd#L294), [:774](autoload/GameState.gd#L774), [:783](autoload/GameState.gd#L783). Same pattern again for `tactical_band: bool` and `rate_scale: String` |
| [resources/ShipDefinition.gd](resources/ShipDefinition.gd) + [data/ships/kestrel.tres](data/ships/kestrel.tres) | New exports `registry`, `hull_serial`, `builder`, `build_year` |
| [scenes/ui/MfdUnit.gd](scenes/ui/MfdUnit.gd) | `"SETTINGS"` appended to `PAGES` ([:34](scenes/ui/MfdUnit.gd#L34)) + a `match` arm and preload in `_build_page` ([:200](scenes/ui/MfdUnit.gd#L200)) |
| [scenes/ui/Instrument.gd](scenes/ui/Instrument.gd) | Add `const READOUT := 28` for the boxed tape numerals; the band otherwise adopts the existing scale rather than inventing a second one |
| [project.godot](project.godot) | `[autoload]` NavReference; `[input]` actions `nav_ref_cycle`, `nav_ref_pad`, `nav_ref_target`, `tactical_band_toggle` (all `"events": []`, per the project's convention that only F5/F6/F7 are hardcoded) |
| [autoload/InputRouter.gd](autoload/InputRouter.gd) | Keyboard default `{"key": KEY_Y, "action": "nav_ref_cycle"}` in the displays block (**Y is free** — verified against the whole bound-key set); the other three ship unbound like `tactical_scope`/`tactical_chart` do. Handlers in `_process_panel_commands()` beside the tactical ones at [:613-619](autoload/InputRouter.gd#L613-L619) |
| [scenes/displays/ControlsSetup.gd](scenes/displays/ControlsSetup.gd) | Four `BUTTON_TARGETS` rows in a new `"NAV"` group |
| [tools/ScreenshotCheck.gd](tools/ScreenshotCheck.gd) | New `tactical [SCOPE\|CHART]` target mirroring `_build_mfd`, at the real 1280×720 canvas — the only way to eyeball the band short of a playtest |
| [tools/DisplayLoadCheck.gd](tools/DisplayLoadCheck.gd) | Exercise every datum and the band toggle alongside the states it already forces |
| [tools/MfdNavSmoke.gd](tools/MfdNavSmoke.gd) | Assert `SETTINGS` is in `PAGES` |
| [scenes/ui/TacticalScope.gd:196](scenes/ui/TacticalScope.gd#L196) | Drive-by: `"CLICK A MEMBER TO SELECT CUT POINT"` is stale — the scope stopped taking clicks when selection moved to the MFD. Removing the last clickable chrome from Tactical is exactly when to fix it |

`ShipDefinition` values to author in `kestrel.tres` — **all invented, all a
one-line change if you want different**: `registry = "LU-4471-K"` (Lagrange
Union, the volume she works), `hull_serial = "KS-017"`,
`builder = "TESSERA YARDS, L4"`, `build_year = 2371`. The year is the only
figure with no precedent anywhere in the project — there is no established
calendar.

### Documentation (required by CLAUDE.md)

**[README.md](README.md)** — the displays table row for Tactical ([:36](README.md#L36)) now describes
the band and says *no* controls; the mouse/touch table ([:634](README.md#L634)) drops "Mode
buttons"; the Displays key table ([:605](README.md#L605)) gains **Y**; the MFD row ([:37](README.md#L37))
gains SETTINGS; the tool-scenes table gains `InstrumentBandSmoke`. Line 36's
"Mode buttons; mouse pan/zoom on the chart" becomes false when the tabs go —
that line gets **fixed**, not appended to.

**[scenes/displays/PilotManualContent.gd](scenes/displays/PilotManualContent.gd)** — the builder publishes fitted
equipment, so this is handbook-only:

- `displays` chapter ("Instruments & displays") — a TACTICAL BAND section
  listing each instrument and what it reads against. Its closing NOTE currently
  says the contents of the tanks are not repeated outside the MFD POWER page;
  LH2/LOX tapes make that **false** — fix the line.
- `nav` chapter ("Scope & contacts") — a REFERENCE DATUM section: what each
  setting measures from, that AUTO follows the approach and the cut target, and
  the caution that ALT is height above the selected datum's plane and means
  nothing if the wrong datum is pinned. Its closing NOTE ("no waypoint, route or
  navigation-computer facility is fitted") needs rewording so it stays true
  beside a datum selector.
- `ship` chapter ("Description") — the plate and its markings.

**Boundary discipline**, enforced by `PilotManualSmoke._test_boundary()`: the
handbook must not name `ALPHA`/`BRAVO`/`CHARLIE`/`DELTA`
([PilotManualSmoke.gd:39](tools/PilotManualSmoke.gd#L39)). So it says "the harbour's landing platform, when
one has been designated" and never where that platform is or what heading the
lane runs. `TerminalProceduresContent.gd` needs **no change** — no
`DockingSystem` rule, charge, limit or ATC line moves.

**Tone**: flat, declarative, addressed to the operator; hazards as
**WARNING** / **CAUTION** / **NOTE**; no reference to the simulation or to the
player. Every figure quoted from a constant — `45°/s` from
`rotation_rate_deg`, `18 m/s` from `GEAR_LIMIT_SPEED`, the tank capacities from
`kestrel.tres`.

---

## Explicitly out of scope

- **The Main HUD is not touched.** Its `HDG` is the *camera's* bearing by
  design, documented at [PilotManualContent.gd:602](scenes/displays/PilotManualContent.gd#L602). The band's HDG is the
  *hull's*, against the datum — the band labels its source so the two readings
  are never mistaken for the same number.
- **No font is added.** There is no font file in the project; every instrument
  uses `ThemeDB.fallback_font`. A technical/monospace face would be the first
  vendored font and drags in `THIRDPARTY.md` and the `assets/` licence layout —
  worth doing, separately.
- **No planetoid datum.** `StarChart`'s bodies are a hardcoded schematic with no
  world position ([StarChart.gd:14-27](scenes/ui/StarChart.gd#L14-L27)). The `DATUMS` table is data, so a real
  body becomes one entry once one exists in the world.

---

## Verification

Every check is headless and per-scene — the project has no test runner.

```
godot --headless res://tools/InstrumentBandSmoke.tscn   # new
godot --headless res://tools/MfdNavSmoke.tscn           # SETTINGS in the page cycle
godot --headless res://tools/DisplayLoadCheck.tscn      # Tactical loads with the band
godot --headless res://tools/DisplayLayoutSmoke.tscn    # canvas still 1280x720
godot --headless res://tools/BindClashSmoke.tscn        # KEY_Y does not clash
godot --headless res://tools/PilotManualSmoke.tscn      # placeholders, actions, boundary
godot --headless res://tools/DockSmoke.tscn             # PAD datum did not disturb the pattern
```

`InstrumentBandSmoke` asserts:

- **Layout** — `HDG_H + BOTTOM_H + <min pane height> <= 676` and
  `SPD_W + ADI_W + ALT_W + <min pane width> <= 1252`; the band draws two frames
  at `CRAMPED` (320×240) without falling over.
- **ADI symbology** — `horizon_offset()` is monotonic in pitch and **positive
  for nose-up**, so pitching up genuinely fills the box with sky; it is zero at
  level; ±30° lands inside the box and ±60° outside it (which is what the
  off-scale chevron is for). Roll pointer angle equals `attitude().y`, and is
  zero exactly when the ship's wings are level in the datum frame — asserted for
  a ship parked level under each of the datums, including a `PAD` datum on a
  rotated station transform, which is the case where "level" is *not* world-level.
- **Datum integrity** — every datum resolves with unit-length, mutually
  perpendicular `up`/`north`, and `east == north.cross(up)`.
- **AUTO resolution** — `PAD` while `DockingSystem.is_active()`; the cut target
  when a member is selected; `INERTIAL` on a bare scene. An invalid pinned datum
  reports its fallback rather than dividing by zero.
- **Heading generalises the HUD** — under `INERTIAL`, `NavReference.heading()`
  equals `atan2(fwd.x, -fwd.z)` for a ship parked at several known bases via
  `ShipMotion.seize()`.
- **ALT agrees with the landing ladder** — with a live pattern and the `PAD`
  datum, `NavReference.altitude() == DockingSystem.status()["altitude"]`.
- **Attitude and rates** — a ship level in the datum frame reads P≈0 R≈0;
  pitched 10° reads +10 and rolled left 14° reads −14; a written `omega`
  decomposes to the expected signed body rates.
- **Propellant** — `lh2_fraction()` / `lox_fraction()` drive the tape fills, and
  a drained tank reaches the red state.

Visual proof, since this is a graphics change:

```
godot --path . res://tools/ScreenshotCheck.tscn ++ band-scope.png tactical SCOPE
godot --path . res://tools/ScreenshotCheck.tscn ++ band-chart.png tactical CHART
godot --path . res://tools/ScreenshotCheck.tscn ++ settings.png  mfd SETTINGS
```

Then a real run: launch, confirm **Y** cycles the datum and the band follows;
pitch up and confirm the ADI fills with sky, roll and confirm the horizon tilts
the *opposite* way to the stick (the ship rolls, the world stays put); fly an
approach and confirm AUTO switches to the platform and the band's ALT tracks the
HUD landing ladder digit for digit on short final.
