extends Node2D

@export var smelter : PackedScene
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Camera2D/CanvasLayer/Panel/HeatLabel.text = "0"
	$Camera2D/CanvasLayer/Panel/PowerLabel.text = "0"
	Adjust_ui_for_resolution()
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if(Input.is_action_just_released("Zoom Out")):
		$Camera2D.zoomOut()
	elif (Input.is_action_just_released("Zoom In")):
		$Camera2D.ZoomIn()
	elif (Input.is_action_just_released("Show Debug Feed")):
		if $"Camera2D/CanvasLayer/Debug Panel".visible == false:
			$"Camera2D/CanvasLayer/Debug Panel".visible = true
		else:
			$"Camera2D/CanvasLayer/Debug Panel".visible = false


func _on_prod_menu_pressed() -> void:
	$Camera2D/CanvasLayer/ProdMenu/ProdPanel.visible = not $Camera2D/CanvasLayer/ProdMenu/ProdPanel.visible
	
func Adjust_ui_for_resolution() -> void:
	$Camera2D/CanvasLayer/MenuButton.position = Vector2 (15, 15)
	$Camera2D/CanvasLayer/Panel.position = Vector2 (get_viewport().size.x - 180, 5)
	$Camera2D/CanvasLayer/ProdMenu.position = Vector2 (get_viewport().size.x - 75, 42)
