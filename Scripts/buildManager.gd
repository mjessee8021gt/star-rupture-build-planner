extends Node2D

const Palette = preload("res://Scripts/palette.gd")


##------OnReady variables------##
@onready var tile_map_layer: TileMapLayer = $"../TileMapLayer"

##------Object Variables-------##
var current_scene: PackedScene
var ghost_instance: Node2D
var dragged_building : Node2D = null
var ghost_area: Area2D
var ghost_selection_template: Dictionary = {}
var group_build_entries: Array[Dictionary] = []
var selected_buildings: Array[Node2D] = []
var selected_original_modulates: Dictionary = {}

##------Boolean Variables------##
var is_building := false
var is_dragging_building := false
var is_selecting_buildings := false
var drag_last_valid := false

##------Exported Variables-----##
@export var canBuildColor := Palette.BUILD_VALID
@export var cannotbuildColor := Palette.BUILD_INVALID
@export var tile_size := 64

##------Vector2 Variables------##
var drag_mouse_offset := Vector2.ZERO
var selection_start_world := Vector2.ZERO
var selection_current_world := Vector2.ZERO
var selection_start_screen := Vector2.ZERO
var drag_original_position := Vector2.ZERO
var drag_original_rotation := 0.0
var drag_original_rotated_tick := 0
var drag_original_cells : Array[Vector2i] = []
var drag_last_cells : Array[Vector2i] = []
var drag_history_before: Dictionary = {}
var drag_buildings: Array[Node2D] = []
var drag_anchor_offsets: Dictionary = {}
var drag_original_positions: Dictionary = {}
var drag_original_rotations: Dictionary = {}
var drag_original_rotated_ticks: Dictionary = {}
var drag_original_modulates: Dictionary = {}
var drag_original_cells_by_building: Dictionary = {}
var drag_last_cells_by_building: Dictionary = {}
var occupied_cells : Dictionary = {} #Verctor2i -> Node(Building)

##------Constant Variables-----##
const MULTI_BUILD_ACTION := &"Multi-build"
const EYEDROPPER_ACTION := &"Eyedropper"
const EYEDROPPER_ALT_ACTION := &"Eyedropper (Alt)"
const PORT_BUTTON_GROUP := &"port_button"
const PORT_BUTTON_ORIGINAL_MOUSE_FILTER_META := &"build_manager_original_mouse_filter"
const SELECTION_TEMPLATE_OPTION_NAMES := ["Recipe", "Purity", "CoreLevel"]
const SELECTION_DRAG_THRESHOLD := 6.0
const SELECTION_BOX_FILL := Color(0.337255, 0.705882, 0.823529, 0.18)
const SELECTION_BOX_OUTLINE := Color(0.337255, 0.705882, 0.823529, 0.9)
const SELECTED_BUILDING_MODULATE := Color(1.0, 0.88, 0.42, 1.0)

func _ready() -> void:
	if tile_map_layer != null and tile_map_layer.tile_set != null:
		tile_size = tile_map_layer.tile_set.tile_size.x

func _exit_tree() -> void:
	_set_port_buttons_passthrough_for_build_mode(false)

func _draw() -> void:
	if not is_selecting_buildings:
		return

	var local_start := to_local(selection_start_world)
	var local_current := to_local(selection_current_world)
	var selection_rect := _rect_from_points(local_start, local_current)
	if selection_rect.size.length() <= 0.0:
		return

	draw_rect(selection_rect, SELECTION_BOX_FILL, true)
	draw_rect(selection_rect, SELECTION_BOX_OUTLINE, false, 2.0, true)

# --- helpers ---
func _rect_from_points(from: Vector2, to: Vector2) -> Rect2:
	var top_left := Vector2(min(from.x, to.x), min(from.y, to.y))
	var bottom_right := Vector2(max(from.x, to.x), max(from.y, to.y))
	return Rect2(top_left, bottom_right - top_left)

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

func _is_scene_input_blocked() -> bool:
	var main_scene := get_parent()
	return main_scene != null and main_scene.has_method("is_scene_input_blocked") and main_scene.is_scene_input_blocked()

func is_build_mode_active() -> bool:
	return is_building
	
func _is_multi_build_active() -> bool:
	if not InputMap.has_action(MULTI_BUILD_ACTION):
		return false
	return Input.is_action_pressed(MULTI_BUILD_ACTION)

func _get_history_host() -> Node:
	var main_scene := get_parent()
	if main_scene == null:
		return null
	if not main_scene.has_method("_capture_history_state") or not main_scene.has_method("_commit_history_action"):
		return null
	return main_scene

func _capture_history_state() -> Dictionary:
	var history_host := _get_history_host()
	if history_host == null:
		return {}
	var captured = history_host.call("_capture_history_state")
	return captured if captured is Dictionary else {}

func _commit_history_action(label: String, before_state: Dictionary) -> void:
	var history_host := _get_history_host()
	if history_host == null:
		return
	history_host.call("_commit_history_action", label, before_state)

func _get_prod_source_id(building: Node) -> int:
	# Prefer explicit metadata if you set it from the building when registering production.
	if building != null and building.has_meta("prod_source_id"):
		return int(building.get_meta("prod_source_id"))
	return building.get_instance_id()

func _get_building_footprint_offset(building: Node) -> Vector2:
	if building == null:
		return Vector2.ZERO

	var footprint = get_rotated_footprint(building)
	if footprint != Vector2i.ZERO:
		return Vector2(footprint) * (float(tile_size) * 0.5)

	return Vector2.ZERO

func _anchor_cell_from_building_position(building: Node, building_pos: Vector2) -> Vector2i:
	var anchor := Vector2i.ZERO
	var anchor_value = building.get("anchor")
	if anchor_value is Vector2i:
		anchor = anchor_value

	var top_left_world := building_pos - _get_building_footprint_offset(building)
	var top_left_cell := world_to_cell(top_left_world)
	return top_left_cell + anchor

func _position_from_anchor_cell(building: Node, anchor_cell: Vector2i) -> Vector2:
	var anchor := Vector2i.ZERO
	var anchor_value = building.get("anchor")
	if anchor_value is Vector2i:
		anchor = anchor_value

	var top_left_cell := anchor_cell - anchor
	var top_left_world := cell_to_world(top_left_cell)
	return top_left_world + _get_building_footprint_offset(building)

#entry point to the build manager for the MenuButton
func start_build(scene: PackedScene) -> void:
	if scene == null:
		return

	var pm := $"../PathManager"
	if pm != null and pm.has_method("cancel_active_path_drag"):
		pm.cancel_active_path_drag()
	cancel_build()
	_clear_selection()
	
	current_scene = scene
	ghost_instance = scene.instantiate()
	ghost_area = ghost_instance.get_node("PlacementArea")
	is_building = true
	
	ghost_instance.modulate.a = 0.5
	add_child(ghost_instance)
	ghost_area.monitoring = true
	ghost_area.monitorable = false
	_set_port_buttons_passthrough_for_build_mode(true)

func can_place_at(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if not is_cell_free(cell):
			return false
	return true
	
func get_rotated_footprint(building: Node) -> Vector2i:
	if building == null:
		return Vector2i.ZERO
	var footprint = building.get("footprint")
	if not (footprint is Vector2i):
		return Vector2i.ZERO
		
	var rotation_steps := 0
	
	if "rotatedTick" in building:
		rotation_steps = int(building.rotatedTick) %4
		
	if rotation_steps %2 == 1:
		return Vector2i(footprint.y, footprint.x)
	
	return footprint
	
func get_building_anchor(building: Node) -> Vector2i:
	var rotated_footprint := get_rotated_footprint(building)
	return Vector2i(int(floor(rotated_footprint.x / 2.0)), int(floor(rotated_footprint.y/2.0)))
	
func get_building_anchor_cell(building: Node2D) -> Vector2i:
	var top_left_cell := world_to_cell(building.global_position)
	return top_left_cell + get_building_anchor(building)
	
func get_building_cells(building: Node, anchor_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var footprint:= get_rotated_footprint(building)
	var top_left = anchor_cell - building.anchor

	for y in footprint.y:
		for x in footprint.x:
			cells.append(top_left + Vector2i(x, y))

	return cells

func _handle_selection_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return false

		if mouse_event.pressed:
			if is_building or is_dragging_building or _mouse_is_over_any_control():
				return false
			_start_selection_box(mouse_event.position)
			return true

		if is_selecting_buildings:
			_finish_selection_box(mouse_event.position)
			return true

	elif event is InputEventMouseMotion and is_selecting_buildings:
		_update_selection_box()
		return true

	return false

func _start_selection_box(screen_position: Vector2) -> void:
	is_selecting_buildings = true
	selection_start_world = get_global_mouse_position()
	selection_current_world = selection_start_world
	selection_start_screen = screen_position
	queue_redraw()

func _update_selection_box() -> void:
	selection_current_world = get_global_mouse_position()
	queue_redraw()

func _finish_selection_box(screen_position: Vector2) -> void:
	selection_current_world = get_global_mouse_position()
	is_selecting_buildings = false

	if selection_start_screen.distance_to(screen_position) < SELECTION_DRAG_THRESHOLD:
		var clicked_building := get_building_under_mouse()
		if clicked_building != null:
			_select_buildings([clicked_building])
		else:
			_clear_selection()
		queue_redraw()
		return

	var selection_rect := _rect_from_points(selection_start_world, selection_current_world)
	var buildings_in_rect: Array[Node2D] = []
	for building in _get_all_placed_buildings():
		var building_rect := _get_building_world_rect(building)
		if selection_rect.intersects(building_rect, true):
			buildings_in_rect.append(building)

	_select_buildings(buildings_in_rect)
	queue_redraw()

func _get_all_placed_buildings() -> Array[Node2D]:
	var placed_buildings: Array[Node2D] = []
	var seen := {}
	for building in occupied_cells.values():
		if not (building is Node2D):
			continue
		if seen.has(building):
			continue
		seen[building] = true
		if is_instance_valid(building):
			placed_buildings.append(building)
	return placed_buildings

func _get_building_world_rect(building: Node2D) -> Rect2:
	if building == null:
		return Rect2()

	var anchor_cell := _anchor_cell_from_building_position(building, building.global_position)
	var cells := get_building_cells(building, anchor_cell)
	if cells.is_empty():
		return Rect2(building.global_position, Vector2.ZERO)

	var min_cell := cells[0]
	var max_cell := cells[0]
	for cell in cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)

	var top_left := cell_to_world(min_cell)
	var bottom_right := cell_to_world(max_cell + Vector2i.ONE)
	return Rect2(top_left, bottom_right - top_left)

func _select_buildings(buildings: Array[Node2D]) -> void:
	_clear_selection()

	var seen := {}
	for building in buildings:
		if building == null or not is_instance_valid(building) or seen.has(building):
			continue
		seen[building] = true
		selected_buildings.append(building)
		selected_original_modulates[building] = building.modulate
		building.modulate = SELECTED_BUILDING_MODULATE

func _clear_selection() -> void:
	for building in selected_buildings:
		if is_instance_valid(building):
			building.modulate = selected_original_modulates.get(building, Color(1, 1, 1, 1))
	selected_buildings.clear()
	selected_original_modulates.clear()

func _remove_building_from_selection(building: Node) -> void:
	if building == null:
		return
	selected_buildings.erase(building)
	selected_original_modulates.erase(building)

func _is_building_selected(building: Node) -> bool:
	return building != null and selected_buildings.has(building)

func _prune_selection() -> void:
	for building in selected_buildings.duplicate():
		if not is_instance_valid(building):
			selected_buildings.erase(building)
			selected_original_modulates.erase(building)

func _get_valid_selected_buildings() -> Array[Node2D]:
	_prune_selection()
	var valid_buildings: Array[Node2D] = []
	for building in selected_buildings:
		if is_instance_valid(building):
			valid_buildings.append(building)
	return valid_buildings

func _get_single_selected_building() -> Node2D:
	var valid_buildings := _get_valid_selected_buildings()
	if valid_buildings.size() == 1:
		return valid_buildings[0]
	return null

func _can_place_group_cells(cells: Array[Vector2i]) -> bool:
	var seen := {}
	for cell in cells:
		if seen.has(cell):
			return false
		seen[cell] = true
		if not is_cell_free(cell):
			return false
	return true

func _unhandled_input(event: InputEvent) -> void:
	if _is_scene_input_blocked():
		return

	var building = get_building_under_mouse()

	if event.is_action_pressed(EYEDROPPER_ALT_ACTION, false, true):
		if not is_dragging_building and not is_selecting_buildings and not _mouse_is_over_any_control():
			_start_eyedropper_build(building, true)
		return

	if event.is_action_pressed(EYEDROPPER_ACTION, false, true):
		if not is_dragging_building and not is_selecting_buildings and not _mouse_is_over_any_control():
			_start_eyedropper_build(building, false)
		return
	
	if is_building:
		if event.is_action_pressed("Build Confirm"):
			confirm_build(_is_multi_build_active())
		elif event.is_action_pressed("Build Cancel", true):
			cancel_build()
		return

	if _handle_selection_input(event):
		return
		
	if is_dragging_building and event.is_action_released("Move Build"):
		_finish_drag_building()
		return
	if is_dragging_building:
		return
		
	if not event.is_action_pressed("Move Build"):
		return
	if _mouse_is_over_control():
		return
		
	if building != null:
		_start_drag_building(building)
	
func _start_eyedropper_build(building: Node2D, copy_selection_state := false) -> void:
	var source_buildings := _get_eyedropper_source_buildings(building)
	if source_buildings.is_empty():
		return

	if source_buildings.size() > 1:
		_start_group_eyedropper_build(source_buildings, _get_eyedropper_anchor_building(building, source_buildings), copy_selection_state)
		return

	var source_building := source_buildings[0]
	var scene := _get_scene_for_building(source_building)
	if scene == null:
		return

	var selection_template := _capture_building_selection_template(source_building) if copy_selection_state else {}
	start_build(scene)
	_apply_build_template_from_building(source_building)
	ghost_selection_template = selection_template
	_apply_building_selection_template(ghost_instance, ghost_selection_template, false)

func _get_eyedropper_source_buildings(cursored_building: Node2D) -> Array[Node2D]:
	var source_buildings: Array[Node2D] = []
	var selected := _get_valid_selected_buildings()

	if not selected.is_empty():
		if cursored_building != null and _is_building_selected(cursored_building):
			return selected
		if cursored_building == null:
			return selected

	if cursored_building != null:
		source_buildings.append(cursored_building)
	return source_buildings

func _get_eyedropper_anchor_building(cursored_building: Node2D, source_buildings: Array[Node2D]) -> Node2D:
	if cursored_building != null and source_buildings.has(cursored_building):
		return cursored_building
	if not source_buildings.is_empty():
		return source_buildings[0]
	return null

func _start_group_eyedropper_build(source_buildings: Array[Node2D], anchor_building: Node2D, copy_selection_state := false) -> void:
	if source_buildings.is_empty() or anchor_building == null:
		return

	var source_anchor_cell := _anchor_cell_from_building_position(anchor_building, anchor_building.global_position)
	var pending_entries: Array[Dictionary] = []
	for source_building in source_buildings:
		var scene := _get_scene_for_building(source_building)
		if scene == null:
			continue

		var source_building_anchor_cell := _anchor_cell_from_building_position(source_building, source_building.global_position)
		pending_entries.append({
			"source": source_building,
			"scene": scene,
			"anchor_offset": source_building_anchor_cell - source_anchor_cell,
			"selection_template": _capture_building_selection_template(source_building) if copy_selection_state else {}
		})

	if pending_entries.is_empty():
		return

	var pm := $"../PathManager"
	if pm != null and pm.has_method("cancel_active_path_drag"):
		pm.cancel_active_path_drag()
	cancel_build()
	_clear_selection()

	is_building = true
	group_build_entries.clear()
	for entry in pending_entries:
		var scene := entry.get("scene") as PackedScene
		var source_building := entry.get("source") as Node2D
		if scene == null or source_building == null:
			continue

		var ghost := scene.instantiate() as Node2D
		if ghost == null:
			continue
		add_child(ghost)
		_apply_build_template_to_ghost(source_building, ghost)
		_apply_building_selection_template(ghost, entry.get("selection_template", {}), false)
		ghost.modulate.a = 0.5
		entry["ghost"] = ghost
		group_build_entries.append(entry)

	if group_build_entries.is_empty():
		cancel_build()
		return

	ghost_instance = group_build_entries[0].get("ghost") as Node2D
	ghost_area = null
	if ghost_instance != null:
		ghost_area = ghost_instance.get_node_or_null("PlacementArea") as Area2D
	_set_port_buttons_passthrough_for_build_mode(true)
	_update_group_ghost_placement()

func _get_scene_for_building(building: Node) -> PackedScene:
	if building == null:
		return null

	if "id" in building:
		var building_id := StringName(building.get("id"))
		if building_id != StringName(""):
			var registered_scene := BuildRegistry.get_scene(building_id)
			if registered_scene != null:
				return registered_scene

	if building.scene_file_path != "":
		return load(building.scene_file_path) as PackedScene

	return null

func _apply_build_template_from_building(building: Node2D) -> void:
	_apply_build_template_to_ghost(building, ghost_instance)

func _apply_build_template_to_ghost(building: Node2D, target_ghost: Node2D) -> void:
	if building == null or target_ghost == null:
		return

	if "is_alternate" in building and "is_alternate" in target_ghost:
		var source_is_alternate := bool(building.get("is_alternate"))
		var ghost_is_alternate := bool(target_ghost.get("is_alternate"))
		if source_is_alternate != ghost_is_alternate and target_ghost.has_method("flip_footprint"):
			target_ghost.flip_footprint()

	var rotation_tick := _get_rotation_tick_for_building(building)
	if "rotatedTick" in target_ghost:
		target_ghost.rotatedTick = rotation_tick
	target_ghost.rotation = deg_to_rad(90.0 * rotation_tick)

func _get_rotation_tick_for_building(building: Node2D) -> int:
	if building == null:
		return 0

	if "rotatedTick" in building:
		var stored_tick := int(building.get("rotatedTick")) % 4
		if stored_tick != 0 or is_zero_approx(building.rotation):
			return stored_tick

	var rotation_tick := int(round(rad_to_deg(building.rotation) / 90.0)) % 4
	if rotation_tick < 0:
		rotation_tick += 4
	return rotation_tick

func _capture_building_selection_template(building: Node) -> Dictionary:
	var template: Dictionary = {}
	if building == null:
		return template

	for option_name in SELECTION_TEMPLATE_OPTION_NAMES:
		var selection := _serialize_option_button(building.get_node_or_null(option_name))
		if not selection.is_empty():
			template[option_name] = selection

	return template

func _serialize_option_button(node: Node) -> Dictionary:
	if node == null or not (node is OptionButton):
		return {}

	var option_button := node as OptionButton
	var selected := option_button.selected
	if selected < 0 or selected >= option_button.item_count:
		return {}

	var metadata_path := ""
	var metadata = option_button.get_item_metadata(selected)
	if metadata is Resource:
		metadata_path = (metadata as Resource).resource_path
	elif metadata != null:
		metadata_path = str(metadata)

	return {
		"selected": selected,
		"metadata_path": metadata_path
	}

func _apply_building_selection_template(building: Node2D, selection_template: Dictionary, call_handlers: bool) -> void:
	if building == null or selection_template.is_empty():
		return

	var recipe_dropdown := building.get_node_or_null("Recipe") as OptionButton
	var purity_dropdown := building.get_node_or_null("Purity") as OptionButton
	var core_level_dropdown := building.get_node_or_null("CoreLevel") as OptionButton

	_restore_option_selection(recipe_dropdown, selection_template.get("Recipe", {}))

	if purity_dropdown != null:
		if call_handlers:
			_call_option_selection_handler(building, "_on_recipe_item_selected", recipe_dropdown)
		else:
			_populate_purity_for_selected_recipe(building, recipe_dropdown)

	_restore_option_selection(purity_dropdown, selection_template.get("Purity", {}))

	if call_handlers:
		var applied_purity := _call_option_selection_handler(building, "_on_purity_item_selected", purity_dropdown)
		if purity_dropdown == null or not applied_purity:
			_call_option_selection_handler(building, "_on_recipe_item_selected", recipe_dropdown)

	_restore_option_selection(core_level_dropdown, selection_template.get("CoreLevel", {}))
	if call_handlers:
		_call_option_selection_handler(building, "_on_core_level_item_selected", core_level_dropdown)

func _populate_purity_for_selected_recipe(building: Node, recipe_dropdown: OptionButton) -> void:
	if building == null or recipe_dropdown == null:
		return
	if not building.has_method("_populate_purity_for_recipe"):
		return
	if recipe_dropdown.selected < 0 or recipe_dropdown.selected >= recipe_dropdown.item_count:
		return

	var recipe = recipe_dropdown.get_item_metadata(recipe_dropdown.selected)
	if recipe == null:
		return

	building.call("_populate_purity_for_recipe", recipe)

func _call_option_selection_handler(building: Node, method_name: String, option_button: OptionButton) -> bool:
	if building == null or option_button == null:
		return false
	if not building.has_method(method_name):
		return false
	if option_button.selected < 0 or option_button.selected >= option_button.item_count:
		return false

	building.call(method_name, option_button.selected)
	return true

func _restore_option_selection(node: Node, selection_data: Dictionary) -> void:
	if node == null or not (node is OptionButton) or selection_data.is_empty():
		return

	var option_button := node as OptionButton
	var matched := false
	var metadata_path := String(selection_data.get("metadata_path", ""))

	if metadata_path != "":
		for i in range(option_button.item_count):
			var metadata = option_button.get_item_metadata(i)
			if metadata is Resource and (metadata as Resource).resource_path == metadata_path:
				option_button.select(i)
				matched = true
				break
			elif str(metadata) == metadata_path:
				option_button.select(i)
				matched = true
				break

	if not matched:
		var selected := int(selection_data.get("selected", -1))
		if selected >= 0 and selected < option_button.item_count:
			option_button.select(selected)

func _apply_confirmed_building_selection_template(building: Node2D) -> void:
	_apply_confirmed_selection_template(building, ghost_selection_template)

func _apply_confirmed_selection_template(building: Node2D, selection_template: Dictionary) -> void:
	if building == null or selection_template.is_empty():
		return

	var heat_text = $"../Camera2D/CanvasLayer/Panel/HeatLabel".text
	var power_text = $"../Camera2D/CanvasLayer/Panel/PowerLabel".text
	_apply_building_selection_template(building, selection_template, true)
	$"../Camera2D/CanvasLayer/Panel/HeatLabel".text = heat_text
	$"../Camera2D/CanvasLayer/Panel/PowerLabel".text = power_text

func _is_group_build_active() -> bool:
	return not group_build_entries.is_empty()

func _get_group_entry_anchor_offset(entry: Dictionary) -> Vector2i:
	var anchor_offset := Vector2i.ZERO
	var stored_offset = entry.get("anchor_offset", Vector2i.ZERO)
	if stored_offset is Vector2i:
		anchor_offset = stored_offset
	return anchor_offset

func _update_group_ghost_placement() -> bool:
	if not _is_group_build_active():
		return false

	var anchor_cell := world_to_cell(get_global_mouse_position())
	var all_group_cells: Array[Vector2i] = []
	for entry in group_build_entries:
		var ghost := entry.get("ghost") as Node2D
		if ghost == null:
			continue

		var target_anchor_cell := anchor_cell + _get_group_entry_anchor_offset(entry)
		var ghost_cells := get_building_cells(ghost, target_anchor_cell)
		ghost.global_position = _position_from_anchor_cell(ghost, target_anchor_cell)
		entry["last_cells"] = ghost_cells.duplicate()
		for cell in ghost_cells:
			all_group_cells.append(cell)

	var valid_placement := not all_group_cells.is_empty() and _can_place_group_cells(all_group_cells)
	var ghost_color := canBuildColor if valid_placement else cannotbuildColor
	for entry in group_build_entries:
		var ghost := entry.get("ghost") as Node2D
		if ghost != null:
			ghost.modulate = ghost_color

	return valid_placement

func _flip_group_ghosts() -> void:
	for entry in group_build_entries:
		var ghost := entry.get("ghost") as Node2D
		if ghost != null and ghost.has_method("flip_footprint"):
			ghost.flip_footprint()

func _rotate_group_ghosts_90_degrees() -> void:
	for entry in group_build_entries:
		var ghost := entry.get("ghost") as Node2D
		if ghost != null:
			_rotate_building_90_degrees(ghost)

func _configure_real_building_from_ghost(real_building: Node2D, source_ghost: Node2D) -> void:
	if real_building == null or source_ghost == null:
		return

	real_building.global_position = source_ghost.global_position
	if "is_alternate" in source_ghost and bool(source_ghost.get("is_alternate")) and real_building.has_method("flip_footprint"):
		real_building.flip_footprint()
	if "rotatedTick" in real_building:
		real_building.rotatedTick = int(source_ghost.rotatedTick) if "rotatedTick" in source_ghost else 0
	real_building.rotation = source_ghost.rotation

func _apply_constructed_building_effects(real_building: Node2D) -> void:
	$"../Camera2D/CanvasLayer/Panel/HeatLabel".text = str(int($"../Camera2D/CanvasLayer/Panel/HeatLabel".text) + real_building.heat)
	$"../Camera2D/CanvasLayer/Panel/PowerLabel".text = str(int($"../Camera2D/CanvasLayer/Panel/PowerLabel".text) + real_building.power)
	_apply_build_cost_delta(real_building, 1)

	if real_building.id == &"helium_extractor" or real_building.id == &"sulfur_extractor" or real_building.id == &"laser_drill" or real_building.id == &"oil_extractor":
		ProdLedger.add_source(real_building.get_instance_id(), real_building, real_building.get_production_deltas(real_building.recipe))

func _confirm_group_build(_multi_build_held: bool = false) -> void:
	if not _update_group_ghost_placement():
		return

	var history_before := _capture_history_state()
	for entry in group_build_entries:
		var scene := entry.get("scene") as PackedScene
		var ghost := entry.get("ghost") as Node2D
		if scene == null or ghost == null:
			continue

		var real_building := scene.instantiate() as Node2D
		if real_building == null:
			continue

		_configure_real_building_from_ghost(real_building, ghost)
		$"../buildings".add_child(real_building)
		_apply_confirmed_selection_template(real_building, entry.get("selection_template", {}))
		occupy_cells(_get_cell_array_from_dictionary(entry, "last_cells"), real_building)
		_apply_constructed_building_effects(real_building)

	_commit_history_action("Buildings constructed", history_before)
	if not _multi_build_held:
		cancel_build()

func confirm_build(_multi_build_held : bool = false) -> void:
	if _is_group_build_active():
		_confirm_group_build(_multi_build_held)
		return

	$"../Camera2D/CanvasLayer/Debug Panel/DebugFeed".text = $"../Camera2D/CanvasLayer/Debug Panel/DebugFeed".text + "\n" + "We are now confirming the build..."
	var anchor_cell := _anchor_cell_from_building_position(ghost_instance, ghost_instance.global_position)
	var footprint = get_building_cells(ghost_instance,anchor_cell)
	var real_building := current_scene.instantiate()
	
	if not can_place_at(footprint):
		return
	
	var history_before := _capture_history_state()
	real_building.global_position = ghost_instance.global_position
	if ghost_instance.is_alternate == true:
		real_building.flip_footprint()
	if "rotatedTick" in real_building:
		real_building.rotatedTick = int(ghost_instance.rotatedTick) if "rotatedTick" in ghost_instance else 0
	real_building.rotation = ghost_instance.rotation
	$"../buildings".add_child(real_building)
	_set_port_buttons_passthrough_for_build_mode(true)
	_apply_confirmed_building_selection_template(real_building)
	
	occupy_cells(footprint, real_building)
	
	$"../Camera2D/CanvasLayer/Panel/HeatLabel".text = str(int($"../Camera2D/CanvasLayer/Panel/HeatLabel".text) + real_building.heat)
	$"../Camera2D/CanvasLayer/Panel/PowerLabel".text = str(int($"../Camera2D/CanvasLayer/Panel/PowerLabel".text) + real_building.power)
	_apply_build_cost_delta(real_building, 1)
	
	if real_building.id == &"helium_extractor" or real_building.id == &"sulfur_extractor" or real_building.id == &"laser_drill" or real_building.id == &"oil_extractor":
		ProdLedger.add_source(real_building.get_instance_id(), real_building,real_building.get_production_deltas(real_building.recipe))

	_commit_history_action("Building constructed", history_before)
		
	if _is_multi_build_active() == false:
		cancel_build()
	
func free_cells_for_building(building: Node) -> void:
	var anchor_cell := _anchor_cell_from_building_position(building, building.global_position)
	var cells = get_building_cells(building, anchor_cell)
	for cell in cells:
		#only clear cells that still point to the identified building
		if occupied_cells.get(cell) == building:
			occupied_cells.erase(cell)

func cancel_build() -> void:
	if _is_group_build_active():
		for entry in group_build_entries:
			var ghost := entry.get("ghost") as Node2D
			if ghost != null:
				ghost.queue_free()
	elif ghost_instance:
		ghost_instance.queue_free()
		
	current_scene = null
	ghost_instance = null
	ghost_area = null
	ghost_selection_template = {}
	group_build_entries.clear()
	is_building = false
	_set_port_buttons_passthrough_for_build_mode(false)
	
func try_remove_building_under_mouse() -> bool:
	var mouse_pos := get_global_mouse_position()
	var cell := world_to_cell(mouse_pos)
	var building := get_building_at_cells(cell)
	var build_ledger := _get_prod_ledger()
	var pm := $"../PathManager"
	
	if building == null:
		return false

	var history_before := _capture_history_state()
		
	if pm != null and pm.has_method("cancel_active_path_drag"):
		pm.cancel_active_path_drag()

	# 1) Production deltas: remove this building's contribution from the ledger
	if build_ledger != null and build_ledger.has_method("remove_source"):
		build_ledger.remove_source(_get_prod_source_id(building))

	# 2) Remove any paths that reference this building
	if pm != null and pm.has_method("remove_paths_for_building"):
		pm.remove_paths_for_building(building)

	# Update the global heat and power consumption.
	$"../Camera2D/CanvasLayer/Panel/HeatLabel".text = str(int($"../Camera2D/CanvasLayer/Panel/HeatLabel".text) - building.heat)
	$"../Camera2D/CanvasLayer/Panel/PowerLabel".text = str(int($"../Camera2D/CanvasLayer/Panel/PowerLabel".text) - building.power)
	_apply_build_cost_delta(building, -1)

	# Free grid occupancy
	free_cells_for_building(building)
	_remove_building_from_selection(building)

	# Remove from scene
	var building_parent := building.get_parent()
	if building_parent != null:
		building_parent.remove_child(building)
	building.queue_free()

	_commit_history_action("Building deleted", history_before)

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
	
func occupy_cells(cells: Array[Vector2i], building_node: Node) -> void:
	for cell in cells:
			occupied_cells[cell] = building_node

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

	_prune_selection()
	var buildings_to_drag: Array[Node2D] = []
	if _is_building_selected(building):
		buildings_to_drag = _get_valid_selected_buildings()
	else:
		_clear_selection()
		buildings_to_drag.append(building)

	if buildings_to_drag.is_empty():
		return
		
	is_dragging_building = true
	dragged_building = building
	drag_mouse_offset = building.global_position - get_global_mouse_position()
	drag_original_position = building.global_position
	drag_original_rotation = building.rotation
	drag_original_rotated_tick = int(building.rotatedTick) if "rotatedTick" in building else 0
	drag_history_before = _capture_history_state()
	drag_buildings = buildings_to_drag
	drag_anchor_offsets.clear()
	drag_original_positions.clear()
	drag_original_rotations.clear()
	drag_original_rotated_ticks.clear()
	drag_original_modulates.clear()
	drag_original_cells_by_building.clear()
	drag_last_cells_by_building.clear()
	drag_original_cells = []
	drag_last_cells = []

	var primary_anchor_cell := _anchor_cell_from_building_position(building, building.global_position)
	var all_original_cells: Array[Vector2i] = []
	for drag_target in drag_buildings:
		var target_anchor_cell := _anchor_cell_from_building_position(drag_target, drag_target.global_position)
		var target_cells := get_building_cells(drag_target, target_anchor_cell)
		drag_anchor_offsets[drag_target] = target_anchor_cell - primary_anchor_cell
		drag_original_positions[drag_target] = drag_target.global_position
		drag_original_rotations[drag_target] = drag_target.rotation
		drag_original_rotated_ticks[drag_target] = int(drag_target.rotatedTick) if "rotatedTick" in drag_target else 0
		drag_original_modulates[drag_target] = drag_target.modulate
		drag_original_cells_by_building[drag_target] = target_cells.duplicate()
		drag_last_cells_by_building[drag_target] = target_cells.duplicate()
		for cell in target_cells:
			all_original_cells.append(cell)
	
	#We are recording and freeing the current cell occupancy of the building so the building can move through itself
	drag_original_cells = _get_cell_array_from_dictionary(drag_original_cells_by_building, building)
	drag_last_cells = drag_original_cells.duplicate()
	for drag_target in drag_buildings:
		free_cells_for_building(drag_target)
	drag_last_valid = _can_place_group_cells(all_original_cells)
	
func _finish_drag_building() -> void:
	var path_manager := $"../PathManager"
	if not is_dragging_building or  dragged_building == null:
		return
	
	var should_record_move := drag_last_valid and _drag_group_changed()

	if drag_last_valid:
		for drag_target in drag_buildings:
			if not is_instance_valid(drag_target):
				continue
			occupy_cells(_get_cell_array_from_dictionary(drag_last_cells_by_building, drag_target), drag_target)
	else:
		for drag_target in drag_buildings:
			if not is_instance_valid(drag_target):
				continue
			drag_target.global_position = drag_original_positions.get(drag_target, drag_target.global_position)
			drag_target.rotation = float(drag_original_rotations.get(drag_target, drag_target.rotation))
			if "rotatedTick" in drag_target:
				drag_target.rotatedTick = int(drag_original_rotated_ticks.get(drag_target, 0))
			occupy_cells(_get_cell_array_from_dictionary(drag_original_cells_by_building, drag_target), drag_target)
	
	for drag_target in drag_buildings:
		if not is_instance_valid(drag_target):
			continue
		_restore_drag_visual(drag_target)
		if path_manager != null and path_manager.has_method("update_paths_for_building"):
			path_manager.update_paths_for_building(drag_target)

	if should_record_move:
		_commit_history_action("Building moved", drag_history_before)
	
	_reset_drag_state()

func _get_cell_array_from_dictionary(source: Dictionary, key) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var stored_cells = source.get(key, [])
	if stored_cells is Array:
		for cell in stored_cells:
			if cell is Vector2i:
				cells.append(cell)
	return cells

func _drag_group_changed() -> bool:
	for drag_target in drag_buildings:
		if not is_instance_valid(drag_target):
			continue
		var original_position: Vector2 = drag_original_positions.get(drag_target, drag_target.global_position)
		var original_rotation := float(drag_original_rotations.get(drag_target, drag_target.rotation))
		var original_rotated_tick := int(drag_original_rotated_ticks.get(drag_target, 0))
		var final_rotated_tick := int(drag_target.rotatedTick) if "rotatedTick" in drag_target else original_rotated_tick
		if drag_target.global_position.distance_to(original_position) > 0.01:
			return true
		if not is_equal_approx(drag_target.rotation, original_rotation) or final_rotated_tick != original_rotated_tick:
			return true
	return false

func _restore_drag_visual(building: Node2D) -> void:
	if _is_building_selected(building):
		building.modulate = SELECTED_BUILDING_MODULATE
	else:
		building.modulate = drag_original_modulates.get(building, Color(1, 1, 1, 1))

func _reset_drag_state() -> void:
	is_dragging_building = false
	dragged_building = null
	drag_original_cells = []
	drag_last_cells = []
	drag_original_rotation = 0.0
	drag_original_rotated_tick = 0
	drag_history_before = {}
	drag_buildings.clear()
	drag_anchor_offsets.clear()
	drag_original_positions.clear()
	drag_original_rotations.clear()
	drag_original_rotated_ticks.clear()
	drag_original_modulates.clear()
	drag_original_cells_by_building.clear()
	drag_last_cells_by_building.clear()
	drag_last_valid = false
	
func _mouse_is_over_control() -> bool:
	var hoveredControl = get_viewport().gui_get_hovered_control()
	return hoveredControl != null and hoveredControl.is_in_group("port_button")

func _mouse_is_over_any_control() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func _set_port_buttons_passthrough_for_build_mode(build_mode_active: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return

	for node in tree.get_nodes_in_group(PORT_BUTTON_GROUP):
		if not (node is Control):
			continue

		var control := node as Control
		if build_mode_active:
			if not control.has_meta(PORT_BUTTON_ORIGINAL_MOUSE_FILTER_META):
				control.set_meta(PORT_BUTTON_ORIGINAL_MOUSE_FILTER_META, control.mouse_filter)
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		elif control.has_meta(PORT_BUTTON_ORIGINAL_MOUSE_FILTER_META):
			control.mouse_filter = int(control.get_meta(PORT_BUTTON_ORIGINAL_MOUSE_FILTER_META))
			control.remove_meta(PORT_BUTTON_ORIGINAL_MOUSE_FILTER_META)
	
func _apply_build_cost_delta(building: Node, direction: int) -> void:
	if building == null or not ("build_cost_amount" in building):
		return

	var amount := int(building.get("build_cost_amount"))
	if amount == 0:
		return

	var panel_path := "../Camera2D/CanvasLayer/Panel/"
	var label_path := ""
	var cost_type := int(building.get("build_cost_type")) if "build_cost_type" in building else 0
	match cost_type:
		Building.BuildCostType.BBM:
			label_path = "BBMCostLabel"
		Building.BuildCostType.IBM:
			label_path = "IBMCostLabel"
		Building.BuildCostType.METEOR_CORE:
			label_path = "MeteorCoreCostLabel"
		_:
			return

	var cost_label := get_node_or_null(panel_path + label_path) as Label
	if cost_label == null:
		return

	cost_label.text = str(int(cost_label.text) + amount * direction)

func _rotate_building_90_degrees(building: Node2D) -> bool:
	if building == null:
		return false

	building.rotate(deg_to_rad(90.0))
	if "rotatedTick" in building:
		building.rotatedTick = (int(building.rotatedTick) + 1) % 4

	return true

func _rotate_drag_buildings_90_degrees() -> bool:
	var rotated := false
	for building in drag_buildings:
		if is_instance_valid(building):
			rotated = _rotate_building_90_degrees(building) or rotated
	return rotated

func _rotate_selected_buildings_90_degrees() -> bool:
	var buildings_to_rotate := _get_valid_selected_buildings()
	if buildings_to_rotate.is_empty():
		return false

	var path_manager := get_node_or_null("../PathManager")
	var history_before := _capture_history_state()
	var original_positions := {}
	var original_rotations := {}
	var original_rotated_ticks := {}
	var original_cells_by_building := {}

	for building in buildings_to_rotate:
		var anchor_cell := _anchor_cell_from_building_position(building, building.global_position)
		original_positions[building] = building.global_position
		original_rotations[building] = building.rotation
		original_rotated_ticks[building] = int(building.rotatedTick) if "rotatedTick" in building else 0
		original_cells_by_building[building] = get_building_cells(building, anchor_cell)

	for building in buildings_to_rotate:
		free_cells_for_building(building)

	for building in buildings_to_rotate:
		_rotate_building_90_degrees(building)

	var all_rotated_cells: Array[Vector2i] = []
	var rotated_cells_by_building := {}
	for building in buildings_to_rotate:
		var anchor_cell := _anchor_cell_from_building_position(building, building.global_position)
		var rotated_cells := get_building_cells(building, anchor_cell)
		rotated_cells_by_building[building] = rotated_cells
		for cell in rotated_cells:
			all_rotated_cells.append(cell)

	if _can_place_group_cells(all_rotated_cells):
		for building in buildings_to_rotate:
			occupy_cells(_get_cell_array_from_dictionary(rotated_cells_by_building, building), building)
			building.modulate = SELECTED_BUILDING_MODULATE
			if path_manager != null and path_manager.has_method("update_paths_for_building"):
				path_manager.update_paths_for_building(building)
		_commit_history_action("Buildings rotated", history_before)
		return true

	for building in buildings_to_rotate:
		building.global_position = original_positions.get(building, building.global_position)
		building.rotation = float(original_rotations.get(building, building.rotation))
		if "rotatedTick" in building:
			building.rotatedTick = int(original_rotated_ticks.get(building, 0))
		occupy_cells(_get_cell_array_from_dictionary(original_cells_by_building, building), building)
		building.modulate = SELECTED_BUILDING_MODULATE
		if path_manager != null and path_manager.has_method("update_paths_for_building"):
			path_manager.update_paths_for_building(building)

	return false
	
func _process(_delta: float) -> void:
	if _is_scene_input_blocked():
		return

	var mouse_pos
	var anchor_cell
	var path_manager := get_node_or_null("../PathManager")
	var building_footprint
	var new_pos
	var valid_placement
	
	if is_dragging_building and dragged_building != null:
		if not Input.is_action_pressed("Move Build"):
			_finish_drag_building()
			return
		var rotated_during_drag := false
		if Input.is_action_just_pressed("Rotate"):
			rotated_during_drag = _rotate_drag_buildings_90_degrees()
		mouse_pos = get_global_mouse_position() + drag_mouse_offset
		anchor_cell = world_to_cell(mouse_pos)
		var position_changed := false
		var all_drag_cells: Array[Vector2i] = []
		drag_last_cells_by_building.clear()

		for drag_target in drag_buildings:
			if not is_instance_valid(drag_target):
				continue
			var anchor_offset := Vector2i.ZERO
			var stored_offset = drag_anchor_offsets.get(drag_target, Vector2i.ZERO)
			if stored_offset is Vector2i:
				anchor_offset = stored_offset
			var target_anchor_cell: Vector2i = anchor_cell + anchor_offset
			new_pos = _position_from_anchor_cell(drag_target, target_anchor_cell)
			building_footprint = get_building_cells(drag_target, target_anchor_cell)
			position_changed = position_changed or drag_target.global_position.distance_to(new_pos) > 0.01
			drag_target.global_position = new_pos
			drag_last_cells_by_building[drag_target] = building_footprint.duplicate()
			for cell in building_footprint:
				all_drag_cells.append(cell)

		drag_last_cells = _get_cell_array_from_dictionary(drag_last_cells_by_building, dragged_building)
		drag_last_valid = _can_place_group_cells(all_drag_cells)
		
		var drag_color := canBuildColor if drag_last_valid else cannotbuildColor
		for drag_target in drag_buildings:
			if not is_instance_valid(drag_target):
				continue
			drag_target.modulate = drag_color
			drag_target.modulate.a = 1.0
			
		if (position_changed or rotated_during_drag) and path_manager != null and path_manager.has_method("update_paths_for_building"):
			for drag_target in drag_buildings:
				if is_instance_valid(drag_target):
					path_manager.update_paths_for_building(drag_target, false)
		return

	if not is_building and Input.is_action_just_pressed("Rotate"):
		_rotate_selected_buildings_90_degrees()
		return

	if is_building and Input.is_action_just_pressed("Alternate"):
		if _is_group_build_active():
			_flip_group_ghosts()
		elif ghost_instance != null:
			ghost_instance.flip_footprint()
	if is_building and Input.is_action_just_pressed("Rotate"):
		if _is_group_build_active():
			_rotate_group_ghosts_90_degrees()
		elif ghost_instance != null:
			_rotate_building_90_degrees(ghost_instance)
	if Input.is_action_just_pressed("Build Cancel", true):
		if is_building:
			cancel_build()
		else:
			if path_manager != null and path_manager.has_method("try_remove_path_under_mouse") and path_manager.try_remove_path_under_mouse():
				return
			try_remove_building_under_mouse()
		return
	
	if not is_building:
		return

	if _is_group_build_active():
		_update_group_ghost_placement()
		return
		
	mouse_pos = get_global_mouse_position()
	anchor_cell = world_to_cell(mouse_pos)
	building_footprint = get_building_cells(ghost_instance, anchor_cell)
	valid_placement = can_place_at(building_footprint)
	
	ghost_instance.global_position = _position_from_anchor_cell(ghost_instance, anchor_cell)
	
	if valid_placement == false:
		ghost_instance.modulate = cannotbuildColor
	else:
		ghost_instance.modulate = canBuildColor
