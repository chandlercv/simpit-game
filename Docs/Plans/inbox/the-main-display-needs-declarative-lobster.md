# Main-display nose reticle + velocity vector indicator

## Context

The hull-camera HUD currently draws a **fixed** reticle at screen center
([HUDOverlay.gd:125](scenes/ui/HUDOverlay.gd#L125) `_draw_reticle()`). Because the
glance system rotates only the camera gimbal (Yaw/Pitch nodes under
[HullCameraRig.gd](scenes/world/HullCameraRig.gd)) and leaves the hull fixed, a
center-locked reticle actually marks *where you're looking*, not where the nose
points. It gives the pilot no way to see the nose's orientation while glancing,
and no read on the ship's actual direction of travel.

This change makes the HUD show two flight cues, both standard in a cockpit:

1. **Nose reticle** — the reticle projects the ship's nose (forward) direction
   into the camera, so at rest it sits dead center (identical to today) and
   slides off-center as you glance, always marking the nose.
2. **Velocity vector indicator** — a flanking pair of brackets `[ ]` at the
   ship's direction of travel. Pure main-engine thrust drives velocity toward
   the nose, so the brackets converge to frame the reticle: `[ ⊕ ]`. Side
   thrust / drift makes them diverge.

The HUD work is all in one file: [scenes/ui/HUDOverlay.gd](scenes/ui/HUDOverlay.gd)
— no scene or physics changes. Alongside it, this change also updates
[README.md](README.md) to document the new velocity indicator and the (already
merged) throttle-POV strafe/thrust controls, and adds a root `CLAUDE.md` so the
README is kept in sync with future control/HUD changes.

## Key facts (from exploration)

- HUD already holds the live `camera: Camera3D` ([HUDOverlay.gd:16](scenes/ui/HUDOverlay.gd#L16)),
  injected by [MainViewWindow.gd:14](scenes/displays/MainViewWindow.gd#L14). Unprojected
  coords map 1:1 to this Control.
- `_draw()` already uses `camera.unproject_position()` / `camera.is_position_behind()`
  and runs every frame via `_process` → `queue_redraw` ([:45-47](scenes/ui/HUDOverlay.gd#L45)).
- Nose direction (world) = `-GameState.local_ship()["transform"].basis.z`.
- Velocity (world Vector3) = `GameState.local_ship()["velocity"]` — manually
  integrated in [SalvageSystem.gd:319-338](systems/SalvageSystem.gd#L319); zero/near-zero
  when flight-assist damps to rest.
- Glance is bounded to ±60° yaw / ±45° pitch, so the nose is never behind the
  camera; velocity *can* be (reversing / drifting rearward).

## Implementation (all in HUDOverlay.gd)

### 1. Shared projection helper

Add a helper that turns a world-space **direction from the eyepoint** into a
screen point, clamped into the frame so off-fov directions pin to the nearest
edge. Returns `null` when the direction is behind the camera.

```gdscript
const EDGE_MARGIN := 24.0

## Screen point for a world-space direction from the camera eyepoint, clamped
## into the frame (minus a margin) so out-of-fov directions pin to the nearest
## edge. Returns null when the direction is behind the camera.
func _project_direction(dir: Vector3) -> Variant:
    var world_point := camera.global_position + dir.normalized() * 1000.0
    if camera.is_position_behind(world_point):
        return null
    var p := camera.unproject_position(world_point)
    return p.clamp(Vector2(EDGE_MARGIN, EDGE_MARGIN), size - Vector2(EDGE_MARGIN, EDGE_MARGIN))
```

### 2. Repurpose `_draw_reticle()` to follow the nose

Keep the exact circle+ticks glyph; just move its center to the projected nose.
Falls back to screen center if the camera isn't wired yet (preserves the
current call order where `_draw_reticle()` runs before the camera null-guard).

```gdscript
func _draw_reticle() -> void:
    var c := size / 2.0
    if camera != null:
        var nose := -GameState.local_ship()["transform"].basis.z
        var p = _project_direction(nose)
        if p != null:
            c = p
    draw_arc(c, 14.0, 0.0, TAU, 48, HUD_COLOR, 1.5, true)
    for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
        draw_line(c + dir * 22.0, c + dir * 34.0, HUD_COLOR, 1.5)
```

### 3. Velocity vector indicator

New `[ ]` glyph drawer plus a draw method, gated on non-trivial speed and
hidden only when travel is behind the view.

```gdscript
const VEL_EPSILON := 0.05

func _draw_velocity_vector() -> void:
    if camera == null:
        return
    var vel: Vector3 = GameState.local_ship().get("velocity", Vector3.ZERO)
    if vel.length() < VEL_EPSILON:
        return
    var p = _project_direction(vel)
    if p == null:  # travelling behind the view — nothing to bracket
        return
    _draw_flanking_brackets(p, 18.0, HUD_COLOR, 1.5)

## A pair of vertical brackets [ ] flanking `center` — the flight-path marker.
## When travel aligns with the nose these frame the reticle.
func _draw_flanking_brackets(center: Vector2, r: float, color: Color, width: float) -> void:
    var arm := r * 0.5
    for s: float in [-1.0, 1.0]:
        var x := center.x + s * r
        var top := Vector2(x, center.y - r)
        var bot := Vector2(x, center.y + r)
        draw_line(top, bot, color, width)                        # spine
        draw_line(top, top + Vector2(-s * arm, 0), color, width)  # top serif (toward center)
        draw_line(bot, bot + Vector2(-s * arm, 0), color, width)  # bottom serif
```

`s = -1` yields `[` (spine left, serifs point right/inward); `s = +1` yields `]`.

### 4. Wire the velocity draw into `_draw()`

Call `_draw_velocity_vector()` in [`_draw()`](scenes/ui/HUDOverlay.gd#L71) right
after `_draw_reticle()` so the brackets layer over the reticle glyph.

## Notes / decisions

- **Single reticle** that follows the nose (no separate fixed center marker).
- **Flanking `[ ]`** glyph for velocity (not the box `_draw_corner_brackets`).
- **Clamp-to-edge** off-screen: nose reticle is always visible; the velocity
  marker clamps to the edge when travel is ahead-but-out-of-fov and is hidden
  only when travel is behind the camera.
- Both cues use `HUD_COLOR`; the different glyphs (⊕ vs `[ ]`) distinguish them.
  If they read as too similar in-sim, dropping the velocity marker's alpha is a
  trivial follow-up.

## Documentation updates

### 5. README.md — velocity indicator + throttle-POV strafe

The throttle-POV strafe/thrust bindings are now on this branch after the rebase
([InputRouter.gd:44-47](autoload/InputRouter.gd#L44): button 19→`thrust_up`,
20→`strafe_right`, 21→`thrust_down`, 22→`strafe_left`), but the README still
predates them and doesn't mention the new HUD cues. Edits:

- **Screenshot caption** ([README.md:16-17](README.md#L16)) — add the nose reticle
  and velocity vector to the HUD description.
- **New "## The Main flight HUD" section** (right after "## The four displays",
  ~line 34) — a short bullet list of what the Main HUD draws:
  - **Nose reticle** (circle + ticks) — marks where the ship's nose points;
    centered when looking forward, slides toward the nose as you glance, pinning
    to the screen edge on a hard glance.
  - **Velocity vector** (`[ ]` brackets) — marks the ship's direction of travel;
    pure main-engine thrust converges the brackets onto the reticle, side thrust
    / drift splits them off, hidden at rest.
  - **Readouts** — VEL, HDG/EL, and lock brackets + distance on the tracked
    contact (existing behavior, mentioned for completeness).
- **X52 throttle table** ([README.md:92-98](README.md#L92)) — add a POV-hat row:
  hat left/right = strafe, hat up/down = vertical thrust (buttons 19–22, clear of
  the reserved selector bank 23–25).
- **Keyboard-fallback note** ([README.md:126-131](README.md#L126)) — this line
  currently claims "Strafe (A/D) and vertical thrust (R/F) are **keyboard-only**,"
  which the rebase made false. Reword: lateral strafe and vertical thrust are now
  also on the X52 throttle POV hat; A/D and R/F remain the desk fallback; reverse
  thrust is still **S**.

### 6. New root `CLAUDE.md` — keep the README in sync

Create `CLAUDE.md` at the repo root with a concise, actionable instruction that
`README.md` is the source of truth for controls, displays, the flight HUD, and
the gameplay loop, and must be updated in the same change whenever those change.
It maps the code areas to README sections so the rule is concrete:

- Controls/bindings (`autoload/InputRouter.gd` PROFILES, `project.godot [input]`)
  → the relevant Controls table.
- HUD/Main-display indicators (`scenes/ui/HUDOverlay.gd`) → the "Main flight HUD"
  section + screenshot caption.
- Displays/windows, gameplay loop, power channels, simpit setup → the matching
  section.
- Explicitly: when a change makes an existing README statement false, fix that
  line — don't just append (the "strafe is keyboard-only" line is the cautionary
  example).

## Verification

Run the sim (via the `/run` skill or `godot` on `scenes/displays/MainViewWindow.tscn`)
and confirm on the main view:

1. **At rest / forward flight** — reticle sits at screen center. Apply main-engine
   throttle (X52 throttle or `thrust_forward`): the `[ ]` brackets slide in and
   settle framing the reticle → `[ ⊕ ]`.
2. **Glance** (X55 POV hat, or arrow-key `glance_*` fallback) — reticle slides
   opposite the glance to mark the nose; a hard glance pins it at the frame edge.
   The velocity brackets stay on the travel direction independently.
3. **Strafe** (`strafe_left`/`strafe_right`, `thrust_up`/`down`) — velocity
   brackets diverge from the reticle toward the drift direction.
4. **Reverse / hard rearward drift** — velocity brackets disappear (travel behind
   the view); the reticle remains.
5. **Coast to rest** — velocity brackets vanish below `VEL_EPSILON`; no flicker.

**Docs:** confirm the README no longer says strafe is "keyboard-only", the X52
throttle table lists the POV-hat strafe/thrust row, the new "Main flight HUD"
section describes the nose reticle and velocity vector, and `CLAUDE.md` exists at
the repo root. (Optionally re-render the screenshot via `tools/ScreenshotCheck.tscn`
to update `assets/docs/main_view.png` with the new indicators.)
