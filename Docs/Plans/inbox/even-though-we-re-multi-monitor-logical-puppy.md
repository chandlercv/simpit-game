# Tiled display layouts for 1- and 2-monitor rigs

## Context

Salvager is built for a four-screen simpit: four logical roles (`main`,
`tactical`, `mfd`, `camera`) each get a native OS window on their own monitor.
When there are fewer screens than roles, the overflow currently collapses into a
**tabbed host** — one panel visible at a time:

- **1 monitor** — all three secondary roles land on the Main screen and become a
  *dimmed full-screen overlay* over the live hull-cam view
  ([WindowManager.gd:232-240](autoload/WindowManager.gd#L232-L240)). You either
  fly, or you read an instrument. Not both.
- **2 monitors** — `main` on screen 0, all three secondaries packed onto screen 1
  as an opaque tabbed host
  ([WindowManager.gd:216-229](autoload/WindowManager.gd#L216-L229)). One of the
  three, ever.

That is a poor deal for anyone not on the full rig. The fix is to **tile** shared
screens instead of tabbing them, so every display a screen hosts is visible and
usable at once:

- **1 monitor** — the Main flight view keeps the **top two-thirds**; the bottom
  third is split into three equal tiles holding tactical, MFD and camera.
- **2 monitors** — Main is fullscreen on screen 0; screen 1 carries tactical and
  camera across the top row with the MFDs spanning the full width below.

A secondary benefit falls out of doing this with real windows rather than
reparented content: each display scene's `Window` node carries its own
`content_scale_size` (1280×720, or 1280×800 for the MFDs) with
`CONTENT_SCALE_MODE_CANVAS_ITEMS` + `CONTENT_SCALE_ASPECT_EXPAND`. That is the
mechanism that keeps a panel legible at a smaller physical size, and
[`_harvest_content()`](autoload/WindowManager.gd#L247-L254) throws it away — so
today a docked panel renders at 1:1 physical pixels and `StatusStrip`'s
`offset_right = 700` assumption silently breaks. Tiling with the scenes' own
`Window` nodes fixes that for free, and brings `RoleWindow.gd`'s Esc/close
handling along with it.

## Decisions taken

| | |
| --- | --- |
| Bottom strip | Bottom **1/3** of the Main screen, split into **equal** tiles in `ALL_ROLES` order (TACTICAL │ MFD │ CAMERA) |
| Spare screen, 3 roles | Top row split between tactical and camera; **MFD full width on the bottom row** — it is the display you reach for, and two MFD units want the width |
| Spare screen, 2 roles | Two full-width rows; the MFD-preferring role takes the bottom |
| Spare screen, 1 role | Unchanged — full-coverage borderless, exactly as today |
| Collapse key | **None.** The strip is permanently allocated; no new binding |

## Approach

### 1. New pure layout planner — `scenes/displays/ScreenLayout.gd`

A `class_name ScreenLayout` with **static functions only** and **no
`DisplayServer` calls**, so it is fully testable under `--headless`.

```gdscript
const DOCK_FRACTION := 1.0 / 3.0
## A tile below 0.45x the 1280x720 design canvas can't render a panel legibly.
const MIN_TILE := Vector2i(576, 324)
const DESIGN_CANVAS := Vector2i(1280, 720)
## Which role takes the full-width bottom row of a shared spare screen.
const WIDE_ROW_PRIORITY: Array[String] = ["mfd", "tactical", "camera"]

## rect: the screen's rect. has_main: whether MAIN lives on this screen.
## roles: the secondary roles on it, in ALL_ROLES order.
## Returns { main_fullscreen: bool, main: Rect2i, tiles: {role: Rect2i},
##           tab_region: Rect2i, tab_roles: Array[String] }
static func plan_screen(rect: Rect2i, has_main: bool, roles: Array) -> Dictionary
```

Rules:

- `has_main` and no secondaries → `main_fullscreen = true`, nothing else.
- `has_main` with N secondaries → `main` = top `1 - DOCK_FRACTION` of `rect`;
  the bottom strip splits into N equal columns in the given order. The last
  column absorbs integer-division remainder so the tiles exactly cover the strip.
- No main, 1 role → that role gets the whole `rect`.
- No main, N ≥ 2 roles → the first role of `WIDE_ROW_PRIORITY` present takes the
  full-width **bottom** row; the remaining N−1 split the **top** row into equal
  columns in `ALL_ROLES` order.
- **Legibility floor**: if any computed tile is smaller than `MIN_TILE` on either
  axis, discard `tiles` and return the region as `tab_region` + `tab_roles`
  instead. All-or-nothing per region.

Sanity check of the floor against real resolutions: 1920×1080 strip thirds are
640×360 ✓; 2560×1440 → 853×480 ✓; 1600×900 → 533×300 ✗ and 1366×768 → 455×256 ✗,
both correctly falling back to a tabbed strip.

The floor is set by the **MFDs**, whose canvas is the tallest at 1280×800: in a
wide, short tile `CONTENT_SCALE_ASPECT_EXPAND` picks the smaller ratio, so a
640×360 tile scales the MFD by `min(640/1280, 360/800)` = **0.45**, putting
`MENU_BUTTON_H` ([MfdUnit.gd:40](scenes/ui/MfdUnit.gd#L40)) at 54 physical px and
`MENU_FONT` at ~12 px. Legible, and deliberately the worst case `MIN_TILE`
allows — hence 0.45 rather than a rounder number.

### 2. `autoload/WindowManager.gd` — place from the plan

- `_place_all()` ([:173-195](autoload/WindowManager.gd#L173-L195)): group roles
  by screen as it does now, then for each screen call `ScreenLayout.plan_screen`
  and realize the result — `_spawn_window(role, rect)` per tile, or
  `_spawn_packed_window(tab_roles, tab_region)` on the fallback path.
  **Watch the empty-main case**: `by_screen` is built from `SECONDARY_SCENES`, so
  when Main has its screen to itself there is no `by_screen` entry for it. Plan
  the main screen explicitly (with `roles = []`) rather than only inside the
  loop, or a four-monitor rig never gets its main window positioned.
- `_position_main_window()` ([:198-203](autoload/WindowManager.gd#L198-L203))
  takes the plan. Fullscreen branch is unchanged; the shared branch must set
  `mode = Window.MODE_WINDOWED` **before** `borderless`/`position`/`size`, since
  Godot ignores geometry writes while a window is fullscreen. The F5 rebuild path
  must be able to go windowed→fullscreen too, so both directions set `mode`
  explicitly.
- `_spawn_window(role, screen)` → `_spawn_window(role, rect: Rect2i)`. Body is
  otherwise unchanged; the scene's own `content_scale_*` is preserved.
- `_spawn_packed_window(roles, screen)` → `(roles, rect)`, and while it is being
  touched, fix its two latent defects: give the host `Window` a
  `content_scale_mode`/`aspect`/`size` of `ScreenLayout.DESIGN_CANVAS` so
  harvested panels stop rendering at 1:1, and `set_script(RoleWindowScript)`
  **before** `add_child` so it gets `close_requested`/Esc like every other
  secondary window.
- New `_screen_rect(screen: int, tiled: bool) -> Rect2i`: `tiled` screens use
  `DisplayServer.screen_get_usable_rect(screen)` because ordinary borderless
  windows sit *under* the Windows taskbar; full-coverage cases (main fullscreen,
  lone role on a spare screen) keep `screen_get_position/size` so the verified
  four-monitor behaviour is bit-for-bit unchanged.
- Delete `_make_overlay_host()` ([:232-240](autoload/WindowManager.gd#L232-L240)).
  **Keep `_ensure_overlay_layer()`** ([:271-280](autoload/WindowManager.gd#L271-L280))
  and the `_overlay_layer` teardown — the display chooser still uses that
  CanvasLayer ([:153](autoload/WindowManager.gd#L153)); only the tab host leaves it.
- Update the header doc-comment ([:13-20](autoload/WindowManager.gd#L13-L20)),
  which currently specifies the tabbed-host rules.

### 3. `scenes/displays/RoleTabHost.gd` — drop overlay mode

Under the new rules a role on the Main screen always lands in the bottom strip,
so the dimmed-overlay mode is unreachable. Delete it rather than leave dead code
whose doc-comment describes behaviour that no longer happens: remove the
`_opaque` flag, `_scrim` transparency branch, the `MAIN` button, `show_main()`,
`_toggle()` and the backtick handling; `configure()` loses its argument. What
remains is the small-screen fallback host — opaque, always showing a panel,
F1/F2/F3 + `Tab`. Rewrite the header comment to say only that.

### 4. Documentation (required by [CLAUDE.md](CLAUDE.md))

- [README.md:729-733](README.md#L729-L733) — the intro claims fewer screens
  "share one via a **tabbed host**". Rewrite for tiling.
- [README.md:750-755](README.md#L750-L755) — the "How shared screens look"
  bullet is now false end to end (dimmed overlay, `MAIN` tab, backtick).
  Replace with the bottom-third strip, the spare-screen row split, and the
  tabbed fallback on screens too small to tile.
- [README.md:782](README.md#L782) — "packs the overflow into a tabbed host".
- [README.md:28-30](README.md#L28-L30) — add a sentence to **The four displays**
  noting that on fewer screens the windows are tiled rather than given a monitor
  each. "Each is its own OS window with its own input stream" stays true.
- [DisplaySetup.gd:78-87](scenes/displays/DisplaySetup.gd#L78-L87) — the chooser
  hint text describes the tabbed host and the dimmed overlay.
- [TitleCard.gd:392](scenes/displays/TitleCard.gd#L392) — the summary line
  "displays sharing a screen open as a tabbed panel".
- `autoload/DisplayConfig.gd` comments at
  [:13-14](autoload/DisplayConfig.gd#L13-L14),
  [:95](autoload/DisplayConfig.gd#L95) and
  [:178-179](autoload/DisplayConfig.gd#L178-L179) — all three describe the tabbed
  host, and the last names the dimmed overlay explicitly. No logic changes in
  this file; `_fill_defaults()` already packs overflow onto the last screen,
  which is exactly the input the new planner wants.
- No Controls-table change: no new binding. F1/F2/F3/`Tab` survive on the
  fallback host only; backtick disappears with overlay mode.
- **No ship-document change.** The handbook's THE FOUR DISPLAYS chapter
  ([PilotManualContent.gd:548-577](scenes/displays/PilotManualContent.gd#L548-L577))
  describes what each display *presents*, never how many monitors there are or
  how they share one — nothing in it becomes false.

## Verification

```
godot --headless res://tools/DisplayLayoutSmoke.tscn
godot --headless res://tools/DisplayLoadCheck.tscn
```

Extend [tools/DisplayLayoutSmoke.gd](tools/DisplayLayoutSmoke.gd) with a
`_test_layout_planner()` — the planner is pure, so every case is asserted without
a display server:

- 1920×1080, main + 3 roles → `main` = `(0,0,1920,720)`, `main_fullscreen` false,
  tiles `(0,720,640,360)` / `(640,720,640,360)` / `(1280,720,640,360)`.
- Same, main alone → `main_fullscreen` true, `tiles` empty.
- Spare 1920×1080, 3 roles → `mfd` = `(0,540,1920,540)`, `tactical` =
  `(0,0,960,540)`, `camera` = `(960,0,960,540)`.
- Spare, 2 roles (mfd + camera) → mfd full-width bottom, camera full-width top.
- Spare, 1 role → the whole rect.
- 1366×768 main + 3 roles → `tiles` empty, `tab_region` = the bottom strip.
- **Invariants** over a handful of rects and role counts: tiles never overlap,
  and their union exactly equals the region (catches the rounding remainder).

Adjust `_test_harvest_and_host()` ([:87-133](tools/DisplayLayoutSmoke.gd#L87-L133)):
drop the overlay-mode half, keep the opaque host, and add an assertion that the
fallback host window carries a non-zero `content_scale_size`.

Then run it for real — the layouts are geometry, so they need eyes:

1. **1 monitor**: unplug/disable all but one screen, `F5`. Confirm the flight
   view occupies the top two-thirds with the HUD reflowed to it (bottom-anchored
   VEL/HDG/EL sit just above the strip, the nose reticle still reaches the edge
   at full glance deflection), three panels tile the bottom third, all three take
   mouse input, and the camera tile renders the world rather than black — it
   borrows the Main `World3D` through `WindowManager.main_world_3d()`.
2. **2 monitors**: confirm Main is fullscreen on screen 0 and screen 1 shows
   tactical + camera over a full-width MFD, and that the Windows taskbar does not
   cover the bottom row.
3. **4 monitors** (the real rig): confirm nothing changed — one full-coverage
   borderless window per screen, Main fullscreen.
4. `F5`/`F6` round-trips between those topologies, including
   windowed→fullscreen when going back up to four screens.

---

## Revisions made during implementation

A design review landed after approval and pressure-tested the plan. Three of its
findings were adopted, three rejected after checking the numbers.

**Adopted**

- **Overlay mode is NOT deleted.** It is the tier below tiling for a screen too
  short to carry a strip at all (a 1366×768 laptop's bottom third is 240px). The
  plan was wrong to call it unreachable.
- **`_restore_main_window()`** — `_show_setup()`/`_show_title()` tear down the
  strip and then paint on a Main window still sized to two-thirds height, leaving
  the bottom third showing the desktop. Both now restore fullscreen first. Not
  inside `_teardown()`, which `_place_all()` also calls and would flash on F5.
- Window hygiene: `unresizable` (Aero Snap can't drag a tile out of its rect),
  explicit `initial_position`, `transient` left default, and `mode` set before
  geometry.

**Rejected**

- **The `host_canvas` clamp** (clamp `content_scale_size` so scale is never below
  1.0). It trades a working layout for a broken one: clamped, a 640×344 tile gives
  the MFD only 344 logical px of height for a MENU grid whose minimum is 664
  ([MfdUnit.gd:40](scenes/ui/MfdUnit.gd#L40)), which overflows. Unclamped, the same
  tile gives it 1488×800 logical — its authored canvas — drawn at 0.43×. Small
  type beats a broken grid, and downscaling is what the scenes' `EXPAND` content
  scale was authored for.
- **"1080p single-monitor must be a docked tabbed strip, not three tiles."** The
  opposite: a 640×344 *tile* is aspect 1.86:1 against a 1.78:1 canvas, giving
  logical 1340×720 — essentially the authored size. One full-width 1920×344 strip
  is 5.6:1, giving logical 4019×720 and stretching the composition across three
  times its design width. Tiling wins on the measurement.
- **A scoring function to derive arrangements.** The arrangements were chosen
  explicitly; a scorer picked a different spare-screen layout than the one asked
  for. Kept as an explicit table.

**Consequent changes to the design**

- The legibility floor is `ScreenLayout.MIN_SCALE = 0.42` (a fraction of each
  role's own canvas) rather than a `MIN_TILE` pixel size — it states the rule it
  enforces, and reads per-role so the 1280×800 MFDs are measured against 800.
- Two tiers, not three: tile, else the tab host that region already used before
  this change. No new intermediate "docked tab strip" tier.
- No `RoleTabHost` hotkey change and no new input actions: the tab host never
  moves into a new focus context, so `_input` still reaches it exactly as before.

**Left alone, deliberately**

- `RoleWindow.gd` still quits on Esc from any secondary window. Tiles sit closer
  to the flight view on one monitor, so a stray Esc is likelier — but changing
  quit behaviour was not asked for and the rig relies on it. Worth a follow-up.
