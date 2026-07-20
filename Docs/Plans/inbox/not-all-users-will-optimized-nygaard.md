# Flexible displays: graceful degradation for fewer/variable monitors & no touchscreen

## Context

Salvager assumes a 4-monitor simpit (Main / Tactical / Tablet / Chart, one native
OS window per screen). But not every player has four monitors, a touchscreen, or
even all four monitors connected on a given day. We want the game to stay fully
playable — and feel intentional, not broken — from a single laptop screen up to
the full rig, and to cope when the monitor topology changes mid-session.

Where things stand today (already in the code):

- **No touchscreen is already solved.** Touch emulation is off both directions
  ([project.godot:128](d:/simpit-game/project.godot)), and every secondary
  widget explicitly handles *both* touch and mouse (`scenes/ui/TouchSlider.gd`,
  `InventoryGrid.gd`, `HullHeatmap.gd`, `StarChart.gd`, plus plain `Button`s).
  A mouse drives all of it. No work is needed here beyond keeping the *new*
  tab strip and assign screen mouse- and keyboard-reachable.
- **Fewer monitors "works" but is clunky and non-consensual.**
  [DisplayConfig.gd:77-99](d:/simpit-game/autoload/DisplayConfig.gd) auto-piles
  overflow roles onto the main screen and
  [WindowManager.gd:52-63](d:/simpit-game/autoload/WindowManager.gd) spawns them
  as small 960×540 **cascaded floating windows** over the fullscreen Main view.
  The player never gets a say in what goes where.
- **Topology changes are boot-only** — a monitor plugged/unplugged mid-session
  isn't picked up without a restart.
- **`tools/ScreenLabeler.gd` already models exactly what we want**: per screen,
  a row of role buttons assigns each role to that screen; multiple roles can
  share a screen; `DisplayConfig.get_roles_for_screen()` reports the grouping;
  `set_role_screen()` persists. It's just a standalone dev tool with no
  "confirm & launch" step and global (not per-setup) persistence.

## Goal (chosen approach)

1. **Ask the player what goes where** the first time a given monitor setup is
   seen (when there aren't enough screens for one-role-per-screen), remember the
   choice per setup, and let a hotkey reopen the chooser. Full control:
   any role on any screen; **two or more roles on one screen group into a tabbed
   host**.
2. Replace the cascade-window fallback with **one reusable tabbed role-host**:
   - roles sharing a **spare** screen → an opaque tab-host filling that screen;
   - roles sharing the **Main** screen → a **dimmed panel overlay** on the live
     Main view, switched one-at-a-time by an on-screen tab strip **and** hotkeys.
3. **Hot-plug:** a key re-reads screens and rebuilds; an unknown new setup
   re-opens the chooser, a known one applies the saved layout — no restart.
4. **4 monitors:** unchanged — four dedicated borderless windows, no prompt.

The tabbed host is one component in two visual modes (dimmed-over-Main vs
opaque-fills-a-window), so "overlay" and "packed onto a spare screen" are the
same system, and the player decides which roles land together.

## Implementation

### 1. Extract each secondary display's content into a reusable Control scene

Today the UI lives in the `Root` Control child of each `Window` scene. Pull that
subtree into its own Control scene so both the standalone window **and** the
tab-host embed identical content.

- New: `scenes/displays/content/TacticalContent.tscn`, `TabletContent.tscn`,
  `ChartContent.tscn` — root Control holding the existing `Background /
  Margin/Layout / … / StatusStrip` subtree (moved verbatim; per-widget scripts
  travel with their nodes, so no script edits).
- Edit `scenes/displays/{TacticalWindow,TabletWindow,StarChartWindow}.tscn`:
  keep the `Window` root (title, `content_scale_*`,
  [RoleWindow.gd](d:/simpit-game/scenes/displays/RoleWindow.gd)); replace the
  inline `Root` with a single **instance** of the matching `*Content.tscn`.
  Standalone-window behavior is unchanged.

### 2. New component: `scenes/displays/RoleTabHost.tscn` + `RoleTabHost.gd`

A Control that hosts 1..N role-content panels and shows one at a time.

- Nodes: `Dim` (semi-transparent black `ColorRect`, toggled), `TabStrip`
  (`HBoxContainer` of `Button`s — one per hosted role, plus a `MAIN` tab in
  overlay mode), `PanelHolder` (holds the active content instance).
- API: `add_role(role, content_scene)` (instantiate once, hidden),
  `show_role(role)` (swap visible panel + raise `Dim`), `show_main()`
  (hide panel + `Dim`), `set_opaque(bool)` (spare-screen mode: solid background,
  no `Dim`, no `MAIN` tab).
- Input in `_input()`: `F1/F2/F3` → select first/second/third hosted role,
  `Tab` → cycle, backtick (`` ` ``) → toggle/hide. **Not `Esc`** — it's the Quit
  key ([RoleWindow.gd:15](d:/simpit-game/scenes/displays/RoleWindow.gd) and the
  keyboard fallback). Content instances persist hidden, so per-panel state
  survives switches. `TabStrip` sets `mouse_filter` so it only eats clicks in its
  own rect (flight input via `InputRouter._process` polling is never blocked).

### 3. In-game Display Setup screen (adapt `tools/ScreenLabeler`)

Turn the ScreenLabeler model into a bootable chooser the game can show before it
spawns the play windows, and reuse it for the hotkey re-open.

- New: `scenes/displays/DisplaySetup.gd` (+ `.tscn`), factored from
  [ScreenLabeler.gd](d:/simpit-game/tools/ScreenLabeler.gd): a labeled,
  numbered overlay per screen (`_build_overlay`) with the per-screen role buttons
  that call `DisplayConfig.set_role_screen(role, screen)`, plus the live
  `get_roles_for_screen()` summary. Add:
  - a **pre-filled suggested layout** (the current auto-default) so the common
    case is one confirming click;
  - a **START / CONFIRM** button that validates every role is assigned (Main
    required), saves the layout for the current setup, and emits `confirmed`;
  - grouping is expressed naturally — assigning 2+ roles to one screen *is* the
    tab-host group; a small hint notes "2+ on one screen share a tabbed panel
    (dimmed overlay on the Main screen)".
- `tools/ScreenLabeler.tscn` stays as the standalone dev tool (can become a thin
  wrapper around the shared overlay builder to avoid duplication).

### 4. Per-setup persistence + when to prompt — `autoload/DisplayConfig.gd`

Make the saved mapping keyed by monitor setup, and expose whether the current
setup is already configured.

- Add `_topology_signature()` → a stable string from
  `DisplayServer.get_screen_count()` + each screen's `screen_get_size` /
  `screen_get_position` (so different arrangements don't collide; handles the
  spacedesk index-shuffle case the README warns about).
- Store layouts per signature: config sections keyed `[layout:<sig>]` with
  `role=screen` entries (replacing the single `[roles]` section;
  `save()`/`reload()` read+write the current signature's section).
- `has_layout_for_current_setup() -> bool`.
- `needs_setup_prompt() -> bool` = `screen_count < ALL_ROLES.size()` **and not**
  `has_layout_for_current_setup()`. (≥4 screens → each role gets its own screen
  by default, no prompt, as today.)
- `_fill_defaults()` stays as the *suggested* pre-fill for the chooser and the
  no-prompt path; keep the stale-index guard.

### 5. Orchestrate & rework `autoload/WindowManager.gd`

Replace the `_claimed_screens`/`_cascade` cascade branch (lines 15-64) with:

- Track spawned nodes (`_windows`, `_hosts`) for teardown.
- `_setup()`: if `DisplayConfig.needs_setup_prompt()` → instance `DisplaySetup`,
  show it (over the already-loaded Main window + labeled overlays on other
  screens), and defer `_place_all()` until its `confirmed` signal. Otherwise call
  `_place_all()` immediately.
- `_place_all()` (data-driven from `DisplayConfig.get_roles_for_screen()`):
  - Main window → fullscreen on Main's screen
    ([WindowManager.gd:39-44](d:/simpit-game/autoload/WindowManager.gd), kept).
  - For each screen, look at its non-main roles:
    - **exactly one, on a non-Main screen** → full-coverage borderless `Window`
      (`_spawn_window`, kept).
    - **two or more, on a non-Main screen** → `RoleTabHost` inside a borderless
      full-coverage `Window` on that screen, `set_opaque(true)`.
    - **any role(s) on the Main screen** → a single `RoleTabHost` added into the
      primary window via a `CanvasLayer` over `MainViewWindow`, dimmed overlay,
      `MAIN` tab shown.
- Hotkeys in `_unhandled_input()`:
  - `F5` **re-detect**: free `_windows`/`_hosts`, `DisplayConfig.reload()`, then
    `_setup()` — which re-prompts if the new setup is unknown, else applies its
    saved layout.
  - `F6` **open Display Setup**: show the chooser on demand; on `confirmed`,
    rebuild via `_place_all()`.
- Add `redetect_displays` (`F5`) and `open_display_setup` (`F6`) actions to the
  `[input]` section of `project.godot`, following the existing action pattern.

### Files touched

- New: `scenes/displays/content/{Tactical,Tablet,Chart}Content.tscn`,
  `scenes/displays/RoleTabHost.tscn` + `.gd`,
  `scenes/displays/DisplaySetup.tscn` + `.gd`
- Edit: `scenes/displays/{TacticalWindow,TabletWindow,StarChartWindow}.tscn`
  (inline `Root` → content instance)
- Edit: `autoload/WindowManager.gd` (orchestration + tab-host placement + hotkeys)
- Edit: `autoload/DisplayConfig.gd` (per-setup persistence, prompt gate)
- Edit (optional dedup): `tools/ScreenLabeler.gd` → wrap shared overlay builder
- Edit: `project.godot` (`redetect_displays`, `open_display_setup` actions)
- Update: `README.md` "Simpit / multi-display setup" + "Running" to describe the
  chooser, F1–F3/backtick/Tab panel controls, and F5/F6.

## Verification

Run `scenes/boot/Boot.tscn` in **Godot 4.7 (Forward+)**.

- **4 monitors (regression):** four dedicated borderless windows, no chooser.
- **First run on < 4 monitors** (disconnect to fewer screens, *or* delete
  `user://display_config.cfg`): the **Display Setup** chooser appears with a
  pre-filled suggestion; assign roles per screen (put 2+ on one screen to prove
  grouping), press START, and confirm the game lays out to match — a shared spare
  screen shows an opaque tab-host; roles on the Main screen show as a **dimmed
  overlay** switched by `F1/F2/F3`, the tab strip (click/tap), and backtick.
- **Second run, same setup:** no prompt — the saved layout is applied straight
  away. **Different monitor count/arrangement:** prompts again.
- **No-touch path:** with a mouse only, drag the power sliders and click a wreck
  member to select a cut target inside the overlay; with keyboard only, switch
  panels via `F1/F2/F3`.
- **Hot-plug:** while running, change monitors and press **F5** — a known setup
  re-lays-out silently; an unknown one re-opens the chooser. Press **F6** anytime
  to re-open the chooser and rebuild on confirm.
- Optionally extend the `tools/Phase5Smoke.tscn` pattern with a headless check
  that `_place_all()` produces the expected windows/hosts for a given
  `DisplayConfig` mapping at screen counts 1–4.
