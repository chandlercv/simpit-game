# Salvager — Simpit Game Plan (Godot 4)

## Context

The user has a hardware simpit: 32" 21:9 1200p main monitor, Android tablet, Surface Go, 13" 16:9 1080p secondary monitor, X52 throttle, X55 joystick, and a Logitech flight switch panel. The design philosophy is that **screens are displays showing external reality, not windows** — each screen has a distinct informational role. Priority is multi-display information design.

The game is a cyberpunk near-future mercenary salvage operation: fly into contested debris fields and derelict wrecks, assess structural risk, extract cargo, and sell through faction markets.

**Tech stack history:** this plan originally targeted Node.js + Vite + TypeScript + Three.js + socket.io, on the reasoning that a native game engine would require installing an app on the tablet and Surface Go, while a browser just needs a URL. Two things changed that reasoning:

1. **spacedesk.** The user is happy to use spacedesk to turn the tablet and Surface Go into ordinary extended Windows monitors (network-streamed, capped ~30fps; touch passthrough is used for the tablet, but the Surface Go is treated as non-touch per the desk layout — see Display Assignments). That already requires an install on those devices, so "zero-install secondary displays" — the original stack's strongest justification — no longer holds. Once spacedesk is running, those devices are just more monitors on the gaming PC.
2. **Clarified design intent.** The "screens are displays, not windows" philosophy from [impetus.md](impetus.md) was being read too literally as "4 fixed discrete camera angles." The actual intent: no cockpit dashboard framing drawn around the main view — a continuously free-look camera slewed live by the joystick's POV hat, filling the screen edge-to-edge like a real external hull camera. Combined with a "photo-realistic to some degree" fidelity target (Allegiance as the floor, not the ceiling) and the presence of a real GPU (GTX 1660), a hand-rolled Three.js rendering pipeline is more work than necessary, and browser Gamepad API hat-switch handling is unreliable.

Given both, the user chose to pivot to **Godot 4**, run as a single process with one native `Window` per monitor, sharing in-memory state directly instead of a client-server/socket.io split.

**Note on the MechWarrior "Virtual World" battlepod precedent** (one of the stated inspirations): historically, each BattleTech Center pod ran on a *single* machine driving all of that pod's displays — the original 1990 pods used one Amiga 500 (with a custom coprocessor for the main screen) that also drove the radar display; the later "Tesla II" pods used one Alienware rig per pod with multiple GPUs driving the main view, a secondary radar/map display, and five MFDs. Networking connected pod to pod for multiplayer, not display to display within a pod. That's a direct precedent for this plan's one-PC-per-pit, multi-window approach, and for keeping pod-to-pod networked multiplayer open as a separate, later concern (see Networking, below).

**World setting** ([simpit-world.md](simpit-world.md)): a single K-dwarf star system, post-war economic-salvage backdrop (commerce raiders are the in-fiction source of wrecks), real orbital-mechanics-based navigation between moons/planets/gas giants (L1 necklaces, orbital nodes, resonance windows, Trojan points), with inter-system travel deliberately rare/expensive so scope stays bounded to one system. This mostly slots into systems already planned (`MarketSystem.gd`'s faction/reputation model, the multiplayer-readiness design) with one real technical implication — see "World-scale navigation — precision guardrail," below.

---

## Recommended architecture

One Godot 4 project, one process, four native OS windows (`embed_subwindows = off`), each on its own physical/virtual monitor, all reading/writing one autoload singleton (`GameState`). No HTTP server, no socket.io, no serialization — mutation happens only through `systems/*.gd`, everything else reads state and reacts to signals.

```
D:\simpit-game\
  project.godot                  # Renderer: Forward+
  autoload/
    GameState.gd                 # ships: Dictionary[peer_id -> ShipState] (transform, hull, cargo,
                                  #   power), contacts, faction rep — keyed by player from day one,
                                  #   not a hardcoded singleton ship (see Networking / multiplayer readiness)
    DisplayConfig.gd             # logical role -> physical screen index (user://display_config.cfg)
    WindowManager.gd             # spawns/positions the 3 secondary Window nodes at boot
    InputRouter.gd               # raw joypad/keyboard -> GameState intents
  scenes/
    boot/Boot.tscn               # main scene = the main-view window itself
    displays/
      MainViewWindow.tscn        # 32" main: SubViewport 3D + thin HUD CanvasLayer
      TacticalWindow.tscn        # spacedesk Surface Go: radar/sensor scope, structural risk (NEW role, non-touch)
      TabletWindow.tscn          # spacedesk tablet: inventory, hull heatmap, power sliders (touch)
      StarChartWindow.tscn       # 13" secondary (physical, gaming PC): star chart, market, comms log (non-touch)
    world/Wreck.tscn, DebrisField.tscn, Ship.tscn, HullCameraRig.tscn
    ui/HUDOverlay.tscn, TacticalScope.tscn, InventoryGrid.tscn, PowerSliders.tscn, StarChart.tscn, MarketPanel.tscn, CommsLog.tscn
  systems/
    SalvageSystem.gd, MarketSystem.gd, ThreatSystem.gd, CargoSystem.gd
  tools/
    ScreenLabeler.tscn            # dev utility: prints screen index on every detected monitor
    InputEcho.tscn                 # dev utility: logs every raw joypad/key event for HOTAS discovery
```

**Convention to enforce (code-review level, not an engine feature):** window/UI scripts only read `GameState` and call intent methods; only `systems/*.gd` mutate state and emit `*_changed` signals. This preserves the separation a server/broadcast split would otherwise give you, without needing a network layer.

---

## Display assignments

| Display | Device | Content | Aesthetic |
|---|---|---|---|
| Main (32" 21:9 1200p) | Physical, gaming PC | Free-look hull camera feed, edge-to-edge, thin HUD (reticle, velocity/heading, target distance) | Photoreal-leaning: PBR materials, real lighting/shadows, bloom/SSAO/SSR |
| Tactical | Surface Go, via spacedesk — **non-touch**, mouse/keyboard driven | Radar/contacts, wreck structural graph/risk overlay, target lock list, sensor mode | Amber monochrome CRT/gauge (this is where that aesthetic belongs, not on the 3D view) |
| Tablet | Android, via spacedesk — touch | Inventory grid, hull integrity heatmap, power allocation sliders | Touch-first, tap-to-select over free-drag |
| Chart (13" 16:9 1080p) | Physical, gaming PC — non-touch, mouse/keyboard driven | Star chart, market prices, mission/comms log | Instrument/gauge-adjacent, matches the physical monitor's non-touch input |

Assignment per the user's desk layout: the Surface Go carries the Tactical role; the 13" physical monitor carries the Chart role.

---

## Phase 1 — Multi-window skeleton

- Create the Godot 4 project; set Renderer = Forward+, Embed Subwindows = off.
- Build `tools/ScreenLabeler.tscn` first — borderless window per `DisplayServer` screen index showing that index, run it the moment spacedesk is connected (virtual-display index order isn't guaranteed stable across reconnects).
- `DisplayConfig.gd` stores the role→screen-index mapping in `user://display_config.cfg`, populated from the labeler.
- `WindowManager.gd` spawns `TacticalWindow`, `TabletWindow`, `StarChartWindow` at boot, positioned/sized to their configured screen.
- All four windows show a role label + a shared tick counter from `GameState`, proving shared state with no drift.
- **Test with spacedesk actually connected** on both tablet and Surface Go, not just the two physical monitors — the one thing that can't be validated without the real hardware.

**Done when:** four windows land on the correct monitors and show identical, non-drifting tick counts.

## Phase 2 — Main display: free-look camera + thin HUD

- `HullCameraRig.tscn`: two-axis gimbal (yaw node → pitch node → `Camera3D`), pitch clamped ~±80° to avoid flip.
- **Hat input is digital, not analog** (Windows currently reads only the primary POV hat per device, exposed as `JOY_BUTTON_DPAD_*` — a real, currently-open Godot engine limitation on this hardware family, not a hypothetical). This is fine — the intended interaction is a **glance**, not a free-position pan: holding a hat direction eases the camera toward a bounded look offset that way (partial yaw/pitch toward that side), and releasing eases it back to forward-center automatically. Digital input is a natural fit for "glance while held, let go to look forward again" — no separate recenter binding needed, since release *is* the recenter.
- `MainViewWindow.tscn` root is the viewport filling the entire window — no dashboard/frame `Control` behind or around it. The `CanvasLayer` on top is thin (no full dashboard chrome) but not empty — it carries whatever reads naturally as something overlaid on a camera feed: reticle, velocity/heading, target distance, lock brackets drawn on a currently-tracked contact if it's in frame, and proximity/threat flashes for things relevant to what's actually on screen right now. What it does *not* duplicate is the abstracted, always-on instrument view of everything regardless of facing — full radar sweep, the complete contact list, the numeric structural-risk-over-time readout — that lives on the dedicated Tactical window. Rule of thumb: if it's tied to what's currently in the camera's view, it can live on the main HUD; if it's an omnidirectional or historical readout, it belongs on Tactical.
- Rendering: Forward+ (GTX 1660 handles this fine, no RT cores needed for Godot's GI). Skip SDFGI/VoxelGI initially — not needed for a small ship+wreck+debris scene. Get the photoreal-leaning look from: one `DirectionalLight3D` + a few `OmniLight3D`s (thrusters/beacons), PBR `StandardMaterial3D`s with wear/metal maps, `ReflectionProbe`s near ship/wreck, and a `WorldEnvironment` with Glow, SSAO, SSR, ACES tonemapping.
- **Asset sourcing (no budget, no modeling):** Kenney.nl's Space Kit and Space Station Kit (CC0, modular hull/station pieces — a direct fit for the wreck generator's "modular segments") and Quaternius (also CC0) cover low-poly hull/debris geometry. Sketchfab has a strong "derelict/crashed spaceship" niche across CC0 and CC-BY/CC-BY-NC licenses — CC-BY-NC is usable here since this isn't being monetized, which widens the pool beyond CC0-only. Poly Haven supplies free CC0 PBR textures/HDRIs for skybox and environment lighting. All of the above export as glTF, which Godot imports natively.
- **License-segregated asset layout, so monetizing later doesn't mean hunting through the whole project:** organize imported third-party assets by license at the folder level, not mixed together —
  ```
  assets/
    cc0/            # Kenney, Quaternius, Poly Haven, any CC0 Sketchfab finds — zero restriction, ship as-is
    cc-by/          # attribution required — fine to keep, just credit
    cc-by-nc/       # non-commercial only — the folder to empty out first if ever monetizing
  ```
  Godot resource paths (`res://assets/cc-by-nc/...`) are referenced directly by scenes, so auditing "what needs replacing before I could sell this" is a `grep` for that one folder path, not a per-asset license lookup. Pair with `CREDITS.md` listing each asset, its source URL, and its license — updated as assets are added, not reconstructed after the fact.

**Done when:** holding each hat direction produces a smooth glance toward that side, releasing eases back to forward-center, and zero dashboard chrome is visible at any point; glow/SSAO/SSR visibly improve the hull read; frametime stays comfortable with all four windows open.

## Phase 3 — Secondary displays

- **Tactical (Surface Go, via spacedesk):** radar/contacts, structural risk meter, target lock list, sensor mode — amber CRT aesthetic, 2D `Control` only. **Treated as non-touch** — interaction (if any is needed at all beyond passive readout) is mouse/keyboard, same as any other spacedesk-driven monitor without touch assumptions. This fits the role naturally: Tactical is mostly a glance-at display, not something you'd expect to poke.
- **Tablet (Android, via spacedesk) — the only touch surface:** touch arrives as ordinary `InputEventScreenTouch`/`ScreenDrag` scoped to the tablet's window — no spacedesk-specific code needed. Set Emulate Mouse from Touch / Emulate Touch from Mouse both **off** so touch on the tablet doesn't bleed into the other windows' mouse handling. Given spacedesk's ~30fps cap and network passthrough latency, prefer tap-to-select/tap-to-place over continuous free-drag for cargo; validate real drag feel on the actual tablet before committing to it.
- **Chart (13" physical monitor, gaming PC):** star chart, market prices, mission/comms log — mouse-driven pan/zoom (click-drag to pan, scroll wheel to zoom), since this is a regular non-touch monitor.
- Each window sets its own `content_scale_mode`/`content_scale_size` — don't inherit one global UI scale across a 21:9 1200p main, the tablet's spacedesk resolution, the Surface Go's spacedesk resolution, and the 13" 1080p physical monitor.

**Done when:** touch-drag/tap works on the physical tablet over spacedesk without stealing focus from other windows and hull heatmap/power sliders respond correctly; the Tactical (Surface Go) and Chart (13") windows work fully via mouse/keyboard with no touch dependency; star chart pans/zooms via mouse.

## Phase 4 — Gameplay loop

Systems read/write `GameState` directly, no serialization, plus one refinement to give "structural risk" an actual physical basis instead of an arbitrary cut counter:

- `SalvageSystem.gd`: the wreck generator produces not just visual geometry but a **structural graph** — which modular segments/members are load-bearing (carrying the wreck's residual stress: whatever's keeping its already-battle/collision-damaged frame from tearing itself apart) versus purely cosmetic panels. Risk is driven by *which* member gets cut, not how many cuts have happened — severing a load-bearing spar spikes risk sharply, a non-structural panel barely moves it. This is discoverable, not hidden: a sensor/scan pass exposes the structural graph as an overlay on the Tactical display (a real structural map, not just a numeric meter), so choosing where to cut becomes an actual read-the-wreck decision — in the spirit of the Elite-mining and Gato instrument-density inspirations, rather than a countdown timer. Also owns approach/match-velocity.
- `CargoSystem.gd`: weight/volume-limited inventory (feeds tablet).
- `MarketSystem.gd`: faction pricing/reputation (feeds Chart market panel).
- `ThreatSystem.gd`: rival salvagers, patrol timers, collapse events (feeds Tactical contacts/risk).
- **Convention:** ship stats (thrust, hull, cargo capacity, power budget) and market goods/faction definitions are authored as `Resource` subclasses (`ShipDefinition.gd`, `GoodDefinition.gd`) loaded from `.tres` files, not hardcoded fields on scripts/scenes — even with only one ship type and one faction set today. Keeps a future content-modding surface (or just a second ship type) a data-authoring task instead of a code extraction.

**Done when:** a full salvage run works end-to-end — jump in, scan (revealing the wreck's structural graph on Tactical), approach, extract 3 items by choosing cut points with visibly different risk impact depending on whether they're load-bearing, manage cargo, sell at a station.

## Phase 5 — Physical controls

- **X52 + X55:** enumerate as separate joypads; discover actual axis/button/hat indices with `tools/InputEcho.tscn` before writing bindings (don't trust documentation numbering for this hardware — community SDL mappings for X52/X55 are known to be incomplete). Bind through the Input Map as named actions (`thrust_forward`, `yaw_rudder`, …), not hardcoded device/axis numbers, so hardware swaps (X52 → Pro) or future SDL mapping fixes don't touch gameplay code. Use the one hat Windows exposes per device (X55 primary POV) for the Phase 2 glance camera — matches conventional HOTAS "view hat" placement anyway, and digital d-pad-style events are exactly what a hold/release glance interaction wants.
- **Logitech switch panel (Saitek Pro Flight Switch Panel, VID `0x06a3`/PID `0x0d67`):** confirmed — not a speculative unknown — that it does **not** enumerate as a standard joystick. The existing `C:\Users\charl\flightbridge\devices\flight_panel.py` tool reads it via raw `hidapi` calls direct to the USB HID interface and hand-parses report bytes, which is a fundamentally different path than the DirectInput/XInput joystick enumeration Godot's `Input` singleton relies on — `Input.get_connected_joypads()` will not see it. **Plan: native in-engine support, no external process.** This is well-trodden ground for Godot 4 — the same "raw HID device the OS doesn't expose as a joystick" problem is solved by existing GDExtensions for devices like the 3DConnexion SpaceMouse. Concretely:
  - First try `hid-gd` (an existing generic hidapi GDExtension for Godot 4.1+: open a device by VID/PID, read raw reports) rather than writing a bespoke GDExtension from scratch.
  - Port `flight_panel.py`'s already-proven report-parsing logic (open `0x06a3`/`0x0d67`, decode switch bits per byte) into GDScript on top of `hid-gd` — the byte layout is already known and validated, this is a straight port, not new reverse-engineering.
  - Expose parsed switch state through `InputRouter.gd` the same way HOTAS buttons are handled, so `GameState` doesn't care whether an input came from a real joypad or the panel's raw HID reports.
  - Fallback only if `hid-gd` proves incompatible/unmaintained for the target Godot version: write a small dedicated GDExtension in C++ modeled on the SpaceMouse project's pattern, linking hidapi directly.
  - `flightbridge` itself is no longer part of the running architecture — its Python source stays valuable purely as a reference for the panel's HID report format.
- **Many buttons across multiple simultaneous HID devices:** confirmed acceptable — single digital hat is fine (per above), so the only remaining requirement is button count. On Windows, Godot's joypad backend reads raw per-device button/axis counts (not capped to a standard-controller layout the way XInput/SDL_GameControllerDB abstractions are), so X52 + X55 + switch panel as three independent devices each exposing many buttons is expected to work. Still confirm on the actual hardware with `InputEcho.tscn` in this phase rather than assuming — that's exactly what the tool is for.

**Done when:** `InputEcho.tscn` correctly identifies every axis/button/hat on both HOTAS devices; a placeholder ship responds to thrust/rotation and the hat drives a glance-while-held/return-on-release camera; the switch panel is read natively in-engine via `hid-gd` (or the bespoke-GDExtension fallback) and its switches toggle the right `GameState` flags with no external process running.

---

## Networking — not built now, kept open for later multiplayer

No networking code ships in Phases 1–5 — for a single local pit, `GameState` is mutated in-process via `systems/*.gd`, and there's no server/socket.io broadcast to replace. But the user wants networked multiplayer (multiple pits/players, matching the BattleTech Center precedent above) to stay genuinely reachable later without a rewrite. That's mostly a data-modeling discipline now, not infrastructure now:

- **Model state as multi-entity from day one.** `GameState.ships` is a `Dictionary[peer_id -> ShipState]`, not a single hardcoded ship. In single-player, there's exactly one entry (keyed by a local peer id of `1`, Godot's convention for the local/server peer). This is the one thing that's expensive to retrofit later — cheap to model correctly now.
- **Keep the intent/mutation split disciplined** (already the stated convention: windows read + call intents, only `systems/*.gd` mutate). This maps directly onto Godot's built-in high-level multiplayer authority model: an intent call becomes an `@rpc("any_peer")` sent to whichever peer holds authority (the server), the server's `systems/*.gd` validates and mutates authoritative `GameState`, and results replicate back down via `MultiplayerSynchronizer` or manual RPC broadcast. Because gameplay code already only touches `GameState` through intents and signals, swapping "intent call happens locally" for "intent call happens over RPC" doesn't touch window/UI code at all.
- **Prefer replication-friendly types in `GameState`** (Vector3/float/int/String/Array/Dictionary) over engine objects that can't cross the wire, so a future `MultiplayerSynchronizer` can point at fields directly.
- Godot's multiplayer stack (ENet transport, `@rpc`, `MultiplayerSynchronizer`, server-authority pattern) is mature and well-documented — when multiplayer is actually built, it's additive (new autoload for the network peer, RPC wrapper around existing intents), not a redesign.

**Separate, still-open gap:** splitting *one* pit's own four displays across multiple physical PCs (rather than one PC + spacedesk) isn't solved by any of the above and isn't currently planned for — if that's ever wanted, the same multiplayer mechanism could double as the bridge (treat each display-hosting machine as a network peer subscribed to one player's `ShipState`), but that's a deliberate future addition, not something this plan builds.

**What's traded away by not running a server process today:** crash isolation (one process backs all four local windows — mitigate by testing each display scene standalone against a mock `GameState`) and per-window hot-reload during development (same mitigation). What's gained: no HTTP server, no message schema, no serialization boilerplate, for the common case of one local pit.

---

## Scaling to more monitors

The architecture is already built for this rather than hardcoded to four — `DisplayConfig.gd` maps logical roles to screen indices, and `WindowManager.gd` just loops over whatever roles are configured, spawning a `Window` per entry. Adding a 5th/6th display is: connect it (physical port or a new spacedesk client on any spare device — another tablet, an old laptop, a phone), run `tools/ScreenLabeler.tscn` to find its new screen index, add a role + a scene for it (e.g. splitting "Power" out of the Tablet into its own panel, or a dedicated Comms/Threat-warning display), and add the role to `DisplayConfig`. No changes to `GameState`, `InputRouter`, or existing windows are needed — this is exactly the kind of extension the config-driven design was meant to absorb.

Two practical ceilings, not architectural ones:
- **Physical monitor count is capped by the GTX 1660's actual output ports** (typically 3 DisplayPort + 1 HDMI on this card, so likely one or two more physical monitors before needing a DisplayPort MST hub or a second GPU output source).
- **Each additional spacedesk virtual monitor adds more capture/encode overhead on the same GPU** (risk #5 below) — fine for a couple of cheap 2D-UI displays, but this is the real limit on "how many more" before it starts stealing frame time from the main 3D view, not any Godot-side limit on window count.

---

## Modding & simpit-building friendliness — watch for these triggers

This isn't being built as a public modding platform, but several choices here are cheap to keep friendly to other simpit builders and DIY hardware if handled as they come up, and expensive to retrofit if left until someone actually asks:

- **HID device parsing:** keep each raw-HID device's byte-decode logic as an isolated pure function (raw report → named switch states), not inlined into `InputRouter.gd`'s dispatch logic (see Phase 5). Cheap now. The trigger to generalize into a declarative device-profile schema (VID/PID + byte-offset map, loaded from a resource instead of code) is *when a second raw-HID device actually exists* — not before, since a schema designed from one example (the Saitek panel) will likely be the wrong shape for whatever shows up next.
- **DIY Arduino/HID panels:** default guidance for anyone adding their own panel is to flash it as a standard-HID joystick (Arduino Joystick Library / HID-Project) rather than building custom raw-HID support — that needs zero engine code, same Input Map named-actions path as the X52/X55. Only reach for the `hid-gd`/raw-HID path if a device genuinely can't fit standard joystick HID limits (32 buttons, a handful of axes/hats).
- **Ship stats & market goods:** author as `Resource` subclasses (`ShipDefinition.gd`, `GoodDefinition.gd`) from day one, per the Phase 4 convention above — cheap now, expensive to extract from hardcoded fields later.
- **Wreck generation:** `SalvageSystem.gd`'s structural-graph generator mixes rules (how segments connect, what's load-bearing) with data (which piece catalog) in ways that are fine for one generator but harder to split later. Trigger to separate rules from data: *when a second wreck "kit" or a meaningfully different generation behavior is wanted* — don't build a generic data-driven wreck-authoring format speculatively before that.
- **Display roles:** already handled well — `DisplayConfig.gd`'s role→screen-index mapping and `WindowManager.gd`'s loop-over-configured-roles mean a different pit layout (fewer/more monitors, different roles) is a config change, not a code change. No action needed, just don't regress this by hardcoding a four-window assumption elsewhere.
- **Multi-PC pits:** genuinely out of scope for now (see Networking, above) — splitting one pit's displays across multiple physical machines isn't solved by the current single-process design. If it ever becomes a real ask, the planned multiplayer RPC layer is the natural bridge (treat each display-hosting machine as a peer subscribed to one player's `ShipState`); don't build a bespoke solution for it in the meantime.
- **Asset licensing:** keep the `cc0` / `cc-by` / `cc-by-nc` folder segregation current as assets are added (see Phase 2) — if this is ever shared with other builders or a modding community, `cc-by-nc` content constrains what they can redistribute, so the folder boundary needs to stay accurate, not just exist.

**Done when:** none of the above is a phase deliverable — this is an ongoing discipline. Revisit this list whenever a second instance of any of these (second HID device, second wreck kit, second ship type) actually shows up.

---

## World-scale navigation — precision guardrail

[simpit-world.md](simpit-world.md) describes a to-scale single-star-system setting: multiple gas giants each with several moons, navigation via real orbital mechanics (inter-moon L1 necklaces, orbital nodes, resonance conjunction windows, Trojan points, empty orbital foci), with inter-system travel deliberately rare/expensive so the game stays scoped to one system. That's a genuinely large-world simulation problem, and it's worth a stated guardrail now rather than discovering it by accident later.

**The risk:** Godot's `Vector3`/`Node3D` positions are 32-bit floats by default. Placing a whole to-scale star system in one continuous 3D scene at real astronomical distances is exactly the scenario Godot's own docs call out as causing jitter and precision loss far from the origin — this is a known, common failure mode for "to-scale solar system" games specifically, not a hypothetical edge case.

**The guardrail — no rework needed, it's already the natural shape of this plan:**
- Keep continuous, high-fidelity 3D flight scenes **local** — the volume around one debris field, one wreck, one nav node — which is already exactly what Phase 2's hull camera is scoped to. Nothing in the game ever needs to render two gas-giant systems in the same continuous `Node3D` tree at real scale.
- Treat interplanetary navigation (the L1/node/resonance graph across the whole system) as an **abstract data model** — computed in plain GDScript, where scalar `float` is already 64-bit double regardless of the engine's `Vector3` build, so the actual orbital mechanics math (Lagrange points, node crossings, resonance timing) is precision-safe without any special engine build — and displayed on the Chart window as a schematic/plot rather than a literal continuously-rendered 3D space.
- This is the same abstraction Elite Dangerous uses (supercruise/hyperspace hides the large distances; normal space is local high-fidelity flight) and requires no change to any phase already planned — it's a boundary to respect when Chart/StarChart.tscn and the eventual system-navigation system get built, not new work now.
- If a literal to-scale 3D representation is ever wanted (e.g. a system-map fly-through), the fallback is Godot's documented double-precision compile option or a floating-origin scheme — a deliberate choice to make at that point, not a default to fall into.

---

## Risks flagged for early validation

1. **HOTAS hat is single, digital-only** — Windows reads one hat per device, as `JOY_BUTTON_DPAD_*` events rather than an analog vector. Not a blocker: the Phase 2 camera design is a glance-while-held/return-on-release interaction, which digital input drives naturally. Re-verify the single-hat constraint against whatever Godot 4.x version is current at implementation time, since this area is under active upstream change — the glance behavior itself doesn't depend on that changing.
2. **spacedesk touch latency + 30fps cap** — validate tap/drag feel on real hardware early (Phase 3), don't assume desktop-mouse responsiveness.
3. **Mixed DPI across four windows** — per-window content scaling; may need to force 100% OS scaling on spacedesk virtual monitors and let Godot own scaling instead.
4. **Switch panel `hid-gd` compatibility, not the HID descriptor** — the report format is already known and validated (ported from `flight_panel.py`), so the actual open question is narrower: whether the `hid-gd` GDExtension works cleanly against the target Godot 4.x version. If it doesn't, the fallback is a small bespoke GDExtension (C++ + hidapi) using the same already-known byte layout — not a from-scratch reverse-engineering effort.
5. **spacedesk's own capture/encode overhead shares the GTX 1660 with the game** — keep the three secondary windows cheap 2D UI; concentrate the rendering budget on the one main-view window.
6. **Four native windows, one process** — verify HOTAS/keyboard input (process-global via Godot's `Input` singleton) keeps working regardless of OS focus, and that borderless+always-on-top behavior doesn't cause alt-tab/focus problems in practice.

---

## Verification

- **Phase 1:** Four windows land on correct monitors (including both spacedesk displays actually connected), showing a shared, non-drifting tick.
- **Phase 2:** Hat-driven glance is smooth in both directions (toward on hold, back to center on release) with zero dashboard framing; contextual overlays (lock brackets, proximity/threat flashes) appear only for what's actually in view; lighting/materials read as "photoreal-leaning," not vector-scope.
- **Phase 3:** Touch works on the physical tablet over spacedesk without cross-window focus issues; Tactical (Surface Go) and Chart (13") are fully usable via mouse/keyboard alone.
- **Phase 4/Full loop:** Complete a salvage run across all four displays — scan (Tactical), approach (Main), extract with rising risk (Tactical + Main HUD), manage cargo (Tablet), sell (Chart).
- **Phase 5:** `InputEcho.tscn` output confirms every HOTAS axis/button/hat index on the real hardware before any bindings are written.
