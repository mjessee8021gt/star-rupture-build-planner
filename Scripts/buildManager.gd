extends Node2D

var current_scene: PackedScene
var ghost_instance: Node2D
var ghost_area: Area2D
var occupied_cells := {}
var is_building := false
@export var canBuildColor := Color(0,1,0, 0.5)
@export var cannotbuildColor := Color(1,0,0,0.5)
@export var tile_size := 32


#entry point to the build manager for the MenuButton
func start_build(scene: PackedScene) -> void:
	print("We are now starting the build preview in the build manager")
	cancel_build()
	
	current_scene = scene
	ghost_instance = scene.instantiate()
	ghost_area = ghost_instance.get_node("PlacementArea")
	is_building = true
	
	ghost_instance.modulate.a = 0.5
	add_child(ghost_instance)
	ghost_area.monitoring = true
	ghost_area.monitorable = false

func can_place_at(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if not is_cell_free(cell):
			return false
	return true
	
func _unhandled_input(event: InputEvent) -> void:
	if not is_building:
		return
	
	if event.is_action_pressed("Build Confirm"):
		confirm_build()
	elif event.is_action_pressed("Build Cancel"):
		cancel_build()

func confirm_build() -> void:
	var anchor_cell := world_to_cell(ghost_instance.global_position)
	var footprint = ghost_instance.get_footprint_cells(anchor_cell, ghost_instance.footprint, ghost_instance.anchor)
	
	if not can_place_at(footprint):
		return
	
	var real := current_scene.instantiate()
	real.global_position = ghost_instance.global_position
	if ghost_instance.footprint == Vector2i(4,4):
		real.flip_footprint()
	$"../buildings".add_child(real)
	
	occupy_cells(footprint)
	$"../Camera2D/CanvasLayer/Panel/HeatLabel".text = str(int($"../Camera2D/CanvasLayer/Panel/HeatLabel".text) + real.heat)
	$"../Camera2D/CanvasLayer/Panel/PowerLabel".text = str(int($"../Camera2D/CanvasLayer/Panel/PowerLabel".text) + real.power)
	cancel_build()
	$"../PathManager"._update_building_list()
	
func cancel_build() -> void:
	if ghost_instance:
		ghost_instance.queue_free()
		
	current_scene = null
	ghost_instance = null
	is_building = false
	
func snap_to_grid(pos: Vector2) -> Vector2:
	return (pos/tile_size).floor() * tile_size
	
func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(pos / tile_size)
	
func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell * tile_size)
	
func occupy_cells(cells: Array[Vector2i]) -> void:
	for cell in cells:
			occupied_cells[cell] = true

func is_cell_free(cell: Vector2i) -> bool:
	return not occupied_cells.has(cell)

func _process(_delta: float) -> void:
	if not is_building:
		return
	
	if Input.is_action_just_pressed("Alternate"):
		ghost_instance.flip_footprint()
	if Input.is_action_just_pressed("Rotate"):
		ghost_instance.rotate(deg_to_rad(90.0))
	if Input.is_action_just_pressed("Build Cancel"):
		cancel_build()
	
	var mouse_pos := get_global_mouse_position()
	var anchor_cell = world_to_cell(mouse_pos)
	var top_left_cell = anchor_cell - ghost_instance.anchor
	print("The recorded footprint of the ghost instance is: %s, %s" %[ghost_instance.footprint.x, ghost_instance.footprint.y])
	var footprint = ghost_instance.get_footprint_cells(anchor_cell, ghost_instance.footprint, ghost_instance.anchor)
	var valid = can_place_at(footprint)
	
	ghost_instance.global_position = cell_to_world(top_left_cell)
	
	if valid == false:
		ghost_instance.modulate = cannotbuildColor
	else:
		ghost_instance.modulate = canBuildColor
