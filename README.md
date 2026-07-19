# Salvager

A cyberpunk mercenary **salvage sim** built for a multi-display hardware simpit.
One process drives one native window per monitor — an external hull-camera view,
a tactical scope, a systems tablet, and a market chart — fed by a HOTAS,
a Saitek switch panel, and touch/mouse on the secondary screens.

> Status: Phases 1–5 complete and hardware-verified. Engine: Godot 4.7
> (Forward+). Main scene: `scenes/boot/Boot.tscn`.

![Main hull-camera view: a derelict frigate at cutting range with the target
reticle and velocity/heading HUD.](assets/docs/main_view.png)

*The Main display — an external hull-camera feed of the wreck at cutting range,
with the thin flight HUD (velocity, heading/elevation, locked target).*

---

## The four displays

Displays are assigned to physical screens by role (see `autoload/DisplayConfig.gd`;
roles are re-labelled with `tools/ScreenLabeler.tscn`). Each is its own OS window
with its own input stream.

| Role | Window | What it shows | How you interact |
| --- | --- | --- | --- |
| **Main** | `MainViewWindow` | Edge-to-edge hull-camera feed of the 3D world (ship, wreck, debris) with a thin HUD. | Flight + camera glance (HOTAS / keyboard). |
| **Tactical** | `TacticalWindow` | Sensor scope, contact list, structural risk meter, sensor-mode + ops controls. | Mouse/touch: sensor mode, approach, cut, **click a wreck member to select it**. |
| **Tablet** | `TabletWindow` | Power sliders, cargo inventory grid, hull-damage heatmap. | Touch sliders for the four power channels. |
| **Chart** | `StarChartWindow` | Market price feed, comms/mission log, star chart. | Mouse/touch: dock, sell hold, depart. |

---

## Core gameplay loop

You fly a salvage ship to a wreck, cut it apart for cargo without letting the
frame collapse on you, then dock and sell. On site (`ON_SITE` phase):

1. **Scan the wreck.** On the Tactical display set sensor mode to **STRUCT**,
   allocate **SENSORS** power on the tablet, and close inside 300 u. A full
   structural scan takes ~5 s at 100% SENSORS and reveals the wreck's member
   graph (which parts carry frame stress).
2. **Approach & match velocity.** Trigger the approach autopilot. It flies you
   to a standoff just inside cutting range (14 u) and matches the wreck's
   velocity → state goes `HOLDING` → `APPROACHING` → `MATCHED`.
   *The throttle must be eased back under ~40% to arm the autopilot, and any
   real stick/throttle input while it's flying hands control back to you.*
3. **Pick a cut target.** Click a structural member on the Tactical scope.
   The overlay shows each member's load class and the risk spike cutting it
   would cause.
4. **Power the cutter.** Raise the **CUTTER** power channel to at least 0.2 on
   the tablet.
5. **Cut.** With the approach `MATCHED`, fire the cutter. The member severs over
   time and its salvage is stowed in the hold.
6. **Watch structural risk.** Cutting load-bearing members spikes risk and
   ratchets the resting baseline up; cosmetic panels barely move it. If the
   frame collapses, every uncut member is lost.
7. **Dock and sell.** On the Chart display, dock at a faction (this leaves the
   claim), sell your hold at that faction's prices, then depart back to the
   claim for a fresh wreck.

**Power budget:** four channels — **THRUST, CUTTER, SENSORS, LIFE** — each
0..1. The reactor can't run everything at full; the tablet header turns red on
overdraw. THRUST gates approach/manual acceleration, CUTTER gates cutting,
SENSORS gates scan speed.

---

## Controls

The physical rig is a **Saitek X55 Rhino stick** + **Saitek X52 throttle** +
**Saitek Pro Flight Switch Panel**. Devices are matched by GUID at runtime
(`autoload/InputRouter.gd`), so replugging never rebinds anything. Everything
also has a keyboard/mouse fallback so the game is playable at a desk.

### X55 Rhino stick (flight + cutter + camera)

| Control | Action |
| --- | --- |
| Stick **left / right** (axis 0) | Yaw left / right |
| Stick **forward / back** (axis 1) | Pitch down / up (pull back = nose up) |
| Stick **twist** (axis 2) | Roll left / right |
| **Trigger** (button 0) | **Fire cutter** (`ops_cut`) |
| **POV hat** | **Glance** the hull camera — hold a direction to look that way, release to recenter. Read over raw HID to dodge the stick's always-held selector button. |

> Buttons 14–16 are the stick's selector-position bank (one is always held) —
> reserved, never bind actions to them.

### X52 throttle (thrust + approach)

| Control | Action |
| --- | --- |
| **Throttle lever** (axis 2) | Forward thrust. Idle near the top; push forward to accelerate. Folds into the ship's forward thrust and must sit under ~40% travel to arm the approach autopilot. |
| **Button 7** (Fire E) | **Toggle approach / match-velocity** (`ops_approach`) |

> Buttons 23–25 are reserved selector-bank buttons.

### Saitek Pro Flight Switch Panel (raw HID)

The panel never enumerates as a joystick; it's read directly over HID
(`systems/hardware/SwitchPanelBridge.gd`). All 20 switches post their state to
the comms log, but only these are wired to gameplay today:

| Switch | Effect |
| --- | --- |
| **MASTER BAT** | Off = cut all reactor power (zeros every channel); On = restore the previous allocation. |
| **NAV** | Ship nav lights on/off. |
| **LANDING** | Ship landing light on/off. |

The remaining switches — MASTER ALT, AVIONICS, FUEL PUMP, DE-ICE, PITOT HEAT,
COWL, PANEL, BEACON, STROBE, TAXI, the 5-position magneto (OFF/R/L/BOTH/START),
and the GEAR UP/DOWN lever — are decoded and logged but have no gameplay effect
yet.

### Keyboard fallback (main window focus)

| Key | Action | | Key | Action |
| --- | --- | --- | --- | --- |
| **W / S** | Thrust forward / back | | **I / K** | Pitch up / down |
| **A / D** | Strafe left / right | | **J / L** | Yaw left / right |
| **R / F** | Thrust up / down | | **Q / E** | Roll left / right |
| **Arrow keys** | Glance camera | | **V** | Toggle approach |
| **C** | Fire cutter | | **Esc** | Quit |

> Strafe (A/D) and vertical thrust (R/F) are keyboard-only — the stick profile
> binds rotation, throttle-forward, the trigger, and the hat, not lateral
> translation. Reverse thrust is the **S** key (the throttle only pushes
> forward).

### Mouse / touch (secondary displays)

| Display | Controls |
| --- | --- |
| **Tactical** | Sensor mode buttons (PASSIVE / ACTIVE / STRUCT); approach and cut buttons; **click a member on the scope to select the cut target**. |
| **Tablet** | Touch sliders for THRUST / CUTTER / SENSORS / LIFE power. |
| **Chart** | Per-faction **DOCK**, then **SELL HOLD** / **DEPART FOR CLAIM**. |

Any input surface can drive the same intent — e.g. the master-battery power-kill
is reachable from the switch panel and, via the power sliders, from the tablet.

---

## Simpit / multi-display setup

The game is **one process** that opens **one native OS window per monitor** —
there is no split-screen or window-embedding. At boot, `WindowManager` puts the
Main view fullscreen on its screen and spawns the Tactical, Tablet, and Chart
windows borderless, each full-coverage on its own screen.

- **Assigning screens to roles.** The mapping of role → physical screen index
  lives in `user://display_config.cfg` (`autoload/DisplayConfig.gd`). Set it by
  role, not by guessing indices.
- **Labelling screens.** Virtual-display index order isn't stable across
  reconnects, so run `tools/ScreenLabeler.tscn` to see which physical screen is
  which and reassign roles. **Re-run it whenever spacedesk (or any display)
  reconnects** — indices can shuffle.
- **Fewer monitors than roles (desk dev).** Any role that lands on an
  already-claimed screen falls back to a small bordered, cascaded 960×540 window
  so nothing gets buried — you can develop all four displays on a single
  monitor.
- **spacedesk.** The secondary displays are designed to run over spacedesk
  virtual monitors (e.g. tablets as the Tablet/Chart screens). Because each role
  is full-coverage and borderless, and input is process-global, the four windows
  stay in sync regardless of which one has OS focus.
- **Adding a fifth display** is a role entry in `DisplayConfig` + a scene in
  `WindowManager.SECONDARY_SCENES` — no changes to `GameState` or existing
  windows.

`config/name` is **Salvager**; each secondary window is titled `Salvager — <Role>`.

---

## Running

Open the project in **Godot 4.7** and run `scenes/boot/Boot.tscn`. The game runs
degraded-gracefully: with no HOTAS, switch panel, or extra monitors connected it
falls back to keyboard/mouse on a single window and retries hardware in the
background. The `hid-gd` GDExtension is required for the switch panel and the
X55 POV glance; without it those inputs are disabled but the rest still works.

### Handy tool scenes (`tools/`)

| Scene | Purpose |
| --- | --- |
| `ScreenLabeler.tscn` | Identify physical screens and assign display roles. |
| `InputEcho.tscn` | Live dump of joystick axes/buttons and raw HID reports (used to derive the HOTAS bindings). |
| `ScreenshotCheck.tscn` | Render the Main hull-camera view to a PNG without a full playtest (`godot --path . res://tools/ScreenshotCheck.tscn ++ <out.png> [close]`). |
| `Phase4Smoke.tscn` / `Phase5Smoke.tscn` | Headless smoke tests for the salvage/market and input/flight systems. |
