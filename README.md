# Salvager

A space-sim that treats HOTAS, switches and multi-monitors as first-class components in the simulation experience.

A cyberpunk mercenary **salvage sim** built for a multi-display hardware simpit.
One process drives one native window per monitor — an external hull-camera view,
a read-only tactical scope, two touch MFDs, and a second external camera — fed by
a HOTAS, a Saitek switch panel, and touch/mouse on the secondary screens.

> Status: Phases 1–5 complete and hardware-verified. Engine: Godot 4.7
> (Forward+). Main scene: `scenes/boot/Boot.tscn`.

![Main hull-camera view: a derelict frigate — one continuous hull with a flared
engine bell, radiator fins, and a sensor mast — at cutting range, framed by the
thin flight HUD: a centre nose reticle, drift brackets, VEL/HDG/EL readouts, and a
locked-target box on the frigate.](assets/docs/main_view.png)

*The Main display — an external hull-camera feed of the wreck at cutting range. The
derelict reads as a single hulled frigate (engine bell aft, radiator fins, dorsal
sensor mast) that the cutter carves into removable sections, under the thin flight
HUD: nose reticle, drift brackets, velocity/heading/elevation readouts, and a
locked-target box on the derelict frigate.*

---

## The four displays

Displays are assigned to physical screens by role (see `autoload/DisplayConfig.gd`;
roles are re-labelled with `tools/ScreenLabeler.tscn`). Each is its own OS window
with its own input stream.

| Role | Window | What it shows | How you interact |
| --- | --- | --- | --- |
| **Main** | `MainViewWindow` | Edge-to-edge hull-camera feed of the 3D world (ship, wreck, debris) with a thin HUD. | Flight + camera glance (HOTAS / keyboard). |
| **Tactical** | `TacticalWindow` | **Read-only instruments in two modes** — SCOPE (sensor scope, hull-damage heatmap, structural-risk meter) and CHART (system star chart). | Mode buttons; mouse pan/zoom on the chart. No touch controls — it's an instrument you read. |
| **MFDs** | `MfdWindow` | **Two side-by-side MFDs**, each with a MENU home and pages: **POWER** (channel sliders), **CARGO**, **SALVAGE** (cut-target list + sensor mode + approach/cut), **ALIGN** (the pre-cut alignment mini-game — crosshair, lock/slip meters, COMMIT/CANCEL), **MARKET** (prices + comms), **CONTACTS** (lock list). The primary MFD auto-opens **ALIGN** while alignment is live and hands the screen back after. | Touch/mouse: tap MENU to jump straight to any page, then operate it. Every command is also HOTAS-mappable. |
| **Camera** | `CameraWindow` | A **second external camera** of your own ship — **REAR** (rear-view, looking aft), **SIDE**, **CHASE**, **TOP** — rendering the same 3D world as the Main view. | Selectable by a mapped control (cycle, or one button per view). |

---

## The Main flight HUD

The Main display overlays a thin HUD on the hull-camera feed (drawn in
`scenes/ui/HUDOverlay.gd`):

- **Nose reticle** — a small circle with crosshair ticks marking where the
  ship's **nose** points. Looking straight ahead it sits at screen centre; because
  a *glance* rotates only the camera and not the hull, the reticle slides
  off-centre toward the nose as you glance, pinning to the screen edge on a hard
  glance. It's how you keep track of where "forward" is while looking around.
- **Drift marker** — a pair of brackets `[ ]` offset from the nose reticle by how
  fast you're sliding **sideways** (your velocity across the nose; straight-ahead
  speed shows in the VEL readout, not here). Fly straight and they rest on the
  reticle (`[ ⊕ ]`); strafe or drift and they slide off proportionally to the way
  you're sliding. The offset tracks drift *magnitude*, so counter-thrusting eases
  the brackets smoothly back onto the reticle and parks them there once you've
  nulled the drift — that's your cue you're dead in the water. Hidden at rest.
- **Readouts** — bottom-left **VEL** (speed) and **HDG / EL** (heading and
  elevation of the view); a tracked contact gets corner brackets with its name and
  range, plus a pulsing threat frame and **PROXIMITY** warning when it's a close
  hostile.
- **Cut-target marker** — once you've picked a cut target it gets a diamond `◆`
  with its name and range, pinned to that member on the wreck so you can see which
  part you're going for and turn to face it. When the member is off-screen the
  diamond becomes an **edge arrow** pointing the short way round to it. It's amber
  while you're closing in and greens to **MATCHED — FIRE TO ALIGN** the moment the
  approach matches on that member — your cue the cutter trigger will now open the
  alignment step.
- **Alignment crosshair** — only while you're lining up a cut (see the gameplay
  loop). It's anchored **over the member you're cutting** (where its diamond was),
  so the seam target `⊕` sits on the actual hull. The seam is a fixed point on the
  member, so it drifts only because the **derelict is tumbling** — you're tracking a
  real spot on a spinning wreck, not a random wander. Steer your torch reticle `✛`
  (with pitch/yaw) onto the seam and hold it inside the tolerance ring to fill the
  lock arc; the seam greens up on-seam, flashes **SLIP** when the torch wanders toward
  a fail, and the banner reads **ALIGNING … — LOCK NN%**. The **cutting beam** itself
  is drawn in 3D — a torch laser from the ship's **right wing** to where you're aiming
  (see below). The bigger version of the crosshair instrument is the MFD **ALIGN** page.
- **Cutting beam** — a torch beam fired from the Kestrel's **right wing** to the cut
  point on the wreck, shown in the camera feed. While aligning it's a thin targeting
  beam that walks onto the seam as you line up; once the cut commits it thickens into
  a hot, flickering cutting beam with an impact glow on the hull until the member
  severs.

---

## Core gameplay loop

You fly a salvage ship to a wreck, cut it apart for cargo without letting the
frame collapse on you, then dock and sell. On site (`ON_SITE` phase):

1. **Scan the wreck.** On an MFD **SALVAGE** page set sensor mode to **STRUCT**,
   raise **SENSORS** power on the **POWER** page, and close inside 300 u. A full
   structural scan takes ~5 s at 100% SENSORS and reveals the wreck's member
   graph (which parts carry frame stress); read it on the Tactical **SCOPE**.
2. **Pick a cut target.** Tap a member in the **SALVAGE** list on an MFD (or
   cycle it with a mapped control). Each row shows the member's load class and
   the risk spike cutting it would cause; the Tactical **SCOPE** plots the same
   graph so you can read the wreck while you pick. **Pick before you approach —
   the autopilot flies to the member you've selected.** A diamond `◆` (or an edge
   arrow when it's off-screen) marks that member on the Main HUD so you can see
   where it is and turn to face it.
3. **Approach & match velocity on that member.** Trigger the approach autopilot.
   The **derelict is slowly tumbling** (each claim spins on its own random axis and
   rate — some barely turn, some drift faster), so the member is orbiting the
   wreck's centre; the autopilot flies you to a standoff off the **selected member**
   and holds station on it as it moves → state goes `HOLDING` → `APPROACHING` →
   `MATCHED`. The autopilot only translates — it won't turn you, and it can't match
   the wreck's *spin* — so watch the cut-target marker and glance/steer to keep the
   member in view. The marker greens to **MATCHED — FIRE TO ALIGN** once you match
   on it. The match belongs to that member: **select a different target and you
   drop back to `HOLDING` and must re-arm the approach to reposition** onto the new
   one.
   *The throttle must be eased back under ~40% to arm the autopilot, and any
   real stick/throttle input while it's flying hands control back to you.*
4. **Power the cutter.** Raise the **CUTTER** power channel to at least 0.2 on
   an MFD **POWER** page.
5. **Align the cutting head.** With the approach `MATCHED`, fire the cutter to
   open the alignment mini-game (it does **not** cut yet). The seam target `⊕` is a
   real point on the member, so it drifts across your view **because the wreck is
   tumbling** — since you matched the wreck's drift but not its spin, holding the
   cut takes hands-on tracking. Steer your torch reticle `✛` — with **pitch/yaw** —
   onto the seam and hold it inside the tolerance ring to fill the **lock**. Watch
   it on the Main HUD crosshair or the MFD **ALIGN** page. Let the torch wander too
   far and the **slip** meter fills and the alignment aborts (no cut).
6. **Commit the cut.** The lock auto-commits at full, or press the cutter again to
   commit early at the current quality. The cutting beam from the ship's **right
   wing** bites into the member, which severs over time, and its salvage is stowed.
   **Alignment quality is the payoff:** a clean lock cuts faster, spikes structural
   risk less, and preserves more yield; a sloppy one crawls, spikes harder, and
   loses salvage.
7. **Watch structural risk.** Cutting load-bearing members spikes risk and
   ratchets the resting baseline up; cosmetic panels barely move it. If the
   frame collapses, every uncut member is lost.
8. **Dock and sell.** On an MFD **MARKET** page, dock at a faction (this leaves
   the claim), sell your hold at that faction's prices, then depart back to the
   claim for a fresh wreck.

**Power budget:** four channels — **THRUST, CUTTER, SENSORS, LIFE** — each
0..1. The reactor can't run everything at full; the MFD **POWER** page header
turns red on overdraw. THRUST gates approach/manual acceleration, CUTTER gates
cutting, SENSORS gates scan speed.

**Manual flight throttle:** by default the throttle (forward/back) commands a
target speed, not raw thrust — ease it to 50% and the ship accelerates to,
then holds, 50% of max speed; let go and it holds station on that axis. A
mapped **Throttle Cmd Mode** button swaps this for the legacy direct-thrust
feel (throttle = acceleration, no cruise control). Strafe, vertical, and
reverse are all secondary thrusters off the same drive — each rated at 50% of
the main thruster's forward performance (`ShipDefinition.secondary_thrust_fraction`,
one knob for the whole maneuvering profile).

Each channel can be driven from the switch panel (see the switch table below):
FUEL PUMP→THRUST, AVIONICS→SENSORS, DE-ICE→CUTTER, PITOT HEAT→LIFE. The first
three toggle a shared **high (80%) / low (20%)** setting; PITOT HEAT runs LIFE
full (100%) on / low off. Any channel can also be set to any value on an MFD
**POWER** page, from a mapped analog axis (used as a slider), or nudged up/down
by a mapped key/button. The two master electrical switches
override the whole mix: **MASTER ALT
off** rigs for escape (THRUST 100% and LIFE 100%, cutter and sensors to 0);
**MASTER BAT off** kills everything. While either master is off the live mix is
locked and the master override owns it, but the physical channel switches still
register — the mix comes back matching the panel's current switch positions when
the master returns (touch-slider edits made while locked are ignored). Running
dark this way also halves the ship's visibility to
passive scanners — the claim-holder's patrol has to close to half its usual range
before it can fine you (a quarter if both masters are off).

Each channel can be driven from the switch panel (see the switch table below):
FUEL PUMP→THRUST, AVIONICS→SENSORS, DE-ICE→CUTTER, PITOT HEAT→LIFE. The first
three toggle a shared **high (80%) / low (20%)** setting; PITOT HEAT runs LIFE
full (100%) on / low off. Any channel can also be set to any value on the tablet
sliders. The two master electrical switches override the whole mix: **MASTER ALT
off** rigs for escape (THRUST 100% and LIFE 100%, cutter and sensors to 0);
**MASTER BAT off** kills everything. While either master is off the mix is locked
(switches and sliders do nothing) and comes back exactly as it was when the
master returns. Running dark this way also halves the ship's visibility to
passive scanners — the claim-holder's patrol has to close to half its usual range
before it can fine you (a quarter if both masters are off).

---

## Controls

The physical rig is a **Saitek X55 Rhino stick** + **Saitek X52 throttle** +
**Saitek Pro Flight Switch Panel**. Devices are matched by GUID at runtime
(`autoload/InputRouter.gd`), so replugging never rebinds anything. The secondary
displays are driven by mouse/touch. **Every gameplay control is assigned in the
remapper** (F7) — HOTAS *and* keyboard — but sensible defaults ship for each, the
keyboard ones as a *data profile* rather than hardcoded keys. So the game is
playable at a desk out of the box; you only open the remapper to change something
(see **Remapping the controls** below).

### X55 Rhino stick (flight + cutter + camera)

| Control | Action |
| --- | --- |
| Stick **left / right** (axis 0) | Yaw left / right — *aims the torch left/right during pre-cut alignment* |
| Stick **forward / back** (axis 1) | Pitch down / up (pull back = nose up) — *aims the torch up/down during alignment* |
| Stick **twist** (axis 2) | Roll left / right |
| **Trigger** (button 0) | **Fire cutter** (`ops_cut`) — from a matched target this **opens the alignment mini-game**, then **commits** the lock (auto-commits at full). |
| **POV hat** | **Glance** the hull camera — hold a direction to look that way, release to recenter. Read over raw HID to dodge the stick's always-held selector button. |

> Buttons 14–16 are the stick's selector-position bank (one is always held) —
> reserved, never bind actions to them.

### X52 throttle (thrust + approach)

| Control | Action |
| --- | --- |
| **Throttle lever** (axis 2) | Forward/back command. Idle near the top; push forward to command more speed (a target % of max speed by default — see **Manual flight throttle** above). Folds into the ship's forward/back command and must sit under ~40% travel to arm the approach autopilot. |
| **POV hat** (buttons 19–22) | **Strafe & vertical thrust** — hat left/right strafes left/right, hat up/down thrusts up/down. Lateral and vertical translation without touching the stick. |
| **Button 7** (Fire E) | **Toggle approach / match-velocity** (`ops_approach`) — needs a cut target selected first; the autopilot flies to that member. |

> This throttle reports its hat as plain buttons 19–22 (not the DPAD), clear of
> the reserved selector bank. Buttons 23–25 are reserved selector-bank buttons.

### Saitek Pro Flight Switch Panel (raw HID)

The panel never enumerates as a joystick; it's read directly over HID
(`systems/hardware/SwitchPanelBridge.gd`). All 20 switches post their state to
the comms log, but only these are wired to gameplay today:

| Switch | Effect |
| --- | --- |
| **MASTER BAT** | Off = cut all reactor power (zeros every channel); On = restore the mix matching the current channel-switch positions. While off, the live mix can't be changed and the ship's visibility to passive scanners drops 50%. |
| **MASTER ALT** | Off = rig for escape — THRUST 100% and LIFE 100%, CUTTER/SENSORS 0 — overriding the switch settings; On = restore the mix matching the current channel-switch positions. While off, the live mix can't be changed and passive-scanner visibility drops 50% (stacks with BAT → 25% if both off). |
| **FUEL PUMP** | THRUST power: On = high (80%), Off = low (20%). |
| **AVIONICS** | SENSORS power: On = high, Off = low. |
| **DE-ICE** | CUTTER power: On = high, Off = low. |
| **PITOT HEAT** | LIFE power: On = 100% (life support runs full), Off = low (20%). |
| **NAV** | Ship nav lights on/off. |
| **LANDING** | Ship landing light on/off. |

The four channel switches toggle between shared **high (80%)** and **low (20%)**
settings; the MFD **POWER** page sliders (or a mapped power axis / nudge
key) can still set any value in between (until the next switch flip). MASTER ALT / MASTER BAT off
lock the live mix on every surface, though physical switch positions still
register for when power returns.

The remaining switches — COWL, PANEL, BEACON, STROBE, TAXI, the 5-position
magneto (OFF/R/L/BOTH/START), and the GEAR UP/DOWN lever — are decoded and logged
but have no gameplay effect yet.

### Keyboard (default mapping — overridable in the remapper)

A default keyboard mapping **ships as a built-in profile** (the `keyboard` entry
in `BUILTIN_PROFILES`, `autoload/InputRouter.gd`) — it's *data*, not hardcoded
`project.godot` keys, so the remapper shows it and a user profile
(`user://input_profiles/keyboard.json`) can override or clear any of it. The
defaults:

| Key | Action | | Key | Action |
| --- | --- | --- | --- | --- |
| **W / S** | Thrust forward / back | | **I / K** | Pitch up / down |
| **A / D** | Strafe left / right | | **J / L** | Yaw left / right |
| **R / F** | Thrust up / down | | **Q / E** | Roll left / right |
| **Arrow keys** | Glance camera | | **V** | Toggle approach (needs a target) |
| **C** | Fire cutter / align + commit | | **M** | Cycle sensor mode |
| **, / .** | Prev / next cut target | | **N** | Cycle locked contact |
| **G / H** | MFD-A / MFD-B → MENU | | **T** | Toggle Tactical SCOPE / CHART |
| **]** | Cycle external camera | | **1 / 2 / 3 / 4** | Camera REAR / SIDE / CHASE / TOP |

MFD paging, cargo, market, and the power-channel axes ship **unbound** on the
keyboard — bind them in the remapper if you want keys for them. Every default
here is also HOTAS-bindable, and a key + a HOTAS bind can coexist on one function.

During the pre-cut alignment mini-game the **pitch/yaw keys** (I / K, J / L) aim
the cutting head instead of flying the ship, so you steer the torch reticle onto
the seam with the same keys, then press **C** to commit.

The only fixed keys — not rebindable, since F7 must stay fixed to open the
remapper at all:

| Key | Action |
| --- | --- |
| **F7** | Open the remapper (Configure Controls) |
| **F5 / F6** | Re-detect monitors / open Display Setup |
| **Esc** | Quit (or cancel an in-progress bind while the remapper is open) |

### Mouse / touch (secondary displays)

| Display | Controls |
| --- | --- |
| **Tactical** | Read-only. **SCOPE** / **CHART** mode buttons; mouse pan/zoom on the chart. |
| **MFDs** | Tap **MENU** to open a page. **POWER** sliders; **CARGO** tap-to-select + jettison; **SALVAGE** sensor mode + approach/cut + tap a cut target; **MARKET** per-faction dock / sell / depart; **CONTACTS** tap to lock. |
| **Camera** | View is picked by a mapped control (no on-screen buttons). |

Any input surface can drive the same intent — e.g. the four power channels are
set from an MFD's touch sliders, from a mapped power axis (slider) or key/button
(nudge), and, equivalently, from the switch panel's channel toggles (FUEL PUMP / AVIONICS / DE-ICE / PITOT
HEAT). Everything you can do on an MFD is also bindable to a HOTAS button or
axis (see the remapper groups **MFD / SALVAGE / TACTICAL / CARGO / MARKET / VIEW
/ POWER**). The Tactical SCOPE⇄CHART toggle is in **TACTICAL** — bind it to a
HOTAS button to flip the Tactical display without touching the screen. **Throttle
Cmd Mode** (group **THROTTLE**) ships unbound — map it to a button to flip
between speed- and thrust-command throttle in flight.

The mapped **CARGO** commands (next / prev / jettison) act on whichever CARGO
page is **currently on screen**, not on a hidden one. The two MFDs page
independently, so if you have **CARGO open on both at once**, each keeps its own
selection and a single mapped jettison dumps the selected item from **both** —
two items in one press. Keep CARGO up on only one MFD when jettisoning by HOTAS,
or use the on-screen JETTISON button (which only ever affects its own grid).

### Remapping the controls

Bindings are **data, not code** — you don't edit GDScript to support a new stick
or to move a key. Every device is matched by **GUID** (stable across replugs,
unlike device index) and there are three layers, in precedence order:

- **In-game remapper (easiest).** Press **F7** for *Configure Controls*. Each row
  is a bindable function showing its current mapping; hit a bind button and work
  that control on **whichever device you want** — it auto-detects which
  stick/throttle it was, so a HOTAS split across two devices saves a profile for
  each. **Or press a keyboard key** to bind a key to that function — a key and a
  HOTAS bind can coexist on the same row (both trigger it); this is how you edit
  the shipped default keyboard mapping. On a direction pair, **AXIS** binds
  an analog axis, **−btn / +btn** bind a button *or key* per direction (for a POV
  hat that reports as buttons, e.g. strafe on the X52 hat); **REV** flips an axis,
  the nub can be picked instead (except on the four POWER rows — the self-centring
  nub can't hold an allocation, so those take an axis, buttons, or the switch
  panel). **SAVE** writes the profile(s) and rebinds live
  (no restart). Always-held mode-selector buttons are refused; **Esc** cancels an
  in-progress bind. (Capture picks whichever control moves most from where it sat
  at bind, so a throttle can rest anywhere — just let a spring-loaded stick axis
  recenter first.) Glance from the X55 hat is raw-HID and always on, so its rows
  are blank by design.
- **A profile file.** Each saved device is one JSON file at
  `user://input_profiles/<guid>.json` — hand-editable and shareable (a tester can
  mail theirs back; drop it in the folder). A user profile **overrides** the
  built-in with the same GUID, or adds a brand-new device. Keyboard bindings live
  in the same folder as a device-less `keyboard.json` (GUID `keyboard`) carrying a
  `keys` array — see the schema below.
- **Built-in defaults.** The shipped X52/X55 mappings **and the default keyboard
  mapping** are the `BUILTIN_PROFILES` constant at the top of
  `autoload/InputRouter.gd` (the keyboard one is the device-less `keyboard`
  entry); a matching user profile wins (`_effective_profiles()` merges the two).
  Gameplay code never sees hardware
  numbers — bindings are injected into the Input Map at startup and on each replug.

A profile entry (the file and `BUILTIN_PROFILES` share one schema) has these keys:

| Key | What it maps |
| --- | --- |
| `axes` | Analog axes → a pair of direction actions, e.g. `{"axis": 1, "neg": "pitch_down", "pos": "pitch_up"}`. Swap `neg`/`pos` (or hit **REV**) to reverse. |
| `buttons` | Momentary buttons → one action, e.g. `{"button": 0, "action": "ops_cut"}`. |
| `keys` | **Keyboard keys → one action** (only on the device-less `keyboard` profile), e.g. `{"key": 67, "action": "ops_cut"}`. `key` is a Godot physical keycode. The shipped default keyboard mapping is the built-in `keyboard` profile; a user `keyboard.json` overrides it. |
| `throttle` | The one axis read directly. Two curves, toggled by **MODE** in the remapper: **Lever** (default) — a one-directional lever that rests anywhere, rescaled to 0..1. General form `{"axis": 2, "idle": 1.0, "full": -1.0}` fits any rest/travel range and direction; the legacy X52 form `{"axis": 2, "idle_deadzone": 0.95}` still works. **Gamepad** — `{"axis": 2, "mode": "gamepad", "invert": false}`, for a self-centering stick/trigger axis: raw value is the command directly, 0 at center, ±1 at the stops. |
| `hid_axes` | A **raw-HID virtual axis** → a direction pair, e.g. `{"source": "x52_mouse_x", "neg": "yaw_left", "pos": "yaw_right"}`. Sources: `x52_mouse_x`, `x52_mouse_y` — the X52 throttle's mouse nub, which Godot doesn't expose as joystick axes (see below). |
| `reserved_buttons` | Documentation only — selector-position banks where one button is always held. Never bind an action to these. |

The action names (`pitch_up`, `roll_left`, `ops_approach`, …) are the stable
intent layer consumed in `InputRouter._process()`; they're defined in
`project.godot` under `[input]`.

**Finding the right index (for hand-editing):** don't guess. Run
`tools/InputEcho.tscn` for a live dump of axes/buttons and the device's GUID from
`Input.get_joy_guid()`. Both sticks are read as **raw joysticks** (no SDL
controller mapping), so raw Godot indices are what you bind — a controller
mapping would cap each device to ~21 buttons / 6 axes and silently drop the rest.

**Glance is the exception.** The X55 POV hat is *not* in the profiles: Godot
collapses the hat onto the `DPAD_*` buttons, where `DPAD_RIGHT` collides with the
stick's always-held selector button. It's decoded straight from the raw HID
report in `systems/hardware/HidGlanceBridge.gd` instead. To point glance at a
different hat that *doesn't* collide, bind the `glance_*` actions in a profile
like any other control; to keep using raw HID for a colliding hat, change the
`VID`/`PID`, report offset (`parse_pov()`), and usage filter in
`HidGlanceBridge.gd`. The switch panel is likewise raw-HID
(`SwitchPanelBridge.gd`), not part of the profiles.

**X52 mouse nub.** The throttle's mouse nub is raw-HID-only — Godot's joypad
layer doesn't surface it — so it's read from the X52 joystick HID report in
`systems/hardware/X52MouseBridge.gd` (byte 13: low nibble = X, high nibble = Y)
and exposed as the `x52_mouse_x` / `x52_mouse_y` sources you bind via `hid_axes`.
The bridge opens the X52 collection only when a profile actually binds one of
these. The X52 **scroll wheel**, by contrast, *is* visible to Godot as **joypad
buttons 32 (up) / 33 (down)** — bind it like any button (a wheel notch is a
button press). To inspect either on your unit, run `tools/InputEcho.tscn`.

---

## Simpit / multi-display setup

The game is **one process** that adapts to however many monitors you have — from
the full four-screen rig down to a single laptop panel. With four (or more)
screens it opens **one native OS window per monitor**; with fewer, displays that
can't get their own screen share one via a **tabbed host** (`WindowManager`,
`autoload/DisplayConfig.gd`). There is no split-screen or window-embedding.

- **You choose the layout.** The first time a monitor setup with fewer screens
  than displays is seen, the game shows an in-game **Display Setup** chooser: each
  screen shows a card, and you tap a role (MAIN / TACTICAL / MFD / CAMERA) to
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
degraded-gracefully: with no HOTAS or switch panel it retries hardware in the
background while you fly on the **default keyboard mapping** (mouse/touch on the
secondary displays; rebind any key via **F7**), and with fewer than four
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
| `build_hull.py` | Blender script (not a Godot scene) that regenerates the derelict frigate's continuous hull — one fuselage split into member-named sections plus modeled radiator/mast/engine-bell appendages — into `assets/cc0/derelict-frigate/*.glb` (`blender --background --python tools/build_hull.py`). Edit the profile/appendages here, not the `.glb`s. |
| `Phase4Smoke.tscn` / `Phase5Smoke.tscn` | Headless smoke tests for the salvage/market and input/flight systems. |
| `AlignSmoke.tscn` | Headless smoke for the per-member approach + pre-cut alignment mini-game: approach needs a selected target and re-selecting forces a reposition; the cutter trigger opens alignment (not a cut); on-target aim locks and commits at high quality; a sustained slip aborts and nudges risk; and quality binds the stakes (clean cut is faster and preserves more yield). |
| `CollisionSmoke.tscn` | Headless smoke for collision consequences: the capsule volume follows the hull (not the origin), ramming a body damages the hull and stops the ship at the surface, a gentle nudge does no damage. |
| `ShipColliderBake.tscn` | Bake the ship's collision capsule from its model into `data/ships/*.tres` (`godot --headless res://tools/ShipColliderBake.tscn`). Re-run after swapping the hull mesh. |
| `DisplayLayoutSmoke.tscn` | Headless smoke for the display layout: per-setup config persistence, the content-harvest reparent, and the tab-host show/hide. |
| `PowerSmoke.tscn` | Headless smoke for the switch-driven power model: channel switches drive their mapped channel, the masters override and lock the mix (restoring on return), and passive-scanner visibility halves per master off. |
| `PowerNudgeSmoke.tscn` | Headless smoke for driving a power channel from the remapper rows: an analog axis acts as a slider, a digital key/button nudges the channel per press, and a bound-but-idle digital event never pegs it to the midpoint. |
| `AxisKeyNormalizeSmoke.tscn` | Headless smoke for the remapper's axis-key normalization: a saved axis/nub spec listed in the swapped (REV-encoded) order folds back to its row's canonical key with reverse set, so it stays visible on its row instead of vanishing under a phantom key. |
