extends Node2D


##------OnReady variables------##
@onready var debug_feed : Label = $"../Camera2D/CanvasLayer/Debug Panel/DebugFeed"
@onready var tile_map_layer: TileMapLayer = $"../TileMapLayer"

##------Object Variables-------##
var current_scene: PackedScene
var ghost_instance: Node2D
var dragged_building : Node2D = null
var ghost_area: Area2D

##------Boolean Variables------##
var is_building := false
var is_dragging_building := false
var drag_last_valid := false

##------Exported Variables-----##
@export var canBuildColor := Color(0,1,0, 0.5)
@export var cannotbuildColor := Color(1,0,0,0.5)
@export var tile_size := 64

##------Vector2 Variables------##
var drag_mouse_offset := Vector2.ZERO
var drag_original_position := Vector2.ZERO
var drag_original_cells : Array[Vector2i] = []
var drag_last_cells : Array[Vector2i] = []
var occupied_cells : Dictionary = {} #Verctor2i -> Node(Building)

##------Constant Variables-----##
const MULTI_BUILD_ACTION := &"Multi-build"

func _ready() -> void:
	if tile_map_layer != null and tile_map_layer.tile_set != null:
		tile_size = tile_map_layer.tile_set.tile_size.x

# --- helpers ---
func _get_prod_ledger() -> Node:
	# Autoload is expected to be named "ProdLedger" (per prod_panel.gd),
	# but we also fall back to "ProductionLedger" to be safe.
	var tree_root := get_tree().root
	if tree_root == null:
		return null
	if tree_root.has_node("ProdLedger"):
		return tree_root.get_node("ProdLedger")
	if tree_root.has_node("ProductionLedger"):
		return tree_root.get_node("ProductionLedger")
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
	
func _is_multi_build_active() -> bool:
	if not InputMap.has_action(MULTI_BUILD_ACTION):
		return false
	return Input.is_action_pressed(MULTI_BUILD_ACTION)

func _get_prod_source_id(building: Node) -> int:
	# Prefer explicit metadata if you set it from the building when registering production.
	if building != null and building.has_meta("prod_source_id"):
		return int(building.get_meta("prod_source_id"))
	return building.get_instance_id()

#entry point to the build manager for the MenuButton
func start_build(scene: PackedScene) -> void:
	print("We are now starting the build preview in the build manager")
	$"../Camera2D/CanvasLayer/Debug Panel/DebugFeed".text = $"../Camera2D/CanvasLayer/Debug Panel/DebugFeed".text + "\n" + "We are now starting the build preview in the build manager"
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
	
func get_rotated_footprint(building: Node) -> Vector2i:
	var footprint: Vector2i = building.footprint
	var rotation_steps := 0
	
	if "rotatedTick" in building:
		rotation_steps = int(building.rotatedTick) %4
	
	return footprint
	
func get_building_anchor(building: Node) -> Vector2i:
	var rotated_footprint := get_rotated_footprint(building)
	return Vector2i(int(floor(rotated_footprint.x / 2.0)), int(floor(rotated_footprint.y/2.0)))
	
func get_building_anchor_cell(building: Node2D) -> Vector2i:
	var top_left_cell := world_to_cell(building.global_position)
	return top_left_cell + get_building_anchor(building)
	
func get_building_cells(building: Node, anchor_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var footprint: Vector2i = building.footprint
	var top_left = anchor_cell - building.anchor

	for y in footprint.y:
		for x in footprint.x:
			cells.append(top_left + Vector2i(x, y))

	return cells

func _unhandled_input(event: InputEvent) -> void:
	var building = get_building_under_mouse()
	
	if is_building:
		if event.is_action_pressed("Build Confirm"):
			confirm_build(_is_multi_build_active())
		elif event.is_action_pressed("Build Cancel"):
			cancel_build()
		return
		
	if not Input.is_action_pressed("Move Build"):
		return
	if _mouse_is_over_control():
		return
		
	if building != null:
		_start_drag_building(building)
	else:
		if is_dragging_building:
			_finish_drag_building()
	

func confirm_build(multi_build_held : bool = false) -> void:
	$"../Camera2D/CanvasLayer/Debug Panel/DebugFeed".text = $"../Camera2D/CanvasLayer/Debug Panel/DebugFeed".text + "\n" + "We are now confirming the build..."
	var anchor_cell := get_building_anchor_cell(ghost_instance)
	var footprint = get_building_cells(ghost_instance,anchor_cell)
	var real_building := current_scene.instantiate()
	
	if not can_place_at(footprint):
		return
	
	real_building.global_position = ghost_instance.global_position
	if ghost_instance.is_alternate == true:
		real_building.flip_footprint()
	if ghost_instance.rotatedTick > 0:
		real_building.rotate(deg_to_rad(90.0 * ghost_instance.rotatedTick))
	$"../buildings".add_child(real_building)
	
	occupy_cells(footprint, real_building)
	
	$"../Camera2D/CanvasLayer/Panel/HeatLabel".text = str(int($"../Camera2D/CanvasLayer/Panel/HeatLabel".text) + real_building.heat)
	$"../Camera2D/CanvasLayer/Panel/PowerLabel".text = str(int($"../Camera2D/CanvasLayer/Panel/PowerLabel".text) + real_building.power)
	
	if real_building.id == &"helium_extractor" or real_building.id == &"sulfur_extractor":
		ProdLedger.add_source(real_building.get_instance_id(), real_building,real_building.get_production_deltas(real_building.recipe))
		
	if _is_multi_build_active() == false:
		cancel_build()
	
func free_cells_for_building(building: Node) -> void:
	var anchor_cell := get_building_anchor_cell(building)
	var cells = get_building_cells(building, anchor_cell)
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
	var build_ledger := _get_prod_ledger()
	if building == null:
		return false

	# 1) Production deltas: remove this building's contribution from the ledger
	if build_ledger != null and build_ledger.has_method("remove_source"):
		build_ledger.remove_source(_get_prod_source_id(building))

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
	return cell_to_world(world_to_cell(pos))
	
func world_to_cell(pos: Vector2) -> Vector2i:
	if tile_map_layer != null:
		return tile_map_layer.local_to_map(tile_map_layer.to_local(pos))
	return Vector2i(floor(pos.x / tile_size), floor(pos.y / tile_size))
	
func cell_to_world(cell: Vector2i) -> Vector2:
	if tile_map_layer != null:
		var center_local := tile_map_layer.map_to_local(cell)
		var half_tile := Vector2(tile_size, tile_size) * 0.5
		return tile_map_layer.to_global(center_local - half_tile)
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
	var anchor_cell = get_building_anchor_cell(building)
	
	if building == null:
		return
		
	is_dragging_building = true
	dragged_building = building
	drag_mouse_offset = building.global_position - get_global_mouse_position()
	drag_original_position = building.global_position
	
	#We are recording and freeing the current cell occupancy of the building so the building can move through itself
	drag_original_cells = get_building_cells(building, anchor_cell)
	free_cells_for_building(building)
	
func _finish_drag_building() -> void:
	var path_manager := $"../PathManager"
	if not is_dragging_building or  dragged_building == null:
		return
	
	if drag_last_valid:
		occupy_cells(drag_last_cells, dragged_building)
	else:
		dragged_building.global_position = drag_original_position
		occupy_cells(drag_original_cells, dragged_building)
	
	dragged_building.modulate = Color(1, 1, 1, 1)	
	
	
	if path_manager != null and path_manager.has_method("update_paths_for_building"):
		path_manager.update_path_for_building(dragged_building)
	
	#drag state cleanup
	is_dragging_building = false
	dragged_building = null
	drag_original_cells = []
	drag_last_cells = []
	drag_last_valid = false
	
func _mouse_is_over_control() -> bool:
	var hoveredControl = get_viewport().gui_get_hovered_control()
	return hoveredControl != null and hoveredControl.is_in_group("port_button")
	
func _process(_delta: float) -> void:
	var mouse_pos
	var anchor_cell
	var path_manager := get_node_or_null("../PathManager")
	var building_footprint
	var new_pos
	var top_left_cell
	var valid_placement
	
	if is_dragging_building and dragged_building != null:
		mouse_pos = get_global_mouse_position() + drag_mouse_offset
		anchor_cell = world_to_cell(mouse_pos)
		top_left_cell = anchor_cell - get_building_anchor(dragged_building)
		new_pos = cell_to_world(top_left_cell)
		building_footprint = get_building_cells(dragged_building, anchor_cell)
		
		dragged_building.global_position = new_pos
		drag_last_cells = building_footprint
		drag_last_valid = can_place_at(building_footprint)
		
		if drag_last_valid:
			dragged_building.modulate = canBuildColor
			dragged_building.modulate.a = 1.0
		else:
			dragged_building.modulate = cannotbuildColor
			dragged_building.modulate.a = 1.0
			
		if path_manager != null and path_manager.has_method("update_paths_for_building"):
			path_manager.update_paths_for_building(dragged_building)
		return 
	
	if is_building and ghost_instance != null and Input.is_action_just_pressed("Alternate"):
		ghost_instance.flip_footprint()
	if is_building and ghost_instance != null and  Input.is_action_just_pressed("Rotate"):
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
		
	mouse_pos = get_global_mouse_position()
	anchor_cell = world_to_cell(mouse_pos)
	top_left_cell = anchor_cell - get_building_anchor(ghost_instance)
	print("The recorded footprint of the ghost instance is: %s, %s" %[ghost_instance.footprint.x, ghost_instance.footprint.y])
	building_footprint = get_building_cells(ghost_instance, anchor_cell)
	valid_placement = can_place_at(building_footprint)
	
	ghost_instance.global_position = cell_to_world(top_left_cell)
	
	if valid_placement == false:
		ghost_instance.modulate = cannotbuildColor
	else:
		ghost_instance.modulate = canBuildColor
