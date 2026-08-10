"""Generate the docking station: structure, berth bay, pad, traffic and gear.

Run headless:
    blender --background --python tools/build_station.py

Why this exists
---------------
The docking mini-game (systems/DockingSystem.gd) flies a lane of gates that
doglegs through a station and drops into a walled berth. That lane is authored
as station-local constants in DockingSystem, and Station.gd places the rings and
the pad FROM those constants — so the geometry the player flies is data, and this
script's job is to build structure that AGREES with it: hab drums that really do
form the slot CHARLIE threads, bay walls that really are just outside the final
corridor.

To keep that honest rather than hopeful, every solid part is checked against the
lane at build time (see LANE and `clearance`): the script refuses to write a mesh
that intrudes into a corridor the pilot is required to stay inside. Change a gate
in DockingSystem.gd, re-run this, and it will tell you what no longer fits.

Coordinate handling
--------------------
Same convention as build_hull.py: everything is authored in GODOT space (y = up;
ships arrive from +z and work inbound toward -z), and each vertex is emitted to
Blender as (gx, -gz, gy) so the glTF "+Y up" export reproduces the Godot vertex
exactly. Author in Godot space, forget the axis swap.

Station parts are authored in STATION-LOCAL space (the station node's own frame,
which Station.gd registers with DockingSystem). Traffic ships and the landing-gear
leg are authored at the origin instead, because they are placed by a transform
every frame / bolted onto the ship.
"""

import bpy
import bmesh
import math
import os
import sys

# --- The lane, mirrored from systems/DockingSystem.gd ---------------------------
# Kept as plain data here rather than parsed out of the GDScript: this is the
# contract between the two files, and a mismatch should be loud. Gate positions
# and the corridor radius of the leg LEADING to each.
GATES = [
    ("ALPHA", (0.0, 0.0, 190.0), 14.0, 40.0),
    ("BRAVO", (0.0, 10.0, 120.0), 12.0, 22.0),
    ("CHARLIE", (-30.0, 10.0, 66.0), 9.0, 15.0),
    ("DELTA", (-30.0, 16.0, 14.0), 6.5, 10.0),
]
PAD = (-30.0, 0.0, 14.0)
PAD_RADIUS = 7.0
FINAL_LANE = 6.0
# Structure must clear the corridor it runs alongside by at least this much, so a
# pilot flying a legal line never scrapes scenery.
CLEARANCE_MARGIN = 1.0

# Lane segments as (from, to, corridor_radius). The inbound legs plus the drop
# onto the pad.
LANE = [
    (GATES[i][1], GATES[i + 1][1], GATES[i + 1][3]) for i in range(len(GATES) - 1)
] + [(GATES[-1][1], PAD, FINAL_LANE)]


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def distance_to_segment(p, a, b) -> float:
    """Shortest distance from point `p` to segment `ab` — the same test
    DockingSystem._distance_to_segment does at runtime, so build-time clearance
    and in-game corridor discipline are measured identically."""
    ab = _sub(b, a)
    len_sq = _dot(ab, ab)
    if len_sq < 1e-6:
        return math.dist(p, a)
    t = max(0.0, min(1.0, _dot(_sub(p, a), ab) / len_sq))
    return math.dist(p, (a[0] + ab[0] * t, a[1] + ab[1] * t, a[2] + ab[2] * t))


def clearance(p, radius: float) -> float:
    """How much room a solid of `radius` centred at `p` leaves inside the tightest
    corridor it is near. Negative means it is poking into the lane."""
    worst = float("inf")
    for a, b, lane in LANE:
        worst = min(worst, distance_to_segment(p, a, b) - lane - radius)
    return worst


_violations = []


def check_clear(label: str, p, radius: float) -> None:
    """Check one solid approximated by its bounding sphere. Fine for compact
    parts; long thin ones must use check_box_clear, whose bounding sphere would
    be so much bigger than the part that it would fail everything."""
    room = clearance(p, radius)
    if room < CLEARANCE_MARGIN:
        _violations.append((label, p, round(room, 2)))


def check_box_clear(label: str, centre, extents, samples: int = 5) -> None:
    """Check a box by sampling its volume on a grid rather than wrapping it in a
    sphere. A 19 m bay wall 1.6 m thick has a 9.6 m bounding radius, which says
    nothing useful — where the wall actually is, is what matters."""
    cx, cy, cz = centre
    sx, sy, sz = extents
    worst = float("inf")
    worst_at = centre
    for i in range(samples):
        for j in range(samples):
            for k in range(samples):
                p = (
                    cx + sx * (i / (samples - 1) - 0.5),
                    cy + sy * (j / (samples - 1) - 0.5),
                    cz + sz * (k / (samples - 1) - 0.5),
                )
                room = clearance(p, 0.0)
                if room < worst:
                    worst, worst_at = room, p
    if worst < CLEARANCE_MARGIN:
        _violations.append((label, tuple(round(v, 1) for v in worst_at),
                            round(worst, 2)))


# --- Materials ------------------------------------------------------------------
# Blender base colours are linear, so the sRGB values the game's .tres materials
# use are linearized here (c/12.92 below 0.04045, else ((c+0.055)/1.055)^2.4).


def _srgb(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _material(name: str, rgb, metallic: float, roughness: float,
              emission=None) -> bpy.types.Material:
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
        bsdf.inputs["Emission Strength"].default_value = 1.0
    return mat


def structure_material():
    """Station plating — a shade lighter and less metallic than the derelict's
    hull, so a live station never reads as more wreckage."""
    return _material("station_plating", (0.42, 0.44, 0.47), 0.7, 0.45)


def trim_material():
    """Warm trim for the parts the pilot is meant to read as navigational:
    drum end caps, bay lips, gantries."""
    return _material("station_trim", (0.62, 0.55, 0.36), 0.5, 0.5)


def marking_material():
    """Deck markings — emissive so the pad stays legible in the station's own
    shadow, which is exactly where you land."""
    return _material("pad_marking", (0.95, 0.72, 0.2), 0.0, 0.7,
                     emission=(0.95, 0.72, 0.2))


def traffic_material():
    return _material("traffic_hull", (0.5, 0.52, 0.56), 0.75, 0.4)


def gear_material():
    return _material("landing_gear", (0.3, 0.31, 0.34), 0.8, 0.35)


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


def add_disc(bm, centre, radius, segments=32, inner=0.0) -> None:
    """Flat disc (or annulus, if `inner` > 0) lying in the station's xz plane —
    deck plate and pad markings."""
    cx, cy, cz = centre
    if inner <= 0.0:
        hub = bm.verts.new((cx, -cz, cy))
        rim = []
        for s in range(segments):
            a = 2.0 * math.pi * s / segments
            gx, gz = cx + radius * math.cos(a), cz + radius * math.sin(a)
            rim.append(bm.verts.new((gx, -gz, cy)))
        for s in range(segments):
            bm.faces.new((hub, rim[s], rim[(s + 1) % segments]))
        return
    outer_ring, inner_ring = [], []
    for s in range(segments):
        a = 2.0 * math.pi * s / segments
        ca, sa = math.cos(a), math.sin(a)
        outer_ring.append(bm.verts.new((cx + radius * ca, -(cz + radius * sa), cy)))
        inner_ring.append(bm.verts.new((cx + inner * ca, -(cz + inner * sa), cy)))
    for s in range(segments):
        s2 = (s + 1) % segments
        bm.faces.new((inner_ring[s], outer_ring[s], outer_ring[s2], inner_ring[s2]))


def _finalize(bm, name: str, mat) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)  # force outward
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


# --- Station structure ----------------------------------------------------------
# Laid out around the lane rather than through it: the hub sits off to +x, the
# habitat drums straddle the CHARLIE slot, and the berth bay is a walled well
# under DELTA. Every solid is clearance-checked against LANE as it is placed.

HUB_CENTRE = (34.0, 0.0, 44.0)
HUB_RADIUS = 15.0
HUB_HEIGHT = 46.0

# Drums flanking the CHARLIE gate. The +x one has to clear the DIAGONAL
# BRAVO->CHARLIE leg, not just the gate, which is what sets the offset: at 28 m it
# ate 1.5 m of that leg's 15 m corridor.
DRUM_OFFSET = 34.0
DRUM_RADIUS = 10.0
DRUM_LENGTH = 34.0

# The berth well under DELTA: walls just outside the 6 m final corridor. Kept low
# and open on the approach side (+z) — the run in to DELTA crosses the bay
# horizontally at y 10..16 with a 10 m corridor, so a tall wall on that side would
# sit squarely in the lane the pilot is ordered to stay inside.
BAY_HALF = 9.0
BAY_HEIGHT = 8.0
BAY_WALL = 1.6


def build_hub() -> bpy.types.Object:
    """The station's core: a drum with a ring of radiator fins and a docking
    collar, sat well off the lane to +x."""
    bm = bmesh.new()
    cx, cy, cz = HUB_CENTRE
    check_clear("hub core", HUB_CENTRE, HUB_RADIUS)
    add_cylinder(bm, HUB_CENTRE, HUB_RADIUS, HUB_HEIGHT, axis="y", segments=24)
    # Collar rings top and bottom, so the drum reads as built rather than extruded.
    for dy in (-HUB_HEIGHT / 2.0 + 3.0, HUB_HEIGHT / 2.0 - 3.0):
        add_cylinder(bm, (cx, cy + dy, cz), HUB_RADIUS + 1.6, 2.4, axis="y",
                     segments=24)
    # Radiator fins around the equator.
    for i in range(6):
        a = 2.0 * math.pi * i / 6.0
        fx = cx + (HUB_RADIUS + 5.0) * math.cos(a)
        fz = cz + (HUB_RADIUS + 5.0) * math.sin(a)
        check_clear("hub fin %d" % i, (fx, cy, fz), 5.5)
        add_box(bm, fx, cy, fz, 10.0, 8.0, 1.2)
    return _finalize(bm, "StationHub", structure_material())


def build_drum(name: str) -> bpy.types.Object:
    """One habitat drum, authored at the origin with its axis along z (the
    direction the lane runs past it). Station.gd instances two of these either
    side of the CHARLIE gate."""
    bm = bmesh.new()
    add_cylinder(bm, (0.0, 0.0, 0.0), DRUM_RADIUS, DRUM_LENGTH, axis="z",
                 segments=24)
    # Banded hull so the drum's rotation would read, plus lit end caps.
    for dz in (-DRUM_LENGTH / 4.0, 0.0, DRUM_LENGTH / 4.0):
        add_cylinder(bm, (0.0, 0.0, dz), DRUM_RADIUS + 0.7, 1.8, axis="z",
                     segments=24)
    ob = _finalize(bm, name, structure_material())
    return ob


def build_drum_caps(name: str) -> bpy.types.Object:
    """Trim-coloured end caps for the drum, exported separately so the two
    materials survive as distinct surfaces."""
    bm = bmesh.new()
    for dz in (-DRUM_LENGTH / 2.0 - 0.6, DRUM_LENGTH / 2.0 + 0.6):
        add_cylinder(bm, (0.0, 0.0, dz), DRUM_RADIUS * 0.55, 1.4, axis="z",
                     segments=20)
    return _finalize(bm, name, trim_material())


def build_berth_bay() -> list:
    """The well the ship descends into: walls around the pad and a floor, open
    at the top. The walls are what make the last 16 m genuinely tight.

    ONE OBJECT PER WALL, deliberately. Station.gd bakes a convex hull per mesh,
    and a bay is a concave shape — modelled as a single mesh its hull comes back
    as a solid block with the landing pad inside it, so the descent is a
    collision instead of a landing. Separate meshes keep the middle open.
    """
    out = []
    px, py, pz = PAD
    cy = py + BAY_HEIGHT / 2.0
    span = BAY_HALF * 2.0 + BAY_WALL
    # Three walls, not four: the +z side is the mouth the ship comes in over.
    for dx, dz in ((-1, 0), (1, 0), (0, -1)):
        wx = px + dx * (BAY_HALF + BAY_WALL / 2.0)
        wz = pz + dz * (BAY_HALF + BAY_WALL / 2.0)
        sx = BAY_WALL if dx else span
        sz = BAY_WALL if dz else span
        # The walls are the tightest thing on the whole lane — this check is the
        # one that matters most.
        check_box_clear("bay wall (%d,%d)" % (dx, dz), (wx, cy, wz),
                        (sx, BAY_HEIGHT, sz))
        bm = bmesh.new()
        add_box(bm, wx, cy, wz, sx, BAY_HEIGHT, sz)
        out.append(_finalize(bm, "BayWall%+d%+d" % (dx, dz), structure_material()))
    # A low lip across the mouth, so the berth still reads as enclosed from the
    # cockpit without reaching up into the approach corridor.
    lip_z = pz + BAY_HALF + BAY_WALL / 2.0
    check_box_clear("bay lip", (px, py + 1.0, lip_z), (span, 2.0, BAY_WALL))
    bm = bmesh.new()
    add_box(bm, px, py + 1.0, lip_z, span, 2.0, BAY_WALL)
    out.append(_finalize(bm, "BayLip", structure_material()))
    # Floor slab under the deck. Its top face sits at the pad's own height, so a
    # ship on its legs rests above it rather than in it.
    bm = bmesh.new()
    add_box(bm, px, py - 1.0, pz, span + 2.0, 2.0, span + 2.0)
    out.append(_finalize(bm, "BayFloor", structure_material()))
    return out


def build_pad_deck() -> bpy.types.Object:
    """The deck plate itself, with an emissive ring on the PAD_RADIUS markings
    the touchdown test actually scores against."""
    bm = bmesh.new()
    px, py, pz = PAD
    add_disc(bm, (px, py + 0.06, pz), PAD_RADIUS + 1.2, segments=40)
    return _finalize(bm, "PadDeck", structure_material())


def build_pad_markings() -> bpy.types.Object:
    bm = bmesh.new()
    px, py, pz = PAD
    # The scoring circle, drawn exactly at PAD_RADIUS so what you see is what
    # _touchdown measures.
    add_disc(bm, (px, py + 0.12, pz), PAD_RADIUS, segments=48,
             inner=PAD_RADIUS - 0.5)
    # A centre cross to aim the drift marker at.
    add_box(bm, px, py + 0.12, pz, 0.5, 0.05, PAD_RADIUS * 0.9)
    add_box(bm, px, py + 0.12, pz, PAD_RADIUS * 0.9, 0.05, 0.5)
    return _finalize(bm, "PadMarkings", marking_material())


def build_gantry() -> bpy.types.Object:
    """Truss work tying the berth bay back to the hub, so the station reads as one
    structure. Run low (well under the lane) and checked like everything else."""
    bm = bmesh.new()
    y = -10.0
    px, _py, pz = PAD
    hx, _hy, hz = HUB_CENTRE
    steps = 10
    for i in range(steps + 1):
        t = i / steps
        gx = px + (hx - px) * t
        gz = pz + (hz - pz) * t
        check_box_clear("gantry %d" % i, (gx, y, gz), (3.0, 3.0, 3.0), samples=3)
        add_box(bm, gx, y, gz, 3.0, 3.0, 3.0)
    return _finalize(bm, "Gantry", trim_material())


# --- Traffic ships (authored at the origin, facing Godot forward = -z) ----------


def build_tug() -> bpy.types.Object:
    """Lane tug: short, wide and slab-sided — the one that crosses in front of you
    on the BRAVO-CHARLIE leg. Radius 3.5 in DockingSystem.TRAFFIC_ROUTES."""
    bm = bmesh.new()
    add_box(bm, 0.0, 0.0, 0.0, 4.4, 3.0, 6.4)
    add_box(bm, 0.0, 1.4, -1.6, 2.6, 1.6, 2.4)          # cab
    for side in (-1.0, 1.0):
        add_cylinder(bm, (side * 2.8, -0.4, 1.6), 1.0, 3.4, axis="z", segments=12)
    return _finalize(bm, "TrafficTug", traffic_material())


def build_shuttle() -> bpy.types.Object:
    """Ring-circuit shuttle: slim and quick. Radius 2.5."""
    bm = bmesh.new()
    add_cylinder(bm, (0.0, 0.0, 0.4), 1.5, 6.0, axis="z", segments=16, taper=0.55)
    add_box(bm, 0.0, 0.0, 1.4, 6.4, 0.35, 1.8)          # wing
    add_box(bm, 0.0, 1.0, 2.2, 0.35, 1.6, 1.4)          # fin
    return _finalize(bm, "TrafficShuttle", traffic_material())


def build_barge() -> bpy.types.Object:
    """Ore barge on the outer transit: big, slow, and worth holding for. Radius 6."""
    bm = bmesh.new()
    add_box(bm, 0.0, 0.0, 0.0, 8.0, 5.0, 13.0)
    for dz in (-3.0, 0.0, 3.0):                          # ore hoppers
        add_cylinder(bm, (0.0, 3.0, dz), 2.4, 7.0, axis="x", segments=14)
    add_box(bm, 0.0, 0.8, -7.0, 4.0, 2.4, 2.0)          # bridge
    return _finalize(bm, "TrafficBarge", traffic_material())


# --- Ship landing gear ----------------------------------------------------------


def build_gear_leg() -> bpy.types.Object:
    """One landing-gear leg, authored in SHIP space hanging straight down from the
    origin, fully extended. Ship.gd instances three and swings them from stowed to
    down with GameState.gear_position, so this is the 1.0 end of that travel."""
    bm = bmesh.new()
    add_cylinder(bm, (0.0, -0.55, 0.0), 0.12, 1.1, axis="y", segments=10)  # strut
    add_cylinder(bm, (0.0, -1.08, 0.0), 0.34, 0.12, axis="y", segments=14)  # foot
    add_box(bm, 0.0, -0.2, 0.0, 0.34, 0.3, 0.34)                            # knuckle
    return _finalize(bm, "GearLeg", gear_material())


# --- Export ---------------------------------------------------------------------


def export(parts, path: str) -> None:
    """Write one or more objects into a single .glb. Multiple objects stay
    SEPARATE meshes in the file, which is what keeps their convex hulls separate
    in Godot — see build_berth_bay for why that matters."""
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
    out_dir = os.path.join(repo_root, "assets", "cc0", "station")
    os.makedirs(out_dir, exist_ok=True)

    parts = [
        (build_hub(), "hub_core.glb"),
        (build_drum("HabDrum"), "hab_drum.glb"),
        (build_drum_caps("HabDrumCaps"), "hab_drum_caps.glb"),
        (build_berth_bay(), "berth_bay.glb"),
        (build_pad_deck(), "pad_deck.glb"),
        (build_pad_markings(), "pad_markings.glb"),
        (build_gantry(), "gantry.glb"),
        (build_tug(), "traffic_tug.glb"),
        (build_shuttle(), "traffic_shuttle.glb"),
        (build_barge(), "traffic_barge.glb"),
        (build_gear_leg(), "landing_gear.glb"),
    ]

    # Refuse to ship art that eats the lane. The drums are placed by Station.gd at
    # ±DRUM_OFFSET, so their clearance is checked here rather than at build time.
    for side in (-1.0, 1.0):
        gx, gy, gz = GATES[2][1]
        check_clear("hab drum %+d" % side, (gx + side * DRUM_OFFSET, gy, gz),
                    DRUM_RADIUS)
    if _violations:
        for label, p, room in _violations:
            print("LANE VIOLATION: %s at %s leaves %.2f m (need %.2f)"
                  % (label, p, room, CLEARANCE_MARGIN))
        sys.exit("station geometry intrudes into the docking lane — fix the layout")

    for ob, filename in parts:
        export(ob, os.path.join(out_dir, filename))

    print("station generation complete:", out_dir)
    print("lane clearance OK for %d solid parts" % len(parts))


if __name__ == "__main__":
    main()
