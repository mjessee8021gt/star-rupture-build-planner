extends Node2D

var current_scene: PackedScene
var ghost_instance: Node2D
var ghost_area: Area2D
var occupied_cells : Dictionary = {} #Verctor2i -> Node(Building)
var is_building := false
@export var canBuildColor := Color(0,1,0, 0.5)
@export var cannotbuildColor := Color(1,0,0,0.5)
@export var tile_size := 32

var is_dragging_building := false
var dragged_building : Node2D = null
var drag_mouse_offset := Vector2.ZERO
var drag_original_position := Vector2.ZERO
var drag_original_cells : Array[Vector2i] = []
var drag_last_cells : Array[Vector2i] = []
var drag_last_valid := false


# --- helpers ---
func _get_prod_ledger() -> Node:
	# Autoload is expected to be named "ProdLedger" (per prod_panel.gd),
	# but we also fall back to "ProductionLedger" to be safe.
	var root := get_tree().root
	if root == null:
		return null
	if root.has_node("ProdLedger"):
		return root.get_node("ProdLedger")
	if root.has_node("ProductionLedger"):
		return root.get_node("ProductionLedger")
	return null

func _set_buttons_disabled_recuirsive(node: Node, disabled: bool) -> void:
	if node is Button:
		(node as Button).disabled = disabled
	
	for child in node.get_children():
		_set_buttons_disabled_recuirsive(child, disabled)

func _disable_ports_on_ghost(disabled: bool) -> void:
	if ghost_instance == null:
		return
		
	var ports := ghost_instance.get_node_or_null("Ports")
	if ports != null:
		_set_buttons_disabled_recuirsive(ports, disabled)

func is_build_mode_active() -> bool:
	return is_building

func _get_prod_source_id(building: Node) -> int:
	# Prefer explicit metadata if you set it from the building when registering production.
	if building != null and building.has_meta("prod_source_id"):
		return int(building.get_meta("prod_source_id"))
	return building.get_instance_id()

#entry point to the build manager for the MenuButton
func start_build(scene: PackedScene) -> void:
	print("We are now starting the build preview in the build manager")
	$"../Camera2D/CanvasLayer/Debug Panel/DebugFeed".text = "We are now starting the build preview in the build manager"
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
	if is_building:
		if event.is_action_pressed("Build Confirm"):
			confirm_build()
		elif event.is_action_pressed("Build Cancel"):
			cancel_build()
		return
		
	if not Input.is_action_pressed("Move Build"):
		return
	if _mouse_is_over_control():
		return
		
	var b = get_building_under_mouse()
	if b != null:
		_start_drag_building(b)
	else:
		if is_dragging_building:
			_finish_drag_building()
	

func confirm_build() -> void:
	$"../Camera2D/CanvasLayer/Debug Panel/DebugFeed".text = "We are now confirming the build..."
	var anchor_cell := world_to_cell(ghost_instance.global_position)
	var footprint = ghost_instance.get_footprint_cells(anchor_cell, ghost_instance.footprint, ghost_instance.anchor)
	
	if not can_place_at(footprint):
		return
	
	var real := current_scene.instantiate()
	real.global_position = ghost_instance.global_position
	if ghost_instance.is_alternate == true:
		real.flip_footprint()
	if ghost_instance.rotatedTick > 0:
		real.rotate(deg_to_rad(90.0 * ghost_instance.rotatedTick))
	$"../buildings".add_child(real)
	
	occupy_cells(footprint, real)
	
	$"../Camera2D/CanvasLayer/Panel/HeatLabel".text = str(int($"../Camera2D/CanvasLayer/Panel/HeatLabel".text) + real.heat)
	$"../Camera2D/CanvasLayer/Panel/PowerLabel".text = str(int($"../Camera2D/CanvasLayer/Panel/PowerLabel".text) + real.power)
	
	if real.id == &"helium_extractor" or real.id == &"sulfur_extractor":
		ProdLedger.add_source(real.get_instance_id(), real,real.get_production_deltas(real.recipe))
	cancel_build()
	
func free_cells_for_building(building: Node) -> void:
	var anchor_cell := world_to_cell(building.global_position)
	var cells = building.get_footprint_cells(anchor_cell, building.footprint, building.anchor)
	for cell in cells:
		#only clear cells that still point to the identified building
		if occupied_cells.get(cell) == building:
			occupied_cells.erase(cell)

func cancel_build() -> void:
	if ghost_instance:
		ghost_instance.queue_free()
		
	current_scene = null
	ghost_instance = null
	is_building = false
	
func try_remove_building_under_mouse() -> bool:
	var mouse_pos := get_global_mouse_position()
	var cell := world_to_cell(mouse_pos)
	var building := get_building_at_cells(cell)
	if building == null:
		return false

	# 1) Production deltas: remove this building's contribution from the ledger
	var ledger := _get_prod_ledger()
	if ledger != null and ledger.has_method("remove_source"):
		ledger.remove_source(_get_prod_source_id(building))

	# 2) Remove any paths that reference this building
	var pm := $"../PathManager"
	if pm != null and pm.has_method("remove_paths_for_building"):
		pm.remove_paths_for_building(building)

	# Update the global heat and power consumption.
	$"../Camera2D/CanvasLayer/Panel/HeatLabel".text = str(int($"../Camera2D/CanvasLayer/Panel/HeatLabel".text) - building.heat)
	$"../Camera2D/CanvasLayer/Panel/PowerLabel".text = str(int($"../Camera2D/CanvasLayer/Panel/PowerLabel".text) - building.power)

	# Free grid occupancy
	free_cells_for_building(building)

	# Remove from scene
	building.queue_free()

	return true

func snap_to_grid(pos: Vector2) -> Vector2:
	return (pos/tile_size).floor() * tile_size
	
func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(pos / tile_size)
	
func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell * tile_size)
	
func occupy_cells(cells: Array[Vector2i], Building: Node) -> void:
	for cell in cells:
			occupied_cells[cell] = Building

func is_cell_free(cell: Vector2i) -> bool:
	return not occupied_cells.has(cell)
	
func get_building_at_cells(cell: Vector2i) -> Node:
	return occupied_cells.get(cell, null)
	
func get_building_under_mouse() -> Node2D:
	var mouse_pos := get_global_mouse_position()
	var cell := world_to_cell(mouse_pos)
	return get_building_at_cells(cell)

func _start_drag_building(building: Node2D) -> void:
	if building == null:
		return
		
	is_dragging_building = true
	dragged_building = building
	drag_mouse_offset = building.global_position - get_global_mouse_position()
	drag_original_position = building.global_position
	
	#We are recording and freeing the current cell occupancy of the building so the building can move through itself
	var anchor_cell = world_to_cell(building.global_position)
	drag_original_cells = building.get_footprint_cells(anchor_cell, building.footprint, building.anchor)
	free_cells_for_building(building)
	
func _finish_drag_building() -> void:
	if not is_dragging_building or  dragged_building == null:
		return
	
	if drag_last_valid:
		occupy_cells(drag_last_cells, dragged_building)
	else:
		dragged_building.global_position = drag_original_position
		occupy_cells(drag_original_cells, dragged_building)
	
	dragged_building.modulate = Color(1, 1, 1, 1)	
	
	var pm := $"../PathManager"
	if pm != null and pm.has_method("update_paths_for_building"):
		pm.update_path_for_building(dragged_building)
	
	#drag state cleanup
	is_dragging_building = false
	dragged_building = null
	drag_original_cells = []
	drag_last_cells = []
	drag_last_valid = false
	
func _mouse_is_over_control() -> bool:
	var hovered = get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.is_in_group("port_button")
	
func _process(_delta: float) -> void:
	if is_dragging_building and dragged_building != null:
		var mouse_pos := get_global_mouse_position() + drag_mouse_offset
		var anchor_cell := world_to_cell(mouse_pos)
		var top_left_cell = anchor_cell - dragged_building.anchor
		var new_pos := cell_to_world(top_left_cell)
		dragged_building.global_position = new_pos
		
		var footprint = dragged_building.get_footprint_cells(anchor_cell, dragged_building.footprint, dragged_building.anchor)
		drag_last_cells = footprint
		drag_last_valid = can_place_at(footprint)
		
		if drag_last_valid:
			dragged_building.modulate = canBuildColor
			dragged_building.modulate.a = 1.0
		else:
			dragged_building.modulate = cannotbuildColor
			dragged_building.modulate.a = 1.0
			
		var pm := get_node_or_null("../PathManager")
		if pm != null and pm.has_method("update_paths_for_building"):
			pm.update_paths_for_building(dragged_building)
		
		return 
	
	if Input.is_action_just_pressed("Alternate"):
		ghost_instance.flip_footprint()
	if Input.is_action_just_pressed("Rotate"):
		ghost_instance.rotate(deg_to_rad(90.0))
		if ghost_instance.rotatedTick < 3:
			ghost_instance.rotatedTick += 1
		elif ghost_instance.rotatedTick == 3:
			ghost_instance.rotatedTick = 0
	if Input.is_action_just_pressed("Build Cancel"):
		if is_building:
			cancel_build()
		else:
			try_remove_building_under_mouse()
		return
	
	
	if not is_building:
		return
		
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
