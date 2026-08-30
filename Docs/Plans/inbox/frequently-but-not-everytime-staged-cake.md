# Phantom throttle at scene entry — fix the unsampled-axis default

## Context

On starting the flight scene the ship frequently — but not always — begins moving
forward with the X52 lever physically shut. Controls track correctly once flying.

The cause is in [InputRouter.gd:494-517](autoload/InputRouter.gd#L494-L517).
`throttle()` reads the lever with `Input.get_joy_axis()`, which answers **0.0 for
an axis the engine has never sampled** — the value is a cached last-known reading,
not a live device query. On a lever, raw 0.0 is *mid-travel*, and every lever spec
form maps it to exactly **half throttle**:

- X52 form `{"axis": 2, "idle_deadzone": 0.95}` (the live spec — see below):
  `0.0 >= 0.95` is false, so no idle short-circuit, then `(1.0 - 0.0) / 2.0` = **0.5**
- general form `{"idle": 1.0, "full": -1.0}`: `(1.0 - 0.0) / 2.0` = **0.5**
- inverted form `{"idle": -1.0, "full": 1.0}`: `(-1.0 - 0.0) / -2.0` = **0.5**

Only `mode: "gamepad"` is safe (0.0 is below its deadzone). The rig's live spec is
a *user* profile — `user://input_profiles/0300ea18a30600005c07000000000000.json`,
`{"axis": 2.0, "idle_deadzone": 0.95}`, which replaces the built-in at
[InputRouter.gd:59](autoload/InputRouter.gd#L59) with the same values — so it takes
the vulnerable branch.

Half throttle in the default SPEED command law is a commanded 17.5 m/s
(`speed_ceiling()` 25 + 10 thermal bonus × 0.5) closed at 3.2 m/s², i.e. the ship
departs under power. It self-heals the instant the lever moves, because that
produces the first real sample — matching "controls otherwise track correctly".

There is **no guard anywhere** against acting on an unsampled axis: no first-sample
flag, no idle ratchet, no deferral. `ScreenshotCheck.gd:271-277` already works
around this whole class of problem by disabling `InputRouter` outright.

Why "frequently, but not every time": the sample is missing whenever the engine
has not yet polled that device — device enumeration racing the first unpaused
frame, and a replug/USB hiccup, which re-runs `_bind_hotas()` (wired to
`joy_connection_changed` at [InputRouter.gd:231-232](autoload/InputRouter.gd#L231-L232))
and re-arms `_throttle_device` against a cache Godot cleared on disconnect.

A second, smaller defect compounds it. `ShipMotion._cmd_thrust`
([ShipMotion.gd:57](systems/ShipMotion.gd#L57)) is latched and **never cleared on
pause**. `WindowManager._ready()` defers `_setup()`
([WindowManager.gd:96](autoload/WindowManager.gd#L96)), so the boot frame runs
*unpaused* — `InputRouter._process` samples once (0.5) and latches it — then the
title card pauses the tree at [WindowManager.gd:147](autoload/WindowManager.gd#L147)
and `_process` early-returns for the whole card. `_physics_process` runs ahead of
idle in the same frame, so the first tick after LAUNCH spends that stale command
before `_process` has read anything.

Intended outcome: a lever whose sample has not landed reads **idle**, and no
command latched before the title card survives it.

## Approach

Confirmed with the user: the Logitech Dual Action pad is **not plugged in**, and
the core fix only — no player-facing idle-arming interlock.

### 1. Gate the throttle on a real sample — [autoload/InputRouter.gd](autoload/InputRouter.gd)

Add beside `_throttle_spec` ([line 198-202](autoload/InputRouter.gd#L198-L202)):

```gdscript
## True once the engine has actually REPORTED a value for the bound throttle
## axis. Input.get_joy_axis() answers 0.0 for an axis it has never sampled, and
## 0.0 on a lever is MID-TRAVEL — every lever form in _throttle_curve maps it to
## half open. A throttle whose first sample hasn't landed (enumeration racing the
## first frame; a replug, which clears the cached value and re-runs _bind_hotas)
## would fly the ship off the wreck with the lever shut. Until it lands, idle.
var _throttle_seen := false
```

Latch it from a new `_input()` handler. Use the **event**, not a non-zero polled
reading: Godot emits a motion event on the *first* read of an axis (its cache has
no prior value to match), so this fires even for a lever that has not moved since
boot — which a "reading is non-zero" test could not distinguish from a lever
genuinely parked at mid-travel.

```gdscript
func _input(event: InputEvent) -> void:
	if _throttle_seen or _throttle_device == -1:
		return
	var motion := event as InputEventJoypadMotion
	if motion and motion.device == _throttle_device and int(motion.axis) == _throttle_axis:
		_throttle_seen = true
```

Split `throttle()` into the gate plus a pure curve — the split is what makes the
half-throttle mapping testable without a stick attached:

```gdscript
func throttle() -> float:
	if _throttle_device == -1:
		return 0.0
	var value := Input.get_joy_axis(_throttle_device, _throttle_axis as JoyAxis)
	if not _throttle_seen:
		# Belt and braces behind the _input latch: a non-zero reading is proof of a
		# real sample too. A gate that ONLY an event could open would make a dead
		# throttle out of any case where those don't reach us; this one can't. The
		# cost is a lever parked at EXACTLY raw 0.0 (mid-travel) reading idle until
		# it next moves — the safe direction, and it self-heals on the first nudge.
		if is_zero_approx(value):
			return 0.0
		_throttle_seen = true
	return _throttle_curve(value, _throttle_spec)


## Pure raw-axis -> command mapping for one spec, split out of throttle() so
## ThrottleIdleSmoke can drive every form headless. [three spec forms doc block
## moves here verbatim from lines 483-493]
static func _throttle_curve(value: float, spec: Dictionary) -> float:
	# ... existing body of lines 498-517, reading `spec` instead of _throttle_spec
```

### 2. Re-arm the gate and make the throttle pick deterministic — `_bind_hotas()`

At the reset block ([lines 401-403](autoload/InputRouter.gd#L401-L403)) add
`_throttle_seen = false`, so a replug re-arms the gate rather than trusting a
cache the disconnect cleared.

At [lines 410-413](autoload/InputRouter.gd#L410-L413), the loop lets the
*last-enumerated* device with a `throttle` win, silently and in whatever order the
OS enumerated. The user's saved Logitech Dual Action profile declares one
(`{"axis": 1, "mode": "gamepad"}`) and would steal it from the X52 if ever plugged
back in. Make first match win and say so:

```gdscript
			if profile.has("throttle"):
				# First match wins, not last: enumeration order is the OS's business,
				# and a second stick with a throttle in its profile must not silently
				# take the lever off the one you are flying.
				if _throttle_device == -1:
					_throttle_device = device
					_throttle_spec = profile["throttle"]
					_throttle_axis = int(_throttle_spec["axis"])
					WindowLog.note("input", "throttle bound: %s axis %d (device %d)"
							% [profile.get("name", "?"), _throttle_axis, device])
				else:
					WindowLog.note("input", "throttle already bound — ignoring %s"
							% profile.get("name", "?"))
```

`WindowLog.note(category, text)` is at
[WindowLog.gd:208](autoload/WindowLog.gd#L208); `input` is one of its named
concerns.

### 3. Don't let a command outlive the pause — `_process()`

At the pause early-return ([lines 528-529](autoload/InputRouter.gd#L528-L529)):

```gdscript
	if get_tree().paused:
		# Hands off — and clear anything latched before the card came up. _process
		# last ran on the BOOT frame, ahead of WindowManager's deferred _setup()
		# pausing the tree, so a command read there would sit in ShipMotion across
		# the whole card and be spent by the first physics tick after LAUNCH
		# (physics runs ahead of idle in the same frame).
		ShipMotion.set_command(Vector3.ZERO, Vector3.ZERO)
		return
```

Zeroing is the opposite of the intent leak the existing comment guards against, and
it goes straight to `ShipMotion.set_command` rather than
`SalvageSystem.set_manual_flight`, so it cannot trip the autopilot-disengage path
at [SalvageSystem.gd:189-198](systems/SalvageSystem.gd#L189-L198).

### 4. Regression smoke — `tools/ThrottleIdleSmoke.gd` + `.tscn`

New headless smoke, following [AxisKeyNormalizeSmoke.gd](tools/AxisKeyNormalizeSmoke.gd)
exactly (`_check()` accumulating `_failures`, `quit(0)`/`quit(1)`, a `##` header
naming the bug and the run command). Copy `AxisKeyNormalizeSmoke.tscn` for the
scene. Checks:

- `_throttle_curve(0.0, {"axis": 2, "idle_deadzone": 0.95})` == **0.5** — pins the
  hazard the gate exists for; if this ever stops being 0.5 the gate's rationale
  changed.
- Same spec: raw `1.0` → 0.0 (idle), raw `-1.0` → 1.0 (full).
- General lever `{"idle": 1.0, "full": -1.0}`: raw 0.0 → 0.5, raw 1.0 → 0.0.
- Inverted lever `{"idle": -1.0, "full": 1.0}`: raw 0.0 → 0.5, raw -1.0 → 0.0.
- `{"mode": "gamepad"}`: raw 0.0 → 0.0 (already safe, kept safe).
- **The gate.** Set `InputRouter._throttle_device = 0`, `_throttle_axis = 2`,
  `_throttle_spec = {"axis": 2, "idle_deadzone": 0.95}`, `_throttle_seen = false`
  → `InputRouter.throttle()` == 0.0 even though the curve says 0.5. Flip
  `_throttle_seen = true` → `throttle()` == 0.5 (headless `get_joy_axis` returns
  0.0), proving the gate and only the gate is what suppresses it. Restore with
  `InputRouter._bind_hotas()`.
- **The pause clear.** `ShipMotion.set_command(Vector3(0, 0, 0.5), Vector3.ZERO)`,
  `get_tree().paused = true`, call `InputRouter._process(0.016)`, assert
  `ShipMotion.throttle_command() == 0.0`. (`_process`'s `configure_controls` branch
  is already guarded by `DisplayServer.get_name() != "headless"`.) Unpause after.

### Documentation

No `README.md` or ship-document change. Nothing the player presses, sees, or reads
changes — an idle lever now reads idle, which is what
[README.md:720](README.md#L720) already describes. No quoted constant moves, and
the README states no rule about which device wins a contested throttle. Per
`CLAUDE.md`, a purely internal fix needs no README edit.

## Verification

```
godot --headless res://tools/ThrottleIdleSmoke.tscn   # new — must print ALL CHECKS PASSED
godot --headless res://tools/FlightSmoke.tscn         # command path unchanged
godot --headless res://tools/AxisKeyNormalizeSmoke.tscn
godot --headless res://tools/KeyboardMergeSmoke.tscn  # _bind_hotas still binds keys
godot --headless res://tools/BindClashSmoke.tscn
godot --headless res://tools/ChecklistSmoke.tscn      # reads throttle_command()
```

On the rig, the check that actually settles it — repeat several times, since the
fault is intermittent:

1. Launch with the X52 lever fully shut. Press LAUNCH. **The ship must not move.**
   Confirm on the HUD speed readout and the MFD CHECKLIST throttle figure.
2. Without touching the lever, arm the approach autopilot. It must arm — a phantom
   0.5 exceeds `APPROACH_ARM_THROTTLE_MAX` (0.4,
   [SalvageSystem.gd:209](systems/SalvageSystem.gd#L209)) and would be refused with
   "THROTTLE PAST 50%, EASE BACK TO ARM". This is a good independent tell.
3. Open the lever, confirm normal thrust, close it, confirm it returns to idle.
4. Unplug and replug the X52 mid-flight without touching the lever: the ship must
   not surge. This is the `_throttle_seen` reset in `_bind_hotas()`.
5. `user://window_log.txt` (path printed at boot) should carry one
   `input  throttle bound: Saitek X52 … axis 2` line, and no "already bound" line.
