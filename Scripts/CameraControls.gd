extends Camera2D

const PAN_MOUSE_ACTION := "Pan (Mouse)"
const PAN_UP_ACTION := "Pan Up (Keyboard)"
const PAN_DOWN_ACTION := "Pan Down (Keyboard)"
const PAN_LEFT_ACTION := "Pan Left (Keyboard)"
const PAN_RIGHT_ACTION := "Pan Right (Keyboard)"

var zoom_target := Vector2(0.8, 0.8) #Default zoom level
const ZOOM_OUT_FACTOR := Vector2(1.1, 1.1)
const ZOOM_IN_FACTOR := Vector2 (0.9, 0.9)
const ZOOM_SPEED := 5.0
const ZOOM_IN_CLAMP := Vector2 (0.3, 0.3)
const ZOOM_OUT_CLAMP := Vector2(3.0, 3.0)
@export var keyboard_pan_speed := 900.0

var _mouse_pan_active := false
var _mouse_pan_last := Vector2.ZERO


func _is_scene_input_blocked() -> bool:
	var main_scene := get_parent()
	return main_scene != null and main_scene.has_method("is_scene_input_blocked") and main_scene.is_scene_input_blocked()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if _is_scene_input_blocked():
		_mouse_pan_active = false
		return
	zoom = zoom.lerp(zoom_target, ZOOM_SPEED * delta)
	_process_keyboard_pan(delta)
	_process_mouse_pan()

# Mouse panning is driven from _process by polling the Input singleton rather
# than by consuming input events. The Input state reflects the physical button
# regardless of who owns the event, so panning keeps working even when a
# focused popup window (e.g. the persistent toolbox) would otherwise swallow
# the mouse events before any scene node sees them.
func _process_mouse_pan() -> void:
	if Input.is_action_pressed(PAN_MOUSE_ACTION):
		var mouse_pos := get_viewport().get_mouse_position()
		if _mouse_pan_active:
			position -= mouse_pos - _mouse_pan_last
		_mouse_pan_last = mouse_pos
		_mouse_pan_active = true
	else:
		_mouse_pan_active = false

func _process_keyboard_pan(delta: float) -> void:
	var pan_direction := Input.get_vector(PAN_LEFT_ACTION, PAN_RIGHT_ACTION, PAN_UP_ACTION, PAN_DOWN_ACTION)
	if pan_direction == Vector2.ZERO:
		return

	position += pan_direction * keyboard_pan_speed * delta

#increase the target zoom value to zoom out
func zoomOut():
	zoom_target *= ZOOM_OUT_FACTOR
	zoom_target = zoom_target.clamp(ZOOM_IN_CLAMP, ZOOM_OUT_CLAMP)

#decrease the zoom value to zoom in
func ZoomIn():
	zoom_target *= ZOOM_IN_FACTOR
	zoom_target = zoom_target.clamp(ZOOM_IN_CLAMP, ZOOM_OUT_CLAMP)
