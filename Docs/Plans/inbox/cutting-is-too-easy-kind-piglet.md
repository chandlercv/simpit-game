# Pre-cut alignment mini-game

## Context

Cutting is currently a fire-and-forget progress bar. Once the approach autopilot
reaches `MATCHED` and the CUTTER channel has power, `request_cut()` just sets
`cutting_id`, and `_update_cut()` fills `cut_progress` at a fixed rate with **no
player action and no execution-time failure mode** (`systems/SalvageSystem.gd`
`_update_cut`, lines 443‑457). All the difficulty is front-loaded (scan, read the
structure, pick a safe member, allocate power); the act of cutting itself is a
timer a competent player can't fail.

A second, related weakness: the approach autopilot parks off the wreck's
**nearest surface / centre** (`_update_approach`, lines 355‑390), not off the
member you picked. So one `MATCHED` covers the whole frame — you can cut every
member in turn without ever moving. There's no sense of positioning the ship on a
particular part of the hull.

This change has two halves:

1. **Per-member approach (reposition per target).** The autopilot flies to and
   parks off the **selected member**, and `MATCHED` is bound to that member.
   Selecting a different target drops you out of `MATCHED` — you must re-arm the
   approach to reposition. Cutting several members becomes a fly-to / align / cut
   loop, not a one-and-done park.
2. **Pre-cut alignment skill check.** Once `MATCHED` on a member, before the torch
   bites, the player aims the cutting head onto a drifting seam point with a
   **2-axis crosshair** and holds it to build a lock. Alignment `quality` modulates
   the cut — a clean lock cuts faster, spikes structural risk less, and preserves
   more yield; letting the torch slip aborts the cut outright. It surfaces as new
   **HUD** markings over the hull-camera feed (the seam is in view) and a dedicated
   **MFD ALIGN page** as the precision instrument.

## Design decisions (confirmed with user)

- **Core skill:** 2-axis crosshair — steer a reticle (`✛`) onto a drifting target
  seam point (`⊕`), hold it inside tolerance to build a lock.
- **Stakes (all four):** alignment `quality` (0..1) scales **cut speed**, **risk
  spike**, and **salvage yield**; a **hard-fail** (torch slip) aborts before the
  cut starts.
- **Input:** reuse the existing flight **pitch/yaw** axes to aim (no new bindings;
  works out-of-box on the X55 stick and keyboard). This is the one subtlety —
  see below.

### The autopilot-disengage constraint

`SalvageSystem.set_manual_flight()` (lines 133‑145) aborts the cut and drops the
approach autopilot to `HOLDING` on **any** real stick/rotation input while
`approach_state != "HOLDING"`. Alignment happens *while MATCHED*, so we cannot
feed pitch/yaw straight through. The fix lives in `InputRouter._process()`: while
`GameState.align_state == "ALIGNING"`, route pitch/yaw into
`SalvageSystem.set_align_input()` **and zero those two components** before the
`set_manual_flight()` call, so aiming the torch doesn't break the match. Strafe /
throttle / roll still disengage — grabbing those is a real bid to fly away and
cancels alignment, which is the desired "bail out" path.

## Per-member approach (reposition per target)

**Member world positions already exist** — `Wreck.gd` bakes each member's
world-space convex hull + centroid + radius into `_member_bodies` (keyed by node
name) and registers them as `is_wreck` obstacles (`_bake_member_hulls`,
`_bake_hull`, lines 87‑119). They just aren't reachable from `SalvageSystem`.

- **`scenes/world/Wreck.gd`** — write each baked body's `center`/`radius` onto the
  matching member dict in the graph. Best spot is `_apply_member()` (68‑83), which
  already looks up `_member_bodies[node_name]` and runs on bake, `site_reset`, and
  member-cut — so the graph carries `member["center"]` / `member["radius"]` for
  every intact member, refreshed after `reset_site()` rebuilds the members array.
  Headless runs (no 3D scene) leave these unset → the autopilot falls back to the
  wreck centre, exactly as the surface-distance path does today.

- **`GameState.gd`** — add `var matched_member_id: int = -1` (which member the
  current `MATCHED` belongs to; reuse the existing `approach_changed` signal, no
  new one needed). Members already carry `center`/`radius` via the write above.

- **`SalvageSystem.gd`:**
  - **`toggle_approach()`** (148‑163): require a selected member to arm — refuse
    with a comms line ("APPROACH INHIBITED — SELECT A CUT TARGET FIRST") when
    `selected_member_id == -1`, since the approach now needs a destination.
  - **`_update_approach()`** (355‑390): aim at the selected member's `center`
    (fallback: `wreck["position"]`) instead of the frame surface/centre. Park at
    `member_radius + _ship_radius() + STANDOFF_GAP`; keep the same proportional
    braking + `MATCH_SLACK` / speed-gate to reach `MATCHED`. Obstruction handling
    (`abort_approach_on_collision`) is unchanged, so flying into another member on
    the way still hands back to manual.
  - **`_set_approach("MATCHED")`**: record `matched_member_id = selected_member_id`;
    clear it (`-1`) on any transition to `HOLDING` / `APPROACHING`.
  - **`select_member()` / `cycle_member()`** (99‑127): if `approach_state != "HOLDING"`
    and the pick changes, tear down the match — `_abort_align()`, `_abort_cut()`,
    `_set_approach("HOLDING")`, and post "REPOSITION REQUIRED — RE-ARM APPROACH FOR
    <member>". This is the reposition rule: a new target means flying there again.
  - **`request_cut()`** already gates on `MATCHED`; because selection now breaks the
    match, the matched member is always the selected one, so no extra check needed.

This reorders the gameplay loop: **pick the target first, then approach to it**
(today approach happens before target selection). The README loop is updated to
match (see below).

## State model (`autoload/GameState.gd`)

Follow the existing enum-string + signal + owned-dict pattern (mirrors
`APPROACH_STATES` / `wreck`). Add:

- `signal align_changed(state: String)`
- `const ALIGN_STATES: Array[String] = ["IDLE", "ALIGNING"]` (cutting resumes the
  existing `cutting_id` path once aligned, so no third persistent state needed)
- `var align_state: String = "IDLE"`
- `var align: Dictionary = {}` — owned/mutated by `SalvageSystem`, shape:
  `{ "reticle": Vector2, "target": Vector2, "lock": float 0..1,
     "slip": float 0..1, "quality": float 0..1 }` (all replication-friendly types)

`wreck` gains one field so the completed cut can read the captured score:
`"align_quality": float` (set at commit, default 1.0 for rival/collapse cuts that
don't align).

## Core logic (`systems/SalvageSystem.gd`)

New tuning consts near the existing cut/approach block:

- `ALIGN_LOCK_RADIUS := 0.18` — reticle-to-target distance that counts as on-seam.
- `ALIGN_SLIP_RADIUS := 0.55` — beyond this the slip meter grows.
- `ALIGN_LOCK_RATE := 0.7` / `ALIGN_LOCK_BLEED := 0.9` — lock build / decay per s.
- `ALIGN_SLIP_RATE := 0.6` / `ALIGN_SLIP_RECOVER := 0.4` — slip grow / recover per s.
- `ALIGN_RETICLE_RATE := 1.4` — reticle travel per second at full axis.
- `ALIGN_DRIFT_BASE := 0.12`, `ALIGN_DRIFT_LOAD := 0.35` — target drift amplitude;
  scales with member `load` so a load-bearing spar wanders more than a cosmetic
  panel (reinforces the existing read-the-wreck choice).
- `MEMBER_STANDOFF_GAP := STANDOFF_GAP` — reuse the existing 2.0 m clearance for
  the per-member park point (member radius + ship reach + this).
- Quality → outcome mappings: `ALIGN_RATE_MIN := 0.45` (cut-speed multiplier floor),
  `ALIGN_RISK_MIN := 0.6` / `ALIGN_RISK_MAX := 1.6` (spike multiplier band),
  `ALIGN_YIELD_MIN := 0.55` (yield multiplier floor), `ALIGN_BOTCH_RISK := 0.05`
  (risk nudge on a slip-out).

Changes:

1. **`request_cut()`** (173‑190): keep all current guards, but instead of starting
   the cut, **enter alignment** — set `GameState.align_state = "ALIGNING"`, init the
   `align` dict (reticle centered, target seeded), `align_changed.emit("ALIGNING")`,
   post a comms line. If called again *while* `ALIGNING`, treat as an **early
   commit** (`_commit_align()`), so the single `ops_cut` binding is context-sensitive
   (begin → commit) with no new action.
2. **`set_align_input(v: Vector2)`** (new): store per-frame aim from InputRouter.
3. **`_update_align(delta)`** (new, called from `_process` when `ALIGNING`): also
   guard on still-`MATCHED` + CUTTER power (abort otherwise, same as cutting). Drift
   the target (bounded sinusoid/random-walk, amplitude by selected member `load`);
   integrate the reticle from the stored aim, clamp to the unit square; compute
   `err`. Inside `ALIGN_LOCK_RADIUS`: build `lock`, accumulate `quality` weighted by
   closeness, recover `slip`. Outside: bleed `lock`; beyond `ALIGN_SLIP_RADIUS` grow
   `slip`. `slip >= 1.0` → `_abort_align("TORCH SLIPPED")` + `ALIGN_BOTCH_RISK` nudge
   (the hard-fail). `lock >= 1.0` → `_commit_align()` (auto-commit at full quality).
4. **`_commit_align()`** (new): capture `wreck["align_quality"] = quality`, set
   `align_state = "IDLE"` / emit, then start the real cut exactly as today
   (`cutting_id`, `cut_progress = 0`). Manual early commit banks the current
   (lower) quality — a speed-vs-cleanliness trade.
5. **`_update_cut()`** (443‑457): multiply the progress rate by
   `lerp(ALIGN_RATE_MIN, 1.0, wreck["align_quality"])` — poor alignment cuts slower.
6. **`_complete_cut()`** (459‑471) / **`_apply_cut_stress()`** (476‑480): scale the
   risk spike by `lerp(ALIGN_RISK_MAX, ALIGN_RISK_MIN, quality)` and the stowed
   `qty` by `lerp(ALIGN_YIELD_MIN, 1.0, quality)` before `CargoSystem.stow_salvage`.
7. **Clear alignment** anywhere the cut is torn down: `_abort_cut`, `reset_site`,
   `reset_approach`, and the manual-override branch in `set_manual_flight`, plus
   `rival_strip_member` / `trigger_collapse` default `align_quality` to 1.0 (no
   alignment applies to those).

## HUD (`scenes/ui/HUDOverlay.gd`)

The seam is in the camera view, so this belongs on the HUD (per the file's
"tied to what's in view" rule). Add `_draw_align()`, called from `_draw()` when
`align_state == "ALIGNING"`: map the `align` reticle/target (-1..1) onto a fixed
field centered on the nose-reticle region (~120px radius), draw the target `⊕`
(drifting), the player `✛`, a circular **lock meter** ring, and a pulsing **slip**
warning when `slip` is high — reusing the existing draw helpers' style. Extend
`_draw_ops_state()` (121‑137) so the banner reads `ALIGNING — LOCK NN%` (and the
existing `CUTTING NN%` once committed).

## MFD ALIGN page (new `scenes/ui/AlignPanel.gd` + `MfdUnit.gd`)

New self-contained `Control` page — the dedicated precision instrument — modeled
on `SalvagePanel.gd` (script-only, `@export var accent`, reads `GameState`,
connects signals). Custom `_draw()` renders a large crosshair field: target `⊕`,
reticle `✛`, lock + slip meters, live `quality`, the selected member name, and
status text; plus touch **COMMIT** / **CANCEL** buttons (`ButtonTheme`) calling the
same intents. Redraw on `align_changed` + the 10 Hz `tick_changed` (cut/align
progress has no per-frame signal, same as `OpsBar`).

Register in `scenes/ui/MfdUnit.gd`: add the `preload`, add `"ALIGN"` to `PAGES`
(line 24), and the `match` case in `_build_page()` (114‑143). Also connect
`GameState.align_changed` in `MfdUnit._ready()` to **auto-open** the ALIGN page
when alignment begins and restore the prior page on commit/abort (store
`current_page()` first) — this is a timed skill moment, so surfacing it beats
making the player hunt for the page.

## Ops button (`scenes/ui/OpsBar.gd`)

`_update()` (30‑59) already ticks at 10 Hz. Extend the cut-button branch: while
`ALIGNING`, show `ALIGN — LOCK NN%` and keep the button live as **COMMIT**; the
existing `CUTTING NN%` state is unchanged.

## Input (`autoload/InputRouter.gd`, `project.godot`)

- In `_process()` (359‑381): after composing `thrust`/`rot`, if
  `GameState.align_state == "ALIGNING"` call
  `SalvageSystem.set_align_input(Vector2(rot.y, rot.x))` (yaw→x, pitch→y) and set
  `rot.x = rot.y = 0.0` before `set_manual_flight(thrust, rot)`. `ops_cut` already
  routes to `request_cut()`, which now handles begin-vs-commit internally — no new
  dispatch needed.
- No new **axis** binding required (reuses pitch/yaw). Optionally add
  `mfd_a_align` / `mfd_b_align` direct-jump actions to `project.godot [input]`
  (empty `events`, bound via the remapper) dispatched in
  `_process_panel_commands()` like the other `mfd_*` jumps — nice-to-have, not
  required since auto-open covers it.

## README (`README.md`) — required, same change

Per `CLAUDE.md`, player-facing changes update the README in the same change:

- **Core gameplay loop** (lines ~63‑87): reorder and expand — **pick the cut
  target first**, then **approach to that member** (the autopilot now flies to the
  selected member and matches on it; picking a new target requires re-arming the
  approach to reposition), then the **alignment** step (aim the torch onto the seam
  with pitch/yaw to build a lock; clean alignment cuts faster / risks less / yields
  more, a slip aborts), then the cut. Fix the now-false "approach then pick target"
  ordering rather than appending.
- **The Main flight HUD** (line ~39) + the screenshot caption/alt-text: describe
  the new align reticle/target/lock markings.
- **The four displays** (MFD row, line ~34) and **Mouse / touch** (line ~223):
  add the **ALIGN** page.
- **Controls** tables (X55 line ~135, X52 throttle line ~148, Keyboard line ~186):
  note `ops_cut` is now context-sensitive (begin alignment → commit), that pitch/yaw
  aim the torch during alignment, and that **approach now needs a selected cut
  target** (it flies to that member).

## Verification

1. **Headless smoke** — new `tools/AlignSmoke.gd` + `.tscn`, mirroring
   `tools/Phase5Smoke.gd` (`Engine.time_scale = 10`, `_wait`/`_check`,
   `godot --headless res://tools/AlignSmoke.tscn`). Set up preconditions directly
   (select a member, raise CUTTER power; force `approach_state = "MATCHED"` /
   `matched_member_id` for the alignment asserts since headless has no 3D scene to
   fly the approach), then assert:
   - **Per-member approach:** `toggle_approach()` with no selection refuses;
     selecting a *different* member while not `HOLDING` drops back to `HOLDING`
     (reposition required) and clears `matched_member_id`.
   - `request_cut()` enters `ALIGNING` (not straight to cutting).
   - Feeding on-target `set_align_input` toward the target builds `lock` to 1.0,
     auto-commits, sets `cutting_id`, and yields **high** `align_quality`.
   - Feeding away-from-target input grows `slip` to 1.0 and aborts (no cut, risk
     nudged).
   - A high-quality cut completes faster and stows more `qty` than a low-quality
     one (compare two runs) — the stakes actually bind.
2. **In-app** (`/run` or `godot .`): scan, **pick a cut target**, arm the approach →
   autopilot flies to *that member* and `MATCHED`; fire cutter → HUD shows the
   crosshair and the MFD auto-opens ALIGN; aim with the stick, watch the lock build
   and the cut speed / risk / yield track alignment; deliberately let the torch slip
   to see the abort. Then **select a different member** and confirm you drop out of
   `MATCHED` and must re-arm the approach to reposition before you can cut it.
3. Existing `tools/Phase5Smoke.tscn` still passes (autopilot disengage unchanged
   for non-aligning input).

## Critical files

- `autoload/GameState.gd` — align state/signal/dict, `wreck["align_quality"]`,
  `matched_member_id`.
- `systems/SalvageSystem.gd` — per-member approach, alignment loop, commit,
  quality→outcome scaling, reposition-on-reselect.
- `scenes/world/Wreck.gd` — write baked `center`/`radius` onto each member dict.
- `autoload/InputRouter.gd` — pitch/yaw → align routing while `ALIGNING`.
- `scenes/ui/HUDOverlay.gd` — `_draw_align()` + banner.
- `scenes/ui/AlignPanel.gd` (new) + `scenes/ui/MfdUnit.gd` — ALIGN page + auto-open.
- `scenes/ui/OpsBar.gd` — context-sensitive cut button.
- `tools/AlignSmoke.gd` + `.tscn` (new) — headless coverage.
- `README.md` — controls / HUD / displays / loop.
