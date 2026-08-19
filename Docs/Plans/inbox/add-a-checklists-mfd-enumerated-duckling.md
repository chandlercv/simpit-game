# CHECKLIST MFD page + touch-friendly, legible MFDs

## Context

Three related problems on the MFD panel.

**1. The procedures exist only on paper.** The ship's four operating checklists —
departure, arrival, cutting, collecting — live in
[PilotManualContent.gd:447-618](scenes/displays/PilotManualContent.gd#L447-L618)
and are readable only from the launch title card, before the run starts. Once
you're flying, there is no way to consult them. Meanwhile every condition they
describe is already evaluated live somewhere in code — `DockingSystem.status()`,
`DriftSystem.collection_status()`, `SalvageSystem.request_cut()`'s interlock
ladder, `GameState` flags — but that evaluation is only surfaced on the DOCK and
SCOOP pages, and only for the mini-game in progress. A pilot mid-run cannot ask
"what have I not done yet?"

**2. The MFD touch targets are too small.** Touch itself works — this is purely a
sizing problem. Buttons are sized for a mouse: the MENU grid is `200×88` virtual
px, the bezel MENU button and the ALIGN/SCOOP/DOCK footers are smaller still, and
the SALVAGE / CONTACTS / MARKET rows are 12–13 px text. In the MFD window's
1280×800 virtual canvas, scaled down onto a small panel, these land well under a
finger's width.

*No input plumbing is needed.* The existing hand-rolled tap widgets
([TouchSlider.gd](scenes/ui/TouchSlider.gd), `InventoryGrid.TapButton`) stay
exactly as they are, and `ButtonTheme.make_button` is not changed — only what
call sites ask it for.

**3. The DOCK and SCOOP instrument text is too small to read.** These pages are
custom `_draw()` instruments, and their type is sized well below the button text
around them — the gate checklists that are the whole point of both pages run at
**12 px** in the 1280×800 virtual canvas, ATC's supporting detail at **10 px**,
and the traffic range tags at **9 px**. On a panel that scales the canvas down,
9–12 px is a few physical pixels of a fallback font. The rows you are supposed to
read *while flying a go-around* are the least readable thing on the screen.

The fix has a better shape than bumping literals, because these three instrument
pages already **duplicate their drawing helpers verbatim**:

| Helper | Copies |
| --- | --- |
| `_draw_gate` | [DockPanel.gd:298](scenes/ui/DockPanel.gd#L298), [ScoopPanel.gd:180](scenes/ui/ScoopPanel.gd#L180) — identical but for the value column x (92 vs 84) |
| `_draw_notice` | [DockPanel.gd:289](scenes/ui/DockPanel.gd#L289), [ScoopPanel.gd:171](scenes/ui/ScoopPanel.gd#L171) — identical |
| `_draw_meter` | [ScoopPanel.gd:191](scenes/ui/ScoopPanel.gd#L191), [AlignPanel.gd:123](scenes/ui/AlignPanel.gd#L123) — identical |
| `_draw_diamond` | DockPanel:307, ScoopPanel:202 — identical |
| `_draw_arrowhead` | DockPanel:313, ScoopPanel:208 — identical |

So the type scale gets one home, and five copy-pasted functions collapse to one
module on the way past.

**Outcome:** a CHECKLIST page on both MFDs that presents all four procedures with
live tick-marks against real ship state; MFD controls sized for a finger; and
instrument text you can read at arm's length.

---

## Part 1 — The CHECKLIST page

### Design rules

- **The page quotes no figures of its own.** Every limit in a row's value string is
  read from the constant that enforces it (`SalvageSystem.MIN_CUTTER_POWER`,
  `DriftSystem.SCOOP_RANGE`, `DockingSystem.TILT_LIMIT_DEG`, …), formatted the way
  [DockPanel.gd:268-286](scenes/ui/DockPanel.gd#L268-L286) already does
  (`"%.0f / %.0f M/S"`). Nothing can drift, and CLAUDE.md's *"if you cannot point
  at the constant, do not write the number"* holds without a third copy of the
  numbers.
- **Evaluation stays in the systems.** The panel reads `DockingSystem.status()`,
  `DriftSystem.collection_status()`, `CargoSystem.cargo_mass()`, `GameState.*` —
  the same evaluations the rules enforce, so a row cannot disagree with the ship.
- **Auto rows are not tappable.** Only items nothing can verify accept a tap, so a
  fat finger can never "tick" something the ship says is false.

### New file: `scenes/ui/ChecklistContent.gd`

`extends RefCounted`, the catalog — same catalog-not-branches shape as
`MfdUnit.PAGES` and `PilotManualContent.CHAPTERS`.

```gdscript
enum Status { PASS, FAIL, NA }

## Not a `const`: a const Array cannot hold Callables. Built once and cached by
## the panel in _ready().
static func lists() -> Array[Dictionary]
```

Returns four entries `{"id", "title", "items": Array[Dictionary]}` with ids
matching the handbook chapters they mirror — `departure`, `arrival`, `cutting`,
`collecting`. Each item:

```gdscript
{
  "label": "CUTTER ALLOCATION",     # left column
  "want":  "0.20 MINIMUM",          # what the manual says it should be
  "group": "BEFORE FIRING",         # section heading; a new value starts a group
  "read":  Callable,                # func() -> {"status": Status, "value": String}
}
```

Omit `"read"` for a manual item ("BERTH DEPARTURE PROCEDURE — COMPLY", "HOLD —
DISPOSED OF"). Lambdas are declared inline in the static function; they reference
autoloads (all globals) only, never `self`.

`Status.NA` is for an item that does not apply right now — e.g. the touchdown
limits before the ship is on final, the gear-stow item before the bay is cleared.
It renders dim, not failed.

**Item sources** (each maps to an existing live read; the four lists follow the
handbook's item order and wording so the page and the manual agree):

| List | Auto rows read from |
| --- | --- |
| DEPARTURE | `master_bat`/`master_alt`, `power("THRUST")`, `cargo_hatch_open`, `CargoSystem.cargo_mass()`, `gear_locked_down()`, `run_phase`, `DockingSystem.status()` (`gear_ok`, `outbound`, `state`), `gear_stowed()` |
| ARRIVAL | `wreck["cutting_id"]` + `align_state`, `salvage_pieces.size()`, `cargo_hatch_open`, `run_phase`, `DockingSystem.status()` — `speed_ok`/`lane_ok`/`cleared`/`gear_ok`/`hatch_ok`/`on_pad`/`level`/`drift`/`descent` — and `external_view == "BELLY"` |
| CUTTING | `power("SENSORS")` vs `SalvageSystem.MIN_SENSOR_POWER`, `sensor_mode`, `SalvageSystem.wreck_distance()` vs `SCAN_RANGE`, `wreck["scanned"]`/`["scan_progress"]`, `selected_member_id`, throttle vs `APPROACH_ARM_THROTTLE_MAX`, `approach_state`, `power("CUTTER")` vs `MIN_CUTTER_POWER`, `cargo_hatch_open`, `gear_stowed()`, `align_state`, `structural_risk` |
| COLLECTING | `wreck["cutting_id"]`, `CargoSystem.cargo_mass()`/`cargo_volume()` vs the ship def limits, `cargo_hatch_open`, `DriftSystem.is_collecting()`/`nearest_piece()`, and `DriftSystem.collection_status(piece)` — `in_range`/`speed_ok`/`in_cone`/`scoop`/`gated` |

**One new accessor required.** `SalvageSystem._manual_thrust` is private
([SalvageSystem.gd:118](systems/SalvageSystem.gd#L118)) and nothing else reads
throttle. Add beside `wreck_distance()`:

```gdscript
## The current forward throttle command, 0..1 — what toggle_approach() tests
## against APPROACH_ARM_THROTTLE_MAX. Read-only; for instruments.
func throttle_command() -> float:
    return _manual_thrust.z
```

### New file: `scenes/ui/ChecklistPanel.gd`

`extends Control`, the page. Two states, mirroring `MfdUnit`'s own MENU/page idiom
so it reads consistently:

- **Index** (the default, and where BACK returns): four full-width touch buttons,
  one per list, each showing live progress — `ARRIVAL          7 / 11`.
- **Open list**: a `ScrollContainer` + `VBoxContainer` of rows, with a footer of
  `BACK` and `RESET` (clears this list's manual ticks).

Row rendering keeps the DOCK/SCOOP visual language — label, live value, pass mark
— drawing at `Instrument.ROW` on `Instrument.ROW_PITCH` (Part 3) so this page is
legible on the same terms as the instruments and tunes with them. Rows are
`Control` nodes that `_draw()` themselves rather than one big `_draw()`, because
manual rows must accept taps:

```gdscript
class Row:
    extends Control
    ## Tap (touch or mouse) ticks a manual item. Auto rows set
    ## mouse_filter = MOUSE_FILTER_IGNORE so they cannot be ticked by hand.
    ## Handles ScreenTouch and MouseButton alike, matching InventoryGrid.Tile.
    func _gui_input(event: InputEvent) -> void:   # same shape as Tile/TapButton
```

Marks, using `Instrument.GOOD` / `Instrument.WARN` and a dim accent — the same
trio the DOCK and SCOOP gate rows use, so a green `OK` means the same thing on
every page:

| State | Mark |
| --- | --- |
| `PASS` | `OK`, green |
| `FAIL` | `✗`, amber |
| `NA` | `—`, dim (does not apply yet) |
| manual, untapped | `☐` |
| manual, tapped | `☑`, green |

Group headings render as the manual's blue sub-heading rows.

Redraw on the shared `GameState.tick_changed` (10 Hz) rather than `_process` —
this is a status list, not a flying instrument, and the DOCK/SCOOP pages already
own the per-frame case. Manual ticks clear on `GameState.run_phase_changed` and
`GameState.site_reset` so a new run starts a fresh checklist.

### Registering the page — `scenes/ui/MfdUnit.gd`

- [line 32](scenes/ui/MfdUnit.gd#L32): `PAGES` becomes
  `["CHECKLIST", "POWER", "CARGO", "SALVAGE", "ALIGN", "SCOOP", "MARKET", "DOCK", "CONTACTS"]`.
  First, because it is the page you consult *before* doing a thing; update the
  block comment above it to say so. `default_page` on both units is set explicitly
  in `MfdWindow.tscn`, so neither unit's start page changes.
- [line 178](scenes/ui/MfdUnit.gd#L178) `_build_page()`: add a `"CHECKLIST"` arm
  constructing `ChecklistPanelScript.new()` with `accent`, alongside the other
  script-built pages.
- **No `_auto_page()` hook.** The page is consulted deliberately; it must never
  take the screen from a live mini-game.

---

## Part 2 — Touch-friendly MFD controls

### `scenes/ui/ButtonTheme.gd` — the shared changes

Add named constants (there are currently none anywhere — every size is an inline
literal) and a touch variant, so MFD call sites opt in and the mouse-driven
Tactical / title-card / remapper call sites keep `make_button` unchanged:

```gdscript
## Touch targets on the MFD panel. Sized for a finger on a small screen, in the
## MFD window's 1280x800 virtual canvas.
const TOUCH_MIN_H := 56.0
const TOUCH_MARGIN := 14
const TOUCH_FONT := 18
const TOUCH_SEP := 12

static func make_touch_button(color: Color) -> Button   # make_button + the above
```

`make_touch_button` returns a plain `Button` like `make_button` does, so it drops
into every existing call site unchanged — the only difference is the minimum
height, content margin and font it comes pre-set with. `make_button` itself is not
touched, which is what keeps the Tactical display, title card and remapper at
their current sizes.

### Per-page sizing

| File | Change |
| --- | --- |
| [MfdUnit.gd:161-175](scenes/ui/MfdUnit.gd#L161-L175) `_build_menu()` | Replace the `CenterContainer` + fixed `Vector2(200, 88)` with an expanding `MarginContainer` → `GridContainer`, buttons `SIZE_EXPAND_FILL` with `custom_minimum_size = Vector2(0, 120)`, font 26, h/v separation 16. Nine pages at 2 columns = 5 rows; in the ~622×696 per-unit canvas that yields ~299×126 buttons (vs 200×88 today) with the last cell empty. Filling by flag rather than fixed width also survives the `RoleTabHost` reparent. |
| [MfdUnit.gd:134-142](scenes/ui/MfdUnit.gd#L134-L142) bezel | MENU button via `make_touch_button`, `custom_minimum_size = Vector2(150, TOUCH_MIN_H)`; title font 16 → 18. |
| `AlignPanel.gd:16`, `ScoopPanel.gd:30`, `DockPanel.gd:33` | `FOOTER_H` 52 → 76. This is subtracted from the drawing field (`avail = size.y - FOOTER_H - HEADER_H - CHECKLIST_H`), and Part 3 raises the other two reserves as well — do the layout arithmetic once, in Part 3, with this change already in it. |
| `SalvagePanel.gd:77` | Cut-target rows to `TOUCH_MIN_H`, font 13 → 16. |
| `ContactList.gd:33` | Contact rows to `TOUCH_MIN_H`, font 13 → 16. |
| `SensorModeBar.gd:20-23` | Pass `TOUCH_MARGIN` to `make_toggle_stylebox`, `custom_minimum_size.y = TOUCH_MIN_H`. |
| `InventoryGrid.gd:26` | Jettison 44 → `TOUCH_MIN_H`. Tiles are already 84. |
| `OpsBar.gd:77` | `make_touch_button`. Note this widget is also on the Tactical display, which will get the larger buttons too — acceptable, and worth a line in the commit message. |
| `MarketPanel.gd:121-130` | The densest page (price table × factions, stacked over `CommsLog`). Do this one **last and by measurement** — bump the action buttons to `TOUCH_MIN_H` and font 12 → 15, but verify the table still fits before enlarging the label rows. If it overflows, wrap the table in a `ScrollContainer` rather than shrinking the targets back. |

---

## Part 3 — Instrument text legibility (DOCK, SCOOP, ALIGN)

ALIGN is included with the other two: it is the same family of page, it shares
three of the five duplicated helpers, and leaving it at 12 px while its two
siblings move would make the odd one out.

**The Main flight HUD (`HUDOverlay.gd`) is deliberately out of scope** — it draws
at its own sizes on a different, larger display, and you named the MFDs. Easy to
fold in later if it reads small too.

### New file: `scenes/ui/Instrument.gd`

`extends RefCounted` — the shared drawing vocabulary for the custom-drawn MFD
instrument pages, holding **one type scale** and the five helpers the three pages
currently each keep their own copy of.

```gdscript
## Type scale for the custom-drawn MFD instruments, in the MFD window's
## 1280x800 virtual canvas. One place to tune, because these pages are read at
## arm's length on a small panel while the ship is moving.
const TITLE := 24       ## "NO APPROACH RUNNING" and the like
const HEADING := 20     ## page header, ATC instruction, range
const ROW := 17         ## gate checklist rows, meter labels
const ANNOT := 15       ## field annotations: gate name, ALT/OFF/TILT, sink, closure
const TAG := 13         ## traffic range tags — the smallest thing on the page
const CORNER := 14      ## station / berth corner text
const DETAIL := 16      ## notice sub-line, ATC detail line

## Vertical pitch between gate-checklist rows, and between meters.
const ROW_PITCH := 26.0
const METER_PITCH := 30.0

static func draw_gate(ci: CanvasItem, font: Font, y: float, label: String,
        value: String, ok: bool, accent: Color, label_w: float) -> void
static func draw_notice(ci: CanvasItem, font: Font, title: String,
        detail: String, accent: Color, footer_h: float) -> void
static func draw_meter(ci: CanvasItem, font: Font, pos: Vector2, width: float,
        label: String, value: float, color: Color) -> void
static func draw_diamond(ci: CanvasItem, c: Vector2, r: float, color: Color, width: float) -> void
static func draw_arrowhead(ci: CanvasItem, tip: Vector2, dir: Vector2, r: float, color: Color) -> void

## The GOOD / WARN / BAD trio currently redeclared in DockPanel and ScoopPanel.
const GOOD := Color(0.45, 1.0, 0.55)
const WARN := Color(1.0, 0.62, 0.25)
const BAD  := Color(1.0, 0.38, 0.32)
```

Helpers take the `CanvasItem` to draw into, since a static function has no `self`
to call `draw_string` on.

**The value column is measured, not hardcoded.** Today it is a literal (`x = 92`
in DockPanel, `x = 84` in ScoopPanel) that larger text would overrun. Each page
computes it once per draw from its own widest label:

```gdscript
var label_w := font.get_string_size("CLEARANCE", HORIZONTAL_ALIGNMENT_LEFT, -1,
        Instrument.ROW).x + 16.0
```

so the columns stay aligned at any type size and nobody has to re-tune a literal.

### Per-page edits

| File | Change |
| --- | --- |
| `DockPanel.gd` | Delete the five local helpers and the `GOOD`/`WARN`/`BAD` consts; call `Instrument.*`. Sizes: station/berth 11 → `CORNER`, ATC text 14 → `HEADING`, ATC detail 10 → `DETAIL`, gate name/range 11 → `ANNOT`, traffic tag 9 → `TAG`, sink rate 11 → `ANNOT`, ALT/OFF/TILT 11 → `ANNOT`, notice 18/12 → `TITLE`/`DETAIL`, gate rows 12 → `ROW`. Row pitch 18 → `ROW_PITCH`. `HEADER_H` 52 → 66 (two-line ATC is now 20/14 with leading), `CHECKLIST_H` 108 → **derive**: `5.0 * Instrument.ROW_PITCH + 20.0`. |
| `ScoopPanel.gd` | Same deletions and calls. Header/range 16 → `HEADING`, notice 18/12 → `TITLE`/`DETAIL`, gate rows 12 → `ROW`, closure line 11 → `ANNOT`, meter label 12 → `ROW`. Row pitch 18 → `ROW_PITCH`; the closure and meter offsets below the rows (`y + 74`, `y + 82`) shift with it. `HEADER_H` 34 → 42, `CHECKLIST_H` 116 → **derive**: `4.0 * ROW_PITCH + 60.0` (four gates, plus the closure line and the scoop meter). |
| `AlignPanel.gd` | Delete `_draw_meter`; call `Instrument.draw_meter`. Notice 18/12 → `TITLE`/`DETAIL`, header 16 → `HEADING`, quality 13 → `ROW`. Meter pitch 22 → `METER_PITCH`, quality offset 48 → 64. The `- 40.0` in the field calculation ([AlignPanel.gd:87](scenes/ui/AlignPanel.gd#L87)) is the header reserve — raise to 52. |
| `Instrument.draw_meter` | Track inset 52 → measured from the widest meter label at `ROW`, same reasoning as the gate column. Bar height 12 → 16 so it reads next to 17 px text. |

### The trade this makes, stated plainly

`FOOTER_H` (Part 2) and `HEADER_H` / `CHECKLIST_H` all grow, and all three come
out of the same budget as the cone field:

| Page | Field radius now | After |
| --- | --- | --- |
| DOCK | ~242 px | ~202 px |
| SCOOP | ~247 px | ~209 px |

(per-unit canvas ~622 × 696; `field = clamp(min(size.x * 0.44, avail * 0.5), 24, …)`)

So the aiming field loses about 16% of its radius — `px_per_deg` on the DOCK cone
field goes 2.69 → 2.24. **This is a real cost**, and it is the right way round:
the field is a marker you fly into a ring, which tolerates a coarser scale, while
the checklist is text you must actually read mid-go-around. Both stay far above
the `24.0` floor, so nothing collapses. Judge it on the panel (verification step
5) — if the field feels too tight, the lever to pull is the `size.x * 0.44`
factor, not the type scale.

---

## Part 4 — Documentation (required by CLAUDE.md)

| File | Edit |
| --- | --- |
| `README.md` **The four displays**, MFD row (~line 36) | Add **CHECKLIST** to the page list and describe it: four procedures, live tick-marks, manual items tapped by hand, reached from its own index. |
| `README.md` touch/controls row (~line 449) | Add CHECKLIST to "Everything you can do on an MFD". |
| `README.md` **Handy tool scenes** table | Add the `ChecklistSmoke.tscn` row. |
| [PilotManualContent.gd:404](scenes/displays/PilotManualContent.gd#L404) | Amend the `displays` chapter's MFD line: add CHECKLIST to the page list and one sentence — the page presents the Section 4 procedures against live ship state, items the ship cannot verify are marked off by hand. **Amend, don't add a chapter** (a new chapter would need ≥200 chars of parsed text, and this belongs in `displays`). |

**Do not touch** the four Section-4 checklist chapters. They stay the prose of
record; the page is an instrument that reads the same conditions.

**Boundary rule still binds:** `PilotManualSmoke.HARBOUR_ONLY` forbids ALPHA /
BRAVO / CHARLIE / DELTA anywhere in the handbook. The new sentence must not name a
marker. The *page* may show a marker name at runtime, because that comes live from
`DockingSystem.status()["gate_name"]` — it is data, not published prose.

`TerminalProceduresContent.gd` needs no change: nothing here alters a harbour rule,
charge or limit.

---

## Part 5 — Tests

**Extend [tools/MfdNavSmoke.gd:28](tools/MfdNavSmoke.gd#L28):** add
`_check(pages.has("CHECKLIST"), "the CHECKLIST page is registered")`. The existing
wrap / full-lap / MENU checks then cover the new page automatically.

**New `tools/ChecklistSmoke.gd` + `.tscn`**, following the established
`_check`/`_failures`/`quit(0|1)` idiom (`MfdNavSmoke` is the closest model):

- **Catalog shape** — four lists present by id; every item carries `label`/`want`/
  `group`; group headings contiguous within a list (same reason as the manual:
  an out-of-order item duplicates its heading).
- **Every `read` Callable is valid and survives boot state** — call each one from a
  cold `GameState` and assert it returns a Dictionary with `status` and a non-empty
  `value`. *This is the real regression guard:* an item pointing at a renamed
  `GameState` field or a removed system function fails the build instead of
  silently blanking a row.
- **Auto/manual split** — manual items carry no `read`; every auto item has one.
- **Ticks follow real state**, driven through the real intents:
  `GameState.set_cargo_hatch(true/false)` flips the hatch rows in both directions;
  `set_landing_gear(true)` + advance `gear_position` flips the gear row from
  `FAIL` through to `PASS`; raising `power("CUTTER")` past
  `SalvageSystem.MIN_CUTTER_POWER` flips the cutter row.
- **No hardcoded limits** — assert the cutter row's value string contains
  `str(SalvageSystem.MIN_CUTTER_POWER)` and the scoop range row contains
  `str(DriftSystem.SCOOP_RANGE)`. Changing the constant then fails the test unless
  the row is genuinely reading it.
- **Panel behaviour** — the panel builds; the index shows four buttons; opening a
  list and pressing BACK returns; RESET clears manual ticks; an auto row's
  `mouse_filter` is `IGNORE` (it cannot be hand-ticked).

**Also in `ChecklistSmoke` — the Part 3 layout guard.** Raising three reserves at
once (`FOOTER_H`, `HEADER_H`, `CHECKLIST_H`) is the change most likely to break
quietly on a small unit, so test the arithmetic rather than eyeballing it:

- Each page's checklist reserve actually fits its rows at the current pitch —
  `DockPanel.CHECKLIST_H >= 5.0 * Instrument.ROW_PITCH`, and ScoopPanel's covers
  its four rows plus the closure line and the scoop meter. Raising `ROW_PITCH`
  without re-deriving a reserve then fails the build.
- **Instantiate `DockPanel`, `ScoopPanel` and `AlignPanel`, force each to a
  deliberately cramped size (e.g. 320×240), and step a frame.** The field radius
  must stay positive and finite — `avail` goes negative once the reserves exceed
  the height, and the `maxf(…, 24.0)` floor is what has to catch it. This is the
  regression that would otherwise only show up on the smallest panel someone
  actually uses.

---

## Verification

`godot` is on PATH.

```bash
cd d:/simpit-game
godot --headless res://tools/ChecklistSmoke.tscn    # new
godot --headless res://tools/MfdNavSmoke.tscn       # page registration + nav
godot --headless res://tools/PilotManualSmoke.tscn  # handbook edit, boundary rule
godot --headless res://tools/DockSmoke.tscn         # docking interlocks unchanged
godot --headless res://tools/DriftSmoke.tscn        # scoop gates unchanged
godot --headless res://tools/Phase4Smoke.tscn
godot --headless res://tools/Phase5Smoke.tscn
godot --headless res://tools/DisplayLoadCheck.tscn  # every display scene still loads
```

Then in the running app, which is where the touch work is actually judged:

1. Launch, open the MFD window, tap **☰ MENU** — the 9-button grid should be
   noticeably larger and reachable without aiming.
2. Open **CHECKLIST → CUTTING** on site. Raise CUTTER on the POWER page and watch
   the allocation row flip to `OK` live. Open the cargo hatch and watch the hatch
   row flip on both the CUTTING and COLLECTING lists.
3. Dock at a faction and fly the pattern with **CHECKLIST → ARRIVAL** on the
   secondary MFD while DOCK auto-opens on the primary — the two must never
   disagree about gear, hatch, speed or clearance.
4. Tap a manual row (e.g. "BERTH DEPARTURE PROCEDURE — COMPLY"); tap an auto row
   and confirm nothing happens.
5. **On the actual touch panel**, confirm the MENU grid, the DOCK/SCOOP/ALIGN
   footers, the SALVAGE rows and the CHECKLIST manual rows can all be hit
   first-time without aiming, including near their edges.
6. **Read the DOCK page mid-pattern from your normal seating position**: the gate
   rows, the ATC banner and its detail line, and the traffic range tags. Same for
   the SCOOP gate rows with a piece adrift. This is the check that decides Part 3
   — if any of it still needs a lean-in, raise the `Instrument` constants; they
   are the only thing to change.
7. Judge the shrunken cone field on the same pass (Part 3's stated trade). If it
   is too tight, widen `size.x * 0.44` in `DockPanel._draw` / `ScoopPanel._draw`
   rather than taking the type back down.
8. Check the MARKET page has not overflowed at the panel's real resolution.
