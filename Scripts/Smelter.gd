extends Node2D

@export var tileMap : TileMap
var footprint := Vector2i(3,4)
@export var footprint_primary := Vector2i(3,4)
@export var footprint_alt := Vector2i(4,4)
@export var anchor := Vector2i.ZERO
@onready var placement_area: Area2D = $PlacementArea

var dragging := false
var drag_offset := Vector2.ZERO

func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if(dragging):
				drag_offset = global_position - get_global_mouse_position()
		elif event.button_index == KEY_CTRL:
			if $PrimarySprite.visible == true:
				$PrimarySprite.visible = false
				$AlternateSprite.visible = true
			else:
				$PrimarySprite.visible = true
				$AlternateSprite.visible = false

func _process(delta: float):
	if dragging:
		var mouse_pos = get_global_mouse_position() + drag_offset
		snap_to_grid(mouse_pos)
		
func snap_to_grid(world_pos: Vector2):
	var local_pos = tileMap.to_local(world_pos)
	var map_coords = tileMap.local_to_map(local_pos)
	var snapped_local = tileMap.map_to_local(map_coords)
	global_position = tileMap.to_global(snapped_local)

func get_footprint_cells(anchor_cell: Vector2i, footprint_size: Vector2i, anchor: Vector2i) -> Array[Vector2i]:
	var cells : Array[Vector2i]= []
	
	var top_left := anchor_cell - anchor
	
	for y in footprint_size.y:
		for x in footprint_size.x:
			cells.append(top_left + Vector2i(x, y))
			
	return cells
	
func flip_footprint() -> void:
	if $PrimarySprite.visible == true:
		$PrimarySprite.visible = false
		$AlternateSprite.visible = true
		$CollisionShape2D.disabled = true
		$CollisionShapeAlt.disabled = false
		footprint = footprint_alt
	else:
		$PrimarySprite.visible = true
		$CollisionShape2D.disabled = false
		$AlternateSprite.visible = false
		$CollisionShapeAlt.disabled = true
		footprint = footprint_primary
