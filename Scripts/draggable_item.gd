extends TextureRect
var dragging = false
var offset := Vector2()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if dragging:
			position = get_global_mouse_position() - offset

func _on_button_button_down() -> void:
	print("dragging is now active")
	dragging = true
	offset = get_global_mouse_position() - global_position


func _on_button_button_up() -> void:
	print("dragging is now inactive")
	dragging = false
