# Salvager

A space-sim that treats HOTAS, switches and multi-monitors as first-class components in the simulation experience.

A cyberpunk mercenary **salvage sim** built for a multi-display hardware simpit.
One process drives one native window per monitor — an external hull-camera view,
a read-only glass-cockpit instrument panel, two touch MFDs, and a second
external camera — fed by
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
with its own input stream — a whole screen where there's one to spare, otherwise a
tile of one (see **Simpit / multi-display setup**).

| Role | Window | What it shows | How you interact |
| --- | --- | --- | --- |
| **Main** | `MainViewWindow` | Edge-to-edge hull-camera feed of the 3D world (ship, wreck, debris) with a thin HUD. | Flight + camera glance (HOTAS / keyboard). |
| **Tactical** | `TacticalWindow` | **A glass-cockpit instrument band** — heading tape, speed tape, attitude indicator, altitude tape, rotation-rate ribbons, LH2/LOX tank tapes and the ship's builder's plate — framing one of two modes: SCOPE (sensor scope, hull-damage heatmap, structural-risk meter) or CHART (system star chart). Altitude, heading, range and attitude are all measured against a selectable **navigation reference** (see below). | **No buttons at all** — it's an instrument you read. Mode and datum are stepped by mapped controls; anything these instruments need setting is on the MFD **SETTINGS** page. Mouse pan/zoom still works on the chart. |
| **MFDs** | `MfdWindow` | **Two side-by-side MFDs**, each with a MENU home and pages: **CHECKLIST** (the four operating procedures, ticked off against live ship state), **POWER** (channel sliders), **CARGO**, **SALVAGE** (cut-target list + sensor mode + approach/cut), **ALIGN** (the pre-cut alignment mini-game — crosshair, lock/slip meters, COMMIT/CANCEL), **SCOOP** (the post-cut collection instrument — cone field, drift arrow, gate checklist, OPEN/SECURE HATCH), **MARKET** (prices + comms), **DOCK** (the docking/landing instrument — ATC instruction banner, gate cone field, pad view on final, rule checklist, REQUEST/GEAR/ABORT), **CONTACTS** (lock list), **SETTINGS** (navigation reference, Tactical band show/hide, rate-ribbon scale, and the audio mixer — a level per bus plus MUTE). The primary MFD auto-opens **ALIGN** while alignment is live, **SCOOP** while the cargo hatch is open, and **DOCK** while a station pattern is being flown, handing the screen back after each. | Touch/mouse: tap the bezel **☰ MENU** button (or a mapped MFD-menu button — keyboard **G**/**H**) from any page to reach the home grid, then tap straight to the page you want. The mapped **Page +/−** controls wrap through the pages only — the MENU home is *not* in that cycle, so paging never dumps you onto the menu. Every command is also HOTAS-mappable. Buttons and list rows across every MFD page are sized as touch targets, for working the panel with a finger rather than a mouse. |
| **Camera** | `CameraWindow` | A **second external camera** of your own ship — **REAR** (rear-view, looking aft), **SIDE**, **CHASE**, **TOP**, and **BELLY** (straight down past the hull — the landing view) — rendering the same 3D world as the Main view. | Selectable by a mapped control (cycle, or one button per view). |

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
- **Adrift salvage markers** — a severed member doesn't stow itself: it becomes a
  real, drifting piece with its own diamond `◆` (amber), name, and range, plus an
  edge arrow when it's off-screen — same idiom as the cut-target marker, and it's
  free-for-all (the rival can beat you to a piece, and you can beat it to one it
  cut). Once the **cargo hatch** is open a live **REL SPD** readout appears under
  the marker — the number you're flying to zero out — and holding the four
  collection gates (hatch open, in range, relative speed nulled, piece inside the
  hatch's forward cone) fills a **scoop ring** around the marker, which greens as it
  fills and stows the piece on completion. The cue under the marker names the one
  gate still blocking you — **CLOSE IN**, **OFF-AXIS nn°**, **MATCH SPEED**, then
  **SCOOPING** — so a stalled scoop always tells you what to fix. The full
  instrument version is the MFD **SCOOP** page.
- **Cargo hatch indicator** — a pulsing reminder, top-right, whenever the door is
  anything but shut. Reads **CARGO HATCH IN TRANSIT nn%** through its 2.5-second
  travel and **CARGO HATCH OPEN** once it's on the stop — your cue that the cutter
  and dock/jump are both interlocked off until you secure it. Like the gear, the
  door is *slow on purpose*: a door still moving will neither pass a piece nor
  clear you to cut, so opening the hold is something you commit to on the run-in.
- **Docking markers** — only while a station pattern is being flown. The next
  gate gets a diamond `◆` with its name and range, and its **ring is drawn at the
  size it actually subtends** from where you are, so it grows as you close and
  "am I lined up?" becomes a question about a circle rather than a guess; an edge
  arrow points the way round when it's off frame. The marker turns red the moment
  you're outside the lane corridor or over the pattern speed. **ATC's standing
  instruction** sits under the reticle (pulsing red while it's urgent), and the
  **VEL** readout grows the limit you were given — `VEL 14.2 / 12 M/S` — going red
  exactly when ATC starts counting toward a go-around. On final a **landing
  ladder** reads altitude, sink rate (ambering, then reddening, as it passes what
  the legs will take) and how far off the pad markings you are.
- **Gear indicator** — under the hatch indicator whenever the gear isn't stowed:
  **GEAR IN TRANSIT nn%** during its 3-second travel, then **GEAR DOWN**. Fly
  faster than the gear is rated for with it out and it becomes a pulsing red
  **GEAR OVERSPEED** — the legs are taking the load and wearing.
- **Drive annunciator** — under the assist annunciator, and silent while the
  drive is making its rated thrust. **IMPULSE** or **BOOST** appears beside the
  **VEL** readout while a reaction stage is burning, so spending propellant is
  never silent; **DRIVE R / L / STARTING / OFF** names the selector position when
  it isn't making full thrust; red **THRUST UNPOWERED** calls a THRUST channel
  delivering nothing, which the drive's own state can't show you (the stages keep
  turning on a dead bus); and a pulsing red **LH2 DEPLETED** calls the empty
  hydrogen tank, which costs 60% of the ship's acceleration and is not something
  to discover on short final. There are three quite different ways to end up with
  no thrust — a shut-down drive, a dead bus and a dry tank — and they read
  differently on purpose.
- **Assist annunciator** — under the gear indicator, and *silent while nominal*
  (an annunciator that's always lit tells you nothing). Reads **ASSIST OFF** when
  you've switched the stability augmentation off yourself, or **ASSIST DEGRADED
  nn%** when it can't deliver full authority — starved THRUST allocation, a worn
  DRIVE section, or both. It pulses red once authority drops below the half the
  alignment mini-game requires, which is the point at which the degradation
  starts costing you salvage rather than just feel.

---

## The Tactical instrument band

The Tactical display frames whichever mode is up (SCOPE or CHART) with a
glass-cockpit instrument band, drawn in `scenes/ui/InstrumentBand.gd`. **VEL, the
attitude indicator and ALT form one flight block** down the left in that order,
with the tactical picture outboard on the right — the arrangement a pilot's eye
is trained on, and the reason the attitude indicator is the biggest thing on the
display. Nothing on it is clickable.

- **Heading tape** — across the top. Ticks every 5°, labels every 10°, the live
  hull heading boxed on the lubber line. A **bug** on the tape marks the bearing
  to the navigation reference. This is the **hull's** heading; the Main HUD's
  `HDG` is the **camera's**, and they differ whenever you're glancing.
- **Speed tape** — m/s, with the live figure boxed. The drive's current ceiling
  draws a hatched band across the top of the tape; with the gear out, a second
  amber band marks the 18 m/s the legs are rated for; and inside a station
  pattern ATC's speed limit rides the tape as a bug that reddens the moment
  you're over it.
- **Attitude indicator** — the horizon, split into a dark sky field and a
  stippled ground field. The **waterline symbol at the centre never moves**;
  everything else moves behind it. Pitch up and the horizon drops below the
  waterline and the ball fills with sky; pitch down and the stipple fills it. The
  **pitch ladder** is barred every 5° and labelled every 10°, **solid above the
  horizon and dashed below**, tapering with angle. A **roll pointer** rides a
  fixed sky scale marked to 60° — wings are level when it sits on the index at
  the top, which is the same fact the flat horizon line reports a second way. If
  a steep attitude takes the horizon out of the ball entirely, a chevron at the
  edge points the short way back to level. The ground field is captioned with the
  plane it belongs to, because *level* means level with the **selected datum**.
- **Altitude tape** — height above the datum's plane, with a **vertical-speed
  trend arrow** off the pointer that ambers and then reddens past the sink rates
  the legs will take. On the landing platform the datum plane is a real deck, so
  it gets a ground band — and the tape then reads the same number as the Main
  HUD's landing ladder.
- **Rotation-rate ribbons** — pitch, yaw and roll body rates as centre-zero
  tapes. Nulling a tumble is driving three pointers onto one centre line. Full
  scale is the ship's rated 45°/s, or ±15°/s on the **FINE** setting.
- **Propellant** — LH2 and LOX as vertical tank tapes, amber under a quarter and
  red when dry.
- **Builder's plate** — the ship's name, registry, hull serial, yard and year,
  etched on a plate at the bottom left. It is the one thing on the display that
  never changes.

### The navigation reference

Altitude, heading, range **and** attitude all need something to be measured
against — in space there is no altitude without one. They share a single
selectable **datum** (`systems/NavReference.gd`), so they can never disagree
about which way is up. The datum is named on the band's legend and again on the
attitude indicator's ground field.

| Datum | Measured from |
| --- | --- |
| **AUTO** | Follows the run: the landing platform while an approach is being flown, otherwise the cut target, otherwise the derelict, otherwise inertial. |
| **PLATFORM** | The harbour's landing platform and its deck plane. |
| **DERELICT** | The derelict on site, and a level plane through it. |
| **TARGET** | The selected cut target, or the designated contact. |
| **INERTIAL** | The world's own frame. |

The derelict and the target supply only the *origin* — the horizon stays level
with the station's plane, because a derelict tumbles and an attitude ball pinned
to a tumbling hull is unusable.

Step the datum with **Y** (or a bound HOTAS button), jump straight to the
platform or the target with the unbound `nav_ref_pad` / `nav_ref_target`, or pick
one on the MFD **SETTINGS** page — which also reports what AUTO has resolved to.
Pin a datum that has no fix and the band says so and holds a fallback rather than
quietly reading from somewhere you didn't choose.

The band can be hidden entirely (`tactical_band_toggle`, or SETTINGS), which
hands the sensor scope the whole display back.

---

## The launch screen

The game boots to a **title card** on the Main display (`scenes/displays/TitleCard.gd`),
before any other window opens. It's the one place that gathers everything you set
*before* flying, so a cold start is: read three lines, press **LAUNCH**.

| On the card | What it does |
| --- | --- |
| **SCENARIO** | Which run to fly, with a blurb for the selected one. Today there is exactly one — **DEMO RUN**, the shipped sandbox (tumbling frigate on a Freehold claim, a rival cutter, a patrol). Scenarios are a data list (`GameState.SCENARIOS`), so a second run is a catalog entry, not new UI. |
| **SET UP DISPLAYS  (F6)** | Opens the same **Display Setup** chooser described under *Simpit / multi-display setup*, as a step you come back from — confirm it and you're back on the card with the new assignment shown. The status line reads the live mapping (`3 screens  MAIN→0  TACTICAL→1 …`) and turns amber when this monitor setup has never been assigned. When two or more roles land on one screen it adds a second line saying what **LAUNCH** will do with them — tiled side by side, or tabbed where the tiles would be too small to read — and names the screen when the shared screens don't all come out the same way (`screen 0 is too tight to tile — LAUNCH tabs the displays there and tiles the rest`). |
| **SET UP CONTROLS  (F7)** | Opens the same in-game **remapper** described under *Remapping the controls*. The status line lists the sticks currently detected, or says you're on the keyboard mapping. |
| **PILOT'S MANUAL** | Opens the ship's handbook — her systems, her limits and the four checklists. See below. |
| **TERMINAL PROCEDURES** | Opens the harbour's document — the approach lane and its plate, clearance, charges and local notices. A separate publication because it has a separate publisher. See below. |
| **LAUNCH** | Starts the run: places the display windows and lets the world run. It's focused at boot, so **Enter** launches. If this monitor setup has never been assigned, the display chooser comes up first (the DISPLAYS line warns that it will), then the run starts. |
| **QUIT** | Same as **Esc**. |

**Nothing runs until you launch.** The scene tree is paused while the card is up,
so the wreck, the rival and the clock are all frozen behind it — you're looking at
a still of the world you're about to fly into, not one that started without you.
The F6/F7 surfaces stay live while it's paused, and the secondary display windows
don't open until **LAUNCH**, so plugging in a stick or re-assigning screens costs
you nothing. The switch panel is the one thing deliberately held back: its bridge
writes power and hatch state straight through, so it stays parked until the run
starts and then syncs to whatever position every switch is physically in.

### The ship's documents

The card opens **two documents**, because the ship carries two and they have two
different publishers. Both are read in the same viewer
(`scenes/displays/ManualViewer.gd`) — a contents list, one chapter at a time —
and both are written as operating documents rather than as a guide.

| Button | Publisher | What's in it |
| --- | --- | --- |
| **PILOT'S MANUAL** | The builder. True of the Kestrel wherever she's flown. | The ship: description, flight controls, **electrical & power** (alternator, battery, the bus), **drive & propellant** (the selector's positions, the two tanks, the starter), **drive failures** (what to do when she stops making thrust), sensors, cutting torch, cargo hatch, landing gear, **landing limitations** (what the legs will take), hull, **exterior lighting** (the three groups, what they draw, what they cost in signature), scope, instruments; **how a derelict hull behaves under the torch**; and the four checklists — **departure, arrival, cutting, collecting**. |
| **TERMINAL PROCEDURES** | The harbour, the claim office, the commercial agent. Changes without the handbook changing, and differs berth to berth. | The approach lane and its plate, speed limits and compliance, clearance and traffic, the berth and how an arrival is assessed, the arrival and departure procedures, claim conditions, the schedule of prices (cargo **and propellant**), and the system chart. |

**The division is authorship, not subject.** The builder can state what the legs
will accept at touchdown and how a loaded frame behaves when you cut it — a
tool's manual describes what the tool does to the work. It cannot state where a
harbour will let you put the ship down, what it charges, or how a rival will
behave: those are dictated by others. So the marker names, ring and corridor
sizes and speed limits appear **only** in the terminal procedures, the airframe
figures appear **only** in the handbook, and an arrival is flown from both — the
handbook for the ship's configuration, the plate for the lane.
`tools/PilotManualSmoke.tscn` asserts that neither document publishes the other's
material.

**Every control either names is the one you have bound right now.** The chapters
are written with binding placeholders that resolve through
`scenes/ui/BindingLabel.gd`, which reads the live Input Map, so remapping in
**F7** and reopening shows the new binding — and a control with nothing bound to
it reads **`NOT ASSIGNED`** in amber rather than quietly naming a key you don't
have. Both documents are launch-screen surfaces: read them before you fly, then
**Esc** or **CLOSE** back to the card.

**In flight, the checklists are on the MFD instead.** The handbook's four
procedures — departure, arrival, cutting, collecting — are also carried on the
MFD **CHECKLIST** page, one row per item, marked off against what the ship is
actually doing: hatch secured, gear down and locked, CUTTER at the interlock
minimum, approach `MATCHED`, the scoop's four gates, the touchdown limits. Those
rows read the same evaluations the interlocks themselves test
(`DockingSystem.status()`, `DriftSystem.collection_status()`, `GameState`), so a
green tick and a refused command can't disagree — and a row you can't satisfy is
naming the reason before you press for it. The handful of items nothing aboard
can judge (attitude flown by hand, stowage seen in the log) are **tapped off**;
every other row is live and deliberately **not** tappable, so a tick always means
the ship agrees rather than that you ticked it hopefully. An item that doesn't
apply yet reads `—`, not a failure. The page states no figures of its own — every
limit it prints is read from the constant that enforces it — so the handbook stays
the prose of record and the page can't drift away from it.

Each document's chapters are a data catalog
(`scenes/displays/PilotManualContent.gd`,
`scenes/displays/TerminalProceduresContent.gd`), so a new chapter is an entry
there and nothing else. Every figure in both is quoted from code — see the
`CLAUDE.md` note about keeping them in step.

**Both print.** `pwsh tools/build_manuals.ps1` renders the two catalogs to
print-styled HTML and then to PDF, resolving the binding placeholders through the
real reader so a printed step names the control you actually have bound. Output
lands in `build/manuals/` and is gitignored — the catalogs are the source of
truth, and a committed PDF would be a third in-tree copy of every figure in them.

**Both publish.** Pushing a `v*` tag runs
[.github/workflows/manuals.yml](.github/workflows/manuals.yml), which prints both
documents from a clean checkout and attaches them to that GitHub release, so the
current pair is downloadable without a Godot install:
[pilot's manual](https://github.com/chandlercv/simpit-game/releases/latest/download/pilots-manual.pdf)
and
[terminal procedures](https://github.com/chandlercv/simpit-game/releases/latest/download/terminal-procedures.pdf)
— both links always resolve to the newest release. Every pull request builds the
same two PDFs and attaches them to the run instead, so a catalog change can be
read on paper before it merges.

---

## Core gameplay loop

You fly a salvage ship to a wreck, cut it apart for cargo without letting the
frame collapse on you, then fly a station's docking pattern and sell. On site
(`ON_SITE` phase):

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
   *The autopilot flies on the drive and **burns propellant to do it** — closing
   and braking are charged at the rate the same burn would cost by hand, and
   holding the standoff against a tumbling frame costs a trickle more for as long
   as you hold it. A coast at constant velocity is free either way.*
   *The throttle must be eased back under ~40% to arm the autopilot, the drive
   has to actually be making thrust (it flies on the drive, so a shut-down drive
   or a dry hydrogen tank on `L` refuses the engagement, and shutting the drive
   down while it's flying disengages it), the **THRUST channel has to be
   delivering at least 0.05** (it flies on the amps too, and the stages keep
   turning on a bus that's stopped feeding them — so an allocation wound below
   that, or an alternator off with a flat battery, refuses the engagement and
   disengages it mid-approach; the closing rate scales with the delivered figure,
   so a thin allocation arrives slowly), and
   any real stick/throttle input while it's flying hands control back to you.
   However you lose it, you lose the standoff with it — and any alignment or cut
   in progress ends there.*
4. **Power the cutter.** Raise the **CUTTER** power channel to at least 0.2 on
   an MFD **POWER** page.
5. **Align the cutting head.** With the approach `MATCHED`, fire the cutter to
   open the alignment mini-game (it does **not** cut yet). Aiming takes
   **pitch/yaw away from flying the ship**, so it needs at least half stability
   authority to open — starve THRUST to feed the torch, or fly a badly worn DRIVE
   section, and the alignment is refused (and aborts if authority drops during
   one). The seam target `⊕` is a real point on the member, so it drifts across
   your view **because the wreck is tumbling** — since you matched the wreck's
   drift but not its spin, holding the cut takes hands-on tracking. Steer your
   torch reticle `✛` — with **pitch/yaw** — onto the seam and hold it inside the
   tolerance ring to fill the **lock**. Watch it on the Main HUD crosshair or the
   MFD **ALIGN** page. Let the torch wander too far and the **slip** meter fills
   and the alignment aborts (no cut).
6. **Commit the cut.** The lock auto-commits at full, or press the cutter again to
   commit early at the current quality. The cutting beam from the ship's **right
   wing** bites into the member, which severs over time — and **detaches as a real,
   drifting piece** (picking up the wreck's own tumble plus a parting kick from the
   torch), not a stow. **Alignment quality is the payoff:** a clean lock cuts
   faster, spikes structural risk less, and leaves the piece carrying more yield;
   a sloppy one crawls, spikes harder, and loses salvage.
7. **Collect the piece.** Open the **cargo hatch** — a keybind (`cargo_hatch_open`,
   default **B**) or the switch panel's **COWL** switch — then fly alongside the
   drifting piece: close to scoop range, null your relative speed against it, and
   keep it inside the hatch's forward cone. Hold all four and the scoop fills and
   stows it. **Fly this on the MFD `SCOOP` page**, which the primary MFD opens for
   you the moment the hatch does: its **cone field** puts the piece's marker where
   it actually sits off your nose, so pitching/yawing the marker into the tolerance
   ring *is* the aiming task (an edge arrow points the way round when it's off the
   field); the **drift arrow** off the marker shows which way and how fast the piece
   is sliding relative to you, so you thrust along it to null the drift; and the
   **gate checklist** shows each gate's live value against its limit, so a scoop
   that won't fill always names the gate holding it up. **The hatch is a real
   trade-off: it blocks firing the cutter and blocks docking/jumping while open**,
   so you open it only to collect, then secure it to keep working. Adrift pieces are
   **free-for-all** — the rival cutter runs the same sever-then-retrieve loop (minus
   the alignment step), and whoever reaches a piece first keeps it, including yours.
   It's a ship you can see doing it, lit and lying off the hull with its torch
   flaring each time it takes a member — not just a bracket on the glass.
   Pieces are **solid**: they bounce off the derelict, the station and each other
   rather than sinking through, so one you shove into the frame has to settle
   before it's slow enough to scoop.
8. **Watch structural risk.** Cutting load-bearing members spikes risk and
   ratchets the resting baseline up; cosmetic panels barely move it. If the
   frame collapses, every uncut member is lost.
   *Collapse also wears the hull — and hull damage is no longer just a record.*
9. **Mind the DRIVE section.** The ship carries real rotational momentum: the
   stick commands a rate and the **stability augmentation** holds it, nulling
   residual spin (including whatever a collision imparts). Its authority is the
   product of **THRUST allocation** and **DRIVE integrity**, so a heavy landing,
   flying over the gear limit with the legs out, or a collapse event all cash out
   later as a ship that no longer stops turning when you centre the stick. Lose it
   entirely and the controls command torque and nothing else — still flyable, but
   every rate you start is one you have to stop. You can also switch it off
   yourself (`fbw_mode_cycle`).
10. **Fly the approach and land.** On an MFD **MARKET** page, dock at a faction
    (this leaves the claim — the cargo hatch must be secured first). The transit
    burn only gets you to the station's outer approach: **the berth is flown for**
    (`APPROACH` phase). Work it on the MFD **DOCK** page, which the primary MFD
    opens for you:
    - **Hold at marker ALPHA.** Fly to the hold ring and *stop* (under 3 m/s).
      ATC refuses a clearance while you're still moving, and sequences you behind
      the station's traffic — a lane tug, a shuttle and a slow ore barge working
      the same volume. They are solid, and so is the station.
    - **Run the lane.** Cleared, you fly **BRAVO → CHARLIE → DELTA** in order,
      *through* each ring, staying inside the leg's corridor (22 m, then 15 m
      through the slot between two hab drums, then 10 m) and under the pattern
      speed. Miss a ring, leave the corridor, or sit over the limit and you're
      **sent around** to hold again.
    - **Hitting something is billed, not waved off.** A go-around is for the
      instructions you were given; contact is damage. Scrape a bay wall or clip a
      tug and you pay for it — hull, a **damages invoice** from the station
      (roughly a quarter of a run's takings for a light scrape, half for a bad
      one), and **standing** — but you keep your clearance and carry on flying.
      Anything you can't pay comes out of your reputation instead.
      A knock also buys a few seconds' **amnesty** on the speed and corridor
      rules: the impact shoves you off your line, and being waved off for a
      deviation the station's own wall gave you would make "contact keeps your
      clearance" meaningless. Even a graze too gentle to damage anything gets
      called out, so you are never knocked silently.
      Repeated go-arounds bleed standing, but only **up to a cap per visit** — a
      pattern you are struggling with should cost you a reputation, not erase
      one.
    - **Gear down before the final gate.** The landing gear (keyboard **X**, or
      the switch panel's **GEAR** lever) takes 3 seconds to travel, so it's a call
      you act on early — arriving at DELTA with it up is a go-around, as is an
      open cargo hatch.
    - **Turn the corner.** The descent corridor is a **funnel**: it is wide where
      you cross DELTA — you arrive there with horizontal speed and a vertical drop
      to fly, so the overshoot is part of the manoeuvre — and tightens to 6 m by
      the time you are down between the bay walls, where there is something to hit.
    - **Land it.** Descend into the berth and put it on the pad: inside the deck
      markings, wings level, under the sink rate the legs will take. **You land on
      the legs, level** — the touchdown check rejects more than 20° of tilt, so
      pitching the nose down at the pad both fails it and puts the bow into the
      deck. The pad is directly beneath you and the hull camera looks forward, so
      fly the last stretch on the Camera display's **BELLY** view (keyboard **5**),
      the MFD **DOCK** page's pad view, and the HUD landing ladder. The touchdown
      is **scored** — a greaser earns standing with the faction, a hard arrival
      costs hull, and anything worse bounces you back into the pattern.

    Then **shut the drive down (magneto OFF), open the cargo hatch** and sell your
    hold at that faction's prices — the hold discharges *through* the hatch, so a
    buttoned-up ship has nothing to hand over. This is also where you buy
    propellant. Then **ALT off, BAT off** and she's quiet on the pad.
    **Anything still adrift when you leave the claim is abandoned** — you jump back to a fresh wreck, not to the
    pieces you left floating — so scoop before you depart. Away from the claim the
    `SCOOP` page stops flying the rendezvous and reads **COLLECTION SUSPENDED**,
    counting what you left behind.

    *Don't want the mini-game?* ATC will fly you in: **AUTO-BERTH** on the MARKET
    or DOCK page books the berth for a handling fee and a hit to your standing —
    deliberately a worse deal than flying it well, and refused once you're on
    final.
11. **Fly the departure.** Leaving is flown too. First, though, the ship has to be
    woken up: **BAT on, ALT on, hatch secured, then the drive started** — magneto to
    **START**, ten seconds, then back to a running position. Nothing moves until
    that's done, and it's the price of having shut her down on arrival.

    Undocking then lifts you off the pad into a departure hold; ATC sequences you
    out around the same traffic, and you run the lane in reverse (**DELTA →
    CHARLIE → BRAVO → ALPHA**). **Raise the gear as soon as the pad is clear** —
    there's no longer any point outbound where it has to stay down, and the lane is
    flown faster than the legs are rated for — but ATC won't release you for the
    jump until it's stowed. Break a rule on the way out and you get a reprimand and
    a standing cost rather than a go-around — you're leaving either way.

**Power budget:** four channels — **THRUST, CUTTER, SENSORS, LIFE** — each
0..1. THRUST gates approach/manual acceleration, CUTTER gates cutting, SENSORS
gates scan speed.

The reactor is always lit; the **alternator** turns its output into electricity
(2.5 units' worth) and the **battery** buffers the difference between that and
what the channels are drawing. Draw more than the alternator makes and the
battery covers it and runs down — 120 seconds at a one-unit deficit — so overdraw
is now a real cost rather than a red header. Draw less and the surplus recharges
it. **THRUST's draw depends on what the drive is doing:** the electrodynamic
stage is expensive and the nuclear-thermal stage is nearly free, so running the
hydrogen tank dry raises the bus load at the same moment it costs you thrust.

**Settings and delivery are two different things.** Nothing electrical ever
rewrites an allocation you set: a starved bus shows the slider where you put it
and the smaller figure being delivered against it (`80→31%`), and full output
returns the instant supply does. Edits made on a dark ship stick and take effect
when the lights come back.

**Propulsion:** the drive is a hybrid, and which parts of it are running is a
decision you make on the switch panel's five-position magneto (or two mapped
keys). Speed is capped by the ship's **Higgs coupling** — a drag that only bites
because of the compact fusion reactor she carries — and the only way past that
cap is to throw real reaction mass out the back.

| Selector | Stages | Burns | Thrust | Max speed | Bus load |
| --- | --- | --- | --- | --- | --- |
| **OFF** | none | — | none | — | none |
| **R** | electrodynamic field | nothing | 40% | 25 m/s | high |
| **L** | nuclear thermal | LH2 | 60% | 35 m/s | low |
| **BOTH** | both | LH2 | 100% | 35 m/s | high |
| **+ boost** (held) | + combustion | LH2 **and** LOX | 100% | 50 m/s | as beneath |
| **START** | the starter — 10 s, then turn back to a running position | | | | |

**There's no automatic reversion.** A stage runs when it's *selected* and
*supplied*, and nothing steps in for one that isn't — so at **L** with a dry
hydrogen tank you get **no thrust at all** until you select R or BOTH. At BOTH
the field stage is already selected and you keep flying on it, at 40%. Running
dry never strands you, but it won't fly you home by itself either, and the
recovery costs amps you may not have. Liquid oxygen is useless without hydrogen;
both are bought at a berth (8 CR and 30 CR per unit) and neither is replenished
in flight.

**Manual flight throttle:** by default the throttle (forward/back) commands a
target speed, not raw thrust — ease it to 50% and the ship accelerates to, then
holds, 50% of *whatever maximum the drive can currently hold*; let go and it
holds station on that axis. A mapped **Throttle Cmd Mode** button swaps this for
the legacy direct-thrust feel (throttle = acceleration, no cruise control).
Strafe, vertical, and reverse are all secondary thrusters off the same drive —
each rated at 50% of the main thruster's forward performance
(`ShipDefinition.secondary_thrust_fraction`, one knob for the whole maneuvering
profile).

Each channel can be driven from the switch panel (see the switch table below):
FUEL PUMP→THRUST, AVIONICS→SENSORS, DE-ICE→CUTTER, PITOT HEAT→LIFE. The first
three toggle a shared **high (80%) / low (20%)** setting; PITOT HEAT runs LIFE
full (100%) on / low off. Any channel can also be set to any value on an MFD
**POWER** page, from a mapped analog axis (used as a slider), or nudged up/down
by a mapped key/button — and the four channels now ship **bound by default** on
the number row.

The two master switches decide what the bus can *supply*, not what the mix is.
**MASTER ALT off** stops the alternator generating, so the ship runs on the
battery until it's flat and then goes quiet. **MASTER BAT off** removes the
buffer: delivery is capped at whatever the alternator is making right now and a
heavier load is shared out proportionally. Both off is a dark ship — and it's
also the state you leave her in on the pad. Running dark halves the ship's
visibility to passive scanners — the claim-holder's patrol has to close to half
its usual range before it can fine you (a quarter if both masters are off).

**The exterior lights are the third term**, and a much smaller one: each of the
three groups you switch off takes a further 5% off the signature. They *compound*
with the masters rather than replacing them — a dark bus puts the lights out too —
so a blacked-out ship sits a little below the quarter the masters alone give. See
**Exterior lighting** in the pilot's handbook.

**The masters don't stop the drive.** That's the selector's job, and the two are
independent (see *Propulsion* below).


---

## Sound

### One rule: you are inside a hull, in vacuum

Outside the pressure hull there is no air, so nothing out there radiates sound to
you. Every sound in the game arrives by exactly one of two paths, and that
decides what it is allowed to sound like:

| Path | What you hear | What travels it |
| --- | --- | --- |
| **Structure-borne** | Hard-lowpassed, no crisp top end, smeared by the frame's own ring. Felt as much as heard. | Everything bolted to the outside — the legs, the cargo door's leadscrew, the cutting head, the thrusters, the drive. |
| **Cabin air** | The only sounds with any top end. Dry, close, present. | The ventilation, the annunciator panel, the inboard capacitor bank, and the hold's air arriving through the bulkhead. |

That distinction lives on an audio **bus**, not in the clips, so the hull colours
everything mechanical identically. The payoff is what happens when you starve the
**LIFE** channel: the ventilation is the only continuous airborne machine on the
ship, so the cabin falls to silence — while a landing-gear clunk still arrives
through the frame. Nothing else sells vacuum half as well.

A few consequences you can hear:

- The **landing gear** is three legs, and they don't arrive together — three
  staggered downlock clunks, all of it conducted, with no air rush anywhere,
  because the legs are outside.
- The **cargo door** is the exception, and deliberately so: the hold sits behind
  a pressure bulkhead. Opening it dumps the hold's residual air, and you hear
  that go — a gasp that filters downward and dies as the air runs out. Closing it
  repressurises, and the hiss builds *into* existence.
- The **cutter** never roars, because there's nothing out there to roar in. You
  get the capacitor bank charging (inboard, so it's crisp), a contactor snap, the
  conducted crackle of ablation coming back down the boom — and a coolant pump
  that keeps running for a second after you let go, because the head is still hot.
- **Thrusters** are valves and reaction loads. The plume is silent; what reaches
  you is the solenoid cracking and the load going through the mounts. The main
  drive is mostly sub-200 Hz — felt more than heard — and the **10-second starter
  crank** rises the whole way.

### Three voices

| Voice | Who | Treatment |
| --- | --- | --- |
| **Station** | ATC and the harbour — someone else, on a radio | 300–3400 Hz channel, compressed, announced by a chirp and closed by a squelch tail |
| **Ship** | Your own annunciator, reading a state back to you | Dry and close. It's a machine, and it's allowed to sound like one |
| **Pilot** | You, transmitting | Sidetone in your own headset — it never went over the air, so it keeps its body |

**The ship knows when to shut up.** Three rules keep the annunciator from
narrating:

- It **stands down entirely while the torch is live** — aligning or cutting.
  That's the one thing you're concentrating on, and it's exactly what a real
  annunciator is built not to talk over. The harbour is *not* hushed (that's
  someone else, and it's never chatter), and neither are the warning tones.
- It reports **the state it's in, not how it got there**. Only one of its lines
  can be pending, so a burst of changes is answered by the last of them rather
  than read out as a list you've already flown past.
- Boot banners and settings echoes are **never spoken at all**. An annunciator
  that reads back the switch you're looking at while you move it is noise.

Anything still queued after six seconds is dropped unspoken. The text hits the
instrument instantly and the voice can't keep up with a backlog; reading out a
clearance that was superseded ten seconds ago is worse than silence.

**The harbour addresses you by your tail number.** Full identity on first contact
— name spelled out, registry read letter by letter — and the last three of the
registry for every call after that, which is how a real lane keeps a pattern from
becoming a recital. Both come from the ship's own `ShipDefinition`, so a second
hull answers to its own:

```
FIRST    "SIERRA VICTOR KESTREL, LIMA UNIFORM FOUR FOUR SEVEN ONE KILO —
          MERIDIAN CO. CONTROL. SEQUENCING YOU INTO THE PATTERN FOR BERTH TWO."
AFTER    "SEVEN ONE KILO, CLEARED TO LAND, BERTH TWO."
YOU      "MERIDIAN CONTROL, SEVEN ONE KILO, HOLDING AT ALPHA,
          REQUESTING CLEARANCE."
```

Pressing **Request Clearance / Ack** transmits in your own voice, and it branches
the same four ways the control does: a clearance request, a departure request, a
readback, or the call that tells the harbour you're leaving the pattern.

Numbers are spoken the way a harbour speaks them — digit by digit, so **ONE FIVE**
can't be misheard as fifty, and **NINER** so nine can't be heard as five. Round
money is the exception, because nobody says "two zero zero credits".

### Warning, caution, note

The ship's alarms use the **same three callouts the printed handbook uses**, and
they *latch* — a condition raises once when it starts and clears once when it
stops, rather than re-announcing itself every frame:

| Level | Means | Sound |
| --- | --- | --- |
| **WARNING** | Damage to the ship, or salvage lost | An alternating two-tone warble that repeats until the condition clears. Deliberately the only piercing thing on the ship — that's why it cuts through |
| **CAUTION** | An interlock, a refusal, a limit | One triple-chirp, softer |
| **NOTE** | Clarification | One soft chime |

**WARNING is deliberately rare.** It is held — it sounds until the condition
clears — so it is reserved for the two things you can end *right now*: an open
electrical bus, and the gear out above its limit. Serious conditions you can't
silence by flying well are cautions instead. Structural risk is the clear case:
the resting value never falls, so a held warning there would start on the cut
that crosses the collapse floor and sound for the rest of the site whatever you
did — and an alarm you can't answer is an alarm you stop hearing, taking the two
that mean something down with it.

Nothing new appears on screen for these: the HUD annunciator stack already shows
every one of them. This adds the ear.

### The mixer

Five levels and a mute, on the MFD **SETTINGS** page — **ALL**, **CABIN**,
**HULL**, **RADIO** and **ALARMS** — plus **`\`** on the keyboard. A simpit runs
at odd hours and may have no keyboard within reach, so the one control someone
will want at two in the morning is a touch target. Settings persist under
`user://audio.cfg`.

### Where the sounds come from

Both banks are generated and committed, the same way the derelict's hull is:

| Script | Produces |
| --- | --- |
| `tools/build_sfx.py` | `assets/generated/sfx/*.wav` — every machine on the ship, synthesised from first principles in numpy. None of these could be recorded; a leadscrew heard through a pressure bulkhead in vacuum has no field recording. |
| `tools/build_speech.py` | `assets/generated/voice/*.ogg` — the spoken vocabulary. It reads the comms **format strings straight out of the source**, renders each literal piece between the `%` specifiers, and writes a manifest for putting them back together with the numbers spoken in between. So the lines are never copied: change a comms line, rebuild, and the spoken form follows. |


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
| **MASTER BAT** | The battery. Off = no buffer: delivery is capped at whatever the alternator is making right now, and a heavier load is shared out proportionally. Passive-scanner visibility drops 50%. |
| **MASTER ALT** | The alternator. Off = it generates nothing and the ship runs on the battery until that's flat, then goes quiet. Passive-scanner visibility drops 50% (stacks with BAT → 25% if both off). |
| **Magneto (OFF / R / L / BOTH / START)** | The **drive selector** — see *Propulsion* above. OFF shuts the drive down entirely; R runs the field stage, L the nuclear-thermal stage, BOTH runs both. START is the starter: leave it there **10 seconds**, then turn back to a running position. Selecting OFF costs a full start to undo. |
| **FUEL PUMP** | THRUST power: On = high (80%), Off = low (20%). |
| **AVIONICS** | SENSORS power: On = high, Off = low. |
| **DE-ICE** | CUTTER power: On = high, Off = low. |
| **PITOT HEAT** | LIFE power: On = 100% (life support runs full), Off = low (20%). |
| **COWL** | Open/close the cargo hatch — On = open (required to scoop an adrift salvage piece); Off = secured (required to fire the cutter or dock/jump). Same intent as the `cargo_hatch_open` keybind. |
| **GEAR UP / DOWN** | Raise/lower the landing gear. The gear then *travels* over 3 s — down and locked is what a landing needs, and what interlocks the cutter. Same intent as the `landing_gear` keybind. |
| **NAV** | Position lights — red to port, green to starboard, white on the tail. Steady. |
| **BEACON** | Anti-collision beacons, red, above and below the fuselage. ~45 flashes a minute. |
| **STROBE** | White strobes on both wingtips and the tail. A double pulse, ~1 Hz. |
| **LANDING** | Ship landing light on/off. Lights the pad, not the ship; draws nothing. |

The four channel switches toggle between shared **high (80%)** and **low (20%)**
settings; the MFD **POWER** page sliders (or a mapped power axis / nudge
key) can still set any value in between (until the next switch flip). Neither
master locks anything: an allocation you set is yours, and only what's *delivered*
against it changes when the bus can't carry it.

**The three light groups are a real system, not decoration.** Each draws a token
0.02 units off the bus while it's selected on (0.06 for the whole fit, against an
alternator making 2.5 — it will never starve a channel), each is *out* whenever the
bus has no source behind it whatever its switch says, and each one you extinguish
cuts your passive signature by 5%. They're on the **departure** and **arrival**
checklists for that reason.

The remaining switches — PANEL and TAXI — are decoded and logged but have no
gameplay effect yet.

### Keyboard (default mapping — overridable in the remapper)

A default keyboard mapping **ships as a built-in profile** (the `keyboard` entry
in `BUILTIN_PROFILES`, `autoload/InputRouter.gd`) — it's *data*, not hardcoded
`project.godot` keys, so the remapper shows it and a user profile
(`user://input_profiles/keyboard.json`) can override or clear any of it, key by
key. A control added to the game after you last saved keeps its default here
rather than arriving unbound — see *Remapping the controls* below. The defaults:

The map is laid out in **blocks by function**, so you learn regions rather than
forty separate keys — and so a new control has an obvious home instead of landing
on whatever key happened to be free:

**Number row — the systems panel**, read left to right: the four power channels
as −/+ pairs, then the two electrical masters, then the drive selector.

| Key | Action | | Key | Action |
| --- | --- | --- | --- | --- |
| **1 / 2** | THRUST power − / + | | **7 / 8** | LIFE power − / + |
| **3 / 4** | CUTTER power − / + | | **9** | MASTER BAT on/off |
| **5 / 6** | SENSORS power − / + | | **0** | MASTER ALT on/off |
| **− / =** | Drive selector back / forward (OFF · R · L · BOTH · START) | | | |

**Left hand — flight. Right hand — attitude and glance.**

| Key | Action | | Key | Action |
| --- | --- | --- | --- | --- |
| **W / S** | Thrust forward / back | | **I / K** | Pitch up / down |
| **A / D** | Strafe left / right | | **J / L** | Yaw left / right |
| **R / F** | Thrust up / down | | **Q / E** | Roll left / right |
| **Space** | Drive boost (**held**) | | **Arrow keys** | Glance camera |

**Bottom rows — ops verbs under the flight hand, selection under the other.**

| Key | Action | | Key | Action |
| --- | --- | --- | --- | --- |
| **Z** | Request clearance / acknowledge ATC | | **N** | Cycle locked contact |
| **X** | Landing gear up / down | | **M** | Cycle sensor mode |
| **C** | Fire cutter / align + commit | | **, / .** | Prev / next cut target |
| **V** | Toggle approach (needs a target) | | | |
| **B** | Open/close cargo hatch | | | |

**Displays.**

| Key | Action | | Key | Action |
| --- | --- | --- | --- | --- |
| **T** | Toggle Tactical SCOPE / CHART | | **[** | Camera → BELLY (the landing view) |
| **Y** | Cycle the navigation reference | | **]** | Cycle external camera |
| **G / H** | MFD-A / MFD-B → MENU | | **\** | Mute / unmute all audio |

The camera keeps two keys rather than six: `]` steps every view and `[` jumps
straight to **BELLY**, the one the landing procedure requires. REAR / SIDE /
CHASE / TOP are reachable by stepping and ship **unbound**, rather than eating the
number row the ship's systems now need. MFD paging, cargo, market, the throttle
command-law toggle (`throttle_cmd_toggle`), the flight-assist switch
(`fbw_mode_cycle`), the two direct navigation-reference selects (`nav_ref_pad`,
`nav_ref_target`) and the Tactical band's show/hide (`tactical_band_toggle`)
also ship unbound — bind any of them in the remapper. Every
default here is also HOTAS-bindable, and a key + a HOTAS bind can coexist on one
function.

During the pre-cut alignment mini-game the **pitch/yaw keys** (I / K, J / L) aim
the cutting head instead of flying the ship, so you steer the torch reticle onto
the seam with the same keys, then press **C** to commit.

The only fixed keys — not rebindable, since F7 must stay fixed to open the
remapper at all:

| Key | Action |
| --- | --- |
| **F7** | Open the remapper (Configure Controls) |
| **F5 / F6** | Re-detect monitors / open Display Setup |
| **F8** | Stamp a window/focus dump into the **window log** (see *Running*) |
| **Esc** | Quit (or cancel an in-progress bind while the remapper is open) |

### Mouse / touch (secondary displays)

| Display | Controls |
| --- | --- |
| **Tactical** | Read-only, and there is nothing to click. Mouse pan/zoom on the chart is the only mouse input it takes; mode, datum and the instrument band are driven by mapped controls or the MFD **SETTINGS** page. |
| **MFDs** | Tap **MENU** to open a page. **CHECKLIST** tap a procedure, then BACK / ▲ / ▼ / RESET (and tap a hand-marked item to tick it); **POWER** sliders; **CARGO** tap-to-select + jettison; **SALVAGE** sensor mode + approach/cut + tap a cut target; **MARKET** per-faction dock / sell / depart; **CONTACTS** tap to lock; **SETTINGS** tap a navigation reference, show/hide the Tactical band, pick the rate-ribbon scale. |
| **Camera** | View is picked by a mapped control (no on-screen buttons). |

Any input surface can drive the same intent — e.g. the four power channels are
set from an MFD's touch sliders, from a mapped power axis (slider) or key/button
(nudge), and, equivalently, from the switch panel's channel toggles (FUEL PUMP / AVIONICS / DE-ICE / PITOT
HEAT). Everything you can do on an MFD is also bindable to a HOTAS button or
axis (see the remapper groups **MFD / SALVAGE / TACTICAL / NAV / CARGO / MARKET
/ VIEW / POWER**). The Tactical SCOPE⇄CHART toggle is in **TACTICAL** — bind it
to a HOTAS button to flip the Tactical display without touching the screen. The
**NAV** group holds the navigation reference (cycle, or straight to the landing
platform or the cut target) and the Tactical band's show/hide — hiding the band
hands the sensor scope the whole display back, which is what you want while
reading a wreck. **Throttle
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

- **In-game remapper (easiest).** Press **F7** for *Configure Controls* — or, at
  boot, the launch screen's **SET UP CONTROLS** button, which opens the same
  thing. Each row
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
  in-progress bind. **A key or button another row already uses still binds** —
  you pass through that state constantly while rearranging a layout — but the
  status line names the row it collides with, and *both* rows turn amber and read
  **(clash)** until you move one of them. Two rows on one control means one press
  fires both. (Capture picks whichever control moves most from where it sat
  at bind, so a throttle can rest anywhere — just let a spring-loaded stick axis
  recenter first.) Glance from the X55 hat is raw-HID and always on, so its rows
  are blank by design.
- **A profile file.** Each saved device is one JSON file at
  `user://input_profiles/<guid>.json` — hand-editable and shareable (a tester can
  mail theirs back; drop it in the folder). A user profile **overrides** the
  built-in with the same GUID, or adds a brand-new device. Keyboard bindings live
  in the same folder as a device-less `keyboard.json` (GUID `keyboard`) carrying a
  `keys` array — see the schema below. The keyboard file overrides the shipped
  layout **key by key**, not wholesale: a key you cleared stays cleared, but an
  action your file never mentions *and was never offered* (because it was added to
  the game after the file was written) keeps its shipped default, so a new control
  can't strand a returning pilot with no way to reach it.
- **Built-in defaults.** The shipped X52/X55 mappings **and the default keyboard
  mapping** are the `BUILTIN_PROFILES` constant at the top of
  `autoload/InputRouter.gd` (the keyboard one is the device-less `keyboard`
  entry); a matching user profile wins (`_effective_profiles()` merges the two —
  wholesale for a device, key by key for the keyboard).
  Gameplay code never sees hardware
  numbers — bindings are injected into the Input Map at startup and on each replug.

A profile entry (the file and `BUILTIN_PROFILES` share one schema) has these keys:

| Key | What it maps |
| --- | --- |
| `axes` | Analog axes → a pair of direction actions, e.g. `{"axis": 1, "neg": "pitch_down", "pos": "pitch_up"}`. Swap `neg`/`pos` (or hit **REV**) to reverse. |
| `buttons` | Momentary buttons → one action, e.g. `{"button": 0, "action": "ops_cut"}`. |
| `keys` | **Keyboard keys → one action** (only on the device-less `keyboard` profile), e.g. `{"key": 67, "action": "ops_cut"}`. `key` is a Godot physical keycode. The shipped default keyboard mapping is the built-in `keyboard` profile; a user `keyboard.json` overrides it key by key (see `known_actions`). |
| `known_actions` | Written by the remapper on the `keyboard` profile: every action it offered a row for when the file was saved. It's how the game tells an action you **cleared** (listed, unbound — stays cleared) from one that simply **didn't exist yet** (not listed — gets its shipped key back). A hand-written file can omit it; every shipped default you left out then comes back, unless its key is taken. |
| `throttle` | The one axis read directly. Two curves, toggled by **MODE** in the remapper: **Lever** (default) — a one-directional lever that rests anywhere, rescaled to 0..1 *from the edge of its idle band*, so easing off the stop commands a hair of throttle instead of jumping straight to the band's width. General form `{"axis": 2, "idle": 1.0, "full": -1.0}` fits any rest/travel range and direction, with an optional normalized `deadzone` (default 0.05 — 5% of the lever's travel) at the idle end; the legacy X52 form `{"axis": 2, "idle_deadzone": 0.90}` still works, its raw threshold serving as that edge. **Gamepad** — `{"axis": 2, "mode": "gamepad", "invert": false}`, for a self-centering stick/trigger axis: 0 inside the deadzone (default 0.05), rescaled to ±1 at the stops. |
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
screens it opens **one native OS window per monitor**; with fewer, the displays
that share a screen are **tiled** into it, one native window each, so they stay
readable side by side instead of taking turns (`WindowManager`,
`scenes/displays/ScreenLayout.gd`). There is no window-embedding — a tile is a
real OS window, with its own input stream and its own content scale.

- **You choose the layout.** The in-game **Display Setup** chooser is one of the
  launch screen's two setup steps (**SET UP DISPLAYS**), and it also comes up on
  its own at **LAUNCH** the first time a monitor setup with fewer screens than
  displays is seen: each screen shows a card, and you tap a role (MAIN / TACTICAL
  / MFD / CAMERA) to put it there. A sensible layout is pre-filled — accept it
  with the confirm button, or reassign first. **That button says what it will
  do**, since confirming means something different depending on where you opened
  the chooser: **BACK TO TITLE** when it's the launch screen's DISPLAYS step,
  **LAUNCH** when it came up at launch because this setup was never assigned, and
  **APPLY** for an `F6` re-assign mid-run. The
  choice is saved **per monitor setup**
  (`user://display_config.cfg`, keyed by screen count + geometry), so the same rig
  never asks twice, but a different arrangement asks again. Press **F6** anytime to
  re-open the chooser; **F5** re-detects monitors and rebuilds the layout (a known
  setup applies silently, an unknown one re-opens the chooser). No restart needed.
- **How shared screens look.** Roles that share a screen are tiled into it and are
  all live at once — nothing has to be brought to the front to be read.
  - On the **Main** screen the hull-cam view keeps the **top two thirds** and the
    panels take an equal share of the **bottom third** each, left to right. The
    Main window leaves fullscreen to make room, so the taskbar comes back and each
    tile gets its own taskbar button.
  - On a **spare** screen a lone role still covers it edge to edge. Two or three
    share it as rows: the **MFDs take the full-width bottom row** — the display you
    reach for, and the one that wants the width for two units — with the others
    splitting the row above. So **two monitors show tactical, MFD and camera all
    at once** on the spare screen, with the flight view fullscreen on the other.
  - **Where a region is too small to tile legibly**, it falls back to the old
    **tabbed host**: one panel at a time, switched by an on-screen tab strip
    **and** by `F1`/`F2`/`F3` (`Tab` cycles). A spare screen gets an opaque host
    filling it. A Main screen too short to carry a strip at all — a 1366×768
    laptop panel, say — keeps the hull-cam fullscreen and puts the panels back
    over it as a **dimmed overlay**, which the `MAIN` tab or the backtick
    `` ` `` key hides. The threshold is `ScreenLayout.MIN_SCALE`: no panel is
    tiled at under 42% of the size it was drawn at.
  - Everything works with mouse, touch, **or** keyboard.
- **No touchscreen needed.** Every secondary display is driven by mouse as well as
  touch, and the tab strip / chooser are keyboard-reachable — the game is fully
  playable at a plain desk.
- **spacedesk.** The secondary displays are designed to run over spacedesk
  virtual monitors. Because a dedicated role is full-coverage and borderless (a
  tiled one covers its tile), and input is process-global, windows stay in sync
  regardless of which one has OS focus. A screen that gets split is laid out
  inside its **usable** rect, so the taskbar doesn't clip the bottom row. spacedesk index order isn't stable across reconnects, but the saved
  layout is keyed by geometry and `F5` re-detects — reassign with the chooser
  (or the `tools/ScreenLabeler.tscn` dev tool) if a reconnect shuffles things.
- **The flight view keeps the keyboard.** Each window spawned takes OS focus
  from the one before it, so without help the *last* panel placed ends up owning
  the mouse and keyboard — on a rig where the Main view has a screen to itself,
  that leaves the flight view rendering and flying (HOTAS is polled
  process-globally and needs no focus) while answering no click and no keystroke.
  The Main window therefore takes focus back for the first few seconds after a
  layout is built. It stops the instant you press, click or tap anything — so
  reaching straight for an MFD still works — and it never pulls focus out of
  another application you have switched to.
- **When a window misbehaves**, the **window log** (`user://window_log.txt`, and
  `F8` for a dump on demand — see *Running*) is the thing to read and the thing
  to send: it records where each window was placed, what the OS made of that,
  which window holds OS focus, and which windows are actually receiving input.
  A display that shows the right picture but answers nothing is a focus fault,
  not a binding fault, and only that file can tell the two apart.
- **Adding a fifth display** is a role entry in `DisplayConfig` + a scene in
  `WindowManager.SECONDARY_SCENES` and its canvas in `WindowManager.ROLE_CANVAS`
  — no changes to `GameState` or existing windows.

`config/name` is **Salvager**; each secondary window is titled `Salvager — <Role>`.

---

## Running

Open the project in **Godot 4.7** and run `scenes/boot/Boot.tscn`. It opens on the
**launch screen** (scenario + displays + controls, world paused — see **The launch
screen** above); press **LAUNCH** to start the run. The game runs
degraded-gracefully: with no HOTAS or switch panel it retries hardware in the
background while you fly on the **default keyboard mapping** (mouse/touch on the
secondary displays; rebind any key via **F7**), and with fewer than four
monitors it prompts you (once per setup) to assign displays to screens and tiles
the overflow into the screens it has (see **Simpit / multi-display setup** above;
`F6` re-opens the chooser, `F5` re-detects monitors). The `hid-gd` GDExtension is
required for the switch panel and the X55 POV glance; without it those inputs are
disabled but the rest still works.

**Session log.** Every comms line — ATC calls, collisions, ops chatter — is
mirrored to `user://comms_log.txt` as it is posted, so a run can be read back
instead of photographed off the screen. The real path is printed at boot
(`comms log: …`); on Windows it lands under
`%APPDATA%\Godotpp_userdata\Salvager\`. It is truncated at each launch, so
the file is always the current session. Contact calls carry the ship's altitude
and offset from the pad, so a knock in the berth says exactly where it happened.
The first line of the docking system's boot message also carries a **build**
fingerprint of `DockingSystem.gd`, which is the quickest way to tell whether a
running game predates a change.

**Window log.** Where the OS put each window, and where input went afterwards, is
recorded to `user://window_log.txt` — path printed at boot (`window log: …`),
truncated at each launch like the comms log, and written to alongside it. It is
for the faults that live *outside* the game, where everything in-game looks
right: a window that lands on the correct screen but never takes OS focus (the
ship keeps flying, because HOTAS is polled process-globally and needs no focus at
all), or a pointer that can no longer be dragged onto the other monitor. It
records the screen topology and the role map; what mode, screen and rect each
window was **asked** for against what the DisplayServer **read back**; every
focus change, per window, alongside which Control Godot thinks is focused inside
it; how many key / button / motion events each window has actually received; and
which screens the pointer has managed to reach since the last focus change. Lines
are written only when something changes, plus one status line every 30 seconds so
a quiet log still proves it is running. **F8** stamps a full dump into it — press
it the moment something looks wrong, so the log records where that moment was.
Send this file with any report of a window, focus or multi-monitor problem.

The previous session is kept alongside it as `window_log.prev.txt`, because these
faults are usually reported by someone who has already restarted the game to see
whether they stick — truncating on launch and keeping nothing would destroy the
evidence in the act of confirming it. Each session stops at 20,000 lines (~2 MB),
so the pair costs about 4 MB at worst, however long a session runs. If the older
file *can't* be moved aside — read-only, or held open by something else — the new
session is **appended** rather than written over it, and says so at the top;
appending stops if the file ever passes 8 MB, at which point the game logs to the
console only and names the file to clear.

### Handy tool scenes (`tools/`)

| Scene | Purpose |
| --- | --- |
| `ScreenLabeler.tscn` | Identify physical screens and assign display roles (dev shortcut; the game shows an in-game chooser when needed). |
| `InputEcho.tscn` | Live dump of joystick axes/buttons and raw HID reports (used to derive the HOTAS bindings). |
| `ScreenshotCheck.tscn` | Render a display to a PNG without a full playtest (`godot --path . res://tools/ScreenshotCheck.tscn ++ <out.png> [close\|rival] [title\|manual]`) — `berth` flies out to the station and parks on short final over the pad (wings level, gear down), `close` parks the ship at cutting range, `rival` stands the rival cutter and the patrol up in front of the camera with the rival's torch firing (the only way to judge their models and the light fit without waiting out a spawn window), `title` lays the launch title card over the view, and `manual` opens the pilot's manual over that card (add a chapter id, e.g. `manual checklist-arrival`, to shoot a specific page). **`tactical` shoots the Tactical display** at its real 1280×720 canvas with the instrument band up (`tactical SCOPE` / `tactical CHART`), deliberately parking the ship off level, off north and turning — shot straight and level, every sign on the band looks correct whichever way round it is. **`mfd` shoots the MFD display instead**, at its real 1280×800 canvas — the MENU home by default, a named page with `mfd DOCK`, a named procedure with `mfd CHECKLIST cutting`, and combined with `berth` (`mfd DOCK berth`) to catch the DOCK page with its gate checklist live rather than reading NO APPROACH RUNNING. This is how MFD layout and type sizing get judged short of the physical panel. |
| `build_hull.py` | Blender script (not a Godot scene) that regenerates the derelict frigate's continuous hull — one fuselage split into member-named sections plus modeled radiator/mast/engine-bell appendages — into `assets/cc0/derelict-frigate/*.glb` (`blender --background --python tools/build_hull.py`). Edit the profile/appendages here, not the `.glb`s. |
| `build_ships.py` | Blender script (not a Godot scene) that regenerates the two AI ships — the rival cutter (with the torch boom its cut flare fires from) and the claim-holder's patrol — into `assets/cc0/ships/*.glb` (`blender --background --python tools/build_ships.py`). Every vertex is **checked against `ThreatSystem.SHIP_CONTACT_RADIUS` at build time**: the script refuses to write a hull that pokes out of the sphere the game actually collides against, so the model and the constant can't drift apart. |
| `build_sfx.py` | Python script (not a Godot scene) that synthesises every machine on the ship into `assets/generated/sfx/*.wav` (`python tools/build_sfx.py`). Nothing here is recorded — a leadscrew heard through a pressure bulkhead in vacuum has no field recording — so it is built from first principles in numpy, which also makes it ours outright. Loops are filtered in the FFT domain, which is circular, so every `_loop` clip is seamless by construction with no crossfade. |
| `build_speech.py` | Python script (not a Godot scene) that renders the spoken vocabulary into `assets/generated/voice/*.ogg` plus a manifest (`python tools/build_speech.py`). It reads the comms **format strings out of the source** and renders each literal piece between the `%` specifiers, so the lines are never copied and a changed comms line changes what is said. The raw voice comes from a swappable engine stage (`tools/tts_sapi.ps1` by default) — see [CREDITS.md](CREDITS.md). |
| `build_station.py` | Blender script (not a Godot scene) that regenerates the docking station — hub, habitat drums, berth bay, pad and markings, three traffic ships and the ship's landing-gear leg — into `assets/cc0/station/*.glb` (`blender --background --python tools/build_station.py`). Every solid part is **clearance-checked against DockingSystem's lane at build time**: the script refuses to write geometry that intrudes into a corridor the pilot is required to fly inside, so re-run it after changing a gate. |
| `Phase4Smoke.tscn` / `Phase5Smoke.tscn` | Headless smoke tests for the salvage/market and input/flight systems. |
| `AlignSmoke.tscn` | Headless smoke for the per-member approach + pre-cut alignment mini-game: approach needs a selected target and re-selecting forces a reposition; a drive shutdown or a dead THRUST channel under a flying autopilot disengages it; a flown approach is charged propellant like the burn it is, and a settled standoff isn't; the cutter trigger opens alignment (not a cut); on-target aim locks and commits at high quality; a sustained slip aborts and nudges risk; and quality binds the stakes (clean cut is faster and preserves more yield). |
| `FlightSmoke.tscn` | Headless smoke for the flight model's **failure** cases — the ones a working fly-by-wire hides. A perfect assist is indistinguishable from the old no-momentum model, so these drive authority *down* and assert the residual survives: a spin imparted at zero authority keeps turning the ship, a switched-off assist leaves drift alone, direct thruster torque still flies a dead-stick ship, and the alignment interlock refuses (and aborts) below half authority. |
| `GjkFuzz.tscn` | Property + differential fuzz for the hand-rolled GJK narrowphase, over ~12,800 randomised queries against eight hull families — including the degenerate ones the game really registers (coplanar panels and bay walls, the thin berth-floor slab, collinear/duplicate vertices from a bake). Every result must sit inside an exact bracket (never nearer than the hull's bounding box, never further than its closest vertex), must be invariant under rigid transforms, and must agree with **Godot's own convex collision** on the overlap verdict. The bracket is precisely the property the flat-slab bug violated: with the fix reverted it reports 0 m where the truth is 5.8 m. |
| `CollisionSmoke.tscn` | Headless smoke for collision consequences: the capsule volume follows the hull (not the origin), ramming a body damages the hull and stops the ship at the surface, a gentle nudge does no damage. |
| `DriftSmoke.tscn` | Headless smoke for the post-cut collection mini-game (DriftSystem): a completed cut detaches a drifting piece instead of stowing directly; collisions impart velocity to movable bodies (ramming a piece, and one movable body knocking another); a piece is **solid against static geometry** — it bounces off the derelict/station and is pushed clear rather than sinking through; the hatch/range/speed/cone collection gates are all required and holding them stows the piece; the cargo hatch interlocks the cutter and dock/jump while open; and the rival runs the same sever-then-retrieve loop, with pieces free-for-all. |
| `DockSmoke.tscn` | Headless smoke for the docking/landing mini-game (DockingSystem): the transit burn hands over to a flown approach; the hold gates a clearance on being stopped and on the lane being clear of traffic; markers must be flown through in order, and a miss, a corridor departure or sustained overspeed sends you around; the gear travels in real time, is required at the final gate and interlocks the cutter; a hot touchdown bounces and a clean one books the berth; auto-berth is a paid alternative inbound and refused on final; the departure is flown too; and the 3D station agrees with the lane data it is built from. |
| `AudioSmoke.tscn` | Headless smoke for sound and speech: every clip `SoundBank` names resolves and every bus it names exists; the cargo door **travels** rather than teleporting, and its two predicates disagree while it moves; numbers are spoken digit by digit; the harbour uses the full tail number on first contact, abbreviates after, and starts again next pattern; and — the check that matters most — alerts **latch**, so a condition held across its threshold raises exactly once. It also drives real intents and asserts the lines they produce can still be spoken, so editing a comms line without rebuilding the voice bank fails here instead of going quietly mute in flight. |
| `ThreatShipsSmoke.tscn` | Headless smoke for the rival/patrol 3D bodies and the shared exterior light fit: a contact tagged RIVAL or PATROL stands a hull up and removing it takes the hull away; a contact with no kind gets none (the guard that keeps the derelict, the debris and the station's traffic from being drawn twice); the hull follows the contact's position and points along its heading, wings level; both `.glb`s fit inside `SHIP_CONTACT_RADIUS` **and** actually fill it; and the light fit measures its own mounts off the hull it's bolted to, carries all eight lamps, and switches by group. It also pins the Kestrel's own fit: she wears the same eight lamps, they follow the bus, and they stay off the **hull camera** — a two-file contract (the lamps' visual layer and the camera's cull mask) that does nothing unless both halves agree, since the wingtip lamps sit less than a metre either side of the pilot's eye. |
| `ShipColliderBake.tscn` | Bake the ship's collision capsule from its model into `data/ships/*.tres` (`godot --headless res://tools/ShipColliderBake.tscn`). Re-run after swapping the hull mesh. |
| `DisplayLayoutSmoke.tscn` | Headless smoke for the display layout: per-setup config persistence, the `ScreenLayout` planner (exact partitioning, the arrangement per screen shape, and which tier each 1/2/3/4-monitor topology lands in), the content-harvest reparent, and the tab-host show/hide. |
| `TitleCardSmoke.tscn` | Headless smoke for the launch screen: the scenario catalog and its intents (an unknown id changes nothing, LAUNCH starts the run exactly once), and that the card builds one button per scenario and reports the live display/controls state. |
| `PilotManualSmoke.tscn` | Headless smoke for both of the ship's documents: each catalog is well-formed, sections are contiguous, and the required procedures are present; **neither document publishes the other's material** (the handbook names no harbour marker, the terminal procedures restate no airframe figure, and every harbour chapter names its issuing office); **every binding placeholder in the content names a real Input Map action** (so renaming an action fails the build instead of leaving a hole in a checklist); the resolver agrees with the effective profiles and reports an unassigned control as `NOT ASSIGNED` rather than an empty gap; every chapter renders with no placeholder left unsubstituted; and the card opens either document on a layer above itself but below the chooser and remapper, swaps rather than stacks when the other is opened, hides it for a setup step, and frees it on LAUNCH. |
| `InstrumentBandSmoke.tscn` | Headless smoke for the Tactical instrument band and the navigation reference. Asserts the SIGNS every reading depends on (nose-up fills the ball with sky, a right wing down tilts the horizon the way the world tilts, a climb reads positive) — none of which is visible in a screenshot of a level ship; that the band's ALT under the platform datum is the SAME number DockingSystem reports to the HUD's landing ladder, and its heading under the inertial datum is the same formula the HUD uses; that every datum resolves to a real orthonormal frame, that AUTO picks the right one for the phase being flown, and that a pinned datum with no fix reports the fallback it is holding; and that the band's reserves leave a usable mode pane in the 1280×720 canvas. |
| `MfdNavSmoke.tscn` | Headless smoke for MFD page navigation: paging wraps through the pages alone (a full lap visits each once and never lands on the MENU), while the MENU home stays reachable on demand for a direct jump to any page. |
| `ChecklistSmoke.tscn` | Headless smoke for the MFD **CHECKLIST** page: the catalog is well-formed and carries all four procedures with contiguous sections; **every live read is called against real state** and must return a status and a value (so a renamed `GameState` field fails the build instead of blanking a row); rows follow the ship when the real intents are driven (hatch, gear travel, power channels); a limit is **read from the constant that enforces it** rather than transcribed; no live row can be hand-ticked, and RESET / a site reset clear the ones that can; and the shared vertical budget holds — each checklist reserve fits its rows at the current type scale, and the DOCK / SCOOP / ALIGN pages still draw on a unit far smaller than any real MFD. |
| `PowerSmoke.tscn` | Headless smoke for the alternator/battery power model: channel switches drive their mapped channel; a surplus charges the battery and a deficit discharges it; ALT off runs the ship off the battery until it's flat; BAT off caps delivery at the alternator's output; and — the assertion that matters most — **an electrical condition changes what is delivered and never what is set**, with edits made on a dark ship surviving and taking effect on restoration. Passive-scanner visibility still halves per master off. |
| `PropellantSmoke.tscn` | Headless smoke for the hybrid drive: each selector position's thrust and ceiling; burn metered by commanded thrust **and only to the extent the THRUST channel delivers it** (an open lever on a dead bus costs neither speed nor hydrogen); the same meter charging a burn the approach autopilot flies kinematically, measured as delta-v against what the drive could make; boost drawing on both tanks and refused without either; the starter (10 s at START, and **no thrust until the selector leaves it**); the electrical coupling that makes a dry tank a bus problem too; and buying propellant at a berth. It exists to pin down **the no-automatic-reversion rule** — at `L` with a dry hydrogen tank the ship makes no thrust at all, and nothing helpfully falls back for you. |
| `ManualExport.tscn` | Renders both of the ship's documents to print-styled HTML (`godot --headless res://tools/ManualExport.tscn ++ [out_dir]`, default `build/manuals`). It runs in Godot rather than parsing the catalogs externally because resolving the binding placeholders needs the live Input Map — it instantiates the real `ManualViewer` off-tree and calls its own resolver. `tools/build_manuals.ps1` runs this and then prints the HTML to PDF with headless Chrome or Edge. |
| `PowerNudgeSmoke.tscn` | Headless smoke for driving a power channel from the remapper rows: an analog axis acts as a slider, a digital key/button nudges the channel per press, and a bound-but-idle digital event never pegs it to the midpoint. |
| `AxisKeyNormalizeSmoke.tscn` | Headless smoke for the remapper's axis-key normalization: a saved axis/nub spec listed in the swapped (REV-encoded) order folds back to its row's canonical key with reverse set, so it stays visible on its row instead of vanishing under a phantom key. |
| `BindClashSmoke.tscn` | Headless smoke for the remapper's shared-control detection: a key or button another row already holds still binds, but the capture names that row, **both** rows carry the `(clash)` mark that tints them, rebinding a row to the key it already has isn't a clash, and the same button index on a *different* stick isn't either. |
| `KeyboardMergeSmoke.tscn` | Headless smoke for the keyboard profile merge: a saved `keyboard.json` overrides the shipped layout key by key, a key you cleared stays cleared, a default whose key you reassigned is skipped rather than double-bound, and an action added since the file was written gets its shipped key back — so a new control can't leave a returning pilot unable to reach the masters or the drive selector. |
