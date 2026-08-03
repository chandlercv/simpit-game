"""Generate the derelict frigate's continuous hull as member-named section meshes.

Run headless:
    blender --background --python tools/build_hull.py

Why this exists
---------------
The wreck used to be a loose formation of Kenney kit props with air gaps, so a
completed cut read as "a floating prop vanished" rather than "a piece came off a
whole" (see plan: shared hull skin). This builds ONE continuous fuselage as four
contiguous sections — HullFore (nose), Spine (midbody), HullAft, EngineBell (tail) —
sampled from a single radius profile so their shared boundary rings line up exactly
and the surface reads as one body. Each section exports to its own .glb so it can be
instanced under the matching member node in Wreck.tscn; hiding a cut member then
leaves an open hull section (a hole), which is the point.

Coordinate handling
--------------------
Everything below is authored in GODOT space (z = ship long axis, fore at -z to match
HullFore at z<0; y = up; x = starboard). Each vertex is emitted to Blender as
(gx, -gz, gy) so that the glTF "+Y up" export conversion (Blender (x,y,z) -> glTF
(x, z, -y)) reproduces the Godot vertex (gx, gy, gz) exactly. Author in Godot space,
forget the axis swap.
"""

import bpy
import bmesh
import math
import os
import sys

# --- Hull profile (Godot space) -------------------------------------------------
# Radial segments around the longitudinal axis. Higher = smoother, more tris.
N = 16
# Slightly oblate cross-section so the hull reads as a ship body, not a pipe.
HSCALE = 0.82
# radius(z) control points along the ship's z axis (fore = -z). Boundary z values
# -3.5 / 2.5 / 5.5 are shared endpoints between adjacent sections, so the sections
# meet on identical rings.
CTRL = [
    (-6.5, 0.25),   # nose tip
    (-5.0, 1.20),
    (-3.5, 1.85),   # HullFore | Spine boundary
    (-1.0, 2.05),
    (1.0, 2.05),    # bulky midbody
    (2.5, 1.90),    # Spine | HullAft boundary
    (4.0, 1.60),
    (5.5, 1.35),    # HullAft | EngineBell boundary
    (6.5, 1.15),
    (7.5, 0.95),    # engine collar rim (chimney nozzle prop sits here)
]


def radius(z: float) -> float:
    if z <= CTRL[0][0]:
        return CTRL[0][1]
    if z >= CTRL[-1][0]:
        return CTRL[-1][1]
    for i in range(len(CTRL) - 1):
        z0, r0 = CTRL[i]
        z1, r1 = CTRL[i + 1]
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            t = t * t * (3.0 - 2.0 * t)  # smoothstep for a fairer curve
            return r0 + (r1 - r0) * t
    return CTRL[-1][1]


def ring(bm: bmesh.types.BMesh, z: float):
    r = radius(z)
    verts = []
    for s in range(N):
        a = 2.0 * math.pi * s / N
        gx = r * math.cos(a)
        gy = r * math.sin(a) * HSCALE
        gz = z
        verts.append(bm.verts.new((gx, -gz, gy)))  # Godot -> Blender
    return verts


def hull_material() -> bpy.types.Material:
    """A shared metallic hull material matching scenes/world/materials/
    hull_plating.tres (albedo sRGB (0.34,0.36,0.4), metallic 0.85, roughness 0.38).
    Blender base color is linear, so the sRGB albedo is linearized here; the same
    material on every section is what makes the four read as one hull."""
    mat = bpy.data.materials.get("hull")
    if mat is not None:
        return mat
    mat = bpy.data.materials.new("hull")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    # sRGB (0.34,0.36,0.4) -> linear
    bsdf.inputs["Base Color"].default_value = (0.093, 0.106, 0.133, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.85
    bsdf.inputs["Roughness"].default_value = 0.38
    return mat


def panel_material() -> bpy.types.Material:
    """Lighter, less-metallic material for radiators / mast, matching
    hull_panel.tres (sRGB (0.5,0.48,0.44), metallic 0.35, roughness 0.62) — a tonal
    break from the dark hull so the appendages read as distinct removable parts."""
    mat = bpy.data.materials.get("panel")
    if mat is not None:
        return mat
    mat = bpy.data.materials.new("panel")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.212, 0.194, 0.159, 1.0)  # sRGB->linear
    bsdf.inputs["Metallic"].default_value = 0.35
    bsdf.inputs["Roughness"].default_value = 0.62
    return mat


def _finalize(bm: bmesh.types.BMesh, name: str,
              mat: bpy.types.Material) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)  # force outward
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def build_section(name: str, z0: float, z1: float, nrings: int,
                  cap0: bool, cap1: bool) -> bpy.types.Object:
    bm = bmesh.new()
    zs = [z0 + (z1 - z0) * i / (nrings - 1) for i in range(nrings)]
    rings = [ring(bm, z) for z in zs]
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for s in range(N):
            s2 = (s + 1) % N
            bm.faces.new((a[s], a[s2], b[s2], b[s]))
    if cap0:
        bm.faces.new(rings[0])
    if cap1:
        bm.faces.new(rings[-1])
    return _finalize(bm, name, hull_material())


def add_box(bm: bmesh.types.BMesh, cx, cy, cz, sx, sy, sz) -> None:
    """A box centred at Godot (cx,cy,cz) with full extents (sx,sy,sz)."""
    hx, hy, hz = sx / 2.0, sy / 2.0, sz / 2.0
    corners = [
        (cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
        (cx + hx, cy + hy, cz - hz), (cx - hx, cy + hy, cz - hz),
        (cx - hx, cy - hy, cz + hz), (cx + hx, cy - hy, cz + hz),
        (cx + hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz + hz),
    ]
    v = [bm.verts.new((gx, -gz, gy)) for (gx, gy, gz) in corners]  # Godot -> Blender
    for a, b, c, d in [(0, 1, 2, 3), (7, 6, 5, 4), (4, 5, 1, 0),
                       (6, 7, 3, 2), (5, 6, 2, 1), (7, 4, 0, 3)]:
        bm.faces.new((v[a], v[b], v[c], v[d]))


def build_fin(name: str, side: float, zc: float) -> bpy.types.Object:
    """Radiator fin on the ±x flank: three slats rooted just inside the hull surface
    (so no gap) and cantilevered outward. `side` is +1 starboard / -1 port."""
    bm = bmesh.new()
    rx = radius(zc)                       # hull half-width in x at this z (equator)
    x_root = side * (rx - 0.2)            # bite slightly into the hull -> flush
    x_tip = side * (rx + 2.2)
    cx = (x_root + x_tip) / 2.0
    sx = abs(x_tip - x_root)
    for dz in (-0.95, 0.0, 0.95):         # three slats with gaps between them
        add_box(bm, cx, 0.0, zc + dz, sx, 0.16, 0.55)
    add_box(bm, side * (rx + 0.05), 0.0, zc, 0.5, 0.5, 2.6)  # root spar along the hull
    return _finalize(bm, name, panel_material())


def build_mast(name: str, xc: float, zc: float) -> bpy.types.Object:
    """Sensor mast: a slim pylon rising from the dorsal hull (rooted below the
    surface so it reads as attached), with a small cross-spar near the top."""
    bm = bmesh.new()
    top = radius(zc) * HSCALE             # hull top at this z
    base_y = top - 0.4                    # start inside the hull
    tip_y = top + 2.3
    cy = (base_y + tip_y) / 2.0
    add_box(bm, xc, cy, zc, 0.22, abs(tip_y - base_y), 0.22)
    add_box(bm, xc, tip_y - 0.35, zc, 1.3, 0.12, 0.12)   # cross-spar
    return _finalize(bm, name, panel_material())


def build_flare(name: str, z0: float, r0: float, z1: float, r1: float,
                nring: int) -> bpy.types.Object:
    """Open flared cone (engine bell) lofted between two rings; attaches to the
    hull_engine tail. Left open so it reads as a nozzle mouth."""
    bm = bmesh.new()
    zs = [z0 + (z1 - z0) * i / (nring - 1) for i in range(nring)]
    rs = [r0 + (r1 - r0) * i / (nring - 1) for i in range(nring)]
    rings = []
    for z, r in zip(zs, rs):
        verts = []
        for s in range(N):
            a = 2.0 * math.pi * s / N
            verts.append(bm.verts.new((r * math.cos(a), -z, r * math.sin(a) * HSCALE)))
        rings.append(verts)
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for s in range(N):
            s2 = (s + 1) % N
            bm.faces.new((a[s], a[s2], b[s2], b[s]))
    return _finalize(bm, name, hull_material())


def export(ob: bpy.types.Object, path: str) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
    )
    print("wrote", path)


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)

    script_path = os.path.realpath(__file__)
    repo_root = os.path.dirname(os.path.dirname(script_path))
    out_dir = os.path.join(repo_root, "assets", "cc0", "derelict-frigate")
    os.makedirs(out_dir, exist_ok=True)

    # name, z0, z1, rings, cap_fore, cap_aft
    sections = [
        ("HullFore", -6.5, -3.5, 6, True, False),
        ("Spine", -3.5, 2.5, 8, False, False),
        ("HullAft", 2.5, 5.5, 5, False, False),
        ("EngineBell", 5.5, 7.5, 3, False, True),
    ]
    files = {
        "HullFore": "hull_fore.glb",
        "Spine": "hull_spine.glb",
        "HullAft": "hull_aft.glb",
        "EngineBell": "hull_engine.glb",
    }
    for name, z0, z1, nrings, cap0, cap1 in sections:
        ob = build_section(name, z0, z1, nrings, cap0, cap1)
        export(ob, os.path.join(out_dir, files[name]))

    # Appendage members, modelled flush against the hull surface (verts already in
    # wreck space, so each instances at identity under its member node).
    export(build_fin("PanelA", 1.0, -1.0), os.path.join(out_dir, "panel_a.glb"))
    export(build_fin("PanelB", -1.0, 1.5), os.path.join(out_dir, "panel_b.glb"))
    export(build_mast("Antenna", -0.4, -3.2),
           os.path.join(out_dir, "antenna_mast.glb"))
    export(build_flare("EngineFlare", 7.4, 0.95, 8.5, 1.45, 4),
           os.path.join(out_dir, "engine_bell.glb"))

    print("hull generation complete:", out_dir)


if __name__ == "__main__":
    main()
