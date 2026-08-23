"""Generate the AI ships that work the claim: the rival cutter and the patrol.

Run headless:
    blender --background --python tools/build_ships.py

Why this exists
---------------
systems/ThreatSystem.gd spawns two ships at the derelict — a rival salvager that
runs the same sever-then-retrieve loop the player does, and the claim-holder's
patrol that comes to enforce it. Both are registered as solid contacts with a
collision sphere of ThreatSystem.SHIP_CONTACT_RADIUS, and this script builds the
hulls that sphere is supposed to be wrapped around.

That agreement is checked rather than hoped for: every vertex is measured against
SHIP_CONTACT_RADIUS below, and the script refuses to write a hull that pokes out of
the sphere the game collides against. Change the constant in ThreatSystem, change
it here, re-run, and it will tell you what no longer fits. Same discipline as
build_station.py's lane clearance and build_gear_leg's tie to GEAR_HEIGHT.

These are NOT station parts, which is why they are not in build_station.py: they
live at the claim, hundreds of metres from the lane, and nothing about them is
constrained by the docking corridor.

Coordinate handling
--------------------
Same convention as build_hull.py and build_station.py: everything is authored in
GODOT space (y = up; a ship's nose points along -z), and each vertex is emitted to
Blender as (gx, -gz, gy) so the glTF "+Y up" export reproduces the Godot vertex
exactly. Author in Godot space, forget the axis swap.

Both ships are authored AT THE ORIGIN facing Godot forward (-z), like the traffic
ships in build_station.py, because scenes/world/ThreatShips.gd places them by a
transform every frame.

Scale
-----
They are peers of the Kestrel, not liners. The Kestrel's baked capsule
(data/ships/kestrel.tres) is 2.6 m long and 0.7 m across, and craft_miner is 1.8 m
wide; these hulls are about 3 m long and 1.9 m across, so a rival reads as another
working boat of the same class rather than something that dwarfs you.
"""

import bpy
import bmesh
import math
import os
import sys

# --- The collision sphere, mirrored from systems/ThreatSystem.gd -----------------
# Kept as plain data here rather than parsed out of the GDScript: this is the
# contract between the two files, and a mismatch should be loud.
SHIP_CONTACT_RADIUS = 2.0


# --- Fit check ------------------------------------------------------------------

_violations = []


def check_fit(ob: bpy.types.Object) -> None:
    """Refuse to ship a hull that outgrows the sphere the game collides against.

    A contact registered with `radius` is a sphere of that radius centred on the
    ship's origin (CollisionSystem._bodies), so a vertex further out than
    SHIP_CONTACT_RADIUS is geometry the player would fly straight through. The
    distance is the same measured in either space — the Godot->Blender mapping is
    an axis permutation with a sign flip — so this measures the Blender vertex and
    reports the offender back in Godot coordinates.
    """
    worst = 0.0
    worst_at = (0.0, 0.0, 0.0)
    for v in ob.data.vertices:
        bx, by, bz = v.co
        d = math.sqrt(bx * bx + by * by + bz * bz)
        if d > worst:
            worst, worst_at = d, (bx, bz, -by)  # Blender -> Godot
    if worst > SHIP_CONTACT_RADIUS:
        _violations.append((ob.name, tuple(round(c, 2) for c in worst_at),
                            round(worst, 2)))


# --- Materials ------------------------------------------------------------------
# Blender base colours are linear, so the sRGB values the game's .tres materials
# use are linearized here (c/12.92 below 0.04045, else ((c+0.055)/1.055)^2.4).


def _srgb(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _material(name: str, rgb, metallic: float, roughness: float,
              emission=None, emission_strength: float = 1.0) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (
        _srgb(rgb[0]), _srgb(rgb[1]), _srgb(rgb[2]), 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (
            _srgb(emission[0]), _srgb(emission[1]), _srgb(emission[2]), 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def rival_material():
    """A working boat that has been in the dust a while: warm, scuffed, and matt
    enough that it never catches the light the way the patrol does."""
    return _material("rival_hull", (0.42, 0.38, 0.34), 0.6, 0.6)


def rival_trim_material():
    """The rival's cutting gear and cradle rails — darker than its plating, so the
    working end reads as a separate machine bolted to the boat."""
    return _material("rival_trim", (0.24, 0.23, 0.22), 0.8, 0.35)


def patrol_material():
    """Cold authority grey, cleaner and lighter than either salvager. Identifying a
    patrol on sight is meant to be easy, and that sets the value rather than
    taste: this is a slim hull seen against empty space, usually on its unlit
    side, and the near-black grey it started as read as nothing at all but its own
    navigation lights. Same lesson build_gear_leg records about the landing gear.
    """
    return _material("patrol_hull", (0.56, 0.60, 0.66), 0.55, 0.4)


def patrol_trim_material():
    """Lighter again, so the fin and canards break the fuselage up at range."""
    return _material("patrol_trim", (0.74, 0.78, 0.82), 0.45, 0.45)


# --- Primitives (all authored in Godot space) -----------------------------------


def add_box(bm, cx, cy, cz, sx, sy, sz) -> None:
    """Box centred at Godot (cx,cy,cz) with full extents (sx,sy,sz)."""
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


def add_cylinder(bm, centre, radius, length, axis="y", segments=20,
                 caps=True, taper=1.0) -> None:
    """Cylinder centred at Godot `centre`, `length` long along `axis`. `taper`
    scales the far end's radius (1.0 = a plain tube, <1 = a cone frustum)."""
    cx, cy, cz = centre
    half = length / 2.0
    rings = []
    for end, scale in ((-half, 1.0), (half, taper)):
        verts = []
        for s in range(segments):
            a = 2.0 * math.pi * s / segments
            u, w = radius * scale * math.cos(a), radius * scale * math.sin(a)
            if axis == "y":
                p = (cx + u, cy + end, cz + w)
            elif axis == "z":
                p = (cx + u, cy + w, cz + end)
            else:
                p = (cx + end, cy + u, cz + w)
            verts.append(bm.verts.new((p[0], -p[2], p[1])))  # Godot -> Blender
        rings.append(verts)
    for s in range(segments):
        s2 = (s + 1) % segments
        bm.faces.new((rings[0][s], rings[0][s2], rings[1][s2], rings[1][s]))
    if caps:
        bm.faces.new(rings[0])
        bm.faces.new(list(reversed(rings[1])))


def _finalize(bm, name: str, mat) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)  # force outward
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


# --- The rival cutter -----------------------------------------------------------
# A working salvage boat, and deliberately the same KIND of thing the player flies:
# a blunt hull with a torch on the front and somewhere to put what it cuts. It is
# read from the front nine times out of ten (it spends its life sitting between you
# and the derelict), so the recognisable features are all forward — the boom under
# the chin and the wide, flat bow.


def build_rival_cutter() -> bpy.types.Object:
    bm = bmesh.new()
    # Main hull: a slab-sided working body, widest amidships.
    add_box(bm, 0.0, 0.0, 0.1, 1.5, 0.7, 2.4)
    # Blunt bow, stepped in from the hull so the nose reads as a separate plate
    # rather than the body just stopping.
    add_box(bm, 0.0, -0.05, -1.35, 1.1, 0.5, 0.5)
    # Cab, offset up and forward — where a crew would actually sit to watch a cut.
    add_box(bm, 0.0, 0.42, -0.55, 0.8, 0.36, 0.9)
    # Stub wings. These carry the nav lights and strobes, so they set the ship's
    # widest points and ShipLights.build measures its mounts off them.
    for side in (-1.0, 1.0):
        add_box(bm, side * 0.72, -0.05, 0.15, 0.55, 0.16, 0.9)
    # Thruster pods outboard and aft.
    for side in (-1.0, 1.0):
        add_cylinder(bm, (side * 0.78, -0.05, 0.95), 0.22, 0.8, axis="z",
                     segments=10)
    return _finalize(bm, "RivalCutter", rival_material())


def build_rival_gear() -> bpy.types.Object:
    """The rival's working end, as a second mesh so it keeps its own darker
    material: the torch boom under the chin and the cradle it stacks cut members
    into. The boom's tip is where ThreatShips fires the cut flash from, so it has
    to be the ship's forwardmost point."""
    bm = bmesh.new()
    # Torch boom: a spar under the nose with the emitter head on the end.
    add_cylinder(bm, (0.0, -0.42, -1.25), 0.09, 1.1, axis="z", segments=8)
    add_cylinder(bm, (0.0, -0.42, -1.82), 0.15, 0.16, axis="z", segments=10,
                 taper=0.55)
    # Two struts tying the boom back up into the hull, so it does not read as
    # floating in front of the ship.
    for side in (-1.0, 1.0):
        add_box(bm, side * 0.12, -0.22, -0.95, 0.07, 0.42, 0.09)
    # Cradle rails aft: an open frame with cut members notionally stacked in it.
    for side in (-1.0, 1.0):
        add_box(bm, side * 0.52, 0.34, 0.85, 0.1, 0.36, 1.3)
    add_box(bm, 0.0, 0.5, 1.45, 1.14, 0.1, 0.12)
    return _finalize(bm, "RivalGear", rival_trim_material())


# --- The patrol -----------------------------------------------------------------
# Built to be identified, not to work: a slim fuselage, swept wings and a drive far
# too big for its size. Nothing on it is a tool.


def build_patrol_cutter() -> bpy.types.Object:
    bm = bmesh.new()
    # Fuselage, tapering toward the nose.
    add_cylinder(bm, (0.0, 0.0, 0.05), 0.34, 2.5, axis="z", segments=14)
    # Nose cone.
    add_cylinder(bm, (0.0, 0.0, -1.45), 0.34, 0.6, axis="z", segments=14,
                 taper=0.25)
    # Swept wings, approximated in three steps per side: each panel outboard is
    # shorter and sits further aft, which is what gives the sweep without having to
    # rotate geometry the primitives cannot rotate.
    for side in (-1.0, 1.0):
        add_box(bm, side * 0.42, -0.02, 0.35, 0.44, 0.11, 1.0)
        add_box(bm, side * 0.70, -0.02, 0.55, 0.28, 0.09, 0.72)
        add_box(bm, side * 0.88, -0.02, 0.72, 0.16, 0.08, 0.48)
    return _finalize(bm, "PatrolCutter", patrol_material())


def build_patrol_trim() -> bpy.types.Object:
    """Fin, canards and drive bell — the lighter parts, kept as a second mesh so
    the silhouette has some contrast in it at range."""
    bm = bmesh.new()
    # Dorsal fin.
    add_box(bm, 0.0, 0.42, 1.15, 0.09, 0.62, 0.55)
    # Forward canards, well ahead of the wings.
    for side in (-1.0, 1.0):
        add_box(bm, side * 0.42, 0.06, -0.95, 0.5, 0.07, 0.3)
    # Drive bell, flaring aft.
    add_cylinder(bm, (0.0, 0.0, 1.5), 0.3, 0.5, axis="z", segments=14, taper=1.35)
    return _finalize(bm, "PatrolTrim", patrol_trim_material())


# --- Export ---------------------------------------------------------------------


def export(parts, path: str) -> None:
    """Write one or more objects into a single .glb. Multiple objects stay
    SEPARATE meshes in the file, which is what lets the hull and its trim carry
    different materials — and what lets ShipLights.build measure them all."""
    objects = parts if isinstance(parts, list) else [parts]
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
    )
    print("wrote %s (%d mesh%s)" % (path, len(objects),
                                    "" if len(objects) == 1 else "es"))


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)

    script_path = os.path.realpath(__file__)
    repo_root = os.path.dirname(os.path.dirname(script_path))
    out_dir = os.path.join(repo_root, "assets", "cc0", "ships")
    os.makedirs(out_dir, exist_ok=True)

    parts = [
        ([build_rival_cutter(), build_rival_gear()], "rival_cutter.glb"),
        ([build_patrol_cutter(), build_patrol_trim()], "patrol_cutter.glb"),
    ]

    for group, _filename in parts:
        for ob in group:
            check_fit(ob)
    if _violations:
        for name, at, worst in _violations:
            print("SPHERE VIOLATION: %s reaches %.2f m at %s (limit %.2f)"
                  % (name, worst, at, SHIP_CONTACT_RADIUS))
        sys.exit("hull geometry outgrows ThreatSystem.SHIP_CONTACT_RADIUS — "
                 "shrink the hull or move the constant in both files")

    for group, filename in parts:
        export(group, os.path.join(out_dir, filename))


main()
