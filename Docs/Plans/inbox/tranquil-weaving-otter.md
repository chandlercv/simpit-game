# Simpit UI restructure — MFDs, read-only Tactical, external-camera window

## Context

The current four displays mix "things you touch" and "things you read" on every
screen, with wide margins/separations that waste space and blur what each panel
is *for* (the user's "too much white space, functions are muddled"). This change
re-sorts the panels along a single axis — **interactive controls vs. read-only
instruments** — and repurposes the star-chart screen (a static placeholder) into
a genuinely useful **external camera**. It also fulfils the project's stated
principle that *any* command reachable by touch is also bindable to the HOTAS
(README "any input surface can drive the same intent"), which today holds only
for approach/cut.

### Target layout (stays 4 display roles)

| Role (string) | Was | Becomes |
| --- | --- | --- |
| `main` | hull-cam + HUD | unchanged |
| `tactical` | scope + sensor/ops buttons + risk + contacts | **read-only, mode-switched**: SCOPE mode (scope + hull heatmap + risk + contact readout) and CHART mode (star chart) |
| `tablet` → **`mfd`** | cargo + heatmap + power | **two side-by-side MFD units**, each with a top-level MENU and pages POWER / CARGO / SALVAGE / MARKET / CONTACTS |
| `chart` → **`camera`** | 2D star chart + market + comms | **external camera**: rear (looking aft) / side / chase / top-down of own ship, selectable by mapped control |

Design decisions already confirmed with the user: split one screen into two
MFDs (4 roles kept); MFD pages = Power, Cargo, Salvage cut-list, Approach/Cut +
Sensor-mode, Market+Comms, and **Contacts**; every MFD unit has a **top-level
MENU** (home) so any page is one tap away rather than cycled through; camera
views selectable by **both** a cycle action and four direct-select actions, with
**REAR looking aft** (a rear-view of the space behind the ship).

Guiding rule for the "white space" complaint: in every rebuilt panel, tighten
`MarginContainer` margins (currently 20–24 px) and `separation` (16–28 px) to a
consistent compact scale (≈12 px margins, 8–10 px separation), matching
`ControlsSetup`/`RoleTabHost` density.

---

## Phase 1 — Role rename plumbing (`tablet`→`mfd`, `chart`→`camera`)

Roles are data-driven strings, so this is mechanical:

- `autoload/DisplayConfig.gd:20-25` — rename `ROLE_TABLET`→`ROLE_MFD := "mfd"`,
  `ROLE_CHART`→`ROLE_CAMERA := "camera"`; update `ALL_ROLES`.
- `autoload/WindowManager.gd:15-19` `SECONDARY_SCENES` — keys `"mfd"` →
  `MfdWindow.tscn`, `"camera"` → `CameraWindow.tscn`; `"tactical"` unchanged.
- `tools/DisplayLayoutSmoke.gd:83,91,104-110` — hardcoded `"tablet"`/`"chart"`
  names/indices → new names.
- Window titles / `role_name` exports in the rebuilt `.tscn`s.
- **Config migration:** saved `user://display_config.cfg` is keyed by role
  string inside a per-setup section; old `tablet`/`chart` keys simply won't be
  read and the setup re-prompts once (acceptable). Optionally map old→new keys
  in `DisplayConfig.reload()` to avoid the re-prompt — note in the PR, low
  priority.

## Phase 2 — MFD framework + modes (the interactive panel)

New `scenes/displays/MfdWindow.tscn` (RoleWindow.gd + `Root` Control so
`WindowManager._harvest_content` still works): `Root → Margin → HBox` holding
**two `MfdUnit` instances**, `size_flags_horizontal = FILL` each.

New `scenes/ui/MfdUnit.gd` (+ `.tscn`) — a self-contained page host modeled on
`RoleTabHost`'s show-one-at-a-time pattern but per-unit:
- A **top-level MENU (home) page**: a grid of large page buttons (POWER, CARGO,
  SALVAGE, MARKET, CONTACTS) so any page is one tap away — no cycling. A compact
  `MENU` button on every page's bezel returns home; the current page name is
  shown in the bezel. This is the primary navigation the user asked for.
- A content area that swaps page panels, each reusing an existing widget:
  - **POWER** → existing `scenes/ui/PowerSliders.tscn` (unchanged).
  - **CARGO** → existing `scenes/ui/InventoryGrid.tscn` (unchanged).
  - **MARKET** → existing `MarketPanel.tscn` + `CommsLog.tscn` (moved off the old
    chart window).
  - **SALVAGE** → **new** `scenes/ui/SalvagePanel.gd` (see below), plus
    `SensorModeBar` and the approach/cut buttons from `OpsBar` folded in.
  - **CONTACTS** → existing `scenes/ui/ContactList.gd` (moved off Tactical; keeps
    its click-to-lock — this is where contact locking now lives).
- Each unit exports a `default_page` so the two units start on different pages
  (e.g. left=POWER, right=SALVAGE). `current_page` / `go_home()` are public so
  mapped controls (Phase 5) can jump or return to menu.
- Two instances of any widget scene are fine (they only read GameState + call
  intents); no shared-node assumptions to break.

New `scenes/ui/SalvagePanel.gd` — the cut-target list, **built by copying the
`ContactList.gd` pattern** (a `VBoxContainer` of `Button` rows):
- Iterate `GameState.wreck["members"]`; each row shows name + load class +
  predicted risk (reuse `SalvageSystem.load_class()` / `predicted_spike()`), and
  on `pressed` calls `SalvageSystem.select_member(member["id"])` (same intent the
  scope used at `TacticalScope.gd:68`).
- Highlight the row equal to `GameState.selected_member_id`; refresh on
  `selected_member_changed`, `wreck_scanned`, `wreck_member_cut`,
  `wreck_members_lost`, `site_reset`. Disable cut/destroyed rows (mirrors the
  guard in `SalvageSystem.select_member`, `SalvageSystem.gd:90-97`).

## Phase 3 — Tactical becomes a read-only mode host

Rebuild `scenes/displays/TacticalWindow.tscn` around a mode host (reuse the
`RoleTabHost`-style switcher, or a slim `MfdUnit` in a read-only skin):
- **SCOPE mode**: `TacticalScope` (left) + `HullHeatmap` (moved here from the old
  tablet) + `RiskMeter` (right). The scope still *draws* contact blips (a
  read-only instrument), but the interactive contact **list** moves to the MFD
  CONTACTS page.
- **CHART mode**: `StarChart` (moved here from the old chart window; keeps mouse
  pan/zoom — "non-touch" means no dedicated touchscreen required, not no mouse).
- Remove the interactive controls that moved to the MFD: delete `SensorModeBar`,
  `OpsBar`, and `ContactList` from this window, and **retire the STRUCT
  click-select branch** in `TacticalScope._gui_input` (`TacticalScope.gd:65-71`) —
  the scope is now a pure instrument. Contact locking now lives on the MFD
  CONTACTS page (plus a mapped `contact_cycle` action, Phase 5).
- Nothing else breaks: `OpsBar`/scope already read `selected_member_id` and
  `tracked_contact_id` from GameState; only the *input* origin changes.

## Phase 4 — External-camera window (the repurposed chart screen)

New `scenes/displays/CameraWindow.tscn` — copy `MainViewWindow.tscn`'s
`SubViewportContainer → SubViewport` structure, **without** `own_world_3d`
(it will share the Main world), plus a thin overlay label (current view name +
tick) and a `StatusStrip`.

Shared-world wiring (the one genuinely novel piece — the 3D world lives only in
Main's SubViewport, `own_world_3d = true`):
- Have `MainViewWindow` publish its `World3D` after `_wire_hud` — simplest is a
  tiny accessor on `WindowManager` (e.g. `WindowManager.main_world_3d()` that
  reaches the primary window's `%SubViewport.world`) or a one-line registry set
  from `MainViewWindow.gd`.
- `CameraWindow` on ready assigns `subviewport.world_3d = <shared>` and adds its
  **own** `Camera3D` nodes under its viewport (so they belong to *its* viewport
  but render the shared world). Only one `current` at a time.

New `scenes/world/ExternalCameraRig.gd` (lives under the CameraWindow viewport):
- Each frame reads the authoritative pose `GameState.local_ship()["transform"]`
  (same source as `Ship.gd:18`) and places the active camera at an offset for
  the current view — **rear** (mounted aft, **looking backwards** at the space
  behind the ship — a rear-view, not a chase), **side** (offset to one side
  looking at the ship), **chase** (behind + above, trailing, looking forward),
  **top-down** (above, looking straight down). Reuse `HullCameraRig.gd`'s
  exponential-ease math (`HullCameraRig.gd:33`) for smooth transitions when the
  view switches.
- Reads a new `GameState.external_view` string; switches `current` camera to
  match.

New GameState surface (follow the `sensor_mode` pattern at
`GameState.gd:298-303`):
- `const EXTERNAL_VIEWS := ["REAR","SIDE","CHASE","TOP"]`, var `external_view`,
  `signal external_view_changed(view)`, `set_external_view(view)` and a
  `cycle_external_view()` helper.

## Phase 5 — Make every MFD/camera command mappable

Pattern for each new command (confirmed via `ControlsSetup.gd` +
`InputRouter._process`): (a) add the action to `project.godot [input]` with an
optional keyboard fallback event (append after `configure_controls`, line 141 —
`InputMap.action_add_event` on an *undefined* action errors, so the entry must
exist); (b) add a row to `ControlsSetup.gd` `BUTTON_TARGETS` (or `AXIS_TARGETS`)
with a `group`; (c) consume in `InputRouter._process()`.

New **button** actions (edge-triggered → intent), grouped in the remapper:

| Group | Action(s) | Intent consumed |
| --- | --- | --- |
| MFD | `mfd_a_menu`, `mfd_b_menu` (jump each unit to its MENU home) + `mfd_a_page_next`/`prev`, `mfd_b_page_next`/`prev` | `MfdUnit.go_home()` / step `current_page` |
| SALVAGE | `salvage_prev`, `salvage_next` | new `SalvageSystem.cycle_member(±1)` over cuttable members → `select_member` |
| SALVAGE | `sensor_mode_cycle` | `GameState.set_sensor_mode(next)` |
| MARKET | `market_dock`, `market_sell`, `market_depart` | `MarketSystem.request_dock/sell_hold/request_undock` |
| CARGO | `cargo_prev`, `cargo_next`, `cargo_jettison` | select + `CargoSystem.jettison` |
| VIEW | `view_cycle` + `view_rear`/`view_side`/`view_chase`/`view_top` | `GameState.cycle_external_view()` / `set_external_view(v)` |
| OPS | `contact_cycle` | cycle `set_tracked_contact` over contacts |

(The MENU home is the primary "jump to any page" path for touch; the `mfd_*_menu`
+ `page_next/prev` actions give the HOTAS the same reach. Per-page direct-select
actions can be added later if a HOTAS user wants one button per page.)

(`ops_approach`/`ops_cut` already exist — surface them as before.)

New **axis** actions for the four power channels (grouped POWER) — a bound axis
takes slider-like authority: `power_thrust`, `power_cutter`, `power_sensors`,
`power_life`, each an `AXIS_TARGETS` pair (or single-direction) → in
`InputRouter._process` call `GameState.set_power(channel, value)` **only when the
action actually has bound events** (`InputMap.action_get_events(a).size() > 0`),
so an unbound power axis doesn't peg the channel to 0 and fight the switch
panel/touch. Note this last-writer interaction in code comments.

Add the matching HOTAS defaults to `BUILTIN_PROFILES` (`InputRouter.gd:39-74`)
only if we want out-of-box bindings; otherwise leave blank for the user to bind
via F7.

## Phase 6 — README + smoke tests

- **README.md** (contributor rule requires same-change sync): rewrite **The four
  displays** table (mfd/camera roles, two MFDs, tactical modes); the **Controls**
  tables + **Remapping** section (all new bindable rows); **Core gameplay loop**
  step 3 ("Pick a cut target" now on the MFD salvage list, not the scope) and the
  power/sensor references ("on the tablet" → "on an MFD"); **Simpit /
  multi-display setup** role names; **Handy tool scenes** if `DisplayLayoutSmoke`
  assertions change. Replace now-false statements in place (e.g. "click a wreck
  member on the scope", "Touch sliders … on the tablet").
- Update `tools/DisplayLayoutSmoke.gd` role names; optionally add a headless
  smoke that instantiates `MfdWindow` and asserts each unit switches modes, and
  that `CameraWindow` binds the shared world.

---

## Critical files

- Roles/windows: `autoload/DisplayConfig.gd`, `autoload/WindowManager.gd`,
  `scenes/displays/RoleTabHost.gd` (pattern), `scenes/displays/RoleWindow.gd`.
- New scenes: `scenes/displays/MfdWindow.tscn`, `scenes/ui/MfdUnit.gd/.tscn`,
  `scenes/ui/SalvagePanel.gd`, `scenes/displays/CameraWindow.tscn`,
  `scenes/world/ExternalCameraRig.gd`.
- Reused widgets (unchanged or lightly themed): `scenes/ui/PowerSliders.*`,
  `InventoryGrid.*`, `MarketPanel.*`, `CommsLog.*`, `HullHeatmap.gd`,
  `RiskMeter.gd`, `SensorModeBar.gd`, `OpsBar.gd`, `StarChart.gd`,
  `ContactList.gd` (the list-of-buttons template for `SalvagePanel`).
- Rebuilt windows: `scenes/displays/TacticalWindow.tscn`, `TacticalScope.gd`
  (drop STRUCT click branch).
- Input: `project.godot [input]`, `autoload/InputRouter.gd`,
  `scenes/displays/ControlsSetup.gd`, `autoload/GameState.gd` (external_view +
  helpers), `systems/SalvageSystem.gd` (`cycle_member`), `systems/CargoSystem.gd`,
  `systems/MarketSystem.gd` (intents already exist — just surface them).
- Camera world wiring: `scenes/displays/MainViewWindow.gd/.tscn`.

## Verification

1. **Run** `scenes/boot/Boot.tscn` in Godot 4.7. Confirm 4 windows: Main
   unchanged; MFD screen shows two independently-switchable MFD units; Tactical
   toggles SCOPE↔CHART and has no touch controls; Camera screen shows the ship
   from an external view.
2. **Camera**: cycle `view_*` actions (or map them via F7) — rear/side/chase/top
   all render the shared world and track the ship as it flies.
3. **Salvage flow**: scan a wreck (STRUCT + SENSORS power), pick a member from the
   MFD SALVAGE list (and via `salvage_next`/`prev`), approach, cut — risk still
   spikes; `OpsBar`/scope reflect selection. Confirms the decoupled
   `selected_member_id` path is intact.
4. **Mapping**: press F7 — every new command appears as a bindable row under its
   group; bind one button/axis per group and exercise it. Power axis only drives
   its channel when bound.
5. **Headless**: `godot --headless res://tools/DisplayLayoutSmoke.tscn` (updated
   names) and any new MFD/camera smoke pass.
6. **Screenshot** the Main view via `tools/ScreenshotCheck.tscn` to confirm no
   regression there.
7. Confirm README no longer contains false statements (grep for "tablet",
   "click a wreck member", "star chart" placement).
