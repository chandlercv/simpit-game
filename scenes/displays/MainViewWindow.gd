extends Control
## Main display: edge-to-edge hull-camera feed (SubViewport 3D) with a thin
## HUD CanvasLayer on top. No dashboard/frame Control behind or around the
## viewport — the view fills the window like a real external hull camera
## (plan Phase 2).


func _ready() -> void:
	# Deferred so the SubViewport has registered its active camera; a NodePath
	# in the .tscn can't reach inside the instanced world scene.
	_wire_hud.call_deferred()


func _wire_hud() -> void:
	%HUDOverlay.camera = %SubViewport.get_camera_3d()
