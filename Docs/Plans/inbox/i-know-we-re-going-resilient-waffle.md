# Give the wreck a shared hull skin — so cutting reads as removing a piece from a whole

## Context

**Problem.** The derelict frigate doesn't read as *one thing*. It's a loose formation
of discrete Kenney kit props (a cargo pod, two corridors, a chimney, two platforms,
an antenna, a pipe truss) floating near each other with visible air gaps and no
connective geometry. Cutting a member just flips its node `visible = false`
(`Wreck.gd:_apply_member`, line ~86), so even a perfect cut reads as "one of the
scattered props disappeared," never "a piece came off a whole." There is no whole
on screen for the cutter to divide.

**Chosen direction (user).** A **shared hull skin**: a continuous central hull body
that reads as the ship's "main body," with the other members as appendages hanging
off it. Build the whole first; let cutting divide it.

**Constraints discovered during exploration.**
- **Custom modeling IS allowed** (clarified by user). The `simpit-plan.md:86`
  *"no modeling"* note reflected the user's own lack of modeling skill, not a
  project prohibition — Claude may author custom geometry (Blender, or scripted
  mesh generation). **Reusing existing kit props is still preferred where they fit**;
  model only the continuous hull that no prop provides.
- **No monolithic hull prop** exists in `assets/cc0/kenney-space-kit/` (39 props,
  all modular). Closest whole-body pieces are the small `craft_*` shells — none a
  continuous skin. So the continuous body must be authored.
- **Two shared hull materials already exist and are wired to nothing**:
  `scenes/world/materials/hull_plating.tres` (dark metallic) and `hull_panel.tres`
  (lighter). Almost certainly authored for this and never applied.
- **Collision needs no code change** if the hull is built from `MeshInstance3D`
  nodes: `Wreck.gd:_bake_hull` (line ~151) already collects every member node's
  `MeshInstance3D` children into that member's convex hull. An imported `.glb`
  hull (or a generated ArrayMesh) is composed of MeshInstance3D nodes, so it's
  picked up automatically — same as the kit props today.
- **End-state is relaxed** (clarified by user): the wreck **resets completely on
  every revisit** (treat each visit as a brand-new site), so a leftover hull is no
  longer a correctness problem. We still **partition the centerline into cuttable
  sections** — not for persistence now, but because that's what makes the cutter
  *carve the main body* instead of only shedding appendages, which is the actual
  goal.

## Approach

Turn the four **centerline members** — `HullFore` (nose) → `Spine` (midbody) →
`HullAft` → `EngineBell` (tail), which already run fore-aft down the z-axis and are
the load-bearing core in `MEMBER_TABLE` — into contiguous sections of **one
continuous plated fuselage**, and bolt the side appendages (`PanelA`, `PanelB`,
`Antenna`) flush onto it. Nothing about the salvage graph, cut mechanic, collapse,
or collision system changes — the members stay the same nodes; only their child
geometry and transforms change, and `_bake_hull` re-derives collision for free.

Cutting a centerline member then removes a **fuselage-shaped chunk of the continuous
body → a hole in the hull** = "removed a piece from the whole." Cutting an appendage
detaches it from the visible body. Full strip / collapse still empties the site.

**Geometry technique: one authored continuous hull mesh, split into member-named
sub-objects.** Model the frigate as a *single* continuous fuselage form, then split
it into sub-meshes named to match the member nodes (`Spine`, `HullFore`, `HullAft`,
`EngineBell`, plus attached `PanelA`/`PanelB`/`Antenna`). Export to `.glb` and
instance it into `Wreck.tscn` under those member nodes — because the sub-objects
carry the member names, `Wreck.gd`'s graph-mirroring (`_apply_member`) and
`_bake_hull` collision map onto it with **no code change**. Skin with the existing
`hull_plating.tres` / `hull_panel.tres`. Continuity is guaranteed because the hull
was modeled as one ship, not assembled from gapped props.

**Authoring pipeline (reproducible, repo-friendly).** Generate the hull from a
*script* checked into the repo, not a hand-edited binary blob:
- **Preferred:** a Blender headless Python script (`blender --background --python
  build_hull.py`) that builds the fuselage + named sub-objects and exports the
  `.glb`. Verify Blender is installed on this machine as the first implementation
  step.
- **Fallback (if no Blender):** a Godot `@tool` script generating the hull as an
  `ArrayMesh` (or `CSGCombiner3D` baked to mesh) directly in the scene.
Either way the source generator lives in the repo so the hull is regenerable.
**Reuse kit props as bolt-on detail** on the modeled skin (chimney→engine nozzle,
`craft_cargoA`→nose housing, `RingA/RingB`→structural hull ribs, dish/mast on the
appendages) — modeling fills only the continuous connective mass no prop provides.

## Changes

**New hull generator + asset** (the bulk of the work):
- **`tools/build_hull.py`** (or a Godot `@tool` generator — see technique above):
  builds a continuous frigate fuselage modeled as one form, split into member-named
  sub-objects — centerline `Spine` / `HullFore` / `HullAft` / `EngineBell` as
  contiguous hull sections (no z-gaps), plus `PanelA` / `PanelB` / `Antenna` as
  flush-attached appendages. Exports the `.glb`.
- **`assets/cc0/derelict-frigate/frigate_hull.glb`** (Claude-authored → CC0 folder):
  the generated hull. New license-segregated subfolder, consistent with the existing
  `assets/cc0/…` convention.

**`scenes/world/Wreck.tscn`** (rewire to the new hull):
- Instance the modeled hull's member-named sub-meshes under the existing `Spine` /
  `HullFore` / `HullAft` / `EngineBell` / `PanelA` / `PanelB` / `Antenna` nodes so
  the salvage graph still maps 1:1. Skin with `hull_plating.tres` /
  `hull_panel.tres`.
- **Reuse kit props as bolt-on detail** on the skin: `chimney_detailed` → engine
  nozzle at the tail; `craft_cargoA` → nose housing; `RingA`/`RingB` → structural
  hull ribs; `satelliteDish`/`machine_wireless` → antenna appendage detail. Drop
  props that were only standing in for absent hull mass (the bare `pipe_straight`
  truss, floating corridors).
- Tighten appendage transforms so radiators/mast meet the fuselage surface (kill the
  x-gaps); retint toward the hull material family.
- Beacon/BeaconLight unchanged.

**`scenes/world/materials/hull_plating.tres` / `hull_panel.tres`:** apply as-is;
tweak roughness/albedo only if the fuselage reads too uniform.

**No code changes expected** in `Wreck.gd` or `SalvageSystem.gd`. Confirm during
verification that `_bake_hull` produces a sane convex hull per member sub-mesh (a
fuselage section is roughly convex, so per-member hulls stay tight).

**`README.md`** (required by CLAUDE.md — player-visible visuals changed):
- Update the Main-display **screenshot alt-text + caption** (lines ~13–19) and the
  **The four displays** Main row (line ~32) so the derelict is described as a
  continuous hulled frigate, not implied loose parts. Capture a fresh screenshot.
- The gameplay-loop prose (lines ~87–135: members, seam "sits on the actual hull")
  stays true — do **not** rewrite it.

## Explicitly out of scope (user's separate roadmap)

- Detach/drift physics on a severed piece; velocity imparted by collisions.
- The post-cut collection mini-game.
- A deeper pass partitioning *every* prop into the continuous skin (possible later;
  this pass does the centerline fuselage + flush appendages).

## Verification

0. **Hull generates & imports.** Confirm Blender is available
   (`blender --version`); if not, take the Godot `@tool` ArrayMesh fallback. Run the
   generator, confirm `frigate_hull.glb` imports into Godot with the expected
   member-named sub-meshes.
1. **Launch the game** (via the `/run` skill or the project's normal run path) and
   look at the wreck: does it read as one hulled body with appendages, not scattered
   props? Check for remaining air gaps between centerline sections.
2. **Cut a centerline member** (scan → select `FORE HULL` or `AFT HULL` → approach →
   align → cut). Confirm the severed section leaves a **hull-shaped hole in a
   continuous body**, not just a vanished prop.
3. **Cut / collapse to empty.** Strip all members (or trigger collapse) and confirm
   the site fully clears and `reset_site()` regenerates a fresh whole wreck — no
   leftover permanent hull.
4. **Collision still holds.** Fly the ship into the rebuilt hull; confirm it's solid
   (uses `_bake_hull`'s per-member convex hulls). The `CollisionSmoke` and
   `AlignSmoke` tool scenes are the existing quick checks.
5. **Tumble/seam still track.** Confirm the tumble spins the new hull as one body and
   the cut seam still lands on the member surface (`Wreck.gd:_publish_world`).
