# Fix the hull camera position & ship orientation

## Context

The main-display hull camera is meant to be a **nose forward-cam**: mounted just
ahead of and slightly above the ship's nose, looking forward toward the target,
with the ship's own nose peeking into the bottom-center of the frame for grounding
(plan Phase 2 — "free-look hull camera feed, edge-to-edge").

It's currently wrong in two ways, both confirmed by rendering
[ScreenshotCheck.tscn](tools/ScreenshotCheck.tscn):

1. **Camera sits on top of / to the right of the ship.** In
   [Ship.tscn](scenes/world/Ship.tscn), the `HullCameraRig` is instanced at the
   ship origin with no transform, and its `Camera3D` has no local offset — so the
   camera's optical center is at `(0,0,0)`. Meanwhile the hull mesh is pushed down
   and back (`position = (0, -2.05, 0.4)`). The result: the camera is *above* the
   hull and, because the Kenney `craft_miner` model's origin isn't centered, off to
   one side — the ship only clips into the **bottom-left corner** of the frame, and
   most of the body is *behind* the camera.
2. **Ship model looks backwards.** The hull is yawed 180° (`rotation = (0, π, 0)`),
   which points its nose the wrong way relative to travel/view direction (−Z).

Goal: reposition the camera to a nose-forward vantage and orient the hull so its
nose leads into −Z, so the forward view is clean and centered with the nose grounding
the bottom of the frame.

## Changes

All edits are in **[scenes/world/Ship.tscn](scenes/world/Ship.tscn)** — no script
changes needed. The glance behavior in
[HullCameraRig.gd](scenes/world/HullCameraRig.gd) already rotates yaw→pitch about the
rig root, so placing the rig root at the camera vantage makes glancing a pure
look-around pan (correct for a fixed hull cam) rather than an orbit around the ship.

1. **Move the whole `HullCameraRig` instance to the nose-forward vantage.** Give the
   instanced rig node a transform placing it ahead of and slightly above the nose,
   still facing −Z. Keep `Yaw`, `Pitch`, and `Camera3D` at local zero so the glance
   pivot coincides with the camera's optical center.
   - Starting estimate: `position = Vector3(0, -1.5, -2.5)` (above the hull's
     vertical center of −2.05; ahead of the nose in −Z). Tune so the nose just peeks
     into the bottom-center.

2. **Correct the hull orientation.** Adjust the `Hull` node's `rotation.y` so the
   nose points −Z (the direction the camera looks and the ship travels). Most likely
   this means removing the 180° (`rotation = Vector3(0, 0, 0)`), but the exact value
   is verified empirically in step 4 — the Kenney model's native forward decides it.

3. **Re-center in X if needed.** After fixing facing, if the hull still sits
   left/right of center (the model-origin offset), nudge the `Hull` node's
   `position.x` so the visible body is centered under the reticle. Keep the camera
   itself at `x = 0`.

## Verification

Re-render both framings with the existing tool and eyeball them (no project files are
modified by the tool — it writes a PNG to a temp path):

```
godot --path . res://tools/ScreenshotCheck.tscn ++ <out>/arrival.png
godot --path . res://tools/ScreenshotCheck.tscn ++ <out>/close.png close
```

Check:
- **Arrival** (ship at identity, wreck 40 m ahead): the target/wreck is centered and
  unobstructed; the ship's nose peeks into the bottom-center (not the corner); the
  hull reads nose-forward, not reversed.
- **Close** (parked at cutting range): the working view of the wreck is clean and the
  nose still grounds the bottom without blocking the reticle.
- Iterate the step-1 `position` and step-2/3 hull transform until the framing matches
  the "Nose forward-cam" intent, then confirm live in the running app so the
  hat-driven glance pans the view correctly about the new vantage.
