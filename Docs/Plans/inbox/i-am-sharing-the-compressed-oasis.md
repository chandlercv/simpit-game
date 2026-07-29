# User-authorable HOTAS mappings + raw-HID mouse-stick/wheel exposure

## Context

A tester with a **Thrustmaster T.16000M** is getting a copy of Salvager, but the
dev owns only the X55 stick + X52 throttle and cannot develop a binding profile
for hardware they don't have. Today all HOTAS bindings live in the hard-coded
`PROFILES` constant in [autoload/InputRouter.gd](autoload/InputRouter.gd) and are
matched by **exact GUID** — an unknown device gets zero flight control, and the
only way to add one is to edit GDScript. That doesn't work for a remote,
non-technical tester.

Separately, the X52 throttle's **mouse-stick nub and scroll wheel** are not read
anywhere: Godot doesn't surface them as joystick axes, and (like the X55 POV hat,
which we already read via raw HID in
[systems/hardware/HidGlanceBridge.gd](systems/hardware/HidGlanceBridge.gd)) they
are only reachable through raw HID. The user wants these exposed to the mapping
system so they can be bound like any other axis.

**Chosen scope (confirmed with the user):**
- **Authoring = both.** Ship a file-based profile loader first (small; unblocks
  the tester immediately — they can hand-edit / the dev can build their file from
  a shared InputEcho log), then build an in-game remapper UI as the friendly
  front-end that writes the same files.
- **Raw HID = dedicated X52 mouse bridge**, not a fully general declarative HID
  schema — one bridge sibling to `HidGlanceBridge` that exposes the X52
  mouse-stick X/Y + wheel as named virtual axes the mapping can bind.

Outcome: any HOTAS becomes bindable without a code change, the tester is
unblocked without the dev owning their stick, and the X52 mouse nub/wheel join
the bindable input vocabulary.

---

## Part 1 — Data layer: user-editable profiles loaded at runtime (ship first)

Decouple the binding data from code so a profile can come from disk and override
(or add to) the built-in defaults, matched by GUID.

### New autoload `autoload/InputConfig.gd` (mirror `autoload/DisplayConfig.gd`)
- Register in `project.godot` `[autoload]` (after `InputRouter`, or before — it
  only needs to exist when `InputRouter._bind_hotas()` runs; load-order safe
  because binding also fires on `joy_connection_changed`).
- Storage: **one JSON file per device GUID** under `user://input_profiles/`
  (e.g. `user://input_profiles/<guid>.json`). One-file-per-device makes it
  trivial for the tester to send their T.16000M profile back and for the
  remapper to write exactly one file per stick. Use `FileAccess` + `JSON`
  (JSON is hand-editable for the nested `axes`/`buttons` arrays; the
  `ConfigFile` pattern in DisplayConfig is for flat key=value and is a poor fit
  here — but reuse DisplayConfig's *discipline*: guard reads, don't clobber on
  parse error).
- Schema mirrors `PROFILES` exactly so the two are interchangeable:
  ```json
  {
    "name": "Thrustmaster T.16000M",
    "guid": "03...",
    "axes":    [{"axis": 1, "neg": "pitch_down", "pos": "pitch_up"}],
    "buttons": [{"button": 0, "action": "ops_cut"}],
    "throttle": {"axis": 2, "idle": 1.0, "full": -1.0},
    "hid_axes":[{"source": "x52_mouse_x", "neg": "yaw_left", "pos": "yaw_right"}],
    "reserved_buttons": []
  }
  ```
- API: `get_user_profiles() -> Array[Dictionary]`, `save_profile(profile)`,
  `delete_profile(guid)`; `signal profiles_changed`.

### `autoload/InputRouter.gd` — read merged profiles
- Rename the current `const PROFILES` to `BUILTIN_PROFILES` (the shipped
  defaults — keep the X52/X55 entries byte-for-byte).
- Add `_effective_profiles()`: start from `BUILTIN_PROFILES`, then for each user
  profile from `InputConfig`, **replace** the built-in entry with the same GUID
  (predictable full-override) or append if new. `_bind_hotas()` iterates the
  effective list instead of the const.
- Connect `InputConfig.profiles_changed` → `_bind_hotas()` so an edited/saved
  profile (or the remapper) rebinds live, exactly like the existing replug path.
- **Generalize the throttle rescale** so arbitrary throttles work. Today
  `throttle()` (lines 132-138) hard-codes the X52's `+1(idle)..-1(full)` range
  via `idle_deadzone`. Support a `{axis, idle, full}` form and compute
  `clampf((idle - value) / (idle - full), 0, 1)` with a small idle deadzone;
  keep back-compat by treating the old `idle_deadzone` key as `idle=1, full=-1`.
  This matters because the T.16000M throttle rests/ranges differently.

---

## Part 2 — X52 mouse-stick + wheel via raw HID

### Discovery prerequisite (dev has the X52 throttle — do this first)
Before writing a decoder we must find the report layout, exactly as was done for
the X55 POV. Extend [tools/InputEcho.gd](tools/InputEcho.gd): add an `_open_x52()`
alongside `_open_x55()` that opens the X52's mouse/relevant HID collection and
dumps changing report bytes (the tool already marks changed bytes with `^^`).
- X52 identity from its GUID `0300ea18a30600005c07000000000000` → **VID 0x06a3,
  PID 0x075c**. Enumerate collections with `Hid.list_devices()` and dump each to
  locate the mouse-stick X/Y and wheel byte offsets/encoding.
- **Risk to surface in the dump:** the mouse nub may present as a standard HID
  *mouse* (usage_page 1 / usage 2) that Windows owns as the system pointer —
  a raw read may be empty or conflict. The dump determines which collection
  actually carries the nub/wheel and whether it's readable; if the mouse
  collection is unreadable, check whether the nub/wheel instead ride the X52
  joystick collection as spare axes. Record findings before building the bridge.

### New `systems/hardware/X52MouseBridge.gd` (sibling of `HidGlanceBridge.gd`)
- Same proven shape: `ClassDB.class_exists("Hid")` guard, `open_path` by
  vid/pid/usage filter, `read_timeout` drained per frame, **Variant-typed** read
  with `typeof(...) != TYPE_PACKED_BYTE_ARRAY` error/close/retry handling,
  degrade-gracefully background retry.
- Public state: `axis := Vector2.ZERO` (mouse-stick X/Y, normalized -1..1) and
  `wheel := 0.0`. A static `parse_report(bytes) -> ...` pure decoder (unit-
  testable like `HidGlanceBridge.parse_pov`).
- Instantiated by `InputRouter._ready()` next to the glance/switch bridges.

### Wire `hid_axes` into the mapping
- Add a `HID_SOURCES` lookup in `InputRouter` mapping source names
  (`"x52_mouse_x"`, `"x52_mouse_y"`, `"x52_wheel"`) to the bridge value.
- In `InputRouter._process()`, after composing `thrust`/`rot` from
  `Input.get_axis(...)`, **add each bound `hid_axes` contribution** into the
  matching action pair (same additive pattern `throttle()` already uses for
  thrust.z and `get_glance()` uses for glance). Keeps HID axes first-class
  without forcing them through the InputMap (which can't hold raw HID values).

---

## Part 3 — In-game remapper UI (front-end for the Part 1 files)

New `scenes/displays/ControlsSetup.gd` — a code-built overlay cloning the proven
[scenes/displays/DisplaySetup.gd](scenes/displays/DisplaySetup.gd) pattern
(central panel on the main window; no `.tscn` needed).

- **Reached via** a new `configure_controls` action in `project.godot`
  `[input]`, polled in `InputRouter._process()` (input concern stays in
  InputRouter; avoids entangling with WindowManager's display-overlay teardown).
  Open it on InputRouter's own `CanvasLayer`.
- Lists connected joypads (`Input.get_joy_name` / `get_joy_guid`); the user
  picks which device to map.
- Shows bindable actions grouped by the semantic clusters the sim already uses
  (from `InputRouter._process`): **Rotation** (pitch/yaw/roll), **Translation**
  (strafe L/R, thrust up/down, forward/back), **Throttle**, **Glance**, **Ops**
  (approach/cut). Each row: current binding + a **Bind** button.
- **Bind = listen mode**, reusing `InputEcho.gd`'s `_input()` capture logic:
  next `InputEventJoypadButton` → button binding; next `InputEventJoypadMotion`
  past the 0.08 jitter threshold → axis binding (with the sign → neg/pos).
  Offer the X52 mouse sources as explicit pick options for HID-axis rows.
  A **reverse-axis** toggle. **Honor `reserved_buttons`/always-held selectors**
  (the X55/X52 mode banks) — detect a button that's held at listen-start and
  warn/skip rather than capture it (see the InputRouter header rationale).
- **Save** → `InputConfig.save_profile(...)` → `profiles_changed` → live rebind.

Sequencing: Parts 1+2 land first (tester unblocked, mouse exposed); Part 3 builds
on the same data files and can follow as a second change.

---

## Files

**New**
- `autoload/InputConfig.gd` — JSON profile store (`user://input_profiles/`)
- `systems/hardware/X52MouseBridge.gd` — X52 mouse-stick/wheel raw-HID bridge
- `scenes/displays/ControlsSetup.gd` — in-game remapper overlay (Part 3)

**Edit**
- `autoload/InputRouter.gd` — `BUILTIN_PROFILES` + `_effective_profiles()`,
  merge/override by GUID, general throttle rescale, `hid_axes` compositing,
  X52 bridge instantiation, `configure_controls` polling + overlay
- `tools/InputEcho.gd` — `_open_x52()` discovery dump (do first)
- `project.godot` — new `configure_controls` action; register `InputConfig`
  autoload

---

## README / docs (required by CLAUDE.md — player-facing controls changed)

- **Remapping the HOTAS controls** section (~lines 194-229): the flow is no
  longer "edit `PROFILES` in GDScript." Document (a) dropping a JSON profile in
  `user://input_profiles/`, (b) the in-game remapper (open with the new key),
  and (c) that `BUILTIN_PROFILES` remains the shipped defaults. Keep the
  InputEcho discovery guidance (still how you find raw indices / a new GUID).
- Note the **X52 mouse-stick/wheel** as newly bindable inputs, and the new
  `configure_controls` key in the Keyboard-fallback controls table.
- Update the memory note (`simpit-phase-status`) once verified.

---

## Verification

**Discovery (Part 2, on the dev's X52 throttle):** run
`godot --path . res://tools/InputEcho.tscn`, work the mouse nub and wheel, and
confirm from `user://input_echo.log` which bytes move → offsets for
`X52MouseBridge.parse_report`. If the mouse collection is OS-owned/unreadable,
record that and fall back per the risk note before coding the bridge.

**Part 1 (file loader), without needing a T.16000M present:**
- Hand-write a `user://input_profiles/<guid>.json` for an *already-owned* stick
  (e.g. re-map the X55 with swapped axes) and confirm `InputRouter` applies it
  over the built-in on launch and on save (live rebind, no restart).
- Malformed JSON → logged, ignored, built-in still used (no crash).
- Generalized throttle: a profile with `{axis, idle, full}` gives full 0..1
  sweep; the existing X52 `idle_deadzone` form still behaves identically.

**Part 2 (X52 mouse):** with the bridge live, a profile binding
`x52_mouse_x/y` → yaw/pitch (or glance) moves the ship/camera from the nub;
the wheel drives its bound action; joypad axes/buttons keep working while the
bridge holds the HID handle open (the coexistence check the glance bridge
already passes).

**Part 3 (remapper):** open with `configure_controls`; pick a device; bind pitch
by wiggling an axis and cut by pressing a button; verify an always-held
mode-selector button is refused; Save and confirm the control works immediately
and a matching JSON file exists in `user://input_profiles/`.

**Regression:** on the dev's real rig (X55 + X52) with no user profiles present,
flight/throttle/glance/ops behave exactly as today (built-in defaults unchanged).
