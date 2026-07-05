# Salvager — Simpit Game Plan

## Context

The user has a hardware simpit: 32" 21:9 1200p main monitor, Android tablet, Surface Go, X52 throttle, X55 joystick, and a Logitech flight switch panel. The design philosophy is that **screens are displays showing external reality, not windows** — each screen has a distinct informational role. Priority is multi-display information design.

The game is a cyberpunk near-future mercenary salvage operation: fly into contested debris fields and derelict wrecks, assess structural risk, extract cargo, and sell through faction markets.

---

## Tech Stack Recommendation: Node.js + Web (Vite + TypeScript + Three.js + socket.io)

**Why not a game engine (Unity/Godot):**  
Tablet and Surface Go are separate physical devices. A game engine would require installing the app on each. A browser just opens a URL — zero friction.

**Why web:**
- Secondary displays (tablet, Surface Go) connect by opening `http://[gaming-pc-ip]:PORT/tablet` and `/surface` in any browser — no install
- Touch is native to the web
- Three.js handles the 3D scene needed for the main display
- socket.io makes multi-display sync simple
- CSS/Canvas/SVG are ideal for the tactical display aesthetic (gauges, radar, overlays)
- Gamepad API covers HOTAS input; node-hid (via Electron later) covers the switch panel

**Start simple:** Vite dev server + Node.js (no Electron needed initially). Add Electron later when native HID access for the switch panel is required.

---

## Display Assignments

| Display | Device | Content |
|---|---|---|
| Main (21:9 1200p) | Gaming PC | External cameras + sensor overlay |
| Tablet | Android tablet | Inventory, hull integrity, power allocation |
| Chart | Surface Go | Navigation chart, market intel, mission log |

---

## Architecture

```
Node.js server (gaming PC)
├── Express: serves /main, /tablet, /surface HTML pages
├── socket.io: broadcasts game state to all connected displays (100ms tick)
└── Game loop: physics, world state, event processing

Browser clients (each display)
├── /main     → Three.js scene + Canvas HUD overlay
├── /tablet   → Touch-optimized systems management UI
└── /surface  → Touch-optimized navigation + market UI
```

Game state flows **one direction**: server → all clients. Client inputs (button presses, touch gestures) send events **up** to the server, which updates state and broadcasts the result.

---

## Phase 1: Multi-display skeleton (first milestone)

Goal: All three screens connected and showing live data from the server. Proves the architecture before building content.

Steps:
1. `npm create vite@latest salvager -- --template vanilla-ts`
2. Add `express` + `socket.io` server (`server/index.ts`)
3. Serve three static HTML entry points: `/main`, `/tablet`, `/surface`
4. Server emits a `state` event every 100ms with a stub game state object
5. Each page shows: connection status indicator, display role label, live tick counter
6. Test: open `/tablet` on actual tablet browser and `/surface` on Surface Go browser via local network IP

**Done when:** all three physical displays show "Connected" and a live tick number.

---

## Phase 2: Main display

- Three.js scene: asteroid field with a derelict wreck at centre
- 4 camera modes (fore/aft/port/starboard), switchable via keyboard initially
- Canvas HUD overlay on top of Three.js canvas:
  - Circular radar (contacts as dots)
  - Velocity + heading readout
  - Distance to target
  - Active camera label
- Aesthetic: amber monochrome, worn/industrial, CRT scanline effect optional

---

## Phase 3: Secondary displays

**Tablet (`/tablet`):**
- Inventory grid (touch-draggable cargo items)
- Hull integrity heatmap of the ship (tap section for details)
- Power allocation sliders (engines / shields / sensors / cutting arm)

**Surface Go (`/surface`):**
- Procedural star chart (touch-pan + pinch-zoom)
- Current system: nearby wrecks, faction territory, patrol routes
- Market prices by faction station
- Mission/comms log

---

## Phase 4: Gameplay loop

- **Wreck generator**: procedural derelict (modular station segments or ship hull)
- **Approach mechanic**: match velocity, dock or position alongside
- **Structural risk**: each extraction cut increases collapse probability; tablet shows live risk meter
- **Cargo inventory**: weight/volume limits, item types (scrap, tech salvage, contraband)
- **Faction market**: prices vary by faction and cargo type; reputation affects access
- **Threats**: rival salvagers on radar, faction patrol timers, structural events

---

## Phase 5: Physical controls

- **X55 joystick + X52 throttle**: Gamepad API (browser-native, no drivers needed). Map axes to ship thrust/rotation.
- **Logitech flight switch panel**: USB HID device. Short term: use the user's existing vibecoded remapping tool to map switches to keyboard inputs. Long term: Electron wrapper + `node-hid` for direct reads.
- **Switch functions to design:**
  - Sensor mode: active radar / passive / thermal / EM
  - Camera: fore / aft / port / starboard
  - Cutting arm: armed / safe / intensity up / down
  - Lights: interior / exterior / off
  - Comms: open channel / close / scramble

---

## Aesthetic direction

Industrial amber monochrome primary palette. Red/orange for warnings. Worn, patched-together feel — not military-sleek. Analog gauge style mixed with digital readouts. Influence: Gato's instrument density + Hardwired's gritty tech + Elite's dark cockpit.

---

## Verification

- **Phase 1**: Three physical screens (or browser tabs) show "Connected" + live tick
- **Phase 2**: Three.js asteroid/wreck scene renders on main display; camera modes switch
- **Phase 3**: Tablet inventory responds to touch; Surface Go chart pans/zooms
- **Full loop**: Complete a salvage run — jump in, scan, approach wreck, extract 3 items with increasing risk, sell at a faction station
