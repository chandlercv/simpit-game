# Retire the Higgs ceiling: a fly-by-wire governor, real mass, and gated sub-stepping

## Context

The ship's speed ceiling is currently fiction: a **Higgs coupling** that grows
with velocity and behaves like drag, so a hull's maximum is where thrust and drag
balance (`Docs/Plans/simpit-world.md:83-96`, `README.md:503`,
`GameState.speed_ceiling()`). It makes speed an **absolute** quantity in a
universe where velocity is relative. The moment the setting acquires an
Earth-sized planet — where orbital speeds are kilometres per second — a 25 m/s
universal cap is indefensible, and the lore has to be walked back under a system
that has grown a lot of dependencies.

It is also fiction the code never implemented: there is no drag term anywhere in
the integrator. `ShipMotion.gd:214` is a single hard `velocity.limit_length()`.

The replacement is a **fly-by-wire speed governor** — a limit the flight computer
imposes, not the universe. That is defensible near a planet for one reason and
only one: **a governor names its reference.** It holds the ship to a set speed
*relative to the selected navigation datum*, which is exactly the frame
distinction this branch (`reference-frames-and-mass`) already documents in
`GameState.ships` and `NavReference.vertical_speed()`. Near a planet it governs
closing speed on the thing you are flying at, not speed through space.

Four things follow, and they are one change because each depends on the others:

1. A governor is a **pilot setting**, so it needs a control — the MFD SETTINGS
   page — and a default of **60 m/s**.
2. A governor is **fly-by-wire**, so switching the FBW off must remove it. That
   makes the throttle mean something different in each control law.
3. An ungoverned ship goes fast enough to **tunnel**. The Kestrel's collider is
   0.35 m radius / 1.9 m spine, and collision is a discrete overlap test once per
   60 Hz tick. At the *default* 60 m/s the ship already moves 1.0 m per tick
   against its own 0.7 m diameter. Sub-stepping is not optional at these speeds.
4. Deleting drag removes the last thing standing in for **mass**. The ship
   currently has an acceleration and no mass, an attitude rate and no inertia, a
   "reactor" that is one abstract number. Those become real, and — the decision
   taken here — they reach the flight model: a loaded ship flies heavier.
5. And they have to reach the **collision system** too, or the mass is only half
   real — deciding how the ship accelerates while having no say in what happens
   when it hits something. That system runs on its own arbitrary units today
   (`SHIP_MASS := 500`, debris mass `= r³`, a scalar radius of gyration), so it
   moves to kilograms in one piece, as its own phase.

Decisions taken with the user, so the plan carries only these:

| | |
| --- | --- |
| Governor reference | **The selected nav datum** (`NavReference`) |
| Control laws | **Two: NORMAL / DIRECT**, on `fbw_mode_cycle` |
| Throttle in NORMAL | **Combined** on a lever — position sets both the target speed *and* the thrust used reaching it |
| Throttle law selection | **Follows the device** (LEVER → combined, GAMEPAD → thrust), with `throttle_cmd_toggle` kept as the manual override |
| Reverse | **Stays capped at 50%** of forward in every law |
| Mass | **Live** — dry + propellant + cargo changes acceleration and attitude authority |
| Per-stage ceilings (25/35/50) | **Collapsed.** Stages differ in thrust, bus load and propellant only |

---

## Phase 1 — The two control laws

**`autoload/GameState.gd`** — the law is state the HUD, the band, the settings
page and `AlertSystem` all read, so it lives here per the file's own contract
(`GameState.gd:2-9`), not privately on `ShipMotion` as `_fbw_on` does today:

- `const FBW_LAWS: Array[String] = ["NORMAL", "DIRECT"]` — an array rather than a
  bool because the annunciator, the handbook and the settings page all name the
  law, and because `TACTICAL_VIEWS` sets the two-value precedent (`:854-901`).
- `var fbw_law := "NORMAL"` — **not persisted.** A control law boots in NORMAL
  every flight, like the ship it is modelled on.
- `signal fbw_law_changed(law: String)`, `set_fbw_law()` / `cycle_fbw_law()`,
  following the guard-assign-emit idiom at `GameState.gd:854-901`.

**`systems/ShipMotion.gd`**:

- `authority()` (`:134`) returns `0.0` under DIRECT; NORMAL keeps the existing
  `power_term * drive_term` product unchanged.
- `toggle_fbw()` (`:121`) becomes a passthrough to `GameState.cycle_fbw_law()`,
  or is deleted in favour of it — one of the two, not both.
- `enum ThrottleCmdMode` and `_throttle_cmd_mode` (`:44-51`) **stay**, renamed
  `{ COMBINED, THRUST }`. See the next section — they are not redundant with the
  FBW law, and retiring them was a mistake in an earlier draft of this plan.

### The throttle law is a property of the hardware, not of the assist level

`throttle_cmd_toggle` looks like a second assist switch and is not. A throttle is
one of two physical shapes and they want opposite laws:

| At rest | Combined law | Thrust law |
| --- | --- | --- |
| **X52/X55 lever parked at 50%** | holds 30 m/s — park it and fly ✅ | permanent 2 m/s² burn ❌ |
| **Gamepad stick released to centre** | commands zero, so it **brakes hard every time you let go** ❌ | coasts; push to accelerate, pull to brake ✅ |

A centring axis reads exactly **0** at rest (`InputRouter._throttle_curve`,
`{mode:"gamepad"}`, `:567`, `:593`) — so under the combined law a released stick
is a full-authority braking command, and holding any speed means holding the
stick forward indefinitely. The combined law is good on a lever for precisely the
reason it is hostile on a pad: on a lever, position means a speed you can walk
away from.

**The ship already knows which is fitted.** The F7 remapper carries an explicit
LEVER/GAMEPAD mode per device (`ControlsSetup.gd:692`, `:1034-1047`), persisted
to `user://input_profiles/<guid>.json` and loaded into `InputRouter._throttle_spec`
(`:441-457`). So:

- Add `func throttle_is_centering() -> bool` to `InputRouter` —
  `String(_throttle_spec.get("mode", "")) == "gamepad"`. There is already a
  public spec accessor at `:367-372` to follow for style.
- `ShipMotion` picks the **default** law from it when a profile loads: gamepad →
  `THRUST`, lever → `COMBINED`. Correct out of the box on either shape, with no
  pilot action and no unbound control to discover.
- `throttle_cmd_toggle` **survives as the override**, for the lever pilot who
  wants the Newtonian feel or the pad pilot who wants cruise control. Its
  remapper label ("Throttle Cmd Mode", `ControlsSetup.gd:43`) and its comms line
  are reworded to name the two laws as they now are.
- **DIRECT forces the thrust law** whatever the toggle says. That resolves the
  one incoherent combination: a speed-holding loop is fly-by-wire by definition,
  so it cannot survive the law that removes fly-by-wire.

### `_apply_throttle_axis()` (`:226`) — the combined law

**NORMAL, lever.** The lever's position sets *both* the speed converged on and
the thrust used to get there:

```
var target := z_cmd * GameState.governor_speed()
var closing := absf(target) < absf(fwd_speed)   # lever asks for less than we have
var authority := accel if closing else absf(z_cmd) * accel
new_fwd_speed = move_toward(fwd_speed, target, authority * delta)
```

**The asymmetry is load-bearing, not a nicety.** Scaling authority by lever
position in *both* directions makes a closed lever command target 0 with
authority 0 — `move_toward(60, 0, 0)` does nothing, and the ship coasts forever
with the throttle shut. Deceleration therefore always gets the drive's full
authority: closing the lever means "arrest me with everything you have", which is
what a throttle means and what today's law already does at zero.

This replaces today's `move_toward(fwd, z_cmd * ceiling, accel * delta)`, which
applies **full** thrust at any lever position — so half lever is a full-thrust
slam that stops dead at half speed. Under the combined law half lever is half
thrust easing onto half speed, which is both what the lever feels like it should
do and what makes fine work possible: a 10% lever is 0.4 m/s² onto 6 m/s.

**NORMAL, gamepad (and DIRECT, always).**
`fwd_speed + z_cmd * accel * delta` — open loop. Under NORMAL the Phase 2 clamp
still bites, so a pad pilot converges on the governor speed rather than running
away; under DIRECT it does not run at all, and releasing everything leaves the
ship at its current velocity indefinitely. DIRECT is the only law in which that
is true.

`z_cmd` stays clamped to `[-secondary_thrust_fraction, 1.0]` in **both** laws, so
reverse keeps its 50% authority and stopping from high speed in DIRECT rewards
flipping the ship over braking on reverse (75 s against 150 s from 300 m/s).

**No input action is removed by this change.** `throttle_cmd_toggle` and
`fbw_mode_cycle` both keep their `project.godot` entries and their remapper rows,
so no saved profile under `user://input_profiles/*.json` is invalidated. Both
still ship unbound; `fbw_mode_cycle` is now the one most worth binding.

**Comms lines change, so the voice bank must be rebuilt.** `toggle_fbw` posts
`"FLIGHT ASSIST %s"` (`ShipMotion.gd:123`) and `toggle_throttle_cmd_mode` posts
`"THROTTLE — %s COMMAND"` (`:105`). Both patterns move — the first to name the
two laws, the second because `ThrottleCmdMode.keys()` supplies the `%s` and
`SPEED` becomes `COMBINED`. Per `CLAUDE.md`, re-run `python tools/build_speech.py`
in the same change; `AudioSmoke` fails the build if this is forgotten.

---

## Phase 2 — The governor, measured against the datum

**`systems/NavReference.gd`** — the datum dictionary gains a `velocity`, and a
new `relative_velocity()` returns `ship.velocity - datum["velocity"]`. Today
PAD / WRECK / INERTIAL origins are all static so it equals world velocity, but
**TARGET is not**: `ThreatSystem` moves rivals and patrols, so pinning the datum
to a moving contact makes the governor immediately, observably relative. Write
the frame note in the same voice as the ones already added to
`vertical_speed()` on this branch.

**`autoload/GameState.gd`**:

- Delete `speed_ceiling()` (`:1246`) entirely.
- `const GOVERNOR_STEPS: Array[float] = [20.0, 40.0, 60.0, 90.0, 120.0]`
- `var governor_speed := 60.0`, `signal governor_speed_changed(speed: float)`,
  `set_governor_speed()`.
- `func governor_speed_active() -> float` — `INF` under DIRECT, else the setting.

**`systems/ShipMotion.gd:211-214`** — the clamp, rewritten. Resolve into the
datum frame, limit there, resolve back, and skip entirely under DIRECT:

```
var ref_v := NavReference.datum_velocity()
var relative := velocity - ref_v
velocity = ref_v + relative.limit_length(GameState.governor_speed_active())
```

Delete the Higgs comment above it. The replacement comment states what the
governor is (a flight-computer limit), what it measures against, and that DIRECT
removes it.

**`scenes/ui/SettingsPanel.gd`** — a `GOVERNOR` row above `NAV REFERENCE`, built
with the existing `_add_row()` (`:61-83`), labels formatted from
`GOVERNOR_STEPS` (`"60 M/S"`). Discrete presets rather than a `TouchSlider`,
because `TouchSlider` hardcodes a `%d%%` readout (`TouchSlider.gd:100-104`) and
cannot show m/s, and because round numbers are what a finger can hit. Add
`governor_speed_changed` to the `_sync()` connections at `:33-36`.

**Persistence** — a new `user://flight.cfg` holding the governor setting only,
following `AudioSystem._load_mixer` / `_save_mixer` (`AudioSystem.gd:196-234`):
seed the default first, read guarded and clamped, save on every change. The law
is deliberately not saved. This follows the established convention that a new
settings domain gets its own file (`AudioSystem.gd:38`).

**`scenes/ui/InstrumentBand.gd:276`** — `_draw_limit_band(...speed_ceiling())`
becomes the governor setting, drawn only when the law is not DIRECT, and the
speed tape's caption names the datum (`"VEL M/S REL PLATFORM"`) so the tape says
what it is measuring against. Reuse `_draw_caption` (`:230`) as-is.

---

## Phase 3 — Collapse the stage ceilings, and make boost buy thrust

**`resources/ShipDefinition.gd` + `data/ships/kestrel.tres`** — delete
`max_speed`, `thermal_speed_bonus`, `boost_speed_bonus`.

Boost currently buys **only** ceiling (`+15 m/s`) and no thrust, so deleting the
ceiling would leave it doing nothing. It has to buy thrust instead: add
`thrust_fraction_boost := 1.5` and extend `GameState.thrust_fraction()`
(`:1232`) to return it while `boosting()`. This is a required compensating
change, not a nicety.

Also fix, while in this file: **`secondary_thrust_fraction` is missing from
`kestrel.tres`** and silently runs on the script default `0.5`, against the
"ship stats authored as data" convention at `ShipDefinition.gd:3-5`. Write it in.

---

## Phase 4 — Mass, inertia, and the power plant

### `resources/ShipDefinition.gd` — new properties, SI

| Property | Value | Note |
| --- | --- | --- |
| `dry_mass_kg` | `60_000.0` | chosen so a full ship is ~1.7× dry, a real but flyable swing |
| `inertia_kgm2` | `Vector3(9.0e5, 9.0e5, 2.0e5)` | principal moments, pitch/yaw/roll; roll about the long axis is far smaller |
| `main_thrust_n` | `240_000.0` | 240 kN ÷ 60 t = **4.0 m/s² exactly**, today's figure |
| `attitude_torque_nm` | `Vector3` | authored to give 45°/s² on pitch/yaw at dry mass |
| `lh2_kg_per_unit` / `lox_kg_per_unit` | `40.0` / `60.0` | 60 u LH2 + 20 u LOX ≈ 3.6 t |
| `reactor_output_w` | `1_200_000.0` | thermal. The surplus over the alternator is what heats hydrogen — the NTR stage runs on the reactor's *heat*, which is why it is nearly free on the bus |
| `alternator_output_w` | `500_000.0` | electrical |
| `battery_capacity_j` | `2.4e7` | 24 MJ |
| `power_unit_w` | `200_000.0` | one bus "unit" = 200 kW |

Delete `manual_accel`. `power_budget` becomes derived:
`alternator_output_w / power_unit_w` = **2.5**, bit-identical to today, so the
whole boot power balance and `PowerSmoke` are untouched. `BATTERY_CAPACITY`
(`GameState.gd:159`) likewise becomes `battery_capacity_j / power_unit_w` = 120.

**Keeping the bus arithmetic in abstract units is deliberate.** Converting the
four channels to watts would touch `PowerSliders`, `PowerSmoke`, every published
figure and the tuned 2.4-against-2.5 boot mix, for no gameplay gain. The SI
numbers sit *behind* the units and are what the handbook and the new tapes quote.

### `autoload/GameState.gd` — live mass

- `func ship_mass() -> float` — `dry_mass_kg + lh2_fuel * lh2_kg_per_unit +
  lox_fuel * lox_kg_per_unit + CargoSystem.cargo_mass() * 1000.0`.
- `func ship_inertia() -> Vector3` — `inertia_kgm2 * (ship_mass() / dry_mass_kg)`.
  A crude scale rather than a per-item tensor, and the comment must say so: the
  hold's contents are not tracked positionally, so mass ratio is the honest
  approximation available.

### `systems/ShipMotion.gd` — mass reaches the flight model

- `thrust_accel()` (`:247`) becomes
  `main_thrust_n / ship_mass() * power("THRUST") * thrust_fraction()`.
  Empty and fuelled at boot this is 4.0 m/s²; at 40 t cargo and full tanks it is
  ≈ 2.3 m/s².
- **Angular authority is now torque-limited.** The FBW slew at `:204` is an
  exponential with no limit, so today it would settle a fully loaded ship as fast
  as an empty one. Clamp the per-tick angular correction to the available angular
  acceleration, `attitude_torque_nm / ship_inertia()`, per axis. `fbw_raw_torque_deg`
  is derived from the same figures rather than authored.
- `rotation_rate_deg` stays a single **commanded** rate — full deflection still
  commands 45°/s on every axis, so the handbook's figure stays true. What changes
  is how fast each axis *reaches* it: roll is livelier than pitch and yaw because
  its moment is smaller, and a loaded ship is slower onto all three. This is a
  deliberate flight-feel change and is the point of authoring a tensor at all.

`collision_spin_radius` (the scalar radius of gyration at `:113-115`) is
superseded by `inertia_kgm2` and is deleted in Phase 6, which is where the
collision system moves onto the same kilogram scale as the ship.

---

## Phase 5 — Gated sub-stepping

The problem is not the integrator. `CollisionSystem` is a **discrete overlap test
run once, after** the tick's position update (`CollisionSystem.gd:1-13, 95`), so
sub-stepping motion alone buys nothing — collision has to sub-step with it.

**`systems/CollisionSystem.gd`** — extract the ship pass (`:95-148`) into
`func resolve_ship(delta: float)`. `_physics_process` keeps its cooldown decay,
the movable-vs-movable passes, and one final `resolve_ship` call, so the
authoritative pass still runs last with `ThreatSystem`'s fresh positions, exactly
as the header promises. Cooldown decay must stay in `_physics_process` and not
run per sub-step. Also expose `func min_body_radius() -> float` — the smallest
bounding radius among `_collidables()`, computed once per tick.

**`systems/ShipMotion.gd`** — `step()` becomes the driver. Rename the existing
body to `_integrate(delta)` and make `step()`:

```
const MAX_SUBSTEPS := 8
const SUBSTEP_SAFETY := 0.5

var feature := minf(CollisionSystem.min_body_radius(), CollisionSystem.ship_reach())
var reach := velocity.length() * delta
var n := clampi(ceili(reach / maxf(SUBSTEP_SAFETY * feature, 0.01)), 1, MAX_SUBSTEPS)
for i in n:
    _integrate(delta / n)
    CollisionSystem.resolve_ship(delta / n)
```

The gate is the point: at station-keeping speeds `n` is 1 and the cost is one
`minf` per tick. At 60 m/s against a 0.35 m body it is 6. Eight sub-steps at
60 Hz covers ~170 m/s, which is where DIRECT law gets interesting.

Sub-step the **ship only**. `ThreatSystem` and `DriftSystem` bodies move slowly
enough that their own discrete pass is fine; say so in the comment rather than
leaving it as an unstated assumption.

Rejected alternative, worth recording: a **swept capsule** (extend the ship's
spine along the motion vector and reuse the existing segment-vs-hull GJK) would
be O(1) instead of O(n) and needs no collision-system restructure — but it
detects the crossing without resolving the response at the right position, and it
cannot sub-step the FBW. If sub-stepping ever measures too expensive, that is the
escape hatch.

---

## Phase 6 — Put the collision system on the same kilogram scale

Phase 5 fixed *when* collision runs. This fixes *what its impulses are computed
from*, and without it the ship's mass is only half real: it would decide how the
ship accelerates and have no say in what happens when it hits something.

Today the collision system runs on its own arbitrary units — `SHIP_MASS := 500.0`
(`CollisionSystem.gd:62-66`), `DebrisField`'s `mass = radius³` giving 1–27
(`DebrisField.gd:44-51`), and a scalar radius of gyration standing in for
inertia. They are internally consistent with each other and disconnected from
everything else, which is why Phase 4 cannot simply substitute 60 000 kg: doing
that alone drives `frac = SHIP_MASS / (SHIP_MASS + mass)` from 0.95 to 0.9996 and
silently guts `DriftSmoke`. The units have to move together or not at all.

**The reassuring part:** `_resolve_pair` (`:318-341`) splits by inverse-mass
*ratios* only, so it is scale-invariant. Convert every body together and
movable-vs-movable behaviour is unchanged. Only the ship-vs-body path moves.

### Every mass goes to kilograms

- `CollisionSystem.SHIP_MASS` → `GameState.ship_mass()`, so the figure is live: a
  loaded ship shoves debris harder and is shoved less. Delete the constant.
- `DebrisField.gd:48` → `mass = DEBRIS_DENSITY * (4.0/3.0) * PI * r³`. **Pick the
  density deliberately** — it decides how the field feels. At a realistic rocky
  `2000 kg/m³` a 1 m chunk is 8.4 t and a 3 m chunk is 226 t, so large debris
  becomes genuinely immovable by a 60 t cutter. That is physically right and a
  real feel change; a lighter rubble-pile figure (~500) keeps chunks shovable.
  Start at 2000, fly the field, and tune against `DriftSmoke` — the arithmetic is
  here so the number is chosen rather than inherited.
- Salvage pieces (`DriftSystem` / `SalvagePieces.gd`) take mass from the same
  density and their member radius, so the comment at `DebrisField.gd:45-47` —
  "same density assumption … so the two kinds trade momentum proportionately" —
  stays true, now with a density that is a real number.
- Rival, patrol and traffic ships (`ThreatSystem`) get a real ship mass rather
  than the contact radius standing in for one.
- `GameState.register_obstacle(..., mass := 0.0)`'s **zero-means-immovable
  sentinel survives unchanged** — the wreck frame, the station and the deck stay
  infinite-mass, which is what they should be.

### The ship's own bounce becomes mass-aware

`_physics_process` (`:133-136`) currently reflects the ship's inward velocity with
`RESTITUTION` regardless of what it hit — the header calls this "infinite-mass-
target shorthand" and it is why ramming a pebble and ramming the station feel the
same. Against a **movable** body, split the exchange by mass the way
`_resolve_pair` already does; against a mass-0 body, keep the shorthand, which is
then correct rather than a stand-in. Ramming a 226 t boulder should hurt more
than ramming an 8 t chunk, and after this it does.

### `_impact_spin` uses the real inertia tensor

`:243-251` computes `(contact - origin).cross(dv) / (rg * rg)` — the massless
form, with `collision_spin_radius = 1.0` making the divisor 1. Replace with the
proper `I⁻¹(r × J)`, per axis:

```
delta_omega = GameState.ship_mass() * (contact - origin).cross(dv) / GameState.ship_inertia()
```

Delete `collision_spin_radius` from `ShipDefinition` and `kestrel.tres`.

**This lands the numbers somewhere better than they are now, which is the
argument for doing it.** Today a 1.5 m lever arm and a 10 m/s dv give 15 rad/s
against a `MAX_IMPART_SPIN` cap of 1.5 — the cap saturates on essentially every
impact, so severity is invisible. Under the tensor the same hit gives
`60000 × 15 / 9.0e5 ≈ 1.0 rad/s`, just under the cap, and spin finally scales
with how hard you hit. Re-check `MAX_IMPART_SPIN` still earns its place.

---

## Documentation — mandatory, per `CLAUDE.md`

**`README.md`**
- `:503-505` — the Higgs paragraph. Replace with the governor: what it is, what
  it measures against, that it is a setting, that DIRECT removes it.
- The propulsion selector table (`:509-515`) — **delete the "Max speed" column**,
  and change boost's row to buy thrust.
- The manual-flight throttle paragraph (`:520-527`) — the `Throttle Cmd Mode`
  sentence and the "commands a target speed" description are both now false and
  must be **rewritten**, not appended to: on a lever the throttle commands target
  speed *and* thrust together and closing it brakes at full authority; on a
  centring gamepad axis it commands thrust, chosen automatically from the
  device's profile.
- `:819` — the sentence listing `throttle_cmd_toggle` among the unbound controls.
  Still true that it ships unbound, but it is now an override on a default the
  ship picks from the hardware, not the only way to reach the other law.
- `:37` (Tactical) and `:38` / `:845` (SETTINGS page) — the two new tapes and the
  governor row.
- The Tactical band section (`:153-158`, `:177-178`) — the speed tape's band is
  now the governor and names its datum; the propellant tapes become four.

**`scenes/displays/PilotManualContent.gd`** — the builder's document, so every
figure below is the builder's to state:
- `ship` (PERFORMANCE, `:94-105`) — delete the three maximum-speed lines; add
  mass, moments of inertia, main thrust in newtons, and state acceleration as
  derived from thrust and mass, with the loaded figure.
- `flight` (`:124`) — rewrite STABILITY AUGMENTATION and THROTTLE for NORMAL and
  DIRECT. The SPEED/THRUST block at `:158-166` is rewritten rather than deleted —
  the two throttle laws survive, but as **COMBINED and THRUST**, chosen by the
  throttle's shape rather than by preference. Say which shape gets which and that
  `{{act:throttle_cmd_toggle}}` overrides it. Its worked example ("Set to 50% on
  the field stage alone, the ship accelerates to 12.5 m/s") is false twice over —
  the stage no longer sets a ceiling, and half lever is now half thrust — so
  replace it, and state that closing the lever brakes at full authority. The
  WARNING at `:148` is still true of DIRECT but must name the law. Add the
  governor: what it holds, against **what datum**, that it is set on the MFD
  SETTINGS page, and a **CAUTION** that DIRECT removes it and that nothing then
  stops the ship but the pilot.
- `power` (`:200`) — reactor, alternator and battery in SI, and the causal point
  that the reactor's thermal surplus over the alternator is what the nuclear
  thermal stage runs on.
- `propulsion` (`:244`) — the selector list at `:253-257` loses its speed
  figures; boost at `:283` buys thrust, not 50 m/s.
- `collision` (`:518`) — the IMPACT block at `:523-527`. "Rebound … 30% of
  closing speed" is now conditional: it is the figure against fixed structure,
  and against a movable body the exchange splits by mass. Say so, and add a
  **NOTE** that a loaded ship carries more momentum into everything it hits. The
  damage figures themselves are unchanged.
- `displays` (`:608`) — the speed tape's governor band (`:635`), and the two new
  tapes.

**`scenes/displays/TerminalProceduresContent.gd`** — **no change.** Lane speed
limits are the harbour's, they already penalise rather than clamp, and
`PilotManualSmoke` asserts neither document publishes the other's material.
`DockingSystem._station_relative_speed()` — added uncommitted on this branch —
stays deliberately separate from the nav datum for exactly the reason its comment
gives, and the governor must not be routed through it.

**`Docs/Plans/simpit-world.md:83-120`** — rewrite "Why There's a Speed Ceiling".
Higgs drag goes. The reactor keeps a causal role, a better one: it is the heat
source the thermal stage runs on and the mechanical input the alternator
converts. Speed is limited by propellant, amps, and the pilot's own governor
setting — and by nothing else.

**Voice bank** — `python tools/build_speech.py` after the comms lines change.

---

## Verification

**Headless smoke** (no aggregate runner; each is its own scene):

```
godot --headless res://tools/FlightSmoke.tscn
godot --headless res://tools/ThrottleIdleSmoke.tscn
godot --headless res://tools/PropellantSmoke.tscn
godot --headless res://tools/CollisionSmoke.tscn
godot --headless res://tools/PowerSmoke.tscn
godot --headless res://tools/InstrumentBandSmoke.tscn
godot --headless res://tools/AudioSmoke.tscn
godot --headless res://tools/PilotManualSmoke.tscn
godot --headless res://tools/DockSmoke.tscn
godot --headless res://tools/AlignSmoke.tscn
godot --headless res://tools/DriftSmoke.tscn
```

Existing suites that **must be rewritten, not just re-run**:

- **`tools/PropellantSmoke.gd:58-121`** — every `speed_ceiling()` assertion. These
  become `thrust_fraction()` assertions: the same per-selector table, now checking
  thrust and bus draw rather than a ceiling.
- **`tools/FlightSmoke.gd`** — extend with the two FBW laws and the combined
  throttle. Assert: a half lever settles at **half** the governor speed having
  accelerated at **half** thrust (both halves, not just the endpoint — the
  endpoint alone passes under today's law too); a lever closed from cruise
  decelerates at **full** thrust, which is the regression guard for the
  authority asymmetry; DIRECT clamps nothing, nulls nothing, and a released
  control leaves the ship at its velocity indefinitely. Add the frame case — a
  datum pinned to a **moving** contact governs relative speed, so world speed
  exceeds the setting. The existing zero-authority spin cases stay, driven by the
  law rather than by `_fbw_on`.
- **`tools/ThrottleIdleSmoke.gd`** — already drives every throttle spec form
  headless with no stick attached, so it is the right home for the device-derived
  default: a `{mode:"gamepad"}` profile selects the THRUST law and a lever
  profile selects COMBINED. Add the case that matters most on a pad — **a centred
  gamepad axis must not command braking**, which is the regression this whole
  sub-decision exists to prevent.
- **`tools/CollisionSmoke.gd`** — two additions. The sub-stepping case: fly the
  ship at 400 m/s in DIRECT at a thin body and assert it registers the impact
  rather than passing through — this is the test that fails today. And the
  mass-aware bounce: the same closing speed against a heavy body and a light one
  must now leave the ship with **different** velocities, which is the assertion
  that pins Phase 6's whole point.
- **`tools/DriftSmoke.gd`** — the suite most exposed to Phase 6. Its
  momentum-exchange and mass-0-immovable cases should pass unchanged (
  `_resolve_pair` is scale-invariant), and if they do not, the density constant
  is wrong rather than the physics. Its expectations are the tuning signal for
  `DEBRIS_DENSITY`.
- **`tools/PowerSmoke.gd`** — should pass **unchanged**; it is the check that the
  SI refactor left `power_budget()` at 2.5 and `BATTERY_CAPACITY` at 120.
- **`tools/AudioSmoke.gd`** — fails if `build_speech.py` was not re-run.
- **`tools/PilotManualSmoke.gd`** — fails if a harbour figure leaked into the
  handbook, or a retired action is still named in a `{{act:}}` placeholder.

**In the app** (`/run`, or `tools/ScreenshotCheck.tscn`):

```
godot --path . res://tools/ScreenshotCheck.tscn ++ band.png tactical SCOPE
godot --path . res://tools/ScreenshotCheck.tscn ++ settings.png mfd SETTINGS
```

- The band: four consumable tapes read correctly, ALT shows overdraw above the
  100% line, the speed tape's band sits at the governor and names its datum.
- SETTINGS: the GOVERNOR row selects, and the setting survives a relaunch.
- Fly it on the **lever**: cycle `fbw_mode_cycle` at speed and confirm the ship
  does not jump when the governor drops out; check that a part-open lever now
  *eases* onto its speed instead of slamming; in DIRECT, accelerate past 200 m/s
  and ram the station to confirm the sub-stepping catches it.
- Fly it on a **gamepad** — profile the throttle as GAMEPAD in F7, then confirm
  releasing the stick to centre **coasts** rather than braking, and that
  `throttle_cmd_toggle` still flips it back to the lever law on demand.
- Load 40 t of cargo and confirm the ship is measurably heavier on all three:
  acceleration, attitude, and what happens when you nudge a debris chunk.
- Ram debris of two clearly different sizes at the same closing speed and confirm
  the small chunk flies and the large one mostly doesn't. That is Phase 6
  working, and it is invisible in any single-body test.

**Manual proof:** `tools/build_manuals.ps1` reprints both documents to
`build/manuals/` — the fastest way to read the rewritten chapters on paper.
