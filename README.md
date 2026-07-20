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

### Remapping the HOTAS controls

All stick/throttle bindings live in one place: the `PROFILES` constant at the
top of `autoload/InputRouter.gd`. Gameplay code never sees hardware numbers —
every device is remapped here at startup and re-bound on each replug, so this is
the only file you touch to change bindings. Each device is one entry, matched by
**GUID** (stable across replugs, unlike device index), with four keys:

| Key | What it maps |
| --- | --- |
| `axes` | Analog axes → a pair of direction actions, e.g. `{"axis": 1, "neg": "pitch_down", "pos": "pitch_up"}`. Swap `neg`/`pos` to reverse an axis. |
| `buttons` | Momentary buttons → one action, e.g. `{"button": 0, "action": "ops_cut"}`. |
| `throttle` | The one axis read directly instead of through the Input Map (the X52's `+1 (idle)..-1 (full)` range needs rescaling actions can't express): `{"axis": 2, "idle_deadzone": 0.95}`. |
| `reserved_buttons` | Documentation only — selector-position banks where one button is always held. Never bind an action to these. |

The action names (`pitch_up`, `roll_left`, `ops_approach`, …) are the stable
intent layer consumed in `InputRouter._process()`; they're defined in
`project.godot` under `[input]`. To **rebind** a control, edit the
`axis`/`button`/`action` value in place. To **add a device**, append a new
profile dict with its GUID — no gameplay code changes.

**Finding the right index:** don't guess. Run `tools/InputEcho.tscn` for a live
dump of axes/buttons and read the device's GUID from `Input.get_joy_guid()`.
Note that both sticks are read as **raw joysticks** (no SDL controller mapping),
so raw Godot indices are what you bind — a controller mapping would cap each
device to ~21 buttons / 6 axes and silently drop the rest.

**Glance is the exception.** The X55 POV hat is *not* in `PROFILES`: Godot
collapses the hat onto the `DPAD_*` buttons, where `DPAD_RIGHT` collides with
the stick's always-held selector button. It's decoded straight from the raw HID
report in `systems/hardware/HidGlanceBridge.gd` instead. To point glance at a
different hat that *doesn't* collide, bind the `glance_*` actions through
`PROFILES` like any other control; to keep using raw HID for a colliding hat,
change the `VID`/`PID`, report offset (`parse_pov()`), and usage filter in
`HidGlanceBridge.gd`. The switch panel is likewise raw-HID
(`SwitchPanelBridge.gd`), not part of `PROFILES`.

---

## Simpit / multi-display setup

The game is **one process** that adapts to however many monitors you have — from
the full four-screen rig down to a single laptop panel. With four (or more)
screens it opens **one native OS window per monitor**; with fewer, displays that
can't get their own screen share one via a **tabbed host** (`WindowManager`,
`autoload/DisplayConfig.gd`). There is no split-screen or window-embedding.

- **You choose the layout.** The first time a monitor setup with fewer screens
  than displays is seen, the game shows an in-game **Display Setup** chooser: each
  screen shows a card, and you tap a role (MAIN / TACTICAL / TABLET / CHART) to
  put it there. A sensible layout is pre-filled — press **START** to accept it, or
  reassign first. The choice is saved **per monitor setup**
  (`user://display_config.cfg`, keyed by screen count + geometry), so the same rig
  never asks twice, but a different arrangement asks again. Press **F6** anytime to
  re-open the chooser; **F5** re-detects monitors and rebuilds the layout (a known
  setup applies silently, an unknown one re-opens the chooser). No restart needed.
- **How shared screens look.** Two or more roles on one screen become a tabbed
  host, switched by an on-screen tab strip **and** by `F1`/`F2`/`F3` (`Tab`
  cycles). On a **spare** screen the host fills it opaquely. On the **Main**
  screen the panels appear as a **dimmed overlay** over the live hull-cam view;
  the `MAIN` tab (or the backtick `` ` `` key) hides the panel for an unobstructed
  view. Everything works with mouse, touch, **or** keyboard.
- **No touchscreen needed.** Every secondary display is driven by mouse as well as
  touch, and the tab strip / chooser are keyboard-reachable — the game is fully
  playable at a plain desk.
- **spacedesk.** The secondary displays are designed to run over spacedesk
  virtual monitors. Because a dedicated role is full-coverage and borderless, and
  input is process-global, windows stay in sync regardless of which one has OS
  focus. spacedesk index order isn't stable across reconnects, but the saved
  layout is keyed by geometry and `F5` re-detects — reassign with the chooser
  (or the `tools/ScreenLabeler.tscn` dev tool) if a reconnect shuffles things.
- **Adding a fifth display** is a role entry in `DisplayConfig` + a scene in
  `WindowManager.SECONDARY_SCENES` — no changes to `GameState` or existing
  windows.

`config/name` is **Salvager**; each secondary window is titled `Salvager — <Role>`.

---

## Running

Open the project in **Godot 4.7** and run `scenes/boot/Boot.tscn`. The game runs
degraded-gracefully: with no HOTAS or switch panel it falls back to
keyboard/mouse and retries hardware in the background, and with fewer than four
monitors it prompts you (once per setup) to assign displays to screens and packs
the overflow into a tabbed host (see **Simpit / multi-display setup** above; `F6`
re-opens the chooser, `F5` re-detects monitors). The `hid-gd` GDExtension is
required for the switch panel and the X55 POV glance; without it those inputs are
disabled but the rest still works.

### Handy tool scenes (`tools/`)

| Scene | Purpose |
| --- | --- |
| `ScreenLabeler.tscn` | Identify physical screens and assign display roles (dev shortcut; the game shows an in-game chooser when needed). |
| `InputEcho.tscn` | Live dump of joystick axes/buttons and raw HID reports (used to derive the HOTAS bindings). |
| `ScreenshotCheck.tscn` | Render the Main hull-camera view to a PNG without a full playtest (`godot --path . res://tools/ScreenshotCheck.tscn ++ <out.png> [close]`). |
| `Phase4Smoke.tscn` / `Phase5Smoke.tscn` | Headless smoke tests for the salvage/market and input/flight systems. |
| `DisplayLayoutSmoke.tscn` | Headless smoke for the display layout: per-setup config persistence, the content-harvest reparent, and the tab-host show/hide. |
