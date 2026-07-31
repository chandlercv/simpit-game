extends Control
## Root content of the Camera display: a SubViewport that renders the shared Main
## World3D from an ExternalCameraRig, plus a thin overlay naming the current view.
##
## The world is assigned at runtime (it only exists once the Main view is up), so
## on ready we pull it from WindowManager and hand it to our SubViewport — after
## that our rig's camera sees exactly what the hull-cam sees. Nodes are reached by
## relative path (not %unique-name) so this still works when RoleTabHost harvests
## this Root onto a shared screen.

@onready var _viewport: SubViewport = $SubViewportContainer/SubViewport
@onready var _label: Label = $Overlay/ViewLabel


func _ready() -> void:
	GameState.external_view_changed.connect(_update_label)
	_update_label(GameState.external_view)
	# Deferred so MainViewWindow has wired its SubViewport before we borrow it.
	_wire_world.call_deferred()


func _wire_world() -> void:
	var world := WindowManager.main_world_3d()
	if world:
		_viewport.world_3d = world


func _update_label(view: String) -> void:
	_label.text = "EXTERNAL CAM — %s" % view
