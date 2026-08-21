# Higgs ceiling, alternator/battery, LH2/LOX, and the two documents

## Context

The setting bible currently explains the ship's speed ceiling as a **waste-heat /
radiator-sizing** limit (`Docs/Plans/simpit-world.md:73-96`). We are replacing that
fiction: the **Higgs field** is what limits speed — motion through it couples as a
velocity-proportional drag, giving a *drag-limited* terminal velocity, which two
carried propellants can push past.

That fiction change drags real systems with it, and the ship's electrical model is
being rebuilt at the same time. Three things in the game today are now wrong:

1. **`MASTER ALT` off means "rig for escape"** (`GameState._apply_electrical`,
   `:728-740`) — THRUST/LIFE forced to 1.00, everything else zeroed, mix locked.
   It should mean *the alternator has stopped generating and the ship is running
   off the battery.* The masters own **the bus**; they do not own propulsion.
2. **There is no propellant at all.** `PilotManualContent.gd:109` states it as
   canon: *"The Kestrel carries no propellant… there is no refuelling
   requirement."* Two carried propellants — **liquid hydrogen** and **liquid
   oxygen** — make that false.
3. **The gear may not be raised inside the berth bay** on departure
   (`DockingSystem.gd:916-917`). That restriction is being removed.
4. **The magneto bank does nothing.** `ENGINE_OFF / R / L / BOTH / START` are
   decoded and published but routed nowhere (`SwitchPanelBridge.gd:117-135`). It
   becomes the **drive selector** — which is where the propulsion model gets its
   controls, and it is the reason this change reaches the hardware at all.

Scope confirmed with the user: **simulate all of it**, propellant is **bought at a
berth**, the cargo hatch **gates the sale**, and the PDF pipeline is **build
output, not committed**.

The two propellants are **liquid hydrogen (LH2)** and **liquid oxygen (LOX)**.
Nuclear thermal propulsion consumes LH2; the booster consumes LH2 **and** LOX. A
dry LH2 tank does not stop the ship — the hybrid engine still makes thrust on its
electric stage, at **40%** of its fuelled figure, but that stage costs a great deal
more electricity, which is what ties the propellant model to the electrical one.

Everything below carries a hard constraint from `CLAUDE.md`: *if you cannot point
at the constant, do not write the number* — so every figure that lands in either
ship document must be quoted from code introduced by this change.

---

## 1. Lore — `Docs/Plans/simpit-world.md`

Rewrite the section **"Ship Performance: Why There's a Speed Ceiling"** (lines
73–96). New content:

- **Higgs drag, not waste heat.** The Higgs field is the one frame everything is
  referred to. At ordinary speeds a hull's coupling to it is just the ordinary
  mass term; push harder and the coupling grows with velocity and behaves like a
  drag. The ceiling is the speed at which thrust and that drag balance.
- **The compact fusion reactor is why anyone ever notices.** This is the causal
  claim, and the bible should state it plainly: *without the reactor at the heart
  of the ship, the Higgs interaction would never be limiting at these speeds.*
  Something about running a compact fusion containment makes the coupling
  enormously more observable — the ship is dragging against the field because of
  what it is carrying, not because of how it is shaped. Every ship with one of
  these reactors has a ceiling; the ceiling is a property of **the reactor**, not
  of the airframe. (This also cleanly explains why a ceiling exists at all in a
  vacuum, which "drag" otherwise doesn't.)
- **Salvage hulls still run below a purpose-built ceiling** — same conclusion,
  new cause: a salvager flies a reactor pulled out of somebody else's ship, and
  she sits wherever that reactor sits.
- **Leave the war history out of the speed ceiling entirely.** My earlier draft
  hung the totalitarian/democrat split on drive tuning; that is a stretch and it
  is not the story. The existing sections at `simpit-world.md:5-29` and `:98-124`
  already say the true thing and should simply be *sharpened*: the totalitarians
  did not value or honour their logistical chain and over-valued their "warrior"
  class. That produced over-emphasis on attack, under-emphasis on sensors and
  observation, and **under-protected transports** — and the under-protected
  transports are **why there is so much good salvage to be had**. That is the
  premise of the entire game, and it deserves to be stated as a consequence in
  the bible rather than left implicit under "Commerce raiders / What produced so
  much to salvage".
- **Heat is still real — it just governs efficiency, not speed.** Waste heat is
  why the wreck carries radiator fins (`build_hull.py`;
  `SalvageSystem.gd:107-109` names two RADIATOR PANEL members) and it stays a
  live constraint on **battery efficiency, alternator efficiency, life support,
  sensor operation, cutter operation**, and whatever systems come later. Write
  the thermal architecture into the bible as a first-class part of the setting so
  those hooks exist when they are wanted.

  **Scope note:** heat is *fiction ahead of the simulation* in this change —
  nothing in the code models it yet. Because `CLAUDE.md` forbids writing a figure
  you cannot point at a constant for, heat gets **no numbers and no chapter in
  either ship document** until it is implemented. It lives in
  `simpit-world.md` only.
- **Reverse stays deliberately weak** (still backed by
  `ShipDefinition.secondary_thrust_fraction`) — leave that bullet alone.
- **Why carrying propellant beats the ceiling.** The drag-limited maximum is what
  a *field* drive can do — it is pushing against the Higgs coupling and loses. A
  drive that throws real reaction mass out the back is adding momentum rather
  than fighting the coupling, so it can sit above the field drive's terminal
  velocity for as long as the mass lasts. That is the whole in-fiction reason
  propellant exists, and why it is spent rather than allocated.

Add a short new section, **"Power and Propulsion"**, so the bible states the
fiction the new manual chapters describe operationally:

- **A fusion reactor** is the ship's one energy source. An alternator turns its
  output into electricity for the bus; its thermal output heats propellant.
- **The drive is a hybrid** of a Mass-Effect / photonic / electrodynamic field
  stage — reactionless, propellant-free, and what the ship flies on normally —
  and two reaction stages layered on top of it.
- **Nuclear thermal.** Liquid hydrogen is heated by the fusion reactor and
  expelled. Real thrust, real reaction mass, a ceiling above the field drive's.
- **Combustion.** Liquid oxygen burned with the same liquid hydrogen in a
  conventional bipropellant chamber. The most thrust and the shortest endurance —
  a boost, not a cruise.
- **The hydrogen ramjet** is the intake that feeds the thermal stage. In this
  system's densities it scavenges far too little to matter, which is why hydrogen
  is bought and carried rather than collected. (An optional knob: give it a token
  in-flight LH2 trickle. Left out of the core change — it undercuts buying fuel.)

---

## 2. Electrical — alternator, battery, bus

### Code: `autoload/GameState.gd`

Replace the override model in `_apply_electrical()` (`:728-740`) with a
supply/demand model. New constants and state near the existing power block
(`:103-119`, `:345-360`):

```gdscript
## Battery capacity in unit-seconds of the same abstract units power_total()
## sums, so a 1.0-unit deficit runs the battery flat in BATTERY_CAPACITY seconds.
const BATTERY_CAPACITY := 120.0
## Ceiling on how fast surplus alternator output is returned to the battery.
const BATTERY_CHARGE_RATE := 1.0
## Battery charge below which the low-battery call is made, once per crossing.
const BATTERY_LOW := 0.20

var battery_charge := BATTERY_CAPACITY
```

**Settings versus availability — the distinction the whole model turns on.** The
pilot's allocation is *never* rewritten by an electrical condition. `GameState`
already carries the split: `_power_target` (`:360`) is what the switches, sliders
and nudges set; `local_ship()["power"]` (`:380`) is what is actually delivered.
Losing the alternator, losing the battery, or flattening the battery changes only
what is **available** — the settings stand untouched, and full delivery resumes
the moment supply does. So no condition below "zeroes a channel"; conditions
starve channels.

New model, evaluated each physics tick (a `_advance_electrical(delta)` called
from the existing `_physics_process`, alongside `_advance_gear` at `:832`):

| Condition | Behaviour |
| --- | --- |
| supply | `power_budget()` (2.5) when `master_alt`, else `0.0` |
| demand | the sum of `_power_target` — what the pilot has asked for — with **THRUST scaled by the drive's electric-draw factor** (§3): high on the field stage, low on the thermal stage. Demand is not a constant; the drive selector and the LH2 gauge move it. |
| `supply > demand` | every channel delivered in full; the surplus charges the battery at `min(supply - demand, BATTERY_CHARGE_RATE)`, capped at capacity |
| `supply < demand`, `master_bat` on, charge remaining | every channel delivered in full; the battery discharges at `demand - supply` |
| `supply < demand`, `master_bat` **off** | no buffer — delivery is scaled proportionally so the draw fits the supply. Settings unchanged. |
| battery flat, `master_alt` off | supply 0, nothing to draw on — delivery is nil across the board. A quiet ship with no propulsion, still carrying the pilot's settings. |
| both masters off | supply 0 and no buffer — same quiet ship, same intact settings |

**Delete `power_locked()`** (`:721-722`) and the lockout it drives. Under the new
model an off master is a *supply* condition, not an override, so the mix stays
both **editable and set** from every surface — which is exactly the settings /
availability split above. Callers to update: `set_power()` (`:676-679`, drop the
early return), `set_power_switch()` (`:688-698`, its "record now, apply when power
returns" dance is no longer needed), `PowerSliders.gd:35-53` (`disabled`), and
`PowerSmoke.gd`.

`passive_signature()` (`:745-751`) is **unchanged** — half per master off, quarter
for both — and stays meaningful because both off is now a genuine dark ship.

Emit a new `battery_changed` signal alongside `power_changed`. Post comms on the
low-battery crossing and on the bus dropping (reuse `post_comms("OPS", …)`).

The **reactor overdraw** indication stops being cosmetic: exceeding 2.5 now drains
the battery. That is the change that makes `power_budget` a real limit.

### New input actions — required, not optional

The masters are reachable **only** through the Saitek panel today: there is no
`master_alt` / `master_bat` action in `project.godot`'s `[input]` block, none in
any `InputRouter.BUILTIN_PROFILES` entry, and no row in the F7 remapper
(`ControlsSetup.gd:37-40`). The new arrival and departure procedures *require*
toggling both, so a keyboard-only pilot must be able to.

- Add `master_alt` and `master_bat` to `project.godot` `[input]` (and
  `drive_boost` and the drive selector from §3, which need the same treatment).
- Route them in `InputRouter` to `GameState.set_master_alt` /
  `set_master_battery`, next to the existing `cargo_hatch_open` / `landing_gear`
  handling.
- Add the rows to `ControlsSetup.gd` so they are remappable.
- Give them defaults as part of the keyboard pass in §5 — **not** by picking two
  free keys and moving on.

### MFD

`scenes/ui/PowerSliders.gd` — the header becomes supply/demand plus battery state,
e.g. `POWER 2.4 / 2.5   BAT 87%  CHG` / `… DISCH 0.4`, with the existing
`OVER_BUDGET` colour on discharge. Drop the `— THRUST LOCK (ALT)` and
`— OFFLINE (BAT)` notes; replace with `ON BATTERY` / `NO BUFFER` / `SHIP DARK`.

Each slider keeps showing the pilot's **setting** at its handle; where delivery is
being starved, show the delivered figure alongside it (a dimmed second value or a
partial fill) rather than dragging the handle down. A starved ship must read as
*"you asked for 0.80 and are getting 0.31"*, never as *"your setting changed"*.
`GameState.power(channel)` continues to return delivered power, so every consumer
— `ShipMotion`, `SalvageSystem`, the checklist rows — degrades correctly with no
change.

---

## 3. Propulsion — hybrid drive, LH2 and LOX

### The drive selector — the magneto bank finally does something

The Saitek panel's five-position magneto (`ENGINE_OFF / ENGINE_R / ENGINE_L /
ENGINE_BOTH / ENGINE_START`) is decoded and published to `GameState.panel_switches`
today but **routed nowhere** (`SwitchPanelBridge.gd:117-135`). It becomes the drive
selector, which is exactly the aviation idiom the hardware was built for — BOTH is
the normal cruise position, a single stage is degraded but flyable, and START is
spring-loaded.

| Position | Stages running | LH2 | Electrical THRUST draw | Thrust | Ceiling |
| --- | --- | --- | --- | --- | --- |
| **OFF** | none | — | none | **none — no propulsion at all** | — |
| **R** | field only (Mass-Effect / photonic / electrodynamic) | none | **high** | 40% of rated | 25 m/s |
| **L** | nuclear thermal only | burns | **low** | 60% of rated | 35 m/s |
| **BOTH** | field + thermal together | burns | **high** | **100% of rated** | 35 m/s |
| **BOTH** or **L**, `drive_boost` held | + combustion stage | burns LH2 **and LOX** | as the position beneath it | 100% | 50 m/s |
| **START** | the starter position — see below | | | | |

Electrical draw follows one rule, not a per-row value: **the field stage is what
costs electricity.** Any position running it (R, BOTH) draws heavily; the thermal
stage alone (L) is cheap. Boosting inherits the draw of whatever it is layered on.

That makes a real three-cornered trade, and every position earns its detent:

- **R** — no propellant burnt, but slow and electrically expensive. The get-home
  position, and where a dry ship ends up whether it chose to or not.
- **L** — 60% thrust for very little electricity. The economical cruise, and the
  position to be in when the bus is already loaded or the battery is low.
- **BOTH** — everything, at the cost of both hydrogen and amps. Normal for work.

### The electrical coupling — the thing that ties §2 and §3 together

**Producing thrust without hydrogen takes a lot of electricity; producing it with
hydrogen takes very little.** The field stage is electrically expensive; the
thermal stage runs on the reactor's heat and barely touches the bus.

So the **THRUST channel's demand is mode-dependent**, not fixed: the allocation the
pilot sets is multiplied by an electric-draw factor that is high on the field stage
and low on the thermal stage. Two new `ShipDefinition` knobs —
`thrust_draw_electric` (propose 2.0) and `thrust_draw_thermal` (propose 0.4) —
feed `GameState`'s demand sum in §2.

This produces the failure spiral that makes propellant matter — and because there
is no automatic fallback, **the pilot has to fly themselves out of it**:

> Cruising at **L** on a light electrical load → the LH2 tank runs dry → the
> thermal stage has nothing to burn and **all thrust stops** → the pilot must
> recognise it and select **R** (or BOTH) → thrust returns at 40%, but the THRUST
> channel's draw jumps from cheap to expensive → demand overtakes alternator supply
> → the battery starts discharging → the battery goes flat → delivery is starved
> across every channel → thrust falls further still.

From **BOTH** the accident is gentler: the field stage was already selected and
already expensive, so running dry costs thrust and ceiling but needs no action to
keep moving. Either way a pilot who ignores the hydrogen gauge limps home dark.

That dead stop at L is a **feature, not a rough edge** — it is what earns the
selector an emergency procedure in the handbook, and it is the reason the
`LH2 DEPLETED` annunciator has to be unmissable.

### Three consequences worth stating outright

- **Running out of hydrogen does not strand you — but it can stop you.** The field
  stage will always get you home at 40%, expensively and on the battery. It will
  not do it *for* you: at L a dry tank means no thrust until the pilot selects R
  or BOTH. Knowing that is a piloting skill, and the handbook must teach it as an
  emergency procedure rather than burying it in a chapter.
- **LOX is useless without hydrogen.** A dry LH2 tank costs both reaction modes at
  once, however full the LOX tank is; a dry LOX tank costs only the boost. LH2 is
  the buy that matters; LOX is the luxury.
- **OFF is a real state, and it is not the same state as a dead bus.** There are
  now two independent ways to end up with no thrust, and the pilot must be able to
  tell them apart: **masters off** starves the THRUST channel, so no stage runs;
  **selector at OFF** stops the drive with the bus still alive and every other
  system still fed. A ship parked on a pad is in both. And because starting costs
  ten seconds at START, shutting the drive down is a commitment, not a habit — the
  annunciations for the two conditions must therefore read differently, or a pilot
  will sit turning master switches at a drive that is simply off.

### Code: `resources/ShipDefinition.gd` + `data/ships/kestrel.tres`

New exported fields, documented in the same style as the existing block at
`:26-31`. Proposed values (tunable in the `.tres`; whatever ships is what the two
documents must quote):

| Field | Value | Meaning |
| --- | --- | --- |
| `manual_accel` | 4.0 (unchanged) | **now the BOTH figure** — thrust on field + thermal together |
| `thrust_fraction_field` | 0.4 | field stage alone (selector R, or a dry LH2 tank) → 1.6 m/s² |
| `thrust_fraction_thermal` | 0.6 | thermal stage alone (selector L) → 2.4 m/s² |
| `thrust_draw_electric` | 2.0 | multiplier on THRUST-channel demand while the field stage runs (R **and BOTH**) |
| `thrust_draw_thermal` | 0.4 | multiplier on THRUST-channel demand with the thermal stage alone (L) |
| `drive_start_time` | 10.0 | seconds the selector must sit at START before the drive will run |
| `max_speed` | 25.0 (unchanged) | the **drag-limited** ceiling — field-drive thrust equals Higgs drag |
| `lh2_capacity` | 60.0 | liquid-hydrogen tank, in units |
| `lh2_burn_rate` | 1.0 | units/s at full commanded thrust, thermal stage running |
| `lh2_burn_boost` | 2.5 | units/s at full commanded thrust while boosting — combustion is thirstier |
| `thermal_speed_bonus` | 10.0 | ceiling with the thermal stage running → 35 m/s |
| `lox_capacity` | 20.0 | liquid-oxygen tank, in units |
| `lox_burn_boost` | 2.0 | units/s at full commanded thrust while boosting → ~10 s of boost |
| `boost_speed_bonus` | 15.0 | ceiling above the thermal tier → 50 m/s |

Keeping `manual_accel = 4.0` as the **BOTH** figure preserves the existing flight
tuning as the normal case and makes every degraded state a penalty, rather than
re-tuning every handling constant in the game. `secondary_thrust_fraction` is
**absent from `kestrel.tres`** and falls back to the script default — follow that
precedent or add all new fields explicitly, but be consistent.

### Code: `autoload/GameState.gd` + `systems/ShipMotion.gd`

- `GameState`: `lh2_fuel`, `lox_fuel`, `drive_mode` (OFF/R/L/BOTH), a start-hold
  timer, and signals `propellant_changed` / `drive_mode_changed`.
- **Effective stages** is one derived query, and everything else reads it. The
  rule is simply: **a stage runs if it is selected *and* it is supplied.** There is
  no automatic fallback — the selector is authoritative.
  - **R** — field stage selected; needs no propellant, so it always runs.
  - **L** — thermal stage selected only. With a dry LH2 tank **nothing runs and
    there is no thrust at all**. The field stage is not selected and will not
    quietly step in.
  - **BOTH** — both selected, so a dry tank degrades gracefully: the thermal half
    contributes nothing and the ship keeps flying on the field stage at 40% with
    the high draw.
- Queries off that: `speed_ceiling() -> float` (25 field-only, 35 with the
  thermal stage, 50 boosting) and `thrust_fraction() -> float`
  (`thrust_fraction_field` / `_thermal` / 1.0 for both).
- `ShipMotion.gd:167` — `manual_accel * maxf(power("THRUST"), 0.0)` gains
  `* GameState.thrust_fraction()`, and returns **zero** with the selector at OFF,
  at START, or with the drive not yet started. This is the one line that makes the
  selector *felt* rather than read.
- `ShipMotion.gd:184` — `velocity.limit_length(GameState.ship_def.max_speed)`
  becomes `velocity.limit_length(GameState.speed_ceiling())`.
- `ShipMotion._apply_throttle_axis()` (`:196-206`) — the SPEED command law maps
  the lever to a fraction of the **live ceiling**. (The approach autopilot is
  unaffected: it flies `approach_speed = 8.0` independently, so close-quarters
  work around the wreck does not change — though it will accelerate onto station
  more slowly on a dry tank.)
- **Burn accounting** in `ShipMotion.step()`, scaled by *commanded thrust* rather
  than by speed: station-keeping is nearly free, a hard burn costs. LH2 drains at
  `lh2_burn_rate` whenever the thermal stage is running and at `lh2_burn_boost`
  while boosting; LOX drains at `lox_burn_boost` while boosting only. A tank
  running dry drops the ceiling and the existing `limit_length` clamp decelerates
  the ship into the new one for free.
- **The approach autopilot must respect the selector.** `SalvageSystem.gd:553-554`
  scales its closing speed by `power("THRUST")` alone; with the drive OFF or
  unstarted it would still command a translation the drive cannot deliver. Gate
  the engagement on a live drive and annunciate the refusal in the existing
  `"APPROACH INHIBITED — …"` idiom, then add the matching item to the **cutting**
  checklist.

**BOOST is commanded, not stumbled into.** Add a bindable `drive_boost` action
(held) to `project.godot` `[input]`, the keyboard profile and the F7 remapper,
refused with either tank dry or the thermal stage not running. Automatic engagement
above 35 m/s would let a pilot dump the whole LOX tank by pushing the throttle
forward; and a held boost is the kind of control this project exists to put on a
HOTAS.

### Wiring the selector

- `systems/hardware/SwitchPanelBridge.gd:117-135` — route `ENGINE_OFF` /
  `ENGINE_R` / `ENGINE_L` / `ENGINE_BOTH` to `GameState.set_drive_mode()` and
  `ENGINE_START` to the start-hold intent, alongside the existing `MASTER_BAT` /
  `COWL` / `GEAR_*` routing. The decode already works; only `_route_intent()` needs
  the cases.
- **The start sequence, exactly like a real magneto.** START is a **detented
  position, not spring-loaded** — the pilot turns to it, leaves it there, and
  turns back. So: after the selector has been at OFF the drive is cold; the
  selector must sit at **START for `drive_start_time` (10 s)**, and **thrust
  becomes available only once the selector is moved off START** onto R, L or
  BOTH. Leaving START early means the drive is not started and the run must be
  repeated; sitting at START forever gets you nothing, because START is not a
  running position.

  Advance the timer in the same `_physics_process` that carries `_advance_gear`
  (`GameState.gd:832`), reset it if the selector leaves START before the 10 s are
  up, and annunciate progress and completion on the comms log. Starting needs the
  bus up, so it belongs *after* the masters in the departure checklist.
- **Keyboard parity is mandatory** (§2 and §5 below): a keyboard-only pilot must
  be able to select a drive mode and start the drive or they cannot depart at all.
  Add `drive_mode_cycle` (or five discrete actions — START is one of the five
  positions, not a separate button) to `project.godot` `[input]`, and give it a
  default in the pass below.

### Buying propellant — `systems/MarketSystem.gd`

New price constants (`LH2_PRICE_PER_UNIT`, `LOX_PRICE_PER_UNIT` — propose 8 CR and
30 CR) and a purchase intent that debits credits and fills a tank, refused away
from a berth and refused when the credits are not there. Surface it as controls on
the MFD **MARKET** page (`scenes/ui/`, alongside the existing DOCK / DEPART /
AUTO-BERTH footer controls).

### MFD gauges

LH2 and LOX quantities belong with the ship's other consumable state. Put a
two-row propellant block on the MFD **POWER** page beneath the four sliders —
defensible because LH2 is the fusion reactor's working fluid as well as the
propellant, which makes that page the ship-systems page rather than a purely
electrical one.

### HUD — `scenes/ui/HUDOverlay.gd`

Reactor loading is deliberately absent from the HUD
(`PilotManualContent.gd:455`) and propellant *quantity* should stay absent too.
Two indications are needed all the same:

- **`IMPULSE` / `BOOST`** beside the existing VEL readout while burning, so
  spending propellant is never silent.
- **`LH2 DEPLETED`** as a pulsing annunciator when the tank runs dry, alongside
  the existing `GEAR OVERSPEED` / `CARGO HATCH OPEN` idiom. Losing 60% of thrust
  must announce itself — a pilot who discovers it on short final has been ambushed.
- **`DRIVE OFF`** — distinct from any bus annunciation, per §3. A ship that will
  not move must say *which* of the two reasons applies.

This is a HUD change, so `README.md`'s *Main flight HUD* section and the
handbook's `displays` chapter both move with it.

---

## 4. Arrival and departure procedure changes

### Cargo hatch gates the sale

`MarketSystem` already refuses **dock and undock** with the hatch open
(`:84`, `:150`) — leave those. Add: disposing of the hold requires
`GameState.cargo_hatch_open` and `docking_state == "LANDED"`, refused with a
comms line naming the hatch. This is an **interlock, not a checklist row** — the
sale itself stays off both procedures (see *New procedure content* below), but
a pilot who tries to sell buttoned-up is told exactly why it was refused.

### Remove the gear-over-pad restriction

- `systems/DockingSystem.gd:912-917` — delete the
  `_violation("GEAR RAISED INSIDE THE BERTH BAY")` rule. **Keep `_in_berth_bay()`**
  (`:349-353`): it still drives the `SPEED_FINAL` coupling at `:367-369`.
- `:554` — the ATC line `"GEAR STAYS DOWN UNTIL YOU ARE CLEAR OF MARKER %s"` is now
  false; rewrite.
- `:943-945` — `"CLEAR OF THE BAY — STOW YOUR GEAR…"` still reads fine as advice;
  keep or soften.
- `_release_outbound()` (`:951-963`) — **unchanged**. ATC still withholds the jump
  until the gear is stowed. That is the rule that makes the pilot cycle it.
- Inbound rules are **untouched**: `"GEAR NOT DOWN AND LOCKED AT THE FINAL GATE"`
  (`:845`) and `"GEAR RAISED ON FINAL"` (`:863`) stay.
- `scenes/ui/ChecklistContent.gd:168-179` — the live row returns
  `_na("IN THE BAY — GEAR DOWN")` while inside; that branch goes.

### New procedure content

Both are ship configuration, so both belong to the **handbook**. The order is
driven by dependency and by leaving every switch somewhere sensible: the gear
selector first so it matches the ship standing on its legs, then the bus, then the
drive that needs the bus, with the hatch secured before anything is started.

**Arrival, after touchdown:**

1. DRIVE SELECTOR — **OFF**
   *The drive is shut down before the ship is opened up.*
2. CARGO HATCH — **OPEN**
3. `MASTER ALT` — **OFF**
4. `MASTER BAT` — **OFF**

**Departure, from cold:**

1. LANDING GEAR — **DOWN**
   *The ship is standing on it; confirm the selector agrees before anything else.*
2. `MASTER BAT` — **ON**
3. `MASTER ALT` — **ON**, battery **CHARGING**
4. POWER CHANNELS — **SET**
5. CARGO HATCH — **SECURED**
6. DRIVE SELECTOR — **START**, 10 s
7. DRIVE SELECTOR — **BOTH** — thrust available
   *CAUTION: nothing moves the ship until the selector is off START.*

Then the harbour's items — clearance, clear the pad, run the lane, gear stowed
before release.

**Disposing of the hold is not a checklist item.** Selling is an economic choice,
not a requirement for flight or safety, and a procedure that lists it is telling
the pilot how to run their business. This also means **removing the two rows that
already exist** — departure item 4 `HOLD — DISPOSED OF`
(`PilotManualContent.gd:497`) and arrival item 11 `HOLD — DISPOSE OF` (`:554`) —
so the principle is applied consistently rather than only to the new material. The
hatch-gates-the-sale interlock is unaffected; it is simply enforced by
`MarketSystem` and annunciated, not carried as a procedure step.

Every remaining row is testable from `GameState`, so all of them are **live**
`ChecklistContent.gd` rows, not hand-ticked ones — including the start, which
should show its 10 s counting down while the selector sits at START.

---

## 5. Rework the default keyboard map — now, while there are two users

This change adds at least four bindable things (both masters, the drive selector,
`drive_boost`) to a default map that is already ad hoc. Bolting them onto free keys
makes it worse. **Do the coherent pass now**, before there is an installed base
with muscle memory to protect.

The current default (`InputRouter.BUILTIN_PROFILES`, the `"keyboard"`
pseudo-profile at `:83-122`) is 33 keys with no organising principle:

| Group | Today |
| --- | --- |
| Translation | `W`/`S` fore-aft, `A`/`D` strafe, `R`/`F` vertical |
| Attitude | `I`/`K` pitch, `J`/`L` yaw, `Q`/`E` roll |
| Glance | arrow keys |
| Ops | `V` approach, `C` cut, `B` hatch, `X` gear, `Z` dock request |
| Selection | `M` sensor mode, `,`/`.` salvage prev/next, `N` contact cycle |
| Displays | `G`/`H` MFD menus, `T` tactical, `]` view cycle, `1`–`5` direct views |
| **Unbound by design** | MFD paging, cargo, market, **all four power axes** |

Problems to fix, not just work around: flight is split across two hand positions
with no thumb rest; `M`/`N` are selection verbs sitting where a systems block wants
to be; the digits are spent on camera views while nothing systems-related has a
home; and the four power channels — a headline feature — ship unbound, so a
keyboard pilot cannot run the ship at all without visiting the remapper first.

**The pass, as one task:**

1. **Give the map a shape** — reserve contiguous blocks by function: flight (left
   hand), attitude and glance (right hand), a **systems block** for masters, drive
   selector, power channels and boost, and a **displays block** for views, MFD and
   tactical. Write the intended shape down in the profile's doc comment at
   `:76-82`, which currently only explains the data mechanism, not the layout.
2. **Bind the power channels by default.** They are the ship's central mechanic and
   shipping them unbound is a defect the new procedures make untenable.
3. **Place the new actions inside that shape**, rather than wherever there was room.
4. **Keep `W`/`A`/`S`/`D` and the arrows.** Those two are load-bearing convention;
   everything else is negotiable.
5. **Every action gets a remapper row** in `ControlsSetup.gd` — the F7 surface must
   list everything the default map binds, or a rebinding pilot loses controls the
   default gave them.
6. **Neither ship document needs editing for this.** Both resolve controls live
   through `BindingLabel` (`CLAUDE.md` says so explicitly), so rebinding is free.
   `README.md`'s keyboard table is hand-written and **does** need the rewrite.
7. **`PilotManualSmoke` is the guard** — it fails on a placeholder naming an action
   that no longer exists, so run it after any rename.

**Recommendation:** treat this as its own commit, landed *before* the systems work,
so the input churn is separable from the propulsion and electrical changes in
review and in `git bisect`.

---

## 6. The two documents

Both are second in-tree copies of code figures. `tools/PilotManualSmoke.gd`
enforces: unique ids, **contiguous groups** (insert new chapters adjacent to their
section-mates, never appended), **≥ 200 characters of stripped body per chapter**,
every `{{…}}` token resolvable and naming a real Input Map action, the handbook
free of `ALPHA`/`BRAVO`/`CHARLIE`/`DELTA`, the terminal procedures free of
`45°/s`, `4.0 m/s²`, `manual_accel`, `0.35 of a member`, `stability augmentation`,
`DRIVE integrity`, and every terminal chapter opening with one of the three
masthead consts. `TitleCard.DOCUMENTS` must stay at exactly **2** entries.

Markup dialect is only `[b]`, `[i]`, `[color=#rrggbb]`; bodies never repeat their
own title (`ManualViewer.gd:235`); bindings are **never** coloured by the content
(the viewer wraps them, `:289-291`).

### `scenes/displays/PilotManualContent.gd`

| Chapter | Change |
| --- | --- |
| `ship` (`:81`) | PERFORMANCE block gains the three ceilings and both thrust figures (fuelled 4.0, dry 1.6). **Line 109's "carries no propellant / no refuelling requirement" NOTE is now false — replace it**, don't append. |
| **new `propulsion`** | New SECTION 2 chapter, "Drive & propellant", filed adjacent to `flight`. The selector positions and what each runs, the Higgs-drag ceiling in operational terms, the two tanks and their burn rates, the start procedure and its 10 s, the `drive_boost` control. **WARNING** — a dry LH2 tank costs 60% of thrust, costs the boost, **and raises the electrical draw**; **CAUTION** — LOX cannot be burned without LH2; **CAUTION** — the drive will not start without the bus. |
| `power` (`:170`) | Rewritten: alternator as generator, battery as buffer, supply vs demand, charge/discharge, the four master-switch states, endurance on the battery, the flat-battery condition. State explicitly that **an allocation is never altered by a loss of supply — only what is delivered against it** (a NOTE, since it is the thing a pilot will otherwise misread on the POWER page). The mix-lockout CAUTION (`:196`) is now false — remove it. Emissions paragraph (`:198-199`) unchanged. Master switches gain `{{act:…}}` placeholders alongside `{{sw:…}}`. |
| `flight` (`:112`) | THROTTLE law (`:148-154`) now references the live ceiling, not a fixed 25 m/s. The APPROACH AUTOPILOT block (`:156-166`) gains the drive-live condition and its refusal text. |
| `checklist-cutting` (`:559`) | A drive-running item before the approach is engaged, matching the new autopilot gate. |
| `displays` (`:422`) | New HUD annunciator; new POWER-page battery readout. |
| `checklist-departure` (`:483`) | The seven-item cold sequence from §4 — gear, masters, channels, hatch, START, BOTH. **Item 4 `HOLD — DISPOSED OF` (`:497`) is deleted** (§4). **Item 9's deferral of "when the gear may be raised" to the berth** (`:509-511`) is rewritten — there is no longer a bay restriction, only the stow-before-release rule. The "FROM COLD" closing note (`:513`) says items 1–2 are the whole set-up; that is now false — a cold ship needs the drive started too. |
| `checklist-arrival` (`:516`) | New **AFTER LANDING** section after TOUCHDOWN: drive selector OFF, hatch open, ALT off, BAT off. **Item 11 `HOLD — DISPOSE OF` (`:554`) is deleted** (§4). |
| **new `emergency`** | New chapter for the failure the pilot has to fly out of: **LH2 EXHAUSTED AT L — NO THRUST**. Selector to R or BOTH, expect 40% and a rising electrical draw, watch the battery, get home. Also covers the flat-battery ship and the two distinct no-thrust annunciations. File it in SECTION 2 adjacent to `propulsion`, or open a SECTION 5 — either is fine, but the group must stay contiguous. |
| `gear` (`:327`) | DEPARTURE paragraph (`:346-347`) says the gear must remain down until the bay is cleared — **now false, rewrite**. |

### `scenes/displays/TerminalProceduresContent.gd`

| Chapter | Change |
| --- | --- |
| `departure-procedure` (`:180`) | Delete item 5 (`DOWN UNTIL DELTA IS CLEARED` + its CAUTION, `:196-197`) and renumber. Item 6 (`STOWED BEFORE RELEASE`) survives as the only gear rule outbound. |
| `prices` (`:232`) | **LIQUID HYDROGEN** and **LIQUID OXYGEN** added to the schedule at the new `MarketSystem` prices. **The TERMS line at `:255` — "nothing is offered for sale to vessels — no fuel, no repair, no berthing charge, no consumables" — is now false; rewrite it** to say propellant is offered and repair is not. |

Tank capacities, burn rates and speed bonuses are the **builder's** and belong
only in the handbook; propellant **prices** are the commercial agent's and belong
only in the schedule. Do not add LH2/LOX terms to `PilotManualSmoke.BUILDER_ONLY`
— the agent's price schedule has to name the commodities.

### `README.md`

- **Power budget paragraph** (`:360-380`) — rewritten for the alternator/battery
  model; the MASTER ALT "rig for escape" description is false.
- **Switch panel table** (`:426-427`) — both master rows rewritten, and the
  magneto moves **out of** the "decoded and logged but no gameplay effect yet"
  sentence at `:444-445` into the wired table as the drive selector.
- **Keyboard table** (`:446+`) — **rewritten wholesale** from the reworked default
  map (§5), not patched with four new rows.
- **Manual flight throttle paragraph** (`:374-382`) — the ceiling is now tiered.
- **Core loop steps 10–11** (`:315-318`, `:343-348`) — the gear-in-bay rule is
  gone; buying LH2 and LOX at the berth is new.
- **Main flight HUD** section (`:41+`) — the IMPULSE/BOOST annunciator.
- **Handy tool scenes** (`:662+`) — the manual exporter.

### `CLAUDE.md`

Add rows to the sync table: battery, tank and burn-rate constants → the handbook
chapter that quotes them; propellant prices → the terminal procedures; the PDF
exporter alongside the other `tools/` entries.

---

## 7. PDF export

Two steps, both build-only — **nothing committed** (add the output directory to
`.gitignore`).

**`tools/ManualExport.gd` + `.tscn`**, headless, following the existing tool
conventions: `OS.get_cmdline_user_args()` for the output directory (as
`ScreenshotCheck.gd:29`), `FileAccess.open` + `store_string` to write (as
`ShipColliderBake.gd:123-126`), `get_tree().quit(0/1)`.

```
godot --headless res://tools/ManualExport.tscn ++ <out_dir>
```

It reuses exactly what `PilotManualSmoke.gd:159-175` already does: instantiate a
bare `ManualViewer` off-tree with `ViewerScript.new()`, call `_resolve()` on each
chapter body so **bindings resolve identically to the in-game page**, then free it.
Add a small BBCode→HTML converter — the dialect is only `[b]`, `[i]`,
`[color=#hex]`, so this is a short function, not a parser.

Emit one print-styled HTML per document: a title page from
`TitleCard.DOCUMENTS`' `title`/`subtitle`, a contents page from the `group`/`title`
fields, `@page` rules and a page break per chapter. **The dot-leader tables only
line up in a monospace face** — set the body font accordingly or the PERFORMANCE
and price tables will look broken.

**`tools/build_manuals.ps1`** (or `.py`, matching the `build_hull.py` precedent)
runs the Godot step, then prints each HTML to PDF with headless Chrome, which is
already installed at
`C:\Program Files\Google\Chrome\Application\chrome.exe`:

```
chrome --headless --disable-gpu --no-pdf-header-footer \
       --print-to-pdf=<out.pdf> file:///<out.html>
```

Edge is present as a fallback. This adds **no** third document — `TitleCard`
still opens exactly two, which `PilotManualSmoke` asserts.

---

## 8. Verification

There is no test runner in this repo; each smoke is its own headless scene and
signals through its exit code. `godot` is on PATH (4.7); use `godot_console` on
Windows to actually see stdout.

**Tests to update or add:**

- `tools/PowerSmoke.gd` — **rewrite**. It currently asserts the master overrides
  and the mix lockout, both of which are being deleted. New assertions: surplus
  charges the battery; a deficit discharges it; ALT off runs the ship off the
  battery and drains it; BAT off scales delivery down to fit the supply; both off
  and flat-battery-with-ALT-off both deliver nothing; **and, across every one of
  those states, `_power_target` is unchanged and a slider or switch moved while
  starved still takes effect** — the settings/availability split is the assertion
  that matters most. Signature still halves per master off.
- **New `tools/PropellantSmoke.gd/.tscn`** — the ceiling and thrust figures for
  each selector position; burn scales with commanded thrust and is nil at rest;
  **BOOST drains LH2 and LOX together** and is refused with either tank dry or the
  thermal stage not running; **a dry LH2 tank at L produces no thrust at all** and
  **the same tank at BOTH still gives 40% and 25 m/s** — the no-automatic-fallback
  rule, asserted in both directions; a dry LOX tank leaves the thermal stage at
  full thrust; a purchase at a berth fills the tank and debits credits; a purchase
  away from a berth, over capacity, or without the credits is refused.
- **New `tools/DriveStartSmoke.gd/.tscn`** (or a section of the above) — OFF gives
  literally no thrust; going straight from OFF to R/L/BOTH does not start the
  drive; **START itself produces no thrust however long it is left there**;
  leaving START before `drive_start_time` resets the count; a full 10 s at START
  followed by a move to a running position brings the drive live; and **the
  electric-draw coupling**: L→BOTH raises THRUST demand, and running the LH2 tank
  dry while the alternator is already loaded starts the battery discharging.
- `tools/DockSmoke.gd` — remove the gear-in-bay reprimand assertion; assert that
  raising the gear over the pad outbound now costs nothing, that the release is
  still withheld until stowed, and that both inbound gear rules are intact.
- `tools/ChecklistSmoke.gd` — the new arrival, departure and cutting rows follow
  real state (including the start hold showing progress); the limits they print are
  read from the constants that enforce them.
- `tools/AlignSmoke.gd` / `tools/Phase5Smoke.gd` — the approach autopilot is now
  refused with the drive OFF or unstarted.
- `tools/PilotManualSmoke.gd` — should pass unchanged; run it to prove the new
  chapters are contiguous, long enough, placeholder-clean and on the right side of
  the authorship line, **and that the keyboard rework (§5) renamed no action a
  document still names**. Its `_test_binding_labels()` also asserts that every
  bound key is reported on its action, so it is the guard on the reworked map too.
- `tools/Phase4Smoke.gd` — the hatch now gates the sale.

**Run, from `d:/simpit-game`:**

```bash
godot --headless res://tools/PowerSmoke.tscn         # rewritten
godot --headless res://tools/PowerNudgeSmoke.tscn
godot --headless res://tools/PropellantSmoke.tscn    # new — LH2/LOX, selector tiers
godot --headless res://tools/DriveStartSmoke.tscn    # new — OFF/START, draw coupling
godot --headless res://tools/FlightSmoke.tscn        # ceiling clamp, FBW untouched
godot --headless res://tools/AlignSmoke.tscn         # autopilot drive gate
godot --headless res://tools/DockSmoke.tscn          # gear rules
godot --headless res://tools/ChecklistSmoke.tscn
godot --headless res://tools/PilotManualSmoke.tscn   # both documents
godot --headless res://tools/Phase4Smoke.tscn
godot --headless res://tools/Phase5Smoke.tscn
godot --headless res://tools/DisplayLoadCheck.tscn
godot --headless res://tools/ManualExport.tscn ++ build/manuals   # new
pwsh tools/build_manuals.ps1                          # HTML → PDF
```

**By hand, in the running game** (`scenes/boot/Boot.tscn`):

1. Open **PILOT'S MANUAL** and **TERMINAL PROCEDURES** from the title card and
   read the changed chapters — the manual is the only place the new prose is
   proofed at its real type size.
2. Fly with `MASTER ALT` off and watch the battery drain to flat and the ship go
   quiet; restore ALT and watch it recharge. **Move a slider while the ship is
   starved and confirm the setting holds and takes effect on restoration.**
3. Run the throttle to the stop with both tanks aboard and confirm the tiered
   ceiling and the IMPULSE/BOOST annunciator; run LOX dry and confirm the thermal
   stage survives at full thrust; run LH2 dry and confirm the ship falls back to
   25 m/s with LOX still aboard, that `LH2 DEPLETED` annunciates, that the POWER
   page's draw visibly jumps, and that **it still flies home** on the field stage.
4. Cycle the magneto through OFF / R / L / BOTH on the physical panel and feel each
   position — R sluggish and expensive, L modest and cheap, BOTH everything. Set
   OFF, confirm the ship will not move, then run the start: selector to START, ten
   seconds, selector to BOTH. Confirm nothing moves while it sits at START. Then do
   the same on the keyboard bindings, which is the path a player without the panel
   has to fly.
5. **Run the dead-stop case deliberately**: cruise at L, run the tank dry, confirm
   thrust stops entirely and the annunciator says why, then select R and confirm
   the ship recovers at 40% with the draw and battery behaving as §3 describes.
6. **Fly a full sortie on the reworked keyboard map alone**, with the HOTAS and the
   switch panel unplugged. Every procedure in both documents must be completable —
   that is the only real test that §5 landed.
4. Land, open the hatch, sell, both masters off; then depart — masters on, hatch
   secured, clearance, off the pad, and **raise the gear immediately** to confirm
   no reprimand, and that ATC still holds the release until it is stowed.
5. `tools/ScreenshotCheck.tscn` with `manual power` and `mfd POWER` to check the
   rewritten chapter and the new POWER header at real size.
