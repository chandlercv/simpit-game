# Switch-driven power state

## Context

The Saitek switch panel decodes 20 switches, but only `MASTER_BAT` (power
kill/restore), `NAV`, and `LANDING` (cosmetic lights) do anything. The four
system power channels (`THRUST`, `CUTTER`, `SENSORS`, `LIFE`) can only be set by
the tablet touch sliders. We want the panel's toggle switches to drive power
directly so the player flies from the hardware, plus master electrical switches
that override the whole mix and affect how visible the ship is.

Goals:
- Four toggle switches move a channel between a **high** (default 80%) and
  **low** (default 20%) setting. High/low are one shared pair now, designed so
  they can become per-player-configurable later.
- **Master ALT off** rigs *all power to thrusters* (THRUST = 100%, everything
  else 0), overriding the switch settings; ALT back on restores the prior mix.
- **Master BAT off** zeros everything; BAT back on restores the prior mix.
- Power is **not alterable** while either master is off (switches and sliders
  are ignored/locked).
- Being unpowered lowers the ship's **visibility to passive scanners** by 50%
  per master that is off — ALT off ×0.5, BAT off ×0.5, both off ×0.25.

## Decisions (confirmed with user)

- ALT-off THRUST target = **1.0** (max), others 0.
- Signature multipliers **stack multiplicatively** (both masters off → 0.25).
- Switch→channel mapping (**thematic**), ON = high, OFF = low:
  `FUEL_PUMP→THRUST`, `AVIONICS→SENSORS`, `DE_ICE→CUTTER`, `PITOT_HEAT→LIFE`.

## Design: recompute, don't snapshot

The current `set_master_battery` snapshot/restore approach gets fragile once a
second master (ALT) can also override, so replace it with a single deterministic
recompute. Keep a **desired target** per channel that the switches/sliders write;
the master overrides are computed *on top* of it, so "restore the prior mix" is
automatic (the target is never clobbered by an override).

State model in [GameState.gd](autoload/GameState.gd):
- `var power_high := 0.8`, `var power_low := 0.2` — runtime vars (not `const`) so
  a future settings surface can rewrite them; the "eventually configurable" hook.
- `const CHANNEL_SWITCHES := {"FUEL_PUMP":"THRUST", "AVIONICS":"SENSORS",
  "DE_ICE":"CUTTER", "PITOT_HEAT":"LIFE"}` — the thematic mapping, owned here
  (gameplay semantics), read by the bridge.
- `var master_bat := true`, `var master_alt := true`.
- `var _power_target: Dictionary` — desired per-channel values, seeded from the
  existing `_ready` defaults (`THRUST 0.8, CUTTER 0.0, SENSORS 0.6, LIFE 1.0`).
  Replaces `_power_before_bat` (delete it).

Methods:
- `_apply_electrical()` (private) computes the live `local_ship()["power"]`:
  not `master_bat` → all 0; else not `master_alt` → `{THRUST:1.0, rest:0}`; else
  copy `_power_target`. Writes each channel and emits `power_changed` once.
- `power_locked() -> bool` → `not master_bat or not master_alt`.
- `set_power(channel, value)` (slider intent) — early-return if `power_locked()`;
  else write `_power_target[channel]` (clamped) and `_apply_electrical()`.
- `set_power_switch(switch_name, on)` (new, channel switches) — early-return if
  `power_locked()`; else `_power_target[CHANNEL_SWITCHES[switch_name]] =
  power_high if on else power_low` and `_apply_electrical()`.
- `set_master_alt(on)` (new) — set `master_alt`, `_apply_electrical()`, emit
  `signature_changed`.
- `set_master_battery(on)` (rewrite) — set `master_bat`, `_apply_electrical()`,
  emit `signature_changed`. Same external contract (off kills, on restores), now
  via the target instead of a snapshot.
- `passive_signature() -> float` — `1.0`, ×0.5 if not `master_alt`, ×0.5 if not
  `master_bat`.
- New `signal signature_changed(value: float)` (follows the `*_changed` pattern
  in [GameState.gd](autoload/GameState.gd#L11-L40)).

Because `_apply_electrical` always emits `power_changed`, the tablet re-syncs on
every master toggle without extra wiring.

## Switch routing

[SwitchPanelBridge.gd](systems/hardware/SwitchPanelBridge.gd#L117-L121) —
extend `_route_intent`'s `match`:
- `"MASTER_BAT"` → `GameState.set_master_battery(on)` (unchanged)
- `"MASTER_ALT"` → `GameState.set_master_alt(on)`
- the four names in `GameState.CHANNEL_SWITCHES` → `GameState.set_power_switch(switch_name, on)`

The bridge already emits every switch's state on first HID read (diff vs empty
`panel_switches`), so the game syncs to the physical panel positions at startup —
no extra init needed.

## Lock the tablet UI when unpowered

- [TouchSlider.gd](scenes/ui/TouchSlider.gd) — add `var disabled := false`;
  early-return at the top of `_gui_input` when set; dim the draw (e.g. lower
  accent alpha) so the lock is visible.
- [PowerSliders.gd](scenes/ui/PowerSliders.gd) — in `_sync()` (already runs on
  every `power_changed`), set each slider's `disabled = GameState.power_locked()`
  and surface a short locked note in the header (e.g. `— OFFLINE (BAT)` /
  `— THRUST LOCK (ALT)`).

## Signature consumer

[ThreatSystem.gd](systems/ThreatSystem.gd#L150) — scale the one place the player
is "detected": replace the flat `PATROL_ENFORCE_RANGE` distance check in
`_update_patrol` with `PATROL_ENFORCE_RANGE * GameState.passive_signature()`.
Lower visibility → patrol must close further before it can fine you. This is the
concrete payoff of running dark; future passive scanners read the same
`passive_signature()`.

## Files to change

- [autoload/GameState.gd](autoload/GameState.gd) — power model rewrite (above).
- [systems/hardware/SwitchPanelBridge.gd](systems/hardware/SwitchPanelBridge.gd) — `_route_intent` cases.
- [scenes/ui/TouchSlider.gd](scenes/ui/TouchSlider.gd) — `disabled` support.
- [scenes/ui/PowerSliders.gd](scenes/ui/PowerSliders.gd) — lock sliders + header note.
- [systems/ThreatSystem.gd](systems/ThreatSystem.gd) — signature-scaled enforce range.
- [README.md](README.md) — switch-panel table (MASTER ALT + the four channel
  switches with the thematic mapping and high/low), the master-BAT row (now via
  target restore), the **Core gameplay loop** power paragraph (high/low toggles,
  ALT all-to-thrust, passive-signature effect), and move the four switches out of
  the "not wired to gameplay" list.

## Verification

- **Smoke tests** (headless, the established pattern in `tools/`): mirror
  `tools/Phase5Smoke.gd`. Drive `GameState` directly and assert:
  1. `set_power_switch("FUEL_PUMP", true)` → `power("THRUST") == power_high`;
     `false` → `power_low`. Same for the other three channels.
  2. `set_master_alt(false)` → THRUST 1.0, others 0, `power_locked()`,
     `set_power`/`set_power_switch` no-op while off; `set_master_alt(true)`
     restores the pre-ALT mix.
  3. `set_master_battery(false)` → all 0 and locked; `true` restores.
  4. `passive_signature()` = 1.0 / 0.5 (one off) / 0.25 (both off).
  Run: `& "<godot>" --headless --path d:\simpit-game --script res://tools/<Smoke>.gd`
  (Godot 4.7 per memory).
- **Hardware/manual:** launch the app, watch the comms log for the switch lines,
  flip FUEL PUMP/AVIONICS/DE-ICE/PITOT and confirm the matching tablet slider
  snaps to 80%/20%; flip MASTER ALT and confirm THRUST pins to 100%, others 0,
  and sliders grey out; flip back and confirm the prior mix returns; same for
  MASTER BAT. (Use `/run` to drive the app.)
