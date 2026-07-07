extends Node2D

const Palette = preload("res://Scripts/palette.gd")

signal selection_changed(selected_count: int, anchor_building: Node2D)
# Emitted when a multi-building (group) eyedropper build begins or ends, so the
# contextual mirror toolbar can show/hide itself.
signal group_build_changed(active: bool)

##------OnReady variables------##
@onready var tile_map_layer: TileMapLayer = $"../TileMapLayer"

##------Object Variables-------##
var current_scene: PackedScene
var ghost_instance: Node2D
var dragged_building : Node2D = null
var ghost_area: Area2D
var ghost_selection_template: Dictionary = {}
var group_build_entries: Array[Dictionary] = []
# Rails whose both endpoints are inside the grabbed group, captured on pickup and
# reproduced on confirm. Each entry: {from_index, from_port, to_index, to_port,
# rail_version} where the indices point into group_build_entries.
var group_build_rails: Array[Dictionary] = []
# Live Line2D previews of group_build_rails that follow the ghosts each frame.
var group_build_rail_previews: Array[Dictionary] = []
var _rail_preview_root: Node2D = null
# Rail routing is expensive, so preview polylines are recomputed only when the
# layout actually changes (pickup / mirror / rotate / flip); every other frame
# the whole preview container is translated rigidly to follow the cursor. This
# keeps a 65-building, 65-rail eyedrop at full framerate instead of re-routing
# every rail every frame.
var _rail_preview_routes_dirty := false
var _rail_preview_anchor_cell := Vector2i.ZERO
var selected_buildings: Array[Node2D] = []
var selected_original_modulates: Dictionary = {}
var alignment_anchor_building: Node2D = null
var last_alignment_result: Dictionary = {}

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
const ANCHOR_BUILDING_MODULATE := Color(0.50, 1.0, 0.72, 1.0)
const ALIGN_REF_SELECTION := "selection"
const ALIGN_REF_FIRST := "first"
const ALIGN_REF_LAST := "last"
const ALIGN_REF_ANCHOR := "anchor"
const ALIGN_REF_GRID := "grid"
const ALIGN_METRIC_GAP := "gap"
const ALIGN_METRIC_FIXED_GAP := "fixed_gap"
const ALIGN_METRIC_LEADING := "leading"
const ALIGN_METRIC_TRAILING := "trailing"
const ALIGN_METRIC_CENTER := "center"
const ALIGN_PORT_INPUT := "input"
const ALIGN_PORT_OUTPUT := "output"
const ALIGN_PORT_ANY := "any"
const ALIGN_FLOAT_EPSILON := 0.001
const ALIGN_PORT_EPSILON := 0.5

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

func _preserve_toolbox_popup_for_build_confirm() -> void:
	var main_scene := get_parent()
	if main_scene == null or not main_scene.has_method("preserve_toolbox_popup_for_build_confirm"):
		return
	main_scene.call("preserve_toolbox_popup_for_build_confirm")

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

	var annotation_layer := get_node_or_null("../AnnotationLayer")
	if annotation_layer != null and annotation_layer.has_method("cancel_annotation_interaction"):
		annotation_layer.call("cancel_annotation_interaction", true)

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
			_finish_selection_box(mouse_event.position, mouse_event.shift_pressed)
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

func _finish_selection_box(screen_position: Vector2, additive := false) -> void:
	selection_current_world = get_global_mouse_position()
	is_selecting_buildings = false

	if selection_start_screen.distance_to(screen_position) < SELECTION_DRAG_THRESHOLD:
		var clicked_building := get_building_under_mouse()
		if clicked_building != null:
			# Shift+click toggles a building in/out of the selection. Without
			# shift, keep the existing behavior: reclicking a member of a 2+
			# selection sets it as the anchor, otherwise select just that one.
			if additive:
				_toggle_building_in_selection(clicked_building)
			elif selected_buildings.size() >= 2 and selected_buildings.has(clicked_building):
				set_alignment_anchor(clicked_building)
			else:
				_select_buildings([clicked_building])
		elif not additive:
			# Shift+click on empty space keeps the current selection.
			_clear_selection()
		queue_redraw()
		return

	var selection_rect := _rect_from_points(selection_start_world, selection_current_world)
	var buildings_in_rect: Array[Node2D] = []
	for building in _get_all_placed_buildings():
		var building_rect := _get_building_world_rect(building)
		if selection_rect.intersects(building_rect, true):
			buildings_in_rect.append(building)

	# Shift+box adds the enclosed buildings to the current selection.
	if additive:
		_add_buildings_to_selection(buildings_in_rect)
	else:
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
	if selected_buildings.size() >= 2:
		alignment_anchor_building = selected_buildings[0]
	else:
		alignment_anchor_building = null
	_refresh_selection_visuals()
	_emit_selection_changed()


func _add_buildings_to_selection(buildings: Array[Node2D]) -> void:
	var seen := {}
	for building in buildings:
		if building == null or not is_instance_valid(building):
			continue
		if selected_buildings.has(building) or seen.has(building):
			continue
		seen[building] = true
		selected_buildings.append(building)
		# Capture the true original tint only for newly added buildings so we
		# never overwrite a stored original with an already-selected tint.
		selected_original_modulates[building] = building.modulate
	if alignment_anchor_building == null and selected_buildings.size() >= 2:
		alignment_anchor_building = selected_buildings[0]
	_refresh_selection_visuals()
	_emit_selection_changed()


func _toggle_building_in_selection(building: Node2D) -> void:
	if building == null or not is_instance_valid(building):
		return
	if selected_buildings.has(building):
		# Restore the building's original tint before dropping it.
		building.modulate = selected_original_modulates.get(building, Color(1, 1, 1, 1))
		selected_buildings.erase(building)
		selected_original_modulates.erase(building)
		if alignment_anchor_building == building or not selected_buildings.has(alignment_anchor_building):
			alignment_anchor_building = selected_buildings[0] if selected_buildings.size() >= 2 else null
		_refresh_selection_visuals()
		_emit_selection_changed()
	else:
		var single: Array[Node2D] = [building]
		_add_buildings_to_selection(single)

func _clear_selection() -> void:
	for building in selected_buildings:
		if is_instance_valid(building):
			building.modulate = selected_original_modulates.get(building, Color(1, 1, 1, 1))
	selected_buildings.clear()
	selected_original_modulates.clear()
	alignment_anchor_building = null
	_emit_selection_changed()


func _refresh_selection_visuals() -> void:
	for building in selected_buildings:
		if not is_instance_valid(building):
			continue
		if building == alignment_anchor_building and selected_buildings.size() >= 2:
			building.modulate = ANCHOR_BUILDING_MODULATE
		else:
			building.modulate = SELECTED_BUILDING_MODULATE


func _emit_selection_changed() -> void:
	selection_changed.emit(_get_valid_selected_buildings().size(), alignment_anchor_building)


func cancel_pointer_interaction() -> void:
	if is_selecting_buildings:
		is_selecting_buildings = false
		selection_current_world = selection_start_world
		queue_redraw()

func _remove_building_from_selection(building: Node) -> void:
	if building == null:
		return
	selected_buildings.erase(building)
	selected_original_modulates.erase(building)
	if alignment_anchor_building == building:
		alignment_anchor_building = selected_buildings[0] if selected_buildings.size() >= 2 else null
	_refresh_selection_visuals()
	_emit_selection_changed()

func _is_building_selected(building: Node) -> bool:
	return building != null and selected_buildings.has(building)

func _prune_selection() -> void:
	var changed := false
	for building in selected_buildings.duplicate():
		if not is_instance_valid(building):
			selected_buildings.erase(building)
			selected_original_modulates.erase(building)
			changed = true
	if alignment_anchor_building != null and not selected_buildings.has(alignment_anchor_building):
		alignment_anchor_building = selected_buildings[0] if selected_buildings.size() >= 2 else null
		changed = true
	if changed:
		_refresh_selection_visuals()
		_emit_selection_changed()

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


func get_selected_building_count() -> int:
	return _get_valid_selected_buildings().size()


func has_multi_selection() -> bool:
	return get_selected_building_count() >= 2


func get_alignment_anchor() -> Node2D:
	_prune_selection()
	return alignment_anchor_building if alignment_anchor_building != null and selected_buildings.has(alignment_anchor_building) else null


func set_alignment_anchor(building: Node2D) -> bool:
	if building == null or not selected_buildings.has(building):
		return false
	alignment_anchor_building = building
	_refresh_selection_visuals()
	_emit_selection_changed()
	return true


func set_alignment_anchor_to_hovered_or_first() -> bool:
	var hovered := get_building_under_mouse()
	if hovered != null and selected_buildings.has(hovered):
		return set_alignment_anchor(hovered)
	if selected_buildings.size() >= 2:
		return set_alignment_anchor(selected_buildings[0])
	return false


func cycle_alignment_anchor() -> bool:
	var selected := _get_valid_selected_buildings()
	if selected.size() < 2:
		return false
	var current_index := selected.find(alignment_anchor_building)
	var next_index := 0 if current_index < 0 else (current_index + 1) % selected.size()
	return set_alignment_anchor(selected[next_index])


func align_selected_buildings(command: String, options: Dictionary = {}) -> Dictionary:
	var selected := _get_valid_selected_buildings()
	if selected.size() < 2:
		return _set_alignment_result(false, "Select at least two buildings.", 0, 0)
	if is_building or is_dragging_building or is_selecting_buildings:
		return _set_alignment_result(false, "Finish the current placement or drag before aligning.", 0, 0)

	var entries := _build_alignment_entries(selected)
	if entries.size() < 2:
		return _set_alignment_result(false, "No valid selected buildings found.", 0, 0)

	var reference_mode := String(options.get("reference_mode", ALIGN_REF_SELECTION))
	var metric := String(options.get("metric", ALIGN_METRIC_GAP))
	var gap := maxi(0, int(options.get("gap", 0)))
	var strict := bool(options.get("strict", true))
	var targets := {}

	match command:
		"align_left":
			targets = _build_edge_alignment_targets(entries, "x", "start", reference_mode)
		"align_right":
			targets = _build_edge_alignment_targets(entries, "x", "end", reference_mode)
		"align_hcenter":
			targets = _build_edge_alignment_targets(entries, "x", "center", reference_mode)
		"align_top":
			targets = _build_edge_alignment_targets(entries, "y", "start", reference_mode)
		"align_bottom":
			targets = _build_edge_alignment_targets(entries, "y", "end", reference_mode)
		"align_vcenter":
			targets = _build_edge_alignment_targets(entries, "y", "center", reference_mode)
		"edge_horizontal", "pack_horizontal":
			targets = _build_pack_targets(entries, "x", reference_mode, gap)
		"edge_vertical", "pack_vertical":
			targets = _build_pack_targets(entries, "y", reference_mode, gap)
		"distribute_horizontal":
			targets = _build_distribution_targets(entries, "x", metric, gap)
		"distribute_vertical":
			targets = _build_distribution_targets(entries, "y", metric, gap)
		"arrange_row":
			targets = _build_arrange_line_targets(entries, "x", reference_mode, gap)
		"arrange_column":
			targets = _build_arrange_line_targets(entries, "y", reference_mode, gap)
		"arrange_grid":
			targets = _build_arrange_grid_targets(entries, reference_mode, gap)
		"port_align_x":
			return _align_selected_ports("x", reference_mode, String(options.get("port_role", ALIGN_PORT_INPUT)), strict)
		"port_align_y":
			return _align_selected_ports("y", reference_mode, String(options.get("port_role", ALIGN_PORT_INPUT)), strict)
		_:
			return _set_alignment_result(false, "Unknown alignment command: %s" % command, 0, 0)

	if targets.is_empty():
		return _set_alignment_result(false, "Alignment command produced no movement targets.", 0, 0)

	return _apply_alignment_targets(targets, _alignment_command_label(command), strict)


func _build_alignment_entries(buildings: Array[Node2D]) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for building in buildings:
		if building == null or not is_instance_valid(building):
			continue
		var anchor_cell := _anchor_cell_from_building_position(building, building.global_position)
		var footprint := get_rotated_footprint(building)
		if footprint.x <= 0 or footprint.y <= 0:
			continue
		var anchor_offset := _get_building_anchor_offset(building)
		var top_left := anchor_cell - anchor_offset
		entries.append({
			"building": building,
			"anchor_cell": anchor_cell,
			"anchor_offset": anchor_offset,
			"top_left": top_left,
			"footprint": footprint,
			"left": top_left.x,
			"right": top_left.x + footprint.x,
			"top": top_left.y,
			"bottom": top_left.y + footprint.y,
			"center_x": float(top_left.x) + (float(footprint.x) * 0.5),
			"center_y": float(top_left.y) + (float(footprint.y) * 0.5),
		})
	return entries


func _get_building_anchor_offset(building: Node) -> Vector2i:
	if building == null:
		return Vector2i.ZERO
	var anchor_value = building.get("anchor")
	if anchor_value is Vector2i:
		return anchor_value
	return Vector2i.ZERO


func _build_edge_alignment_targets(entries: Array[Dictionary], axis: String, edge: String, reference_mode: String) -> Dictionary:
	var target := _get_alignment_reference_metric(entries, axis, edge, reference_mode)
	var targets := {}
	for entry in entries:
		var building := entry.get("building") as Node2D
		if building == null:
			continue
		var top_left: Vector2i = entry.get("top_left", Vector2i.ZERO)
		var footprint: Vector2i = entry.get("footprint", Vector2i.ONE)
		var next_top_left := top_left
		if axis == "x":
			match edge:
				"start":
					next_top_left.x = int(round(target))
				"end":
					next_top_left.x = int(round(target - float(footprint.x)))
				"center":
					next_top_left.x = int(round(target - (float(footprint.x) * 0.5)))
		else:
			match edge:
				"start":
					next_top_left.y = int(round(target))
				"end":
					next_top_left.y = int(round(target - float(footprint.y)))
				"center":
					next_top_left.y = int(round(target - (float(footprint.y) * 0.5)))
		targets[building] = _anchor_cell_from_top_left(entry, next_top_left)
	return targets


func _get_alignment_reference_metric(entries: Array[Dictionary], axis: String, metric: String, reference_mode: String) -> float:
	var reference_entry := _resolve_alignment_reference_entry(entries, reference_mode)
	if not reference_entry.is_empty():
		return _entry_axis_metric(reference_entry, axis, metric)

	var bounds := _get_alignment_bounds(entries)
	if reference_mode == ALIGN_REF_GRID:
		match metric:
			"center":
				return float(round(float(bounds.get("center_x" if axis == "x" else "center_y", 0.0))))
			"end":
				return float(round(float(bounds.get("right" if axis == "x" else "bottom", 0))))
			_:
				return float(round(float(bounds.get("left" if axis == "x" else "top", 0))))

	match metric:
		"center":
			return float(bounds.get("center_x" if axis == "x" else "center_y", 0.0))
		"end":
			return float(bounds.get("right" if axis == "x" else "bottom", 0))
		_:
			return float(bounds.get("left" if axis == "x" else "top", 0))


func _resolve_alignment_reference_entry(entries: Array[Dictionary], reference_mode: String) -> Dictionary:
	if entries.is_empty():
		return {}
	match reference_mode:
		ALIGN_REF_ANCHOR:
			var anchor := get_alignment_anchor()
			if anchor != null:
				for entry in entries:
					if entry.get("building") == anchor:
						return entry
		ALIGN_REF_FIRST:
			return entries[0]
		ALIGN_REF_LAST:
			return entries[entries.size() - 1]
	return {}


func _get_alignment_bounds(entries: Array[Dictionary]) -> Dictionary:
	if entries.is_empty():
		return {}
	var left := int(entries[0].get("left", 0))
	var right := int(entries[0].get("right", 0))
	var top := int(entries[0].get("top", 0))
	var bottom := int(entries[0].get("bottom", 0))
	for entry in entries:
		left = mini(left, int(entry.get("left", left)))
		right = maxi(right, int(entry.get("right", right)))
		top = mini(top, int(entry.get("top", top)))
		bottom = maxi(bottom, int(entry.get("bottom", bottom)))
	return {
		"left": left,
		"right": right,
		"top": top,
		"bottom": bottom,
		"center_x": float(left + right) * 0.5,
		"center_y": float(top + bottom) * 0.5,
	}


func _entry_axis_metric(entry: Dictionary, axis: String, metric: String) -> float:
	if axis == "x":
		match metric:
			"end", ALIGN_METRIC_TRAILING:
				return float(entry.get("right", 0))
			"center", ALIGN_METRIC_CENTER:
				return float(entry.get("center_x", 0.0))
			_:
				return float(entry.get("left", 0))
	match metric:
		"end", ALIGN_METRIC_TRAILING:
			return float(entry.get("bottom", 0))
		"center", ALIGN_METRIC_CENTER:
			return float(entry.get("center_y", 0.0))
		_:
			return float(entry.get("top", 0))


func _anchor_cell_from_top_left(entry: Dictionary, top_left: Vector2i) -> Vector2i:
	var anchor_offset: Vector2i = entry.get("anchor_offset", Vector2i.ZERO)
	return top_left + anchor_offset


func _build_distribution_targets(entries: Array[Dictionary], axis: String, metric: String, gap: int = 0) -> Dictionary:
	var sorted := _sort_entries_by_axis(entries, axis)
	var targets := {}
	if sorted.size() < 2:
		return targets

	if metric == ALIGN_METRIC_FIXED_GAP:
		# Keep the first building (in axis order) fixed and respace the rest so
		# exactly `gap` tiles separate each pair of facing surfaces.
		var first: Dictionary = sorted[0]
		var first_top_left: Vector2i = first.get("top_left", Vector2i.ZERO)
		targets[first.get("building")] = _anchor_cell_from_top_left(first, first_top_left)
		var first_footprint: Vector2i = first.get("footprint", Vector2i.ONE)
		var cursor := (first_top_left.x + first_footprint.x) if axis == "x" else (first_top_left.y + first_footprint.y)
		for i in range(1, sorted.size()):
			var entry: Dictionary = sorted[i]
			var building := entry.get("building") as Node2D
			var top_left: Vector2i = entry.get("top_left", Vector2i.ZERO)
			var footprint: Vector2i = entry.get("footprint", Vector2i.ONE)
			var next_top_left := top_left
			if axis == "x":
				next_top_left.x = cursor + gap
				cursor = next_top_left.x + footprint.x
			else:
				next_top_left.y = cursor + gap
				cursor = next_top_left.y + footprint.y
			if building != null:
				targets[building] = _anchor_cell_from_top_left(entry, next_top_left)
		return targets

	if metric == ALIGN_METRIC_GAP:
		var first: Dictionary = sorted[0]
		var last: Dictionary = sorted[sorted.size() - 1]
		var start := int(first.get("left" if axis == "x" else "top", 0))
		var end := int(last.get("right" if axis == "x" else "bottom", 0))
		var total_size := 0
		for entry in sorted:
			var footprint: Vector2i = entry.get("footprint", Vector2i.ONE)
			total_size += footprint.x if axis == "x" else footprint.y
		var spacing := 0.0
		if sorted.size() > 1:
			spacing = float((end - start) - total_size) / float(sorted.size() - 1)
		var cursor := float(start)
		for i in range(sorted.size()):
			var entry: Dictionary = sorted[i]
			var building := entry.get("building") as Node2D
			var top_left: Vector2i = entry.get("top_left", Vector2i.ZERO)
			var footprint: Vector2i = entry.get("footprint", Vector2i.ONE)
			var next_top_left := top_left
			if i == 0 or i == sorted.size() - 1:
				next_top_left = top_left
			elif axis == "x":
				next_top_left.x = int(round(cursor))
			else:
				next_top_left.y = int(round(cursor))
			if building != null:
				targets[building] = _anchor_cell_from_top_left(entry, next_top_left)
			cursor += float(footprint.x if axis == "x" else footprint.y) + spacing
		return targets

	var first_metric := _entry_axis_metric(sorted[0], axis, metric)
	var last_metric := _entry_axis_metric(sorted[sorted.size() - 1], axis, metric)
	var step := 0.0
	if sorted.size() > 1:
		step = (last_metric - first_metric) / float(sorted.size() - 1)

	for i in range(sorted.size()):
		var entry: Dictionary = sorted[i]
		var building := entry.get("building") as Node2D
		if building == null:
			continue
		var top_left: Vector2i = entry.get("top_left", Vector2i.ZERO)
		var footprint: Vector2i = entry.get("footprint", Vector2i.ONE)
		var target_metric := first_metric + (step * float(i))
		var next_top_left := top_left
		if i != 0 and i != sorted.size() - 1:
			if axis == "x":
				next_top_left.x = _top_left_from_axis_metric(target_metric, footprint.x, metric)
			else:
				next_top_left.y = _top_left_from_axis_metric(target_metric, footprint.y, metric)
		targets[building] = _anchor_cell_from_top_left(entry, next_top_left)

	return targets


func _top_left_from_axis_metric(target_metric: float, size: int, metric: String) -> int:
	match metric:
		ALIGN_METRIC_TRAILING, "end":
			return int(round(target_metric - float(size)))
		ALIGN_METRIC_CENTER, "center":
			return int(round(target_metric - (float(size) * 0.5)))
		_:
			return int(round(target_metric))


func _build_pack_targets(entries: Array[Dictionary], axis: String, reference_mode: String, gap: int) -> Dictionary:
	var sorted := _sort_entries_by_axis(entries, axis)
	var targets := {}
	if sorted.is_empty():
		return targets

	var reference_entry := _resolve_alignment_reference_entry(sorted, reference_mode)
	var reference_index := sorted.find(reference_entry) if not reference_entry.is_empty() else -1

	if reference_index >= 0:
		var reference_top_left: Vector2i = reference_entry.get("top_left", Vector2i.ZERO)
		targets[reference_entry.get("building")] = _anchor_cell_from_top_left(reference_entry, reference_top_left)

		var cursor_start := reference_top_left.x if axis == "x" else reference_top_left.y
		for i in range(reference_index - 1, -1, -1):
			var entry: Dictionary = sorted[i]
			var footprint: Vector2i = entry.get("footprint", Vector2i.ONE)
			var top_left: Vector2i = entry.get("top_left", Vector2i.ZERO)
			var next_top_left := top_left
			if axis == "x":
				next_top_left.x = cursor_start - gap - footprint.x
				cursor_start = next_top_left.x
			else:
				next_top_left.y = cursor_start - gap - footprint.y
				cursor_start = next_top_left.y
			targets[entry.get("building")] = _anchor_cell_from_top_left(entry, next_top_left)

		var reference_footprint: Vector2i = reference_entry.get("footprint", Vector2i.ONE)
		var cursor_end := (reference_top_left.x + reference_footprint.x) if axis == "x" else (reference_top_left.y + reference_footprint.y)
		for i in range(reference_index + 1, sorted.size()):
			var entry: Dictionary = sorted[i]
			var footprint: Vector2i = entry.get("footprint", Vector2i.ONE)
			var top_left: Vector2i = entry.get("top_left", Vector2i.ZERO)
			var next_top_left := top_left
			if axis == "x":
				next_top_left.x = cursor_end + gap
				cursor_end = next_top_left.x + footprint.x
			else:
				next_top_left.y = cursor_end + gap
				cursor_end = next_top_left.y + footprint.y
			targets[entry.get("building")] = _anchor_cell_from_top_left(entry, next_top_left)
		return targets

	var bounds := _get_alignment_bounds(entries)
	var cursor := int(bounds.get("left" if axis == "x" else "top", 0))
	for entry in sorted:
		var footprint: Vector2i = entry.get("footprint", Vector2i.ONE)
		var top_left: Vector2i = entry.get("top_left", Vector2i.ZERO)
		var next_top_left := top_left
		if axis == "x":
			next_top_left.x = cursor
			cursor += footprint.x + gap
		else:
			next_top_left.y = cursor
			cursor += footprint.y + gap
		targets[entry.get("building")] = _anchor_cell_from_top_left(entry, next_top_left)
	return targets


func _build_arrange_line_targets(entries: Array[Dictionary], axis: String, reference_mode: String, gap: int) -> Dictionary:
	var targets := _build_pack_targets(entries, axis, reference_mode, gap)
	var reference_entry := _resolve_alignment_reference_entry(entries, reference_mode)
	if reference_entry.is_empty():
		var bounds := _get_alignment_bounds(entries)
		reference_entry = {
			"top_left": Vector2i(int(bounds.get("left", 0)), int(bounds.get("top", 0)))
		}
	var reference_top_left: Vector2i = reference_entry.get("top_left", Vector2i.ZERO)
	var entries_by_building := _entries_by_building(entries)
	for building in targets.keys():
		var entry: Dictionary = entries_by_building.get(building, {})
		if entry.is_empty():
			continue
		var target_anchor: Vector2i = targets.get(building, entry.get("anchor_cell", Vector2i.ZERO))
		var target_top_left := target_anchor - _get_building_anchor_offset(building)
		if axis == "x":
			target_top_left.y = reference_top_left.y
		else:
			target_top_left.x = reference_top_left.x
		targets[building] = _anchor_cell_from_top_left(entry, target_top_left)
	return targets


func _build_arrange_grid_targets(entries: Array[Dictionary], reference_mode: String, gap: int) -> Dictionary:
	var sorted := _sort_entries_reading_order(entries)
	var targets := {}
	if sorted.is_empty():
		return targets

	var columns := maxi(1, int(ceil(sqrt(float(sorted.size())))))
	var rows := int(ceil(float(sorted.size()) / float(columns)))
	var col_widths: Array[int] = []
	var row_heights: Array[int] = []
	for _i in range(columns):
		col_widths.append(1)
	for _i in range(rows):
		row_heights.append(1)

	for i in range(sorted.size()):
		var entry: Dictionary = sorted[i]
		var footprint: Vector2i = entry.get("footprint", Vector2i.ONE)
		var col := i % columns
		var row := int(floor(float(i) / float(columns)))
		col_widths[col] = maxi(col_widths[col], footprint.x)
		row_heights[row] = maxi(row_heights[row], footprint.y)

	var start_top_left := Vector2i.ZERO
	var reference_entry := _resolve_alignment_reference_entry(entries, reference_mode)
	if not reference_entry.is_empty():
		start_top_left = reference_entry.get("top_left", Vector2i.ZERO)
	else:
		var bounds := _get_alignment_bounds(entries)
		start_top_left = Vector2i(int(bounds.get("left", 0)), int(bounds.get("top", 0)))

	var y_cursor := start_top_left.y
	for row in range(rows):
		var x_cursor := start_top_left.x
		for col in range(columns):
			var index := row * columns + col
			if index >= sorted.size():
				break
			var entry: Dictionary = sorted[index]
			var building := entry.get("building") as Node2D
			if building != null:
				targets[building] = _anchor_cell_from_top_left(entry, Vector2i(x_cursor, y_cursor))
			x_cursor += col_widths[col] + gap
		y_cursor += row_heights[row] + gap

	return targets


func _sort_entries_by_axis(entries: Array[Dictionary], axis: String) -> Array[Dictionary]:
	var sorted: Array[Dictionary] = entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_start := int(a.get("left" if axis == "x" else "top", 0))
		var b_start := int(b.get("left" if axis == "x" else "top", 0))
		if a_start == b_start:
			return int(a.get("top" if axis == "x" else "left", 0)) < int(b.get("top" if axis == "x" else "left", 0))
		return a_start < b_start
	)
	return sorted


func _sort_entries_reading_order(entries: Array[Dictionary]) -> Array[Dictionary]:
	var sorted: Array[Dictionary] = entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_top := int(a.get("top", 0))
		var b_top := int(b.get("top", 0))
		if a_top == b_top:
			return int(a.get("left", 0)) < int(b.get("left", 0))
		return a_top < b_top
	)
	return sorted


func _entries_by_building(entries: Array[Dictionary]) -> Dictionary:
	var by_building := {}
	for entry in entries:
		var building := entry.get("building") as Node2D
		if building != null:
			by_building[building] = entry
	return by_building


func _align_selected_ports(axis: String, reference_mode: String, port_role: String, strict: bool) -> Dictionary:
	var selected := _get_valid_selected_buildings()
	var entries := _build_alignment_entries(selected)
	if entries.size() < 2:
		return _set_alignment_result(false, "Select at least two buildings.", 0, 0)

	var reference_entry := _resolve_alignment_reference_entry(entries, reference_mode)
	if reference_entry.is_empty():
		reference_entry = entries[0]
	var reference_building := reference_entry.get("building") as Node2D
	var reference_port := _get_alignment_port_button(reference_building, port_role)
	if reference_port == null:
		return _set_alignment_result(false, "Anchor building has no matching %s port." % port_role, 0, entries.size())

	var reference_port_center = _get_alignment_node_global_center(reference_port)
	if reference_port_center == null:
		return _set_alignment_result(false, "Anchor port position could not be resolved.", 0, entries.size())

	var target_axis := (reference_port_center as Vector2).x if axis == "x" else (reference_port_center as Vector2).y
	var preferred_port_name := reference_port.name
	var targets := {}
	var skipped := 0
	for entry in entries:
		var building := entry.get("building") as Node2D
		if building == null:
			continue
		if building == reference_building:
			targets[building] = entry.get("anchor_cell", Vector2i.ZERO)
			continue

		var port := _get_alignment_port_button(building, port_role, preferred_port_name)
		if port == null:
			if strict:
				return _set_alignment_result(false, "%s has no matching %s port." % [building.name, port_role], 0, entries.size())
			skipped += 1
			continue

		var current_center = _get_alignment_node_global_center(port)
		if current_center == null:
			if strict:
				return _set_alignment_result(false, "%s port position could not be resolved." % building.name, 0, entries.size())
			skipped += 1
			continue

		var current_port_center := current_center as Vector2
		var port_offset := current_port_center - building.global_position
		var desired_position := building.global_position
		if axis == "x":
			desired_position.x += target_axis - current_port_center.x
		else:
			desired_position.y += target_axis - current_port_center.y

		var snapped_anchor := _anchor_cell_from_building_position(building, desired_position)
		var snapped_position := _position_from_anchor_cell(building, snapped_anchor)
		var snapped_port_center := snapped_position + port_offset
		var snapped_axis := snapped_port_center.x if axis == "x" else snapped_port_center.y
		if abs(snapped_axis - target_axis) > ALIGN_PORT_EPSILON:
			if strict:
				return _set_alignment_result(false, "%s cannot align its fixed port on the grid." % building.name, 0, entries.size())
			skipped += 1
			continue

		targets[building] = snapped_anchor

	if targets.size() < 2:
		return _set_alignment_result(false, "No matching ports could be aligned.", 0, entries.size())

	var result := _apply_alignment_targets(targets, "Connector ports aligned", true)
	result["skipped"] = int(result.get("skipped", 0)) + skipped
	last_alignment_result = result
	return result


func _get_alignment_port_button(building: Node, role: String, preferred_name := "") -> Button:
	if building == null:
		return null
	var ports := building.get_node_or_null("Ports")
	if ports == null:
		return null

	var fallback: Button = null
	for child in ports.get_children():
		if not (child is Button):
			continue
		var button := child as Button
		if not _port_matches_alignment_role(button.name, role):
			continue
		if preferred_name != "" and button.name == preferred_name:
			return button
		if fallback == null:
			fallback = button
	return fallback


func _port_matches_alignment_role(port_name: String, role: String) -> bool:
	var lower := port_name.to_lower()
	match role:
		ALIGN_PORT_INPUT:
			return lower.begins_with("input") or lower.begins_with("universal")
		ALIGN_PORT_OUTPUT:
			return lower.begins_with("output") or lower.begins_with("universal")
		_:
			return true


func _get_alignment_node_global_center(node: Node) -> Variant:
	if node == null:
		return null
	if node is Control:
		var control := node as Control
		return control.get_global_transform() * (control.size * 0.5)
	if node is Node2D:
		return (node as Node2D).global_position
	if "global_position" in node:
		return node.global_position
	return null


func _apply_alignment_targets(target_anchor_cells: Dictionary, label: String, strict: bool) -> Dictionary:
	var selected := _get_valid_selected_buildings()
	if selected.size() < 2:
		return _set_alignment_result(false, "Select at least two buildings.", 0, 0)

	var path_manager := get_node_or_null("../PathManager")
	if path_manager != null and path_manager.has_method("cancel_active_path_drag"):
		path_manager.cancel_active_path_drag()

	var history_before := _capture_history_state()
	var original_positions := {}
	var original_cells_by_building := {}
	var target_cells_by_building := {}
	for building in selected:
		var original_anchor := _anchor_cell_from_building_position(building, building.global_position)
		var target_anchor: Vector2i = target_anchor_cells.get(building, original_anchor)
		original_positions[building] = building.global_position
		original_cells_by_building[building] = get_building_cells(building, original_anchor)
		target_cells_by_building[building] = get_building_cells(building, target_anchor)

	for building in selected:
		free_cells_for_building(building)

	var result := _apply_alignment_targets_strict(selected, target_anchor_cells, target_cells_by_building, label) if strict else _apply_alignment_targets_best_effort(selected, target_anchor_cells, original_cells_by_building, target_cells_by_building, label)
	if not bool(result.get("ok", false)):
		for building in selected:
			if not is_instance_valid(building):
				continue
			building.global_position = original_positions.get(building, building.global_position)
			occupy_cells(_get_cell_array_from_dictionary(original_cells_by_building, building), building)
		_refresh_selection_visuals()
		last_alignment_result = result
		return result

	for building in selected:
		if not is_instance_valid(building):
			continue
		if path_manager != null and path_manager.has_method("update_paths_for_building"):
			path_manager.update_paths_for_building(building)

	_refresh_selection_visuals()
	_commit_history_action(label, history_before)
	last_alignment_result = result
	return result


func _apply_alignment_targets_strict(selected: Array[Node2D], target_anchor_cells: Dictionary, target_cells_by_building: Dictionary, label: String) -> Dictionary:
	var all_target_cells: Array[Vector2i] = []
	var moved := 0
	for building in selected:
		var cells := _get_cell_array_from_dictionary(target_cells_by_building, building)
		for cell in cells:
			all_target_cells.append(cell)

	if not _can_place_group_cells(all_target_cells):
		return _set_alignment_result(false, "%s blocked by occupied or overlapping grid cells." % label, 0, selected.size())

	for building in selected:
		if not is_instance_valid(building):
			continue
		var target_anchor = target_anchor_cells.get(building, _anchor_cell_from_building_position(building, building.global_position))
		var next_position := _position_from_anchor_cell(building, target_anchor)
		if building.global_position.distance_to(next_position) > 0.01:
			moved += 1
		building.global_position = next_position
		occupy_cells(_get_cell_array_from_dictionary(target_cells_by_building, building), building)

	return _set_alignment_result(true, "%s applied to %d building%s." % [label, moved, "" if moved == 1 else "s"], moved, 0)


func _apply_alignment_targets_best_effort(selected: Array[Node2D], target_anchor_cells: Dictionary, original_cells_by_building: Dictionary, target_cells_by_building: Dictionary, label: String) -> Dictionary:
	var reserved_original_cells := {}
	for building in selected:
		for cell in _get_cell_array_from_dictionary(original_cells_by_building, building):
			reserved_original_cells[cell] = building

	var accepted_cells := {}
	var accepted_buildings: Array[Node2D] = []
	var skipped_buildings: Array[Node2D] = []

	for building in selected:
		if not is_instance_valid(building):
			continue
		var target_cells := _get_cell_array_from_dictionary(target_cells_by_building, building)
		for cell in _get_cell_array_from_dictionary(original_cells_by_building, building):
			if reserved_original_cells.get(cell) == building:
				reserved_original_cells.erase(cell)

		if _cells_are_available_for_best_effort(target_cells, accepted_cells, reserved_original_cells):
			accepted_buildings.append(building)
			for cell in target_cells:
				accepted_cells[cell] = building
		else:
			skipped_buildings.append(building)
			for cell in _get_cell_array_from_dictionary(original_cells_by_building, building):
				reserved_original_cells[cell] = building

	var moved := 0
	for building in accepted_buildings:
		var target_anchor = target_anchor_cells.get(building, _anchor_cell_from_building_position(building, building.global_position))
		var next_position := _position_from_anchor_cell(building, target_anchor)
		if building.global_position.distance_to(next_position) > 0.01:
			moved += 1
		building.global_position = next_position
		occupy_cells(_get_cell_array_from_dictionary(target_cells_by_building, building), building)

	for building in skipped_buildings:
		occupy_cells(_get_cell_array_from_dictionary(original_cells_by_building, building), building)

	if accepted_buildings.is_empty():
		return _set_alignment_result(false, "%s had no valid grid moves." % label, 0, skipped_buildings.size())

	return _set_alignment_result(true, "%s applied to %d building%s; skipped %d." % [label, moved, "" if moved == 1 else "s", skipped_buildings.size()], moved, skipped_buildings.size())


func _cells_are_available_for_best_effort(cells: Array[Vector2i], accepted_cells: Dictionary, reserved_original_cells: Dictionary) -> bool:
	var seen := {}
	for cell in cells:
		if seen.has(cell):
			return false
		seen[cell] = true
		if occupied_cells.has(cell):
			return false
		if accepted_cells.has(cell):
			return false
		if reserved_original_cells.has(cell):
			return false
	return true


func _alignment_command_label(command: String) -> String:
	match command:
		"align_left":
			return "Aligned left"
		"align_right":
			return "Aligned right"
		"align_hcenter":
			return "Aligned horizontal centers"
		"align_top":
			return "Aligned top"
		"align_bottom":
			return "Aligned bottom"
		"align_vcenter":
			return "Aligned vertical centers"
		"edge_horizontal":
			return "Edge-aligned horizontally"
		"edge_vertical":
			return "Edge-aligned vertically"
		"pack_horizontal":
			return "Packed horizontally"
		"pack_vertical":
			return "Packed vertically"
		"distribute_horizontal":
			return "Distributed horizontally"
		"distribute_vertical":
			return "Distributed vertically"
		"arrange_row":
			return "Arranged row"
		"arrange_column":
			return "Arranged column"
		"arrange_grid":
			return "Arranged grid"
	return "Aligned buildings"


func _set_alignment_result(ok: bool, message: String, moved: int, skipped: int) -> Dictionary:
	last_alignment_result = {
		"ok": ok,
		"message": message,
		"moved": moved,
		"skipped": skipped,
	}
	return last_alignment_result

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
			_preserve_toolbox_popup_for_build_confirm()
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
	_capture_group_rails_from_entries()
	_build_group_rail_previews()
	_update_group_ghost_placement()
	group_build_changed.emit(true)

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

	_position_group_rail_previews(anchor_cell)

	return valid_placement

func _flip_group_ghosts() -> void:
	for entry in group_build_entries:
		var ghost := entry.get("ghost") as Node2D
		if ghost != null and ghost.has_method("flip_footprint"):
			ghost.flip_footprint()
	_rail_preview_routes_dirty = true

func _rotate_group_ghosts_90_degrees() -> void:
	for entry in group_build_entries:
		var ghost := entry.get("ghost") as Node2D
		if ghost != null:
			_rotate_building_90_degrees(ghost)
	_rail_preview_routes_dirty = true

# Rotate 180 degrees (2 ticks) only the group ghosts whose current rotatedTick
# matches the given parity: parity 1 -> ticks 1/3, parity 0 -> ticks 0/2.
# Buildings of the other parity are left untouched. Used by the mirror so only
# buildings whose facing crosses the mirror axis get spun.
func _rotate_group_ghosts_180_for_tick_parity(parity: int) -> void:
	var target_parity := parity & 1
	for entry in group_build_entries:
		var ghost := entry.get("ghost") as Node2D
		if ghost == null:
			continue
		var tick := 0
		if "rotatedTick" in ghost:
			tick = posmod(int(ghost.rotatedTick), 4)
		if (tick & 1) != target_parity:
			continue
		_rotate_building_90_degrees(ghost)
		_rotate_building_90_degrees(ghost)
	_rail_preview_routes_dirty = true

# Mirror the whole group ghost layout in place. "horizontal" reflects the block
# left<->right, "vertical" top<->bottom. We reflect each building's grid position
# about the group's bounding box (so the block stays under the cursor), and spin
# 180 degrees only the buildings whose facing actually crosses the mirror axis:
# a horizontal mirror rotates buildings on ticks 1/3, a vertical mirror rotates
# buildings on ticks 0/2. Buildings already parallel to the mirror axis keep
# their orientation. Captured rails follow automatically because they reconnect
# to the same named ports on the ghosts.
func mirror_group_layout(axis: String) -> void:
	if not _apply_group_mirror(axis):
		return
	if axis == "horizontal":
		_rotate_group_ghosts_180_for_tick_parity(1)
	elif axis == "vertical":
		_rotate_group_ghosts_180_for_tick_parity(0)
	_rail_preview_routes_dirty = true
	_update_group_ghost_placement()

# Recompute each entry's anchor_offset for the mirrored layout. Kept separate
# from the ghost repositioning (which needs the cursor/viewport) so the pure
# grid math is unit-testable headlessly. Returns true if offsets changed.
func _apply_group_mirror(axis: String) -> bool:
	if not _is_group_build_active():
		return false
	if axis != "horizontal" and axis != "vertical":
		return false

	var rects: Array = []
	for entry in group_build_entries:
		rects.append(_group_entry_local_rect(entry))

	var mirrored_top_lefts := _mirror_top_left_cells(rects, axis)
	if mirrored_top_lefts.size() != group_build_entries.size():
		return false

	for i in group_build_entries.size():
		var entry = group_build_entries[i]
		entry["anchor_offset"] = (mirrored_top_lefts[i] as Vector2i) + _group_entry_anchor(entry)

	return true

func _group_entry_anchor(entry: Dictionary) -> Vector2i:
	var ghost := entry.get("ghost") as Node2D
	if ghost != null and "anchor" in ghost and ghost.get("anchor") is Vector2i:
		return ghost.get("anchor")
	return Vector2i.ZERO

# The entry's footprint in group-local cell space: {top_left, size}. top_left
# matches get_building_cells' math (anchor cell minus the raw building anchor),
# and size is the rotation-aware footprint.
func _group_entry_local_rect(entry: Dictionary) -> Dictionary:
	var ghost := entry.get("ghost") as Node2D
	var offset := _get_group_entry_anchor_offset(entry)
	var anchor := _group_entry_anchor(entry)
	var size := Vector2i.ONE
	if ghost != null:
		var footprint := get_rotated_footprint(ghost)
		if footprint != Vector2i.ZERO:
			size = footprint
	return {"top_left": offset - anchor, "size": size}

# Pure reflection math (static so it can be unit tested without building nodes).
# Given a list of {top_left, size} cell rects, reflect each rect about the shared
# bounding box across the requested axis and return the new top-left cells in the
# same order. Reflection about the (inclusive) bounds keeps the group's overall
# footprint fixed, so mirroring feels like an in-place flip.
static func _mirror_top_left_cells(rects: Array, axis: String) -> Array:
	var result: Array = []
	if rects.is_empty():
		return result

	var first_tl: Vector2i = rects[0]["top_left"]
	var first_size: Vector2i = rects[0]["size"]
	var min_x := first_tl.x
	var min_y := first_tl.y
	var max_x := first_tl.x + first_size.x - 1
	var max_y := first_tl.y + first_size.y - 1
	for r in rects:
		var tl: Vector2i = r["top_left"]
		var size: Vector2i = r["size"]
		min_x = mini(min_x, tl.x)
		min_y = mini(min_y, tl.y)
		max_x = maxi(max_x, tl.x + size.x - 1)
		max_y = maxi(max_y, tl.y + size.y - 1)

	for r in rects:
		var tl: Vector2i = r["top_left"]
		var size: Vector2i = r["size"]
		var new_x := tl.x
		var new_y := tl.y
		if axis == "horizontal":
			new_x = (min_x + max_x) - (tl.x + size.x - 1)
		elif axis == "vertical":
			new_y = (min_y + max_y) - (tl.y + size.y - 1)
		result.append(Vector2i(new_x, new_y))

	return result

# --- Group rail capture / preview / reproduction -----------------------------

func _capture_group_rails_from_entries() -> void:
	group_build_rails.clear()
	var pm := $"../PathManager"
	if pm == null or not pm.has_method("get_internal_rails"):
		return

	var index_by_building := {}
	var sources: Array = []
	for i in group_build_entries.size():
		var source = group_build_entries[i].get("source")
		if source != null:
			index_by_building[source] = i
			sources.append(source)

	if sources.size() < 2:
		return

	var rails: Array = pm.get_internal_rails(sources)
	for rail in rails:
		var from_building = rail.get("from_building")
		var to_building = rail.get("to_building")
		if not index_by_building.has(from_building) or not index_by_building.has(to_building):
			continue
		group_build_rails.append({
			"from_index": int(index_by_building[from_building]),
			"from_port": rail.get("from_port"),
			"to_index": int(index_by_building[to_building]),
			"to_port": rail.get("to_port"),
			"rail_version": int(rail.get("rail_version", 0)),
		})

func _build_group_rail_previews() -> void:
	_clear_group_rail_previews()
	if group_build_rails.is_empty():
		return

	var pm := $"../PathManager"
	if pm == null:
		return

	if _rail_preview_root == null or not is_instance_valid(_rail_preview_root):
		_rail_preview_root = Node2D.new()
		_rail_preview_root.name = "GroupRailPreviews"
		_rail_preview_root.z_index = -1
		add_child(_rail_preview_root)
	_rail_preview_root.position = Vector2.ZERO

	var preview_width := 5.0
	if "line_width" in pm:
		preview_width = float(pm.line_width)

	for rail in group_build_rails:
		var line := Line2D.new()
		line.width = preview_width
		line.antialiased = true
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		if pm.has_method("get_rail_color_for_version"):
			line.default_color = pm.get_rail_color_for_version(int(rail.get("rail_version", 0)))
		line.modulate.a = 0.55
		_rail_preview_root.add_child(line)
		group_build_rail_previews.append({
			"line": line,
			"from_index": int(rail.get("from_index", -1)),
			"from_port": rail.get("from_port"),
			"to_index": int(rail.get("to_index", -1)),
			"to_port": rail.get("to_port"),
		})

	_rail_preview_routes_dirty = true

# Per-frame preview upkeep. The expensive rail routing only reruns when the
# layout changed (dirty); otherwise the preview container is translated rigidly
# with the group -- the rail shapes are invariant under a pure translation, so
# following the cursor is a single Vector2 assignment regardless of rail count.
func _position_group_rail_previews(anchor_cell: Vector2i) -> void:
	if group_build_rail_previews.is_empty():
		return
	if _rail_preview_root == null or not is_instance_valid(_rail_preview_root):
		return

	if _rail_preview_routes_dirty:
		_rail_preview_root.position = Vector2.ZERO
		_recompute_group_rail_preview_points()
		_rail_preview_anchor_cell = anchor_cell
		_rail_preview_routes_dirty = false
	else:
		_rail_preview_root.position = cell_to_world(anchor_cell) - cell_to_world(_rail_preview_anchor_cell)

func _recompute_group_rail_preview_points() -> void:
	var pm := $"../PathManager"
	if pm == null or not pm.has_method("build_route_preview_points_local"):
		return

	for preview in group_build_rail_previews:
		var line := preview.get("line") as Line2D
		if line == null or not is_instance_valid(line):
			continue
		var from_ghost := _group_ghost_at(int(preview.get("from_index", -1)))
		var to_ghost := _group_ghost_at(int(preview.get("to_index", -1)))
		if from_ghost == null or to_ghost == null:
			line.points = PackedVector2Array()
			continue
		line.points = pm.build_route_preview_points_local(_rail_preview_root, from_ghost, preview.get("from_port"), to_ghost, preview.get("to_port"))

func _group_ghost_at(index: int) -> Node2D:
	if index < 0 or index >= group_build_entries.size():
		return null
	return group_build_entries[index].get("ghost") as Node2D

func _clear_group_rail_previews() -> void:
	for preview in group_build_rail_previews:
		var line = preview.get("line")
		if line != null and is_instance_valid(line):
			line.queue_free()
	group_build_rail_previews.clear()

func _reproduce_group_rails(real_by_index: Dictionary) -> void:
	if group_build_rails.is_empty():
		return
	var pm := $"../PathManager"
	if pm == null or not pm.has_method("create_rail_between"):
		return

	var created_any := false
	for rail in group_build_rails:
		var from_building = real_by_index.get(int(rail.get("from_index", -1)))
		var to_building = real_by_index.get(int(rail.get("to_index", -1)))
		if from_building == null or to_building == null:
			continue
		if pm.create_rail_between(from_building, rail.get("from_port"), to_building, rail.get("to_port"), int(rail.get("rail_version", 0)), false, false):
			created_any = true

	if created_any and pm.has_method("notify_rail_graph_changed"):
		pm.notify_rail_graph_changed()

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
	var real_by_index := {}
	for i in group_build_entries.size():
		var entry = group_build_entries[i]
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
		real_by_index[i] = real_building

	_reproduce_group_rails(real_by_index)
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
	var was_group_build := _is_group_build_active()
	if was_group_build:
		for entry in group_build_entries:
			var ghost := entry.get("ghost") as Node2D
			if ghost != null:
				ghost.queue_free()
	elif ghost_instance:
		ghost_instance.queue_free()

	_clear_group_rail_previews()
	_rail_preview_routes_dirty = false
	current_scene = null
	ghost_instance = null
	ghost_area = null
	ghost_selection_template = {}
	group_build_entries.clear()
	group_build_rails.clear()
	is_building = false
	_set_port_buttons_passthrough_for_build_mode(false)
	if was_group_build:
		group_build_changed.emit(false)
	
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
		if building == alignment_anchor_building and selected_buildings.size() >= 2:
			building.modulate = ANCHOR_BUILDING_MODULATE
		else:
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
	if is_building and _is_group_build_active():
		if InputMap.has_action("Mirror Horizontal") and Input.is_action_just_pressed("Mirror Horizontal"):
			mirror_group_layout("horizontal")
		if InputMap.has_action("Mirror Vertical") and Input.is_action_just_pressed("Mirror Vertical"):
			mirror_group_layout("vertical")
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
