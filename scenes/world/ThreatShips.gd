extends Node3D
## View-only: a hull for every ship ThreatSystem puts in the volume — the rival
## cutter and the claim-holder's patrol. Exactly the relationship StationTraffic
## has with DockingSystem, and SalvagePieces with DriftSystem: the rules are
## headless maths that move a contact's position, and this node is the optional
## presentation layer bolted on top. It reads GameState and mutates nothing.
##
## Which mesh a contact gets is keyed off its "kind" (RIVAL / PATROL), which
## ThreatSystem sets when it registers the contact. Keying on that rather than
## matching the display name is what keeps this node off contacts that already
## have a body drawn for them somewhere else — the derelict, the debris chunk,
## and the station's traffic, all of which are contacts too.

const SHIP_DIR := "res://assets/cc0/ships/"
const MESHES := {
	"RIVAL": "rival_cutter.glb",
	"PATROL": "patrol_cutter.glb",
}

const RivalTorchScript := preload("res://scenes/world/RivalTorch.gd")

## contact id -> the Node3D standing in for it.
var _visuals: Dictionary = {}


func _ready() -> void:
	GameState.contacts_changed.connect(_sync)
	# The rival's torch is world-space and outlives any one rival, so it hangs here
	# rather than off a hull that gets freed when that rival burns out of the
	# volume mid-flare.
	var torch := RivalTorchScript.new()
	torch.name = "RivalTorch"
	add_child(torch)
	_sync()


func _process(_delta: float) -> void:
	for contact: Dictionary in GameState.contacts:
		var node: Node3D = _visuals.get(int(contact["id"]))
		if node == null:
			continue
		node.global_position = contact["position"]
		# A contact carries a heading rather than a basis, so the roll is ours to
		# choose: level. Guarded for the frame before a ship has moved, and for a
		# heading straight up or down, either of which makes looking_at fail —
		# in both cases the hull keeps the attitude it had.
		var heading: Vector3 = contact.get("heading", Vector3.ZERO)
		if heading.length_squared() > 0.001 and absf(heading.normalized().y) < 0.999:
			node.global_basis = Basis.looking_at(heading, Vector3.UP)


## Ships arrive and leave one at a time and there are never more than two, so a
## rebuild on the signal is simpler than diffing and costs nothing.
func _sync() -> void:
	var live: Dictionary = {}
	for contact: Dictionary in GameState.contacts:
		if MESHES.has(String(contact.get("kind", ""))):
			live[int(contact["id"])] = contact
	for id: int in _visuals.keys():
		if not live.has(id):
			(_visuals[id] as Node3D).queue_free()
			_visuals.erase(id)
	for id: int in live:
		if _visuals.has(id):
			continue
		var node := _spawn(live[id])
		if node != null:
			_visuals[id] = node


func _spawn(contact: Dictionary) -> Node3D:
	var file: String = MESHES.get(String(contact["kind"]), "")
	if file.is_empty():
		push_warning("ThreatShips: no mesh for kind %s" % contact["kind"])
		return null
	var packed: PackedScene = load(SHIP_DIR + file)
	if packed == null:
		push_warning("ThreatShips: missing %s — run tools/build_ships.py" % file)
		return null
	var node: Node3D = packed.instantiate()
	add_child(node)
	node.global_position = contact["position"]
	# The same fit the Kestrel wears. These are not own ship, so they do not follow
	# her switches or her bus, and they carry no omni lights — a contact 150 m out
	# has nothing nearby for one to fall on.
	ShipLights.attach(node, node)
	return node
