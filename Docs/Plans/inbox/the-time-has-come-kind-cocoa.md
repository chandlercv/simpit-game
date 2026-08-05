# Post-cut salvage collection mini-game

## Context

Today a completed cut is anticlimactic: `SalvageSystem._complete_cut()` flips
`member["cut"]=true`, `Wreck._apply_member()` simply *hides* the severed section,
and the yield teleports straight into the hold via `CargoSystem.stow_salvage()`.
There is no physical severed piece, no drift, and no collection step — cutting is
the whole game and the reward is abstract.

This change inserts a real second act between severing and stowing: a cut
**detaches a drifting piece** you must then chase down and scoop. It leans on the
existing hand-integrated simulation (no Godot physics anywhere) and the proven
"movable collidable body = a dict in `GameState.obstacles` re-published each frame"
pattern used by `Wreck.gd` and `DebrisField.gd`.

Confirmed design decisions:
- **Collection is demanding**: hatch open **+** within scoop range **+** relative
  velocity nulled **+** piece inside a forward hatch cone, held for a short scoop.
- **The hatch is a real decision**: firing the cutter and jumping/docking are
  blocked while it's open, so you open it only to collect, then re-secure.
- **Adrift pieces are free-for-all**: whoever reaches a piece first collects it —
  you can steal the rival's cuts and it can steal yours.
- **Collisions impart velocity to debris**, salvage pieces *and* the atmospheric
  debris chunks, so the field is knockable.

## Simulation conventions to honor (already in the codebase)

- 3D, `Node3D`, `-transform.basis.z` = fore, reticle field `+x` screen-right /
  `+y` screen-down.
- Motion is hand-integrated: a system writes `transform`/`velocity` into
  `GameState`, view nodes mirror it. `CollisionSystem` runs **last** as a
  post-integration proximity pass and today only moves the *ship*.
- State lives in `GameState`, mutated only by `systems/*.gd`; world nodes read
  state and register collision bodies. Fan-out via `*_changed` signals.

---

## 1. New state in `autoload/GameState.gd`

- `var salvage_pieces: Array[Dictionary] = []` — the drifting collectibles. Each
  piece (replication-friendly, mirrors the `ships` shape):
  `{ "id", "member_id", "name", "good", "qty" (already quality-scaled),
     "transform": Transform3D, "velocity": Vector3, "omega": Vector3,
     "radius": float, "obstacle_id": int, "scoop": float 0..1, "node": String }`.
- `var cargo_hatch_open := false`.
- Signals: `salvage_pieces_changed`, `salvage_piece_spawned(id)`,
  `salvage_piece_removed(id)`, `cargo_hatch_changed(open)`.
- Hatch intents: `set_cargo_hatch(open)` / `toggle_cargo_hatch()` (emit signal +
  `post_comms`).
- Make obstacles **movable**: add optional `vel := Vector3.ZERO` and
  `mass := 0.0` params to `register_obstacle()` (stored on the dict; `mass > 0`
  marks a body `CollisionSystem` may push). Existing callers (`Wreck`, `DebrisField`)
  are unaffected because the wreck stays immovable (mass 0) unless a chunk is a
  drift body.
- Small helpers: `get_salvage_piece(id)`, `add_salvage_piece(dict)`,
  `remove_salvage_piece(id)`.

## 2. New autoload system `systems/DriftSystem.gd`

Owns the adrift-piece lifecycle, drift integration, and the collection
interaction. Registered in `project.godot` **between `ThreatSystem` and
`CollisionSystem`** so pieces integrate before collision resolves (same ordering
logic as ship vs. `CollisionSystem`).

- `spawn_piece(member: Dictionary, quality: float) -> int` — called by
  `SalvageSystem._complete_cut`. Seeds a piece dict:
  - pose from the member's baked world `center`/`seam`/current basis,
  - `velocity = member.vel` (its orbital `ω×r` at cut instant) **+** a small
    outward `SEPARATION_KICK` along the seam-from-centroid normal,
  - `omega` a gentle random tumble (reuse the `TUMBLE_RATE_*` band),
  - `qty` = quality-scaled yield (moved here from `_complete_cut`),
  - registers a **movable sphere obstacle** (`radius`, `mass ∝ radius³`) and a
    sensor contact (`register_contact("SALVAGE: %s", …, radius 0)`) so it shows on
    Tactical, mirroring how wreck/debris keep a sensor blip separate from the solid
    body. Emits `salvage_piece_spawned`.
- `_process(delta)` (guard `ON_SITE`): for each piece
  `transform.origin += velocity*delta`; rotate basis by `omega`; clamp
  `velocity` to `MAX_DRIFT_SPEED`; write pose into its obstacle dict (position +
  a re-transformed sphere; pieces collide as spheres — simpler than hulls and
  they read as chunky). Then run `_update_collection`.
- `_update_collection(delta)` — the **player** scoop, per piece:
  gates = `GameState.cargo_hatch_open`
  **and** ship-to-piece surface distance `< SCOOP_RANGE`
  **and** relative speed `(ship.velocity - piece.velocity).length() < COLLECT_REL_SPEED`
  **and** piece inside the forward cone (`(-ship.basis.z).dot(dir) > cos(COLLECT_CONE)`).
  All true → `scoop += delta/SCOOP_TIME`, else decay. At `scoop >= 1`:
  `CargoSystem.stow_salvage(name, good, qty)`; on success remove the piece (+
  obstacle + contact, emit `salvage_piece_removed`); on hold-full leave it adrift
  and post the existing "HOLD FULL" line.
- `collect_for_rival(piece_id)` — `ThreatSystem` entry point: despawn the piece
  (yield kept by the rival narratively), emit removed.
- Listen to `site_reset` → clear all pieces/obstacles/contacts. Pieces already
  severed **survive** a frame collapse (they're free of the frame); only
  `trigger_collapse`'s uncut members are lost (unchanged).
- Runs headless (sphere math only); the visual node in §6 is optional.

## 3. Collisions impart velocity — `systems/CollisionSystem.gd`

- `_collidables()`: for each body carry `mass`, `vel`, and `src` (the live
  obstacle dict) so momentum can be written back.
- Ship-vs-body (existing loop): when the body is movable (`mass > 0`), in addition
  to bouncing the ship, apply an impulse to `src["vel"]` along the contact normal —
  ship treated as heavy (`SHIP_MASS` const), so the light piece/chunk takes a
  believable kick: `Δv ≈ (1+RESTITUTION) * closing`, capped. Ship damage on impact
  is unchanged (ramming a severed spar still hurts).
- New `_resolve_movable_pairs()` after the ship pass: O(n²) over movable bodies
  only (~10–15), sphere–sphere — separate along the center line weighted by inverse
  mass and exchange the normal velocity component with `RESTITUTION`, writing back
  to each `src["vel"]`. This lets a drifting salvage piece knock atmospheric debris
  and vice versa.
- Owners integrate positions from the `vel` written here (next frame), matching the
  ship↔SalvageSystem split.

## 4. Atmospheric debris becomes knockable — `scenes/world/DebrisField.gd`

- Register each chunk obstacle with a `mass` (from its bounding radius) so
  `CollisionSystem` can push it; add a per-chunk `vel` field (starts zero).
- `_process`: read `obstacle["vel"]`, `chunk.global_position += vel*delta` (plus
  the existing tumble), apply light linear damping so a knocked chunk eventually
  settles rather than drifting away forever, then re-publish position + world hull
  as it already does. Chunks now drift when hit but otherwise sit as before.

## 5. Cut → detach — `systems/SalvageSystem.gd` (+ `Wreck.gd` unchanged)

- `_complete_cut(member)`: keep the cut flag, stress, and `wreck_member_cut`
  emit; **replace** the direct `CargoSystem.stow_salvage(...)` call with
  `DriftSystem.spawn_piece(member, quality)`. Yield is now delivered on
  *collection*, not on cut.
- `rival_strip_member()`: same swap — after flipping `cut`, call
  `DriftSystem.spawn_piece(member, 1.0)` and return the piece id so `ThreatSystem`
  can chase it. The severed section still vanishes from the hull via the existing
  `Wreck._apply_member` (which hides the node on `wreck_member_cut`) — the drifting
  visual is a separate node (§6), so **`Wreck.gd` needs no change**.
- **Hatch interlock**: `request_cut()` aborts early when
  `GameState.cargo_hatch_open` — `post_comms("OPS", "SECURE CARGO HATCH BEFORE CUTTING")`.

## 6. Drifting-piece visuals — `scenes/world/SalvagePieces.gd` (new)

A view-only manager node added to `DebrisField.tscn` (the gameplay world root),
sibling to `Wreck`/`Debris`. On `salvage_piece_spawned` it **duplicates** the
matching Wreck member's mesh subtree (looked up by the piece's `node` name via a
tiny `Wreck.member_visual(node_name)` helper) as a free-floating drift visual, and
each frame sets that duplicate's `global_transform` from the piece's `transform`.
Frees on `salvage_piece_removed` / `site_reset`. Duplicating (not reparenting)
leaves Wreck's baked hulls and reset logic untouched. Headless smoke runs without
this node.

## 7. Cargo-hatch control (keybind + COWL switch)

- `project.godot` `[input]`: add `cargo_hatch_open={ "deadzone":0.2, "events":[] }`.
- `autoload/InputRouter.gd`: dispatch in `_process` —
  `if Input.is_action_just_pressed("cargo_hatch_open"): GameState.toggle_cargo_hatch()`;
  add a default keyboard bind (an unused key, e.g. **B**) to the `keyboard` entry in
  `BUILTIN_PROFILES`.
- `systems/hardware/SwitchPanelBridge.gd` `_route_intent()`: add
  `"COWL": GameState.set_cargo_hatch(on)` (level: hatch open while COWL is ON).
- `scenes/displays/ControlsSetup.gd` `BUTTON_TARGETS`: add
  `{"label":"Open Cargo Hatch","action":"cargo_hatch_open","group":"OPS"}` so it
  shows in the F7 remapper.

## 8. Jump/dock interlock — `systems/MarketSystem.gd`

Guard the leave-site intents (`request_dock` / `request_undock`, whichever performs
the jump): if `GameState.cargo_hatch_open`, block with
`post_comms("OPS","SECURE CARGO HATCH BEFORE JUMP")`. (Confirm exact function names
when editing.)

## 9. HUD — `scenes/ui/HUDOverlay.gd`

Reuse the `_draw_target_member` marker idiom for adrift pieces:
- Draw each `GameState.salvage_pieces` entry in frame: a distinct salvage-colored
  bracket/diamond + name + range; edge arrow when off-frame.
- When the hatch is open and a piece is near: a collection panel showing **REL SPD**
  (relative velocity magnitude), a cone/aim hint, and a **scoop ring** filling with
  `piece.scoop` (mirrors the align lock ring). Cue text like
  `MATCH & CENTER — SCOOP` vs `SECURE-SPEED` / `OFF-AXIS` when a gate is unmet.
- Persistent `HATCH OPEN` indicator (subtle, e.g. near the ops banner) so the pilot
  knows cutting/jumping are inhibited.

---

## Files touched (summary)

New: `systems/DriftSystem.gd`, `scenes/world/SalvagePieces.gd` (+ node in
`scenes/world/DebrisField.tscn`), `tools/DriftSmoke.gd`/`.tscn`.
Modified: `autoload/GameState.gd`, `autoload/InputRouter.gd`, `project.godot`
(autoload + input action), `systems/SalvageSystem.gd`, `systems/ThreatSystem.gd`
(§10 below), `systems/CollisionSystem.gd`, `systems/MarketSystem.gd`,
`systems/hardware/SwitchPanelBridge.gd`, `scenes/displays/ControlsSetup.gd`,
`scenes/world/DebrisField.gd`, `scenes/ui/HUDOverlay.gd`, `README.md`.

## 10. Rival parity — `systems/ThreatSystem.gd`

Rework `_update_rival` from "strip on a timer, yield vanishes" into a state
machine that mirrors the player's required actions: **APPROACH → CUT → COLLECT**,
looping until the frame is stripped, then **DEPART** (existing).
- APPROACH: fly the contact to the wreck (existing).
- CUT: within `RIVAL_WORK_RANGE`, every `RIVAL_STRIP_INTERVAL` call
  `rival_strip_member()` (which now spawns an adrift piece); store the returned
  piece id and enter COLLECT.
- COLLECT: steer the contact toward the piece's live position; within
  `RIVAL_COLLECT_RANGE` for a short dwell → `DriftSystem.collect_for_rival(id)`,
  then back to CUT. Because pieces are free-for-all, if the tracked piece is gone
  (player scooped it first), abort COLLECT and resume CUT.
This gives the rival the same two-phase "sever then physically retrieve" loop the
player has (it skips only the alignment crosshair), and makes contested pieces a
real race.

## Verification

Headless smoke (follow the `tools/CollisionSmoke.gd` / `Phase5Smoke.gd` pattern —
autoload-driven, no 3D scene, assert-and-print), added as `tools/DriftSmoke.gd`:
1. **Detach**: force a cut; assert a piece appears in `salvage_pieces` with
   nonzero `velocity`, and that `stow_salvage` did **not** fire on cut.
2. **Momentum**: drive the ship into a piece / a debris chunk at speed; assert the
   body's `vel` gains velocity along the normal (ship still bounces), and that a
   moving piece knocks a chunk (movable-pair pass).
3. **Collection gates**: with hatch closed / mismatched speed / off-axis, assert no
   scoop; with hatch open + speed matched + nose-on, assert `scoop→1` then
   `stow_salvage` fires and the piece is removed.
4. **Interlocks**: hatch open ⇒ `request_cut` aborts and the jump intent is blocked.
5. **Rival**: force `rival_strip_member`; assert a piece spawns and
   `collect_for_rival` removes it; assert the player can scoop a rival-cut piece.

Manual (via the `run` skill / normal launch): scan → approach → align → cut and
watch the section detach and drift; open the hatch (key **B** or the COWL switch —
note cutting is now inhibited), fly alongside the tumbling piece, null relative
speed with the nose on it, and confirm the scoop ring fills and the item stows.
Bump a debris chunk and watch it drift. Confirm the README Controls/HUD/loop
sections match what you press and see.

## README updates (required by CLAUDE.md)

- **Switch Panel** table: add a **COWL** row ("Open/close cargo hatch") and remove
  COWL from the "decoded and logged but have no gameplay effect yet" sentence.
- **Keyboard** table: add the cargo-hatch default key (**B**).
- **Main flight HUD** section (+ screenshot caption/alt text): document the adrift
  salvage markers, the collection cue/scoop ring, and the HATCH OPEN indicator.
- **Core gameplay loop**: describe cut → detach → drift → open hatch → match &
  scoop, that the hatch blocks cutting/jump while open, and that adrift pieces are
  contested with the rival.
