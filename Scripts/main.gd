extends Node2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Camera2D/CanvasLayer/Panel/HeatLabel.text = "0"
	$Camera2D/CanvasLayer/Panel/PowerLabel.text = "0"
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	Adjust_ui_for_resolution()
	recenter_camera()
	
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
	elif (Input.is_action_just_released("Recenter Camera")):
		recenter_camera()

func _on_prod_menu_pressed() -> void:
	$Camera2D/CanvasLayer/ProdMenu/ProdPanel.visible = not $Camera2D/CanvasLayer/ProdMenu/ProdPanel.visible
	
func Adjust_ui_for_resolution() -> void:
	$Camera2D/CanvasLayer/MenuButton.position = Vector2 (15, 15)
	$Camera2D/CanvasLayer/Panel.position = Vector2 (get_viewport().size.x - 180, 5)
	$Camera2D/CanvasLayer/ProdMenu.position = Vector2 (get_viewport().size.x - 75, 42)
	$Camera2D/CanvasLayer/ControlMenu.position = Vector2(15, get_viewport().size.y -50)
	$"Camera2D/CanvasLayer/Patch Notes".position = Vector2(15, get_viewport().size.y -90)
	
func _on_viewport_size_changed() -> void:
	Adjust_ui_for_resolution()

func recenter_camera() -> void:
	$Camera2D.position = get_tilemap_center_global()

func get_tilemap_center_global() -> Vector2:
	var used_rect: Rect2i = $TileMapLayer.get_used_rect()
	var center_cell := used_rect.position + used_rect.size/2
	var local_pos = $TileMapLayer.map_to_local(center_cell)
	
	if used_rect.size == Vector2i.ZERO:
		return Vector2i (0,0)
	
	return $TileMapLayer.to_global(local_pos)
	
