# Plan: Fix the glance collision by reading the X55 POV from raw HID (keep both sticks raw)

## Context

The hull-camera **glance** yaws a full 60° right on the first hat input after a cold launch and holds
there ~1.6 s before recovering — confirmed by frame-tracking the launch recording (planet slides
0.66→0.32 = camera yawing right; smooth exponential settle = a held target, not a blip).

Root cause, confirmed by the InputEcho log:

- The "permanently held button" is **not a driver phantom — it's the mode selector.** The Saitek
  M1/M2/M3 rotary always holds one button down for its current position: X55 modes = buttons 15–17
  (1-based) = indices **14–16**; X52 modes = 24–26 = indices **23–25** (the `device 0 BUTTON 23 pressed`
  in the log).
- Godot reads these as raw joysticks and **collapses the POV hat into dpad buttons 11–14**. Index **14**
  is `JOY_BUTTON_DPAD_RIGHT` — so when the mode rotary sits in **mode 1** (index 14), that always-on
  button and the real **hat-right** become the *same* Godot signal, indistinguishable. In mode 2/3
  (indices 15/16) there is no glance collision — which is why the bug is mode-dependent.
- `glance_right` in [project.godot](project.godot#L41-L46) is bound to joypad button 14 (device -1), so
  the mode-1 button drives glance right.

The current defense — a startup "latch" in [InputRouter.gd](autoload/InputRouter.gd#L54-L58) that swallows
glance until the raw vector first changes — releases one event too early (while the mode button is still
held) and has cold-boot races. It's a temporal heuristic fighting an index collision.

**Decision (chosen with the user):** keep both sticks as **raw joysticks** rather than adopting SDL
controller mappings. A controller mapping would fix the collision cleanly but caps each device to SDL's
~21-button / 6-axis vocabulary and drops the rest — foreclosing the mode switch and most HOTAS buttons
for future contributors on this hardware. Instead we keep every button/axis/hat available (mode buttons
included) and fix glance surgically: **read the X55 stick's POV directly from its HID report** and take
glance off the dpad entirely. Nothing about the hardware gets foreclosed.

Scope: fix the glance bug; keep device handling data-driven so adding a device later is a data edit; **no**
rebind UI / arbitrary-hardware auto-detection this pass.

## Approach

1. **Keep both sticks raw** — no SDL mapping. All axes/buttons/hats stay visible to Godot, including the
   mode buttons (14/15/16, 23/24/25), which become plain bindable buttons for future use.
2. **Take glance off the dpad** — strip the `InputEventJoypadButton` (dpad 11–14) events from the
   `glance_*` actions in project.godot, keeping the arrow-key events. This severs the collision path:
   the mode-1 button (dpad_right) can no longer reach glance.
3. **Source the X55 POV from raw HID** — a small bridge opens the X55 stick HID device via hid-gd,
   decodes the POV field to a `Vector2`, and feeds `get_glance()`.
4. **Delete the latch entirely** — glance no longer sees the dpad/mode buttons, so there is nothing to
   swallow and no boot race to guard.
5. **Light profile consolidation** — fold the scattered per-device consts into per-device profile data
   (the "don't make it hard later" step), including the X55's HID-glance descriptor and each stick's
   mode-button indices (documented/reserved).

## Discovery prerequisite (before writing the decoder)

We don't yet know the X55 stick's HID report layout. First, extend [tools/InputEcho.gd](tools/InputEcho.gd)
(it already opens the switch panel via the `Hid` class) to also open the **X55 stick** HID and dump raw
report bytes while the POV is worked, to locate the hat field.

- X55 stick HID: **VID 0x0738 PID 0x2215**, joystick collection **MI_00** (`usage_page 1, usage 4`).
- HID hats are typically a 4-bit value **0–7** (N, NE, E, … NW) with **8 or 0x0F = centered**, packed in
  one byte. The dump tells us the byte offset and encoding.

## Changes

**New `systems/hardware/HidGlanceBridge.gd`** (sibling of [SwitchPanelBridge.gd](systems/hardware/SwitchPanelBridge.gd))
- Opens the X55 stick HID (prefer open-by-path for the MI_00 collection; fall back to vid/pid), reads
  reports each frame, decodes the POV byte → `Vector2` (+x right, +y down, zero when centered). Reuses
  the `ClassDB.instantiate("Hid")` + `read_timeout` pattern already proven in `SwitchPanelBridge`.

**[autoload/InputRouter.gd](autoload/InputRouter.gd)** (primary)
- Instantiate `HidGlanceBridge` alongside `SwitchPanelBridge` in `_ready`.
- `get_glance()` = `clamp(keyboard-arrow vector + HID POV vector)`. **Remove** `_glance_latched`,
  `_glance_initial`, and the latch branch. Simplify `_on_joy_connection_changed` back to just
  `_bind_hotas()` (drop the re-arm block added earlier).
- Consolidate `X52_GUID/X55_GUID/AXIS_ACTIONS/BUTTON_ACTIONS/THROTTLE_*` into a `PROFILES` list, one
  dict per device: `name`, `guid`, `axes` (index→neg/pos action), `buttons` (index→action), optional
  `throttle` (`{axis, idle_deadzone}`), optional `hid_glance` (`{vid, pid}`), `mode_buttons`
  (documented/reserved). `_bind_hotas()` iterates `PROFILES`. **Axis/button/throttle behavior is
  byte-for-byte identical** — the raw indices don't change because we're not mapping anything.
- Rewrite the top-of-file comment: explain the mode-selector/DPAD_RIGHT collision, that glance now comes
  from the HID POV, that the dpad is no longer used for glance, and that mode buttons are free to bind.

**[project.godot](project.godot#L35-L58)**
- Remove the `InputEventJoypadButton` (button_index 11–14) entries from `glance_left/right/up/down`;
  keep the arrow-key `InputEventKey` entries. Nothing else references dpad buttons.

**Docs / memory**
- Update the input section of [Docs/Plans/simpit-plan.md](Docs/Plans/simpit-plan.md) if it documents the
  latch.
- Update the memory note: glance now sourced from X55 HID POV; sticks stay raw (no controller mapping)
  to keep all buttons available; latch removed.

### Profile shape (illustrative)

```gdscript
const PROFILES := [
    {"name": "Saitek X52 Flight Control System",
     "guid": X52_GUID, "axes": [], "buttons": [{"button": 7, "action": "ops_approach"}],
     "throttle": {"axis": 2, "idle_deadzone": 0.95}, "mode_buttons": [23, 24, 25]},
    {"name": "Madcatz Saitek Pro Flight X-55 Rhino Stick",
     "guid": X55_GUID,
     "axes": [{"axis": 0, "neg": "yaw_left",   "pos": "yaw_right"},
              {"axis": 1, "neg": "pitch_down", "pos": "pitch_up"},
              {"axis": 2, "neg": "roll_left",  "pos": "roll_right"}],
     "buttons": [{"button": 0, "action": "ops_cut"}],
     "hid_glance": {"vid": 0x0738, "pid": 0x2215}, "mode_buttons": [14, 15, 16]},
]
```

## Risks & fallback

- **HID layout unknown until captured** — the decoder depends on the discovery dump. Do that first.
- **hid-gd open granularity** — the X55 exposes several HID collections under the same vid/pid; `open(vid,
  pid)` may grab the wrong one. Confirm the `Hid` class supports open-by-path (as listed in the HID
  enumeration) and use the MI_00 joystick path; vid/pid only as fallback.
- **Concurrent HID access** — Godot holds the stick open as a joypad while our bridge opens it for HID
  read. Windows HID reads are normally shared per-handle, so both should work, but **verify axes/buttons
  still function while the bridge is reading**. If they conflict, fall back to reading *all* X55 inputs
  from our HID handle (larger change) — but expect no conflict.
- **Poll cadence** — read the POV in `_process`; confirm no perceptible latency/jitter vs the old dpad
  path.
- **Fallback if raw-HID proves unreliable** — revert to an improved latch (git history preserved); the
  collision returns but is bounded. Reconsidering the controller-mapping route is the last resort.

## Verification

End-to-end on the real rig (X55 connected at cold boot — the primary scenario):

1. **Bug gone:** with the mode rotary parked in **mode 1**, re-record launch→first-glance; re-run the
   planet-centroid tracker from this session (`scratchpad/track2.py` approach) — first glance moves the
   *commanded* direction, **no** 60° right hold. Repeat across several cold launches (kills the old race).
2. **Glance fidelity:** all 8 POV directions register; keyboard arrow-key glance still works; the two
   sources combine sanely.
3. **Mode switch freed:** rotate M1/M2/M3 on both sticks — glance is unaffected in every position (dpad
   no longer feeds it); and InputEcho confirms the mode buttons now surface as plain raw Godot buttons
   (14/15/16, 23/24/25), i.e. bindable by contributors.
4. **No regressions:** full throttle sweep (X52 axis 2 rescale), roll/pitch/yaw (X55 axes 0/1/2),
   `ops_cut` (X55 b0), `ops_approach` (X52 b7).
5. **Coexistence:** joypad axes/buttons keep working while `HidGlanceBridge` holds the stick HID open.
