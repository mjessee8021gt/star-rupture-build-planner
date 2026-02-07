extends Camera2D

var zoom_target := Vector2(1.0, 1.0) #Default zoom level
const ZOOM_OUT_FACTOR := Vector2(1.1, 1.1)
const ZOOM_IN_FACTOR := Vector2 (0.9, 0.9)
const ZOOM_SPEED := 5.0
const ZOOM_IN_CLAMP := Vector2 (0.5, 0.5)
const ZOOM_OUT_CLAMP := Vector2(3.0, 3.0)
# Called when the node enters the scene tree for the first time.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.button_mask == MOUSE_BUTTON_MASK_MIDDLE:
			position -= event.relative
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	zoom = zoom.lerp(zoom_target, ZOOM_SPEED * delta)
	
func zoomOut():
	#increase the target zoom value to zoom out
	zoom_target *= ZOOM_OUT_FACTOR
	zoom_target = zoom_target.clamp(ZOOM_IN_CLAMP, ZOOM_OUT_CLAMP)

func ZoomIn():
	#decrease the zoom value to zoom in
	zoom_target *= ZOOM_IN_FACTOR
	zoom_target = zoom_target.clamp(ZOOM_IN_CLAMP, ZOOM_OUT_CLAMP)
