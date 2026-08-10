extends Node3D
## View-only: a mesh per ship in GameState.traffic, following the live transform
## DockingSystem writes each frame. Exactly the relationship SalvagePieces has
## with DriftSystem — the rules are headless sphere-and-segment maths, and this
## node is the optional presentation layer bolted on top.
##
## Which mesh a ship gets is keyed off its "kind" (TUG / SHUTTLE / BARGE), which
## DockingSystem.TRAFFIC_ROUTES already carries for the Tactical scope's benefit,
## so no new data is needed here.

const STATION_DIR := "res://assets/cc0/station/"
const MESHES := {
	"TUG": "traffic_tug.glb",
	"SHUTTLE": "traffic_shuttle.glb",
	"BARGE": "traffic_barge.glb",
}

## traffic id -> the Node3D standing in for it.
var _visuals: Dictionary = {}


func _ready() -> void:
	GameState.traffic_changed.connect(_sync)
	_sync()


func _process(_delta: float) -> void:
	for entry: Dictionary in GameState.traffic:
		var node: Node3D = _visuals.get(int(entry["id"]))
		if node != null:
			node.global_transform = entry["transform"]


## Traffic arrives and leaves in one go (a whole pattern's worth spawns with the
## approach), so a rebuild on the signal is simpler than diffing and costs
## nothing at three ships.
func _sync() -> void:
	var live: Dictionary = {}
	for entry: Dictionary in GameState.traffic:
		live[int(entry["id"])] = entry
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


func _spawn(entry: Dictionary) -> Node3D:
	var file: String = MESHES.get(String(entry["kind"]), "")
	if file.is_empty():
		push_warning("StationTraffic: no mesh for kind %s" % entry["kind"])
		return null
	var packed: PackedScene = load(STATION_DIR + file)
	if packed == null:
		push_warning("StationTraffic: missing %s — run tools/build_station.py" % file)
		return null
	var node: Node3D = packed.instantiate()
	add_child(node)
	node.global_transform = entry["transform"]
	return node
