extends Node3D
## View-only: turns each DriftSystem-owned adrift salvage piece into a
## free-floating mesh the instant it's cut, by duplicating the matching Wreck
## member's own mesh subtree, then just follows the live piece transform each
## frame. Wreck.gd needs no change for this: it already hides the original
## member's node on wreck_member_cut (Wreck._apply_member) — this duplicate is
## a separate copy living under this node, so nothing here disturbs Wreck's
## baked hulls, collision, or site-reset logic.
##
## DriftSystem itself is headless-safe (sphere math only, no node lookups); this
## node is the optional 3D presentation layer on top of it, added as a sibling
## of Wreck in DebrisField.tscn.

## Path to the Wreck instance this scene's pieces are cut from, resolved once
## in _ready. Sibling by default (both direct children of the world root).
@export var wreck_path: NodePath = NodePath("../Wreck")

var _wreck: Node3D
## piece id -> {"node": the duplicated Node3D drifting free in the scene,
## "offset": its pose relative to that piece's transform}.
##
## The offset exists because a member's geometry is NOT centred on its node:
## every member wrapper in Wreck.tscn sits at the WRECK's own origin, with each
## section's placement baked into the mesh data (build_hull.py lays out one
## continuous fuselage). A piece's transform tracks the member CENTROID — the
## point the approach parks off, the scoop measures against, and the HUD marks —
## so the visual hangs off it by this fixed offset to render where the section
## actually was. Writing the node's pose into the piece instead would put every
## collectible's real position at the middle of the derelict, metres from its
## own visible mesh (7.2 m for the engine bell).
var _visuals: Dictionary = {}


func _ready() -> void:
	_wreck = get_node_or_null(wreck_path)
	GameState.salvage_piece_spawned.connect(_on_spawned)
	GameState.salvage_piece_removed.connect(_on_removed)
	GameState.site_reset.connect(_on_site_reset)
	# Cover pieces that already existed when this node enters the tree (a
	# display window opening after cuts already happened elsewhere).
	for piece: Dictionary in GameState.salvage_pieces:
		_on_spawned(piece["id"])


func _process(_delta: float) -> void:
	for id: int in _visuals:
		var piece := GameState.get_salvage_piece(id)
		if piece.is_empty():
			continue
		var entry: Dictionary = _visuals[id]
		(entry["node"] as Node3D).global_transform = \
				(piece["transform"] as Transform3D) * (entry["offset"] as Transform3D)


func _on_spawned(id: int) -> void:
	var piece := GameState.get_salvage_piece(id)
	if piece.is_empty() or _wreck == null:
		return
	var source: Node3D = _wreck.member_visual(piece["node"])
	if source == null:
		return
	var dup: Node3D = source.duplicate()
	# The source node is already hidden by the time this fires (SalvageSystem
	# emits wreck_member_cut, which Wreck._apply_member handles, before calling
	# spawn_piece) — duplicate() copied that hidden state, so undo it here.
	dup.visible = true
	add_child(dup)
	# Take ONLY the orientation from the hull, so the piece carries on tumbling
	# the way it was instead of snapping to DriftSystem's headless-safe identity
	# basis. Its origin stays on the member centroid DriftSystem seeded — see
	# _visuals for why the node's own origin must never be written into it.
	var xform: Transform3D = piece["transform"]
	xform.basis = source.global_transform.basis
	piece["transform"] = xform
	# Fixed pose of the mesh relative to that centroid: the visual renders
	# exactly where the section was, then rides the piece rigidly.
	var offset := xform.affine_inverse() * source.global_transform
	dup.global_transform = xform * offset
	_visuals[id] = {"node": dup, "offset": offset}


func _on_removed(id: int) -> void:
	if not _visuals.has(id):
		return
	((_visuals[id] as Dictionary)["node"] as Node3D).queue_free()
	_visuals.erase(id)


func _on_site_reset() -> void:
	for id: int in _visuals.keys():
		((_visuals[id] as Dictionary)["node"] as Node3D).queue_free()
	_visuals.clear()
