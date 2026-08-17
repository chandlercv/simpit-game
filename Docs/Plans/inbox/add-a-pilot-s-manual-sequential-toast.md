# Pilot's manual, linked from the title card

## Context

Salvager has no in-game reference. Everything a pilot needs to know — that the
cutter boots at **0.0** power, that the approach autopilot won't arm past 40%
throttle, that the gear takes 3 s to travel so "gear down by DELTA" is a call you
act on early — lives in `README.md`, i.e. outside the game, on a machine that may
not be the simpit. The launch screen is the one place a player already sits and
reads before flying, and it currently offers three things (scenario, displays,
controls) and no answer to "how do I fly this?".

This adds a **PILOT'S MANUAL** screen opened from the title card: a chapter-based
reference covering every system of the SV Kestrel, plus the four procedural
checklists — **departure, arrival, cutting, collecting** — written from the gates
the code actually enforces, with the **live** control binding for each step
rendered inline so the checklist stays true after a remap.

### Base branch — do this first

The working tree is on `pilot-manual` @ `73f1fd8`, which is **behind
`origin/main` @ `4644950`**. The flown docking pattern (`systems/DockingSystem.gd`,
ATC, the ALPHA→DELTA lane, landing gear, the flown departure) landed in between,
and *that feature is what the departure and arrival checklists are about*. Written
on the current base those two checklists would document a DOCK button and a
3-second `await`, and would be wrong on merge.

```
git fetch origin && git rebase origin/main    # note: local `main` is stale at 73f1fd8
```

Everything below assumes the rebased tree. Verify `systems/DockingSystem.gd` and
`scenes/ui/DockPanel.gd` exist before starting.

---

## Approach

Three new files plus wiring. All UI here is **code-built, not `.tscn`** — that is
the house style for this family (`TitleCard.gd`, `ControlsSetup.gd`,
`DisplaySetup.gd` are all `SomeScript.new()`).

### 1. `scenes/ui/BindingLabel.gd` — live binding resolver

A `RefCounted` with statics, same shape as the existing `scenes/ui/ButtonTheme.gd`.

`BindingLabel.for_action(action: String) -> String` returns e.g.
`"Trigger · X55 Rhino / C"`, or `"unbound"`.

Source of truth is **`InputMap.action_get_events(action)`** — `InputRouter._bind_hotas()`
injects every effective binding (keyboard keys, joypad buttons, joypad axes) into
the InputMap via `_inject()`, so the InputMap *is* the resolved mapping and needs
no profile re-parsing. Format per event type:

- `InputEventKey` → `OS.get_keycode_string(physical_keycode)` (as `ControlsSetup._key_name` does)
- `InputEventJoypadButton` → `"Button %d · %s" % [button_index, Input.get_joy_name(device)]`
- `InputEventJoypadMotion` → `"Axis %d · %s"`

Two bindings that are **not** in the InputMap and need their own accessors:

- **Throttle** — `InputRouter._throttle_device` / `_throttle_spec`. Add a small
  public `InputRouter.throttle_binding() -> Dictionary` (`{}` when unbound).
- **Raw-HID axes** (X52 nub) — `InputRouter._hid_axis_bindings`. Add
  `InputRouter.hid_axis_bindings() -> Array`. The X55 POV glance is raw HID with no
  binding at all; the manual states that as prose, not as a resolved label.

**Switch-panel switches** never reach the InputMap either (`SwitchPanelBridge._route_intent`
calls intents by switch name). Expose `BindingLabel.for_switch(name)` returning the
panel legend (`"COWL switch"`, `"DE-ICE switch"`, `"GEAR lever"`), driven off
`GameState.CHANNEL_SWITCHES` where it applies.

### 2. `scenes/displays/PilotManualContent.gd` — the content, as data

A `RefCounted` holding one `const CHAPTERS: Array[Dictionary]`, each
`{"id", "title", "body"}` with `body` as BBCode. Split from the UI script for the
same reason `GameState.SCENARIOS` is a catalog: adding a chapter is a list entry,
not a branch.

Bodies carry `{{act:ops_cut}}` / `{{sw:COWL}}` placeholders, substituted at build
time through `BindingLabel`. This is what makes the checklists survive a remap,
and the smoke test below turns a typo'd or renamed action into a build failure.

**Chapters — systems** (numbers below are quoted from code; do not invent any):

| Chapter | Must cover |
| --- | --- |
| The SV Kestrel | `data/ships/kestrel.tres`: `manual_accel 4.0` m/s² at THRUST 1.0, `rotation_rate_deg 45`, `max_speed 25`, `secondary_thrust_fraction` **defaults to 0.5** (strafe/vertical/reverse), hold 40 t / 30 m³, `approach_speed 8.0`, `cut_rate 0.35`. **No fuel or reaction mass exists** — say nothing about either. |
| Flight & attitude | Rate-controlled attitude, no inertia and **no SAS/attitude hold**. Newtonian translation, flight-assist bleed `exp(-0.35·Δt)` that applies **only when the whole thrust vector is released**. Throttle command laws: SPEED (default, cruise-control) vs THRUST (legacy), `throttle_cmd_toggle` ships unbound. Reverse capped at 50%. |
| Electrical & power | Four channels 0..1; **boot state THRUST 0.8 / CUTTER 0.0 / SENSORS 0.6 / LIFE 1.0** — the cutter-starts-dead fact belongs here *and* in the cutting checklist. Switch high 0.8 / low 0.2, LIFE high 1.0. MASTER BAT / MASTER ALT overrides and `power_locked()`. Budget 2.5 is an **advisory readout only — nothing enforces it**. Passive signature 1.0 / 0.5 / 0.25. Note plainly that LIFE has no consumer yet. |
| Sensors & scanning | Scope ranges PASSIVE 600 / ACTIVE 250 / STRUCT 250; PASSIVE-vs-ACTIVE is scope range and sweep rate only. Structural scan gates: STRUCT mode, ≤ 300 u, SENSORS ≥ 0.1, `delta·power/5.0` (5 s at full, 50 s at 0.1). |
| The cutter | Gate order from `SalvageSystem.request_cut`. Alignment: lock radius 0.18, slip radius 0.55, fill 0.7/s, bleed 0.9/s, slip 0.6/s. Quality drives rate `lerp(0.45,1.0,q)`, risk `lerp(1.6,0.6,q)`, yield `lerp(0.55,1.0,q)`. Beam from the right wing. **`CUT_RANGE = 14.0` is dead code — the real gate is `MATCHED`**; do not quote 14 u as a range. No cutter heat or wear exists. |
| Cargo hatch & scoop | Four simultaneous gates: range < 4.0 m *surface-to-surface*, rel speed < 1.5 m/s, cone ≤ 35°, held 1.5 s (bleeds 1.5× faster). Hold 40 t / 30 m³, jettison is destructive. The **three-way interlock**: open to scoop, blocks the cutter, blocks dock and undock. |
| Structural risk | Baseline ratchet `load·0.09`, spike `pow(load,1.5)·0.3+0.02`, collapse floor 0.55, chance `(risk−0.55)·0.06`/s, collapse damage inside 25 m, every uncut member lost. |
| Landing gear | Travel `GEAR_TRAVEL_TIME 3.0` s, rated `GEAR_LIMIT_SPEED 18.0` m/s (`GEAR_STRESS_PER_S 0.02` hull wear over it), interlocks the cutter, `GEAR_HEIGHT 1.6`. |
| The station & ATC | `DockingSystem.GATES` table (ALPHA/BRAVO/CHARLIE/DELTA with ring and corridor radii), `PAD_LOCAL`, `PAD_RADIUS 7.0`. Speeds 22 / 12 / 6 / 3 with `SPEED_GRACE 2.5`, `LANE_GRACE 1.2`. `CLEARANCE_MIN_HOLD 5.0`, `LANE_CONFLICT_RANGE 22.0`, `SEPARATION_MARGIN 2.5`. Contact is **billed not waved off** (`DAMAGES_CALL_OUT 100` + `DAMAGES_PER_DAMAGE 800`, `CONTACT_GRACE 5.0`). Auto-berth: `AUTO_BERTH_FEE 300`, `REP_AUTO_BERTH 0.03`, refused on FINAL. Traffic: tug, shuttle, ore barge. |
| Touchdown | `FIRM_RATE 1.5` / `HARD_RATE 3.0` / `CRASH_RATE 5.0`, `TILT_LIMIT_DEG 20`, `TOUCHDOWN_DRIFT 2.0`, `DECK_HALF_EXTENT 10.8`. Score weights sink 50 / accuracy 30 / attitude 20. `REP_PER_LANDING 0.04`, wave-off bleed capped at `REP_WAVE_OFF_CAP 0.12` per visit. |
| Hull & collision | Six sections and their **pre-worn** start values (BOW .96 / PORT .88 / STBD .92 / CORE 1.0 / AFT .9 / DRIVE .85). Impact floor 1.5 m/s, 0.03 integrity per m/s over, cap 0.6, restitution 0.3. Rear impacts tag DRIVE. **There is no repair and no destruction** — state both. |
| Navigation & contacts | The scope is real; the **star chart is a static schematic whose own-ship marker does not move**. Contact list, lock/cycle. No waypoints, no nav computer, no cruise autopilot. |
| Market & standing | Goods table with base prices and mass/volume, three factions and biases, price formula spread 0.85×–1.15× by rep, `REP_PER_SALE 0.03`, whole-hold sale only, no buying, 500 CR start. |
| Threats | Rival spawn 45–90 s, work range 20 m, strips a member every 25 s, and **takes adrift pieces including yours**. Patrol window 240–360 s, enforce range `60 × passive_signature`, fine 200 CR + 0.12 rep, once per run. |
| Displays & HUD legend | The four roles and the MFD page set incl. **DOCK**; the HUD marks — nose reticle, drift brackets, VEL/HDG/EL, cut-target diamond and `MATCHED — FIRE TO ALIGN`, align crosshair, scoop ring and its cue ladder, hatch and gear indicators, ATC line, landing ladder. Camera **BELLY** view is the one you land on. |

**Chapters — the four checklists.** Each is an ordered list of `ACTION … CONDITION`
lines in the flight-checklist idiom, with the resolved binding inline and the
failure text the game will actually post when a gate is missed (e.g.
`"APPROACH INHIBITED — THROTTLE PAST 40%, EASE BACK TO ARM"`), so a stuck pilot can
match what they see to a line.

1. **DEPARTURE** — two segments. *Before departure:* masters ON (power can't be
   edited while either is off), channel switches set, hatch **SECURED**, hold
   checked. *Outbound pattern:* `market_depart` → `DEPART_HOLD` on the pad → await
   departure clearance (`dock_request`) → `DEPARTING`, fly **DELTA → CHARLIE →
   BRAVO → ALPHA** under the same corridor and speed rules → **gear stays down
   until the berth bay is behind you**, stow it before ATC releases you → jump to
   the claim. Violations outbound are **reprimands, not go-arounds**. Note the
   cold-start case: the same systems segment applies on the first launch.
2. **ARRIVAL** — hatch secured and cutter idle *before* `market_dock` (else
   `"DEPARTURE HELD — CUTTER ACTIVE"` / `"— SECURE CARGO HATCH FIRST"`) → transit
   burn → `INBOUND`, fly to ALPHA and **stop under 3 m/s** → `HOLD`, wait out the
   sequencing and the traffic, request/accept clearance → `CLEARED`, BRAVO →
   CHARLIE → DELTA through each ring, in the corridor, under 12 → **gear down
   before DELTA** (3 s of travel, so select it early) → `FINAL`, funnel descent
   under 6 → land level, inside the markings, under the sink rate → sell. Include
   the auto-berth out and what it costs.
3. **CUTTING** — SENSORS powered → STRUCT mode → inside 300 u → scan complete →
   **select the member first** → throttle under 40% → arm approach → wait for
   `MATCHED` (the autopilot translates only; you aim) → **CUTTER ≥ 0.2** (it boots
   at 0.0) → hatch secured → gear stowed → fire to open alignment → track the seam
   → commit → watch risk. Call out that re-selecting a target drops the match.
4. **COLLECTING** — cutter idle → open the hatch (aborts a live align/cut) →
   MFD auto-pages to SCOOP → close inside 4 m, null relative speed under 1.5 m/s,
   hold inside the 35° cone → 1.5 s to stow → check hold limits, jettison to make
   room → **secure the hatch** before cutting or docking. Warn that pieces are
   free-for-all and that anything adrift when you depart is deleted.

### 3. `scenes/displays/PilotManual.gd` — the screen

`extends Control`, `class_name PilotManual`, `signal closed`. Structure mirrors
`ControlsSetup.gd` closely enough to be obviously the same family:

```
PilotManual (Control)
├─ ColorRect                       Color(0.02, 0.03, 0.05, 0.98)
└─ MarginContainer (40 all sides)
   └─ VBoxContainer (sep 12)
      ├─ Label "PILOT'S MANUAL — SV KESTREL"   34px
      ├─ Label  hint                            16px  Color(0.65,0.72,0.82)
      ├─ HBoxContainer  SIZE_EXPAND_FILL vertical
      │   ├─ VBoxContainer   chapter list, ~260 wide, one button per CHAPTERS entry
      │   └─ ScrollContainer SIZE_EXPAND_FILL both, horizontal SCROLL_MODE_DISABLED
      │       └─ RichTextLabel  bbcode_enabled, fit_content, autowrap
      └─ HBoxContainer  [CLOSE 160×48]
```

Reuse and gotchas, all of them already documented in the files being copied:

- **`ButtonTheme.make_button(SETUP_ACCENT, 12)`** for CLOSE, and
  **`ButtonTheme.make_toggle_stylebox`** for the chapter buttons — the same
  active/inactive treatment `TitleCard._style_scenario_button` uses. `make_button`
  returns `FOCUS_NONE`; set `focus_mode = FOCUS_ALL` on anything that must be
  keyboard-reachable, exactly as TitleCard does.
- **`_fit_to_viewport()`** — `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`
  *plus* `size = get_viewport().get_visible_rect().size`, re-run on
  `get_viewport().size_changed`. Anchors alone collapse the backdrop to the
  top-left; both `TitleCard` and `ControlsSetup` carry a comment about that bug.
- **Scroll sizing** — give the ScrollContainer expanding height rather than letting
  it size to content (`ControlsSetup` documents the zero-height collapse).
- **`RichTextLabel` font sizes** are `normal_font_size` / `bold_font_size`
  overrides, not `font_size` — see `scenes/ui/CommsLog.gd`, the project's only
  other BBCode consumer.
- **Esc must be swallowed**: `_input` intercepts `KEY_ESCAPE`, calls
  `get_viewport().set_input_as_handled()` and emits `closed`. Without this,
  `InputRouter._unhandled_input` quits the game.

Colour vocabulary, matching the rest of the family: backdrop `(0.02,0.03,0.05)`,
chapter headers `(0.4,0.8,1.0)`, body `(0.65,0.72,0.82)`, resolved bindings in the
green accent `(0.35,0.95,0.55)`, warnings/interlocks amber `(0.95,0.75,0.35)`.

### 4. Wiring into `scenes/displays/TitleCard.gd`

- A third row in the `_add_setup_rows` grid, keeping the `[button][status]` shape:
  `PILOT'S MANUAL` (`_make_setup_button`, SETUP_ACCENT) with a static status line
  naming what's inside (`"ship systems reference · departure / arrival / cutting /
  collecting checklists"`). No hotkey suffix — unlike F6/F7 the manual is
  title-card-only.
- `_open_manual()` builds a `CanvasLayer` at **layer 18** with
  `process_mode = PROCESS_MODE_ALWAYS` (required — the card holds `get_tree().paused`
  and a paused Control takes no input), **parented to the TitleCard node** so it is
  freed with the card at LAUNCH rather than orphaned on the window. Idempotent, the
  way `InputRouter.open_controls_setup` is.
- Layer 18 is deliberate: above the title card (15) so it covers it, **below** the
  display chooser (20) and the remapper (25) so a global F6/F7 press still draws
  over the manual and reveals it again on close.
- `closed` → free the layer, `_launch_button.grab_focus()`.
- `suspend()` / `resume()` carry the manual layer's `visible` with them, so the one
  path that hides the card (F6 → chooser) can't leave the manual floating over it.

### 5. `tools/PilotManualSmoke.tscn` + `.gd`

Headless, in the `TitleCardSmoke.gd` house style (`_check(condition, label)`,
print-and-quit-with-code). The valuable checks:

- every chapter has non-empty `id` / `title` / `body`, and ids are unique;
- the four required checklist chapters are present by id;
- **every `{{act:…}}` placeholder names an action in `InputMap.get_actions()`** —
  this is the check that makes a renamed action fail the build instead of silently
  rotting the manual;
- `BindingLabel.for_action` returns the expected key for a shipped keyboard default
  (e.g. `ops_cut` → `C`) and a defined "unbound" string for an action with no
  binding;
- no `{{…}}` survives substitution in any rendered chapter;
- the screen builds, selecting a chapter swaps the body text, and CLOSE emits `closed`.

Add two card-side assertions to the existing `tools/TitleCardSmoke.gd` (it already
builds a card): the manual button exists, and opening then closing it returns focus
to LAUNCH.

### 6. Docs — required by `CLAUDE.md`

- `README.md` **The launch screen** table: a `PILOT'S MANUAL` row, plus a short
  paragraph naming the four checklists.
- `README.md` **Handy tool scenes** table: a `PilotManualSmoke.tscn` row.
- `CLAUDE.md` mapping table: a new row — *"You changed… a gameplay system, a
  quoted constant, or a procedure gate → also update
  `scenes/displays/PilotManualContent.gd`."* The manual is a second in-tree copy of
  facts the README also owns; without this row it will drift, and drift is exactly
  what that table exists to prevent.

---

## Accuracy constraints

The manual must not describe things that do not exist. Verified absent in this
codebase: **fuel / reaction mass / refuelling, heat or thermal management of any
kind, cutter heat or wear, shields, repair at any price, hull destruction or
game-over, life-support consumption, waypoints, a nav computer, a cruise autopilot,
docking fees, buying goods, per-item sales, and any magnet / tractor / collector
hardware** (the scoop is "fly the hatch onto the piece").

Present but inert, so phrase carefully or omit: the **LIFE** power channel (no
consumer), the **2.5 power budget** (a warning colour, not a limit), the **star
chart** (static, marker doesn't track), **PASSIVE vs ACTIVE** sensor modes (scope
cosmetics only), `SalvageSystem.CUT_RANGE = 14.0` (unused at runtime), and the
switch panel's PANEL / BEACON / STROBE / TAXI / magneto (decoded and logged only —
but **GEAR is live** post-rebase).

---

## Files

| File | Change |
| --- | --- |
| `scenes/ui/BindingLabel.gd` | **new** — static binding resolver over `InputMap` |
| `scenes/displays/PilotManualContent.gd` | **new** — `CHAPTERS` catalog (systems + 4 checklists) |
| `scenes/displays/PilotManual.gd` | **new** — the screen |
| `tools/PilotManualSmoke.gd` / `.tscn` | **new** — headless checks |
| `scenes/displays/TitleCard.gd` | manual row, layer-18 host, suspend/resume carry |
| `autoload/InputRouter.gd` | `throttle_binding()` / `hid_axis_bindings()` accessors |
| `tools/TitleCardSmoke.gd` | two manual-button assertions |
| `README.md`, `CLAUDE.md` | doc sync per the table above |

## Verification

```bash
git fetch origin && git rebase origin/main     # step 0 — do this first

godot --headless res://tools/PilotManualSmoke.tscn   # new
godot --headless res://tools/TitleCardSmoke.tscn     # card wiring still sound
godot --headless res://tools/DockSmoke.tscn          # facts the checklists quote
godot --headless res://tools/DriftSmoke.tscn
godot --headless res://tools/AlignSmoke.tscn
godot --headless res://tools/Phase4Smoke.tscn
godot --headless res://tools/DisplayLoadCheck.tscn   # nothing errors on load
```

Then interactively: launch to the title card, open **PILOT'S MANUAL**, page every
chapter, confirm no `{{…}}` placeholder is visible and the bindings shown match the
rig; press **F7**, confirm the remapper draws *over* the manual and closing it
reveals the manual again; rebind `ops_cut`, reopen, confirm the cutting checklist
shows the new binding; press **Esc** and confirm it closes the manual rather than
quitting the game; **CLOSE** and confirm LAUNCH has focus; **LAUNCH** and confirm
the manual layer is gone.

`tools/ScreenshotCheck.tscn ++ <out.png> title` can capture the card for a README
image if the launch-screen shot is refreshed.
