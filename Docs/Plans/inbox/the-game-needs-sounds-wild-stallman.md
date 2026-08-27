# Give the ship a voice and a soundtrack of her own machinery

## Context

Salvager has no audio at all. There is no `AudioStreamPlayer` anywhere, no bus
layout, no `[audio]` section in [project.godot](project.godot), and not one
`.wav` or `.ogg` in the tree. Every annunciator in the game is drawn text; every
mechanical event is a `post_comms()` line the pilot has to *read*.

That is the wrong load to put on the eyes in a simpit. The pilot is already
reading four screens. A harbour telling you to go around, a leg reaching its
downlock, a capacitor bank charging — these are things you should hear while
looking somewhere else.

The state model is unusually ready for it. Everything routes through one funnel
(`GameState.post_comms`, [GameState.gd:1243](autoload/GameState.gd#L1243)), every
system exposes both an event signal and a continuous state variable, and there is
already an emitted-but-unconsumed `atc_instruction` signal
([GameState.gd:96](autoload/GameState.gd#L96)) carrying the project's only
severity flag. Almost none of this needs inventing — it needs listening to.

Four decisions are settled:

- Speech is a **pre-rendered clip bank**, radio-processed offline, concatenated at
  runtime so numbers and the callsign stay dynamic.
- The cargo hatch gets a **real travel model**, mirroring the landing gear.
- The harbour uses the **full identity on first contact, abbreviated thereafter**.
- Warnings get a **small latching AlertSystem** speaking the handbook's own
  WARNING / CAUTION / NOTE levels.

---

## The one rule everything else follows

Outside the pressure hull there is no air, so nothing out there radiates sound to
you. Every sound in this game arrives by exactly one of two paths:

| Path | What it sounds like | What travels it |
| --- | --- | --- |
| **Structure-borne** | Hard-lowpassed, no crisp top end, smeared by the frame's own ring. Felt as much as heard. | Landing gear, cargo door, cutter head, thrusters, main drive — everything mounted outside. |
| **Cabin air** | The only sounds with any high end. Dry, close, present. | Ventilation, the annunciator speaker, your own headset sidetone. |

This is implemented **once, on a bus**, not forty times in a generator (see
Stage 1). Which is what makes the payoff possible: when the LIFE channel dies,
the cabin-air buses fade out and the structure bus does not. The ship goes to a
silence that still has *thumps* in it. Nothing sells vacuum like the ventilation
stopping.

---

## Stage 0 — De-risk the voice pipeline (do this first, it gates Stage 5)

Verified already on this machine: `numpy 2.2.6`, `ffmpeg` on PATH, and five SAPI
voices (`Microsoft David / Mark / Zira`, plus the two `… Desktop` SAPI5
variants). Not yet verified: that `System.Speech.Synthesis` will actually render
those voices **to a file**. The OneCore voices sometimes refuse
`SetOutputToWaveFile`.

Render one clip per candidate voice to the scratchpad and listen. If the OneCore
voices refuse, fall back to `David Desktop` / `Zira Desktop`, which are true SAPI5
and always render.

**Build the generator with the voice engine as a swappable input stage** —
`--engine sapi|espeak|piper|wavdir` — never a hardcoded SAPI call. The catalogue,
the radio processing and the runtime are all engine-independent, so re-rendering
the bank from a permissively-licensed engine later is one command rather than a
rewrite. This is the mitigation for the licensing note in Stage 5.

---

## Stage 1 — The audio spine

**New:** `resources/default_bus_layout.tres`, `systems/audio/AudioSystem.gd`,
`systems/audio/SoundBank.gd`.

### Buses

```
Master
├─ CABIN       cabin air — dry, full-range
│   ├─ ALERTS      annunciator tones (the only piercing thing in the mix)
│   └─ SIDETONE    our own transmissions, heard in the headset
├─ STRUCTURE   conducted — LowPass ~900 Hz + short, dense, metallic Reverb
└─ RADIO       incoming radio — HighPass 300 + LowPass 3400 + Distortion + Compressor
```

All four effects are Godot built-ins (`AudioEffectLowPassFilter`,
`AudioEffectHighPassFilter`, `AudioEffectDistortion`, `AudioEffectCompressor`,
`AudioEffectReverb`). Register the layout at
`[audio] buses/default_bus_layout` in [project.godot](project.godot).

Putting the hull's colouring on `STRUCTURE` rather than into each file means the
source clips can be authored bright and clean, every mechanical sound picks up
the same structural signature for free, and a change in the cabin's acoustic
state — depressurised, helmet on — tilts one bus instead of forty files.

### `AudioSystem` autoload

Registered **last** in [project.godot](project.godot) `[autoload]`, after
`NavReference`. [DriftSystem.gd:9-14](systems/DriftSystem.gd#L9) documents the
ordering contract; audio observes settled state, so it goes at the end. Audio is
process-global, which is also why this is an autoload and not a node in any
window — `window/subwindows/embed_subwindows=false` means one native window per
monitor, and a per-window player would be wrong.

It owns: the pooled `AudioStreamPlayer`s, the per-frame parameter pass, the
signal subscriptions, and the mixer settings. `SoundBank.gd` is the one place
that maps a logical name to a file path, so a renamed asset fails in one spot and
`AudioSmoke` catches it.

---

## Stage 2 — The machinery

**New:** `tools/build_sfx.py` → `assets/generated/sfx/*.wav`.

Committed generated assets are already the house pattern:
[tools/build_hull.py](tools/build_hull.py) generates the committed
`assets/cc0/derelict-frigate/*.glb`. Same reasoning — a clone must run without
Python, ffmpeg or Windows.

**WAV, not OGG, for these.** Vorbis adds encoder padding that breaks seamless
loops; these are all short, and sample-accurate loop points matter more than the
few hundred KB. (The voice bank in Stage 5 goes the other way, for the opposite
reason.) numpy has no scipy here, so filtering is FFT-based — fully vectorised
and fast enough for a build script.

Each entry below is one or more clips plus the state that drives it.

### Ventilation — the bed, and the only airborne machine

Pink-noise duct rush shaped by two cabin resonances (~180 Hz, ~440 Hz), plus the
fan's blade-pass tone and a slow ~0.3 Hz beat between two fans running slightly
out of sync. Loops on `CABIN`.

Level and brightness track `GameState.power("LIFE") * GameState.delivery_fraction()`,
gated on `GameState.bus_live()`
([GameState.gd:928](autoload/GameState.gd#L928)). `LIFE` currently has no
gameplay effect at all — no reader outside the electrical sum — which makes it
perfect for this and costs nothing to claim. When the bus dies the fan spins
down and the cabin goes silent.

### Landing gear — three legs, staggered

Three detuned screw-jack whines offset ~120 ms, 120–400 Hz, rising slightly under
load, and three staggered downlock clunks. No air rush whatsoever: the legs are
outside, in vacuum, so structure is the *only* path.

- Loop while `0.0 < GameState.gear_position < 1.0`
- Clunks on the stops, off `landing_gear_changed` + position edges
- Constants already exist: `GEAR_TRAVEL_TIME := 3.0`
  ([GameState.gd:236](autoload/GameState.gd#L236)), `GEAR_LIMIT_SPEED := 18.0`

Guard the berth-spawn teleport at
[DockingSystem.gd:1580-1582](systems/DockingSystem.gd#L1580), which sets
`gear_down`/`gear_position` directly and emits the signal — that must not fire a
cycle sound.

### Cargo door — the one with a bulkhead between you and it

Leadscrew whine (~90 Hz fundamental + harmonics) amplitude-modulated by a ~4 Hz
per-rev wobble, a granular rumble of the door in its track, then a two-stage
finish: a heavy latch thunk (damped 60–110 Hz frame mode, ~250 ms decay) and the
small click of the lock pins.

Then the detail that makes it a *ship*: the hold is not the cabin. Opening dumps
its residual air, and you hear that through the bulkhead as a brief gasp that
filters downward and dies to nothing in ~0.6 s **as the air leaves**. Closing
runs the reverse — a repress hiss that builds into existence. The gear has no
equivalent, and that inconsistency is the point: one is behind a pressure
bulkhead, the other is bolted to the outside.

Driven by `hatch_position` — which Stage 3 adds.

### Cutter — no roar, because there is nothing to roar in

Four clips, because firing a torch in vacuum is a sequence, not an event:

| Clip | What it is |
| --- | --- |
| `cutter_charge` | Capacitor bank spooling: rising whine ~600 Hz → 2 kHz over ~1.2 s, plus converter buzz off the ship's own bus. Airborne — the converter is inboard, so this one is crisp. |
| `cutter_ignite` | Contactor snap. |
| `cutter_loop` | The conducted signature: coolant-pump throb plus stochastic crackle from ablation shock coupling back down the boom into the frame. Broadband noise hard-lowpassed under 600 Hz. Density rises with cut load. |
| `cutter_stop` | Contactor drop, whine decays — and the coolant pump **runs on** for a second or two before spinning down. |

**Poll, don't signal.** `_begin_cut` and `_abort_cut`
([SalvageSystem.gd:326](systems/SalvageSystem.gd#L326),
[:740](systems/SalvageSystem.gd#L740)) emit nothing, but the cutter needs a
per-frame parameter pass anyway, so reading `GameState.wreck["cutting_id"] != -1`
each frame gets the edges for free and touches no other system. This is exactly
what [CuttingBeam.gd:38](scenes/world/CuttingBeam.gd#L38) already does.

Modulate off `GameState.wreck["cut_progress"]` and, while aligning,
`GameState.align["quality"]`. [CuttingBeam.gd:79-87](scenes/world/CuttingBeam.gd#L79)
already computes a flicker LFO — 11 Hz cutting, 6 Hz aligning — reuse that
expression verbatim so the beam and its sound flicker together.

Also hook `rival_cut_fired` ([GameState.gd:76](autoload/GameState.gd#L76)), the
one genuinely event-shaped torch cue that already exists.

### Thrusters — two different machines

**RCS:** solenoid valves cracking — conducted, so a dull knock rather than a
click — then a short structural rumble while the jet fires. The plume is silent;
what reaches you is the valve and the reaction load through the mounts. Several
variants, chosen round-robin, with a minimum re-trigger interval so holding an
axis doesn't machine-gun.

**Main drive:** deep continuous rumble, 20–150 Hz filtered noise with a slow
random wander, plus a turbopump whine whose pitch tracks throttle, plus the
frame's own resonance. Mostly sub-200 Hz — in vacuum the drive is felt more than
heard. Boost adds a harder, rougher band.

**Plus a 10-second start.** `drive_start_time = 10.0`
([data/ships/kestrel.tres](data/ships/kestrel.tres)) is already a modelled
starter crank (`drive_starting()`, `drive_start_progress()`,
[GameState.gd:1131-1150](autoload/GameState.gd#L1131)). That is a ready-made
spool-up and it should sound like one.

**Three small accessors to add to [ShipMotion.gd](systems/ShipMotion.gd)**, all
mirroring the existing `throttle_command()`
([ShipMotion.gd:71](systems/ShipMotion.gd#L71)):

```gdscript
func command_thrust() -> Vector3      # _cmd_thrust, body-local, -1..1
func command_rotation() -> Vector3    # _cmd_rot, (pitch, yaw, roll), -1..1
func drive_load() -> float            # 0..1, how hard the drive is being worked
```

`drive_load()` is an **extraction, not a new figure** — the expression
`clampf(absf(_cmd_thrust.z) + lateral.length(), 0.0, 1.0)` is currently inlined
in `_burn_propellant` ([ShipMotion.gd:230](systems/ShipMotion.gd#L230)). Pull it
out and call it from both places, so the propellant meter and the engine note
measure the same thing. Use `CMD_DEADBAND := 0.032`
([ShipMotion.gd:42](systems/ShipMotion.gd#L42)) as the axis-released threshold —
it is the project's existing answer to that question.

---

## Stage 3 — Give the cargo hatch a travel time

Today `cargo_hatch_open` is a boolean flipped instantly
([GameState.gd:688-697](autoload/GameState.gd#L688)). A door that opens over
2.5 s of motor needs somewhere to put that time.

**Model it exactly on the gear, and keep the lever/position split.** That split
is what protects the ~20 existing consumers:

```gdscript
const HATCH_TRAVEL_TIME := 2.5           # next to GEAR_TRAVEL_TIME
var hatch_position: float = 0.0          # 0.0 secured -> 1.0 open
func hatch_open_locked() -> bool         # cargo_hatch_open and hatch_position >= 1.0
func hatch_secured() -> bool             # not cargo_hatch_open and hatch_position <= 0.0
func _advance_hatch(delta: float)        # beside _advance_gear, same physics tick
```

`cargo_hatch_open` **stays the lever** (the pilot's selection), exactly as
`gear_down` is. Copy `_advance_gear`'s exact-compare guard verbatim and the
reason for it ([GameState.gd:1308-1310](autoload/GameState.gd#L1308)) — an
approx guard leaves the hatch permanently in transit.

### Which predicate each consumer takes

| Consumer | Takes | Why |
| --- | --- | --- |
| Cut interlock [SalvageSystem.gd:252](systems/SalvageSystem.gd#L252), jump/dock refusals [MarketSystem.gd:97](systems/MarketSystem.gd#L97), [:210](systems/MarketSystem.gd#L210), wave-off on final [DockingSystem.gd:848](systems/DockingSystem.gd#L848), [:866](systems/DockingSystem.gd#L866), `hatch_ok` [:437](systems/DockingSystem.gd#L437) | `not hatch_secured()` | Anything other than *fully closed* is unsafe. Strictly more conservative than today, and the mirror of `gear_stowed()`. |
| Scoop collection [DriftSystem.gd:189](systems/DriftSystem.gd#L189), discharge [MarketSystem.gd:145](systems/MarketSystem.gd#L145), sell button [MarketPanel.gd:93](scenes/ui/MarketPanel.gd#L93) | `hatch_open_locked()` | You cannot scoop a piece through a half-open door. |
| Checklist gates [ChecklistContent.gd:65](scenes/ui/ChecklistContent.gd#L65), [:350](scenes/ui/ChecklistContent.gd#L350), [:546](scenes/ui/ChecklistContent.gd#L546) | the predicates above | A checklist reads actual state, not intent. |
| HUD + SCOOP page | `hatch_position` | Show transit. |

Comms text follows the gear's shape: the lever posts
`"CARGO HATCH — OPEN SELECTED"` / `"SECURE SELECTED"`, and the two stops post
`"CARGO HATCH OPEN AND LOCKED"` / `"CARGO HATCH SECURED"`.

### Tests this breaks — fix them in the same change

`ChecklistSmoke`, `DriftSmoke`, `Phase4Smoke`, `MfdNavSmoke` and `AlignSmoke` all
call `set_cargo_hatch(...)` and assert immediately. They need `_wait(...)` over
`HATCH_TRAVEL_TIME` inserted, read **from the constant, never transcribed** — the
rule `ChecklistSmoke` already asserts (README:939). `DriftSmoke.gd:216` matches
the substring `"HATCH"` and survives the rewording as-is.

### HUD

Add a hatch-transit readout beside the gear's, reusing
`_draw_gear_indicator`'s idiom ([HUDOverlay.gd:259-272](scenes/ui/HUDOverlay.gd#L259)):
`CARGO HATCH IN TRANSIT %d%%`. Same for the SCOOP page's hatch button state.

---

## Stage 4 — Alerts that latch

**New:** `systems/AlertSystem.gd`, registered before `AudioSystem`.

Every warning except the low battery is re-evaluated per frame with no latch, so
a naive hookup would retrigger an alarm 60 times a second.
`GameState._announce_battery` ([GameState.gd:1009-1020](autoload/GameState.gd#L1009))
is the one place that gets this right — fire once on crossing, rearm above the
threshold. Generalise that.

A declared table of conditions, each with a predicate, a level, a clear
threshold and hysteresis:

```gdscript
signal alert_raised(id: String, level: String)
signal alert_cleared(id: String)
const LEVELS := ["WARNING", "CAUTION", "NOTE"]
```

The levels are **the handbook's own**, already declared as prose and colour at
[PilotManualContent.gd:50-51](scenes/displays/PilotManualContent.gd#L50) and
mandated by [CLAUDE.md](CLAUDE.md): WARNING = damage to the ship or salvage lost;
CAUTION = an interlock, a refusal, a limit; NOTE = clarification. Adopting them
in code makes the sound design agree with the printed manual instead of inventing
a third vocabulary alongside `Instrument.GOOD/WARN/BAD`.

Each predicate **calls the same function the HUD calls** —
`gear_locked_down()`, `ShipMotion.authority()`, `DockingSystem.status()` — so
this is a second reader, not a second copy of the logic.

Conditions to declare, all drawn from the existing inventory: battery low/flat,
LH2/LOX exhausted, gear overspeed ([DockingSystem.gd:687](systems/DockingSystem.gd#L687)),
drive unpowered, degraded assist ([HUDOverlay.gd:291](scenes/ui/HUDOverlay.gd#L291)),
structural risk past its threshold, alignment slip, proximity inside
`PROXIMITY_RANGE := 25.0`, hatch/gear unsafe for the current phase.

Also hook the genuinely edge-triggered ones directly:
`GameState.hull_impact` — whose comment at
[GameState.gd:58-61](autoload/GameState.gd#L58) *already names alarms as the
intended subscriber* — and `ship_contact`, whose `closing` magnitude scales the
impact sound.

### Tones

| Level | Sound |
| --- | --- |
| WARNING | Hard alternating 800/1000 Hz warble at ~4 Hz, repeating until cleared. Deliberately the only piercing thing in the mix — that is why it cuts through. |
| CAUTION | A single triple-chirp, softer. |
| NOTE | One soft chime. |
| Incoming call | A Selcal-style two-tone that precedes every radio transmission, so ATC always announces itself before speaking. |
| Our transmit | Mic click in, squelch tail out, on `SIDETONE`. |

Pulse rates come from the HUD's existing idiom — 1.5 Hz for the standard
threat pulse, 1.2 Hz hatch, 3.0 Hz align slip, 2 Hz urgent ATC — so what you hear
beats in time with what is flashing.

**No HUD change is needed for this stage.** The annunciator stack already shows
every one of these conditions; this adds the ear, not a new indicator.

---

## Stage 5 — Speech

**New:** `data/speech/lines.json`, `tools/build_speech.py`,
`systems/audio/Speech.gd` → `assets/generated/voice/*.ogg`.

### Three voices, three treatments

| Voice | Who | Bus | Treatment |
| --- | --- | --- | --- |
| **STATION** | ATC and HARBOR — someone else, on the radio | `RADIO` | 300–3400 Hz band, compressed, squelch tail, static bed |
| **SHIP** | OPS / SYSTEM / SALVAGE — the ship's automated annunciator | `CABIN` | Dry, close, no radio artifacts. Should sound synthetic; it is. |
| **PILOT** | us, transmitting | `SIDETONE` | Lightly band-limited, drier, low level, mic click either side — you hear yourself in the headset, not off the air |

### The catalogue

`data/speech/lines.json` is the single source of truth, read by **both** the
Python generator and the GDScript runtime (`JSON.parse_string`), so the two
cannot drift. Utterances carry `{}` slots:

```json
"atc.cleared_to_land": {
  "voice": "station",
  "say": "{callsign}, CLEARED TO LAND, BERTH {n}."
}
```

The generator renders each literal segment between slots as one clip, plus an
atomic bank: digits 0–9, the NATO alphabet, `POINT`, `HUNDRED`, `THOUSAND`, unit
words. At runtime `Speech.gd` expands the slots to token clips and plays
segment → slot → segment back to back.

**Names come from data, not from the catalogue.** The generator reads
`display_name` and `registry` out of [data/ships/*.tres](data/ships/) and the
station names out of [data/factions/*.tres](data/factions/), rendering a clip for
each. A second hull speaks its own callsign with no edit — the same rule
[TailPlate.gd](scenes/ui/TailPlate.gd) already follows for the builder's plate.

Numbers are spoken the way ATC speaks them — 25 → "TWO FIVE", 200 → "TWO
HUNDRED", 1.5 → "ONE POINT FIVE".

### The tail number

Full identity on first contact, abbreviated for the rest of the pattern:

```
FIRST    "SIERRA VICTOR KESTREL, LIMA UNIFORM FOUR FOUR SEVEN ONE KILO —
          MERIDIAN CO. CONTROL. SEQUENCING YOU INTO THE PATTERN FOR BERTH TWO."
AFTER    "SEVEN ONE KILO, CLEARED TO LAND, BERTH TWO."
OURS     "MERIDIAN CONTROL, SEVEN ONE KILO, REQUESTING CLEARANCE."
```

Both fields come from `kestrel.tres` (`display_name = "SV KESTREL"`,
`registry = "LU-4471-K"`). `Speech.gd` holds the "have we been addressed yet this
pattern" flag, reset when a pattern begins.

### Hook points

| What | Where | Voice |
| --- | --- | --- |
| Every ATC line | `GameState.atc_instruction` ([GameState.gd:96](autoload/GameState.gd#L96)) — emitted three times, consumed by nobody, and it carries `urgent` | STATION |
| Everything else | `GameState.comms_posted`, filtered by `source` | SHIP, or silent |
| Our transmissions | `request_clearance` ([DockingSystem.gd:562](systems/DockingSystem.gd#L562)), `request_auto_berth` ([:598](systems/DockingSystem.gd#L598)), `abort_approach` ([:625](systems/DockingSystem.gd#L625)), `_repeat_instruction` ([:1295](systems/DockingSystem.gd#L1295)) | PILOT |

`request_clearance` is already the one-button, four-way transmit verb (readback /
departure request / continue / clearance request), so the pilot's voice branches
the same four ways the code does.

Voice the roughly 30 utterances that matter — all ATC and HARBOR, plus gear,
hatch, drive, battery, propellant and cut annunciations. The remaining ~50 comms
lines stay unvoiced and get only the comms chirp, so the log still feels alive
without the ship narrating itself continuously. A queue prevents ATC talking over
itself; `urgent` jumps the queue.

**OGG here, not WAV** — the opposite of Stage 2, for the opposite reason. Nothing
loops, and ~120 clips at 32 kbps mono is roughly 700 KB against ~4 MB as WAV. An
8–16 kHz source rate is not a compromise for radio voice; it is what the band
actually is.

### Licensing

SAPI-rendered audio goes in `assets/generated/voice/`, with a `CREDITS.md` row
naming it as the folder to re-render before any commercial release — mirroring
how `assets/cc-by-nc/` is already documented as "the folder to empty out first".
The synthesised machinery in `assets/generated/sfx/` is ours outright and carries
no constraint. Because Stage 0 keeps the voice engine swappable, clearing that
flag later is one command.

---

## Stage 6 — A mixer the pilot can reach

Add a volume row per bus to the MFD **SETTINGS** page
([SettingsPanel.gd](scenes/ui/SettingsPanel.gd)), reusing `_add_row` and
`ButtonTheme.make_touch_button` — and `TouchSlider` where a continuous control
reads better than buttons. Persist alongside the existing display/input config
under `user://`.

A simpit runs unattended and at odd hours; a master mute that is reachable by
touch without a keyboard is not optional.

---

## Documentation — required, per CLAUDE.md

| File | What changes |
| --- | --- |
| [README.md](README.md) | New **Sound** section: the two-path rule, the three voices, what each alert level means. Update the SETTINGS row in **The four displays** (it now lists volume). Update **The Main flight HUD** for the hatch-transit readout. |
| [PilotManualContent.gd](scenes/displays/PilotManualContent.gd) | New chapter on the annunciators and what the ship tells you aloud. `HATCH_TRAVEL_TIME` quoted in the cargo-hatch chapter, exactly as `GEAR_TRAVEL_TIME` is. Flat, declarative, operator-addressed — no reference to the simulation. |
| [TerminalProceduresContent.gd](scenes/displays/TerminalProceduresContent.gd) | How the harbour addresses you: full identity on first contact, abbreviated after. **This is a harbour convention, so it belongs here and not in the handbook** — the division is authorship. |
| [PilotManualContent.gd:92](scenes/displays/PilotManualContent.gd#L92) | Currently says "The name is the vessel's callsign; a harbour will address her by it." Now that the registry is spoken too, that line is **false** and must be fixed, not appended to. |
| [CREDITS.md](CREDITS.md) | Two new folder rows for `assets/generated/sfx/` and `assets/generated/voice/`, with the constraint on the latter. |
| [CLAUDE.md](CLAUDE.md) | Add the new tool scenes to the sync table, and a row routing audio constants to the chapter that owns them. |

---

## Verification

**New smoke test:** `tools/AudioSmoke.gd` + `.tscn`, following the house harness
(`Engine.time_scale = 10.0`, silence `InputRouter` and its children, `_check()`,
`_wait()`, exit 0/1) — the pattern in
[tools/FlightSmoke.gd](tools/FlightSmoke.gd). Headless Godot uses a dummy audio
driver, so `play()` works and is silent; every assertion below is state, not
sound.

1. Every clip named by `SoundBank` resolves to a real file — catches a rename.
2. Every utterance in `lines.json` has all its segment clips present, and every
   `{slot}` is fillable. This is the `PilotManualSmoke` trick applied to speech.
3. Number expansion: `25 → ["TWO","FIVE"]`, `200 → ["TWO","HUNDRED"]`,
   `1.5 → ["ONE","POINT","FIVE"]`.
4. Callsign: first contact spells the registry, subsequent calls abbreviate, and
   the flag resets when a new pattern begins.
5. Alert latching: drive a condition across its threshold repeatedly and assert
   **exactly one** raise, then one clear on recross.
6. Hatch travel: `set_cargo_hatch(true)` → assert `not hatch_open_locked()`
   immediately → `_wait(HATCH_TRAVEL_TIME)` → assert it. Read the wait from the
   constant.
7. Every bus named by `SoundBank` exists in the loaded layout.

**Existing tests that must still pass**, and which need the hatch waits inserted:

```
godot --headless res://tools/ChecklistSmoke.tscn
godot --headless res://tools/DriftSmoke.tscn
godot --headless res://tools/Phase4Smoke.tscn
godot --headless res://tools/MfdNavSmoke.tscn
godot --headless res://tools/AlignSmoke.tscn
godot --headless res://tools/DockSmoke.tscn
godot --headless res://tools/PilotManualSmoke.tscn
godot --headless res://tools/AudioSmoke.tscn
```

**By ear** — the part no smoke test covers. Run the game and confirm:

- Ventilation is audible at boot, and **cutting the LIFE channel takes the room
  to silence** while a gear clunk still comes through.
- Gear down gives three staggered clunks, not one.
- Opening the cargo door gasps and dies; closing it hisses into existence.
- The cutter charges, snaps, crackles, and the coolant pump runs on after
  shutdown.
- ATC opens with the full registry, then drops to "SEVEN ONE KILO".
- Pressing the transmit key speaks in our own voice, dry, with a mic click.
- A go-around raises the WARNING warble, and it stops when the condition clears —
  once, not sixty times a second.
