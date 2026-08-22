# Salvager — contributor guide

## Keep `README.md` in sync with player-facing changes

`README.md` is the source of truth for **controls, displays, the flight HUD, and
the gameplay loop**. Whenever a change alters any of these, update `README.md` in
the *same* change — a control the player can press or a HUD marking they can see
is not "done" until the README describes it. Map the code you touched to the
section that documents it:

| You changed… | Update this README section |
| --- | --- |
| HOTAS / keyboard / switch-panel bindings (`autoload/InputRouter.gd` `PROFILES`, `project.godot` `[input]`) | The matching **Controls** table (X55 / X52 / Switch Panel / Keyboard fallback) |
| Main-display HUD indicators or readouts (`scenes/ui/HUDOverlay.gd`) | **The Main flight HUD** section, and the screenshot caption / alt text |
| Displays, windows, or simpit/multi-display behaviour | **The four displays** / **Simpit / multi-display setup** |
| Gameplay loop, power channels, salvage/market rules | **Core gameplay loop** |
| A new `tools/` scene | The **Handy tool scenes** table |
| A chapter in either ship document | Nothing by hand — but `tools/build_manuals.ps1` reprints both to `build/manuals/` (gitignored), which is the quickest way to proof new prose on paper |

## Keep the ship's two documents in sync too

The ship carries two documents, both rendered by `scenes/displays/ManualViewer.gd`
and both opened from the title card. They are separate publications because they
have separate publishers, and that decides which one a fact goes in:

| Document | Publisher | Holds |
| --- | --- | --- |
| `scenes/displays/PilotManualContent.gd` | The builder | The ship, her systems and limits; how a derelict hull behaves under the torch; the departure / arrival / cutting / collecting checklists |
| `scenes/displays/TerminalProceduresContent.gd` | Harbour, claim office, commercial agent | The approach lane and plate, speed and clearance rules, charges, the berth and its assessment, arrival and departure procedures, claim conditions, prices, the system chart |

Both are **second in-tree copies of facts the README also states**, and every
figure in them is quoted from code, so they drift the moment a constant or a gate
moves.

| You changed… | Also update |
| --- | --- |
| A quoted constant (`data/ships/kestrel.tres`, a `systems/*.gd` `const`, `GameState` limits or boot state) | The chapter that quotes the number, in whichever document owns it |
| A ship interlock or its comms line (`request_cut`, the scoop gates, the gear/hatch interlocks) | The matching handbook chapter or checklist step, including the failure text it quotes |
| A `DockingSystem` rule, charge, limit or ATC line | The **terminal procedures** — never the handbook |
| A battery, tank, burn-rate or drive-stage constant (`GameState.BATTERY_*`, `ShipDefinition` `lh2_*` / `lox_*` / `thrust_*` / `drive_start_time`) | The handbook chapter that quotes it — **Electrical & power** or **Drive & propellant** |
| A propellant price (`MarketSystem.LH2_PRICE_PER_UNIT`, `LOX_PRICE_PER_UNIT`) | The **terminal procedures**, under the schedule of prices — never the handbook |
| A `ThreatSystem` or `MarketSystem` rule (rival, patrol, prices, standing) | The **terminal procedures**, under LOCAL NOTICES |
| An input action name | Nothing by hand — but run `PilotManualSmoke`, which fails on a placeholder naming an action that no longer exists |
| A new system, MFD page, or HUD marking | The relevant handbook chapter (and add one if none fits) |

Controls are *not* on that list: both documents resolve them live through
`scenes/ui/BindingLabel.gd`, so rebinding needs no edit.

If you cannot point at the constant, do not write the number.

**The division is authorship, not subject.** The builder can state what the legs
will accept at touchdown, and how a loaded frame behaves when you cut it — a
tool's manual describes what the tool does to the work. It cannot state where a
harbour will let you set down, what it charges, or how a rival will behave. So
marker names, ring and corridor sizes and speed limits appear only in the terminal
procedures; airframe figures appear only in the handbook; and an arrival is flown
from both. `PilotManualSmoke` asserts both directions of that, so re-conflating
them fails the build rather than the review.

Each terminal chapter opens with the office that issued it. **That masthead is the
attribution** — do not add a disclaimer saying what a chapter is not.

**Tone — it is a handbook, not a guide.** Write it the way a wartime flight
manual or a car's owner's manual is written: flat, declarative, addressed to the
operator. State limits and procedures; don't sell them, rank them, or describe
how they feel to fly. Nothing refers to the simulation, to scoring, or to the
player as a player — where a system is fitted but has no effect, say what it does
and does not do in operational terms ("it has no bearing on the performance of
any other system"), never in terms of what is or isn't implemented. Hazards use
the three standard callouts: **WARNING** (damage to the ship, or salvage lost),
**CAUTION** (an interlock, a refusal, a limit), **NOTE** (clarification).

When a change makes an existing README statement **false**, fix that line — don't
just append. (Example: adding throttle-POV strafe made the old "strafe is
keyboard-only" note wrong; the fix was to reword that note, not add a second one.)

If a change is purely internal (refactor, tests, collision math) with no effect
on what the player presses, sees, or reads, the README needs no change.
