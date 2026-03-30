extends Node2D

const SAVE_FILE_EXTENSION := "srbp"
const SAVE_FORMAT_VERSION := 1

@onready var camera: Camera2D = $Camera2D
@onready var tile_map_layer: TileMapLayer = $TileMapLayer
@onready var heat_label: Label = $Camera2D/CanvasLayer/Panel/HeatLabel
@onready var power_label: Label = $Camera2D/CanvasLayer/Panel/PowerLabel
@onready var bbm_cost_label: Label = $Camera2D/CanvasLayer/Panel/BBMCostLabel
@onready var ibm_cost_label: Label = $Camera2D/CanvasLayer/Panel/IBMCostLabel
@onready var meteor_core_cost_label: Label = $Camera2D/CanvasLayer/Panel/MeteorCoreCostLabel
@onready var prod_panel: PanelContainer = $Camera2D/CanvasLayer/ProdMenu/ProdPanel
@onready var build_manager: Node = $BuildManager
@onready var path_manager: Node = $PathManager
@onready var buildings_root: Node2D = $buildings

var save_button: Button
var load_button: Button
var save_dialog: FileDialog
var load_dialog: FileDialog

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	heat_label.text = "0"
	power_label.text = "0"
	bbm_cost_label.text = "0"
	ibm_cost_label.text = "0"
	meteor_core_cost_label.text = "0"
	_setup_save_load_ui()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	Adjust_ui_for_resolution()
	recenter_camera()
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
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

func _setup_save_load_ui() -> void:
	save_button = Button.new()
	save_button.name = "SaveButton"
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_pressed)
	$Camera2D/CanvasLayer.add_child(save_button)

	load_button = Button.new()
	load_button.name = "LoadButton"
	load_button.text = "Load"
	load_button.pressed.connect(_on_load_pressed)
	$Camera2D/CanvasLayer.add_child(load_button)

	save_dialog = FileDialog.new()
	save_dialog.name = "SaveDialog"
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.title = "Save Build Plan"
	save_dialog.filters = PackedStringArray(["*.%s ; SRBP Save File" % SAVE_FILE_EXTENSION])
	save_dialog.file_selected.connect(_on_save_file_selected)
	add_child(save_dialog)

	load_dialog = FileDialog.new()
	load_dialog.name = "LoadDialog"
	load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	load_dialog.title = "Load Build Plan"
	load_dialog.filters = PackedStringArray(["*.%s ; SRBP Save File" % SAVE_FILE_EXTENSION, "*.json ; JSON Save File"])
	load_dialog.file_selected.connect(_on_load_file_selected)
	add_child(load_dialog)
	
func Adjust_ui_for_resolution() -> void:
	$Camera2D/CanvasLayer/MenuButton.position = Vector2 (15, 15)
	$Camera2D/CanvasLayer/Panel.position = Vector2 (get_viewport().size.x - 180, 5)
	$Camera2D/CanvasLayer/ProdMenu.position = Vector2 (get_viewport().size.x - 75, 100)
	$Camera2D/CanvasLayer/ControlMenu.position = Vector2(15, get_viewport().size.y -50)
	$"Camera2D/CanvasLayer/Patch Notes".position = Vector2(15, get_viewport().size.y -90)
	
	if save_button != null:
		save_button.position = Vector2(get_viewport().size.x - 300, 8)
	if load_button != null:
		load_button.position = Vector2(get_viewport().size.x - 240, 8)
	
func _on_viewport_size_changed() -> void:
	Adjust_ui_for_resolution()

func recenter_camera() -> void:
	$Camera2D.position = get_tilemap_center_global()

func get_tilemap_center_global() -> Vector2:
	var used_rect: Rect2i = tile_map_layer.get_used_rect()
	var center_cell := used_rect.position + used_rect.size/2
	var local_pos = tile_map_layer.map_to_local(center_cell)
	
	if used_rect.size == Vector2i.ZERO:
		return Vector2i (0,0)
	
	return tile_map_layer.to_global(local_pos)

func _on_save_pressed() -> void:
	if OS.has_feature("web") and JavaScriptBridge != null:
		_download_save_to_browser()
		return

	save_dialog.current_file = "build_plan.%s" % SAVE_FILE_EXTENSION
	save_dialog.popup_centered_ratio(0.7)

func _on_load_pressed() -> void:
	load_dialog.popup_centered_ratio(0.7)

func _on_save_file_selected(path: String) -> void:
	var result := _write_save_file(path)
	if not result:
		push_warning("Failed to save file to %s" % path)

func _on_load_file_selected(path: String) -> void:
	var loaded := _load_save_file(path)
	if not loaded:
		push_warning("Failed to load save file from %s" % path)

func _download_save_to_browser() -> void:
	var save_state := _collect_save_state()
	var json_text := JSON.stringify(save_state, "\t")
	var bytes := json_text.to_utf8_buffer()
	JavaScriptBridge.download_buffer(bytes, "build_plan.%s" % SAVE_FILE_EXTENSION, "application/json")

func _write_save_file(path: String) -> bool:
	var save_state := _collect_save_state()
	var json_text := JSON.stringify(save_state, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(json_text)
	return true

func _load_save_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var raw := file.get_as_text()
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return false

	_apply_save_state(parsed)
	return true

func _collect_save_state() -> Dictionary:
	var building_data: Array[Dictionary] = []
	var building_index: Dictionary = {}
	var occupied: Array[String] = []

	for key in build_manager.occupied_cells.keys():
		occupied.append("%d,%d" % [key.x, key.y])

	for i in buildings_root.get_child_count():
		var building := buildings_root.get_child(i)
		if not (building is Node2D):
			continue

		building_index[building] = building_data.size()
		building_data.append(_serialize_building(building))

	var path_data: Array[Dictionary] = _serialize_paths(building_index)

	return {
		"version": SAVE_FORMAT_VERSION,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"heat": int(heat_label.text),
		"power": int(power_label.text),
		"cost_bbm": int(bbm_cost_label.text),
		"cost_ibm": int(ibm_cost_label.text),
		"cost_meteor_cores": int(meteor_core_cost_label.text),
		"camera": {
			"position": [camera.position.x, camera.position.y],
			"zoom": [camera.zoom.x, camera.zoom.y]
		},
		"production_panel_visible": prod_panel.visible,
		"buildings": building_data,
		"occupied_cells": occupied,
		"paths": path_data
	}

func _serialize_building(building: Node2D) -> Dictionary:
	var recipe_selection := _serialize_option_button(building.get_node_or_null("Recipe"))
	var purity_selection := _serialize_option_button(building.get_node_or_null("Purity"))

	return {
		"id": str(building.get("id")) if building.has_method("get") else "",
		"scene_path": building.scene_file_path,
		"position": [building.global_position.x, building.global_position.y],
		"rotation_degrees": building.rotation_degrees,
		"rotated_tick": int(building.get("rotatedTick")) if "rotatedTick" in building else 0,
		"is_alternate": bool(building.get("is_alternate")) if "is_alternate" in building else false,
		"anchor": [int(building.get("anchor").x), int(building.get("anchor").y)] if "anchor" in building else [0, 0],
		"recipe": recipe_selection,
		"purity": purity_selection
	}

func _serialize_option_button(node: Node) -> Dictionary:
	if node == null or not (node is OptionButton):
		return {}

	var ob := node as OptionButton
	var selected := ob.selected
	var metadata_path := ""

	if selected >= 0 and selected < ob.item_count:
		var metadata = ob.get_item_metadata(selected)
		if metadata is Resource:
			metadata_path = (metadata as Resource).resource_path
		elif metadata != null:
			metadata_path = str(metadata)

	return {
		"selected": selected,
		"metadata_path": metadata_path
	}

func _serialize_paths(building_index: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	for child in path_manager.get_children():
		if not (child is Path2D):
			continue
		if not child.has_meta("from_building") or not child.has_meta("to_building"):
			continue

		var from_building: Node = child.get_meta("from_building")
		var to_building: Node = child.get_meta("to_building")

		if not building_index.has(from_building) or not building_index.has(to_building):
			continue

		out.append({
			"from_index": int(building_index[from_building]),
			"to_index": int(building_index[to_building]),
			"from_port": str(child.get_meta("from_port")),
			"to_port": str(child.get_meta("to_port"))
		})

	return out

func _apply_save_state(save_state: Dictionary) -> void:
	_clear_existing_plan()

	var loaded_buildings: Array[Node2D] = []
	var saved_buildings = save_state.get("buildings", [])
	for entry in saved_buildings:
		if not (entry is Dictionary):
			continue
		var building := _instantiate_saved_building(entry)
		if building == null:
			continue
		loaded_buildings.append(building)

	_restore_paths(save_state.get("paths", []), loaded_buildings)
	_rebuild_occupancy_from_scene(loaded_buildings)
	_restore_camera(save_state.get("camera", {}))
	prod_panel.visible = bool(save_state.get("production_panel_visible", false))

	if save_state.has("heat"):
		heat_label.text = str(int(save_state["heat"]))
	else:
		heat_label.text = str(_sum_building_stat(loaded_buildings, "heat"))

	if save_state.has("power"):
		power_label.text = str(int(save_state["power"]))
	else:
		power_label.text = str(_sum_building_stat(loaded_buildings, "power"))

	if save_state.has("cost_bbm") and save_state.has("cost_ibm") and save_state.has("cost_meteor_cores"):
		bbm_cost_label.text = str(int(save_state["cost_bbm"]))
		ibm_cost_label.text = str(int(save_state["cost_ibm"]))
		meteor_core_cost_label.text = str(int(save_state["cost_meteor_cores"]))
	else:
		var cost_totals := _sum_building_costs(loaded_buildings)
		bbm_cost_label.text = str(cost_totals.get("bbm", 0))
		ibm_cost_label.text = str(cost_totals.get("ibm", 0))
		meteor_core_cost_label.text = str(cost_totals.get("meteor_cores", 0))

	_rebuild_production_ledger(loaded_buildings)

func _clear_existing_plan() -> void:
	if build_manager.has_method("cancel_build"):
		build_manager.cancel_build()

	for child in path_manager.get_children():
		child.queue_free()

	for child in buildings_root.get_children():
		child.queue_free()

	build_manager.occupied_cells.clear()
	_reset_prod_ledger()

func _reset_prod_ledger() -> void:
	if not get_tree().root.has_node("ProdLedger"):
		return
	var ledger := get_node("/root/ProdLedger")
	ledger.net_totals.clear()
	ledger.gross_totals.clear()
	ledger.gross_negative_totals.clear()
	ledger.by_source.clear()
	ledger.totals_changed.emit(ledger.net_totals, ledger.gross_totals, ledger.gross_negative_totals)

func _instantiate_saved_building(data: Dictionary) -> Node2D:
	var scene: PackedScene = null

	var id_key := StringName(data.get("id", ""))
	if id_key != StringName("") and get_tree().root.has_node("BuildingRegistry"):
		scene = BuildingRegistry.get_scene(id_key)

	if scene == null:
		var scene_path := String(data.get("scene_path", ""))
		if scene_path != "":
			scene = load(scene_path) as PackedScene

	if scene == null:
		return null

	var instance := scene.instantiate() as Node2D
	if instance == null:
		return null

	var position_data = data.get("position", [0.0, 0.0])
	if position_data is Array and position_data.size() >= 2:
		instance.global_position = Vector2(float(position_data[0]), float(position_data[1]))

	instance.rotation_degrees = float(data.get("rotation_degrees", 0.0))

	if bool(data.get("is_alternate", false)) and instance.has_method("flip_footprint") and not bool(instance.get("is_alternate")):
		instance.flip_footprint()

	if "rotatedTick" in instance:
		instance.rotatedTick = int(data.get("rotated_tick", 0))

	if data.has("anchor") and "anchor" in instance:
		var anchor_data = data.get("anchor", [0, 0])
		if anchor_data is Array and anchor_data.size() >= 2:
			instance.anchor = Vector2i(int(anchor_data[0]), int(anchor_data[1]))

	buildings_root.add_child(instance)
	_restore_option_selection(instance.get_node_or_null("Recipe"), data.get("recipe", {}))
	_restore_option_selection(instance.get_node_or_null("Purity"), data.get("purity", {}))

	return instance

func _restore_option_selection(node: Node, selection_data: Dictionary) -> void:
	if node == null or not (node is OptionButton):
		return

	var ob := node as OptionButton
	var matched := false
	var metadata_path := String(selection_data.get("metadata_path", ""))

	if metadata_path != "":
		for i in ob.item_count:
			var metadata = ob.get_item_metadata(i)
			if metadata is Resource and (metadata as Resource).resource_path == metadata_path:
				ob.select(i)
				matched = true
				break
			elif str(metadata) == metadata_path:
				ob.select(i)
				matched = true
				break

	if not matched:
		var selected := int(selection_data.get("selected", -1))
		if selected >= 0 and selected < ob.item_count:
			ob.select(selected)

func _restore_paths(path_entries: Array, loaded_buildings: Array[Node2D]) -> void:
	for entry in path_entries:
		if not (entry is Dictionary):
			continue
		var from_idx := int(entry.get("from_index", -1))
		var to_idx := int(entry.get("to_index", -1))
		if from_idx < 0 or to_idx < 0:
			continue
		if from_idx >= loaded_buildings.size() or to_idx >= loaded_buildings.size():
			continue

		var from_b := loaded_buildings[from_idx]
		var to_b := loaded_buildings[to_idx]
		var from_port := NodePath(String(entry.get("from_port", "Ports/Output 1")))
		var to_port := NodePath(String(entry.get("to_port", "Ports/Input 1")))
		var from_pos = path_manager._get_port_center(from_b, from_port)
		var to_pos = path_manager._get_port_center(to_b, to_port)
		if from_pos == null or to_pos == null:
			continue
		path_manager._finalize_path(from_b, from_port, from_pos, to_b, to_port, to_pos)

func _rebuild_occupancy_from_scene(loaded_buildings: Array[Node2D]) -> void:
	build_manager.occupied_cells.clear()
	for building in loaded_buildings:
		var anchor_cell = build_manager._anchor_cell_from_building_position(building, building.global_position)
		var cells: Array[Vector2i] = build_manager.get_building_cells(building, anchor_cell)
		build_manager.occupy_cells(cells, building)

func _rebuild_production_ledger(loaded_buildings: Array[Node2D]) -> void:
	if not get_tree().root.has_node("ProdLedger"):
		return
	var ledger := get_node("/root/ProdLedger")

	for building in loaded_buildings:
		var deltas := _get_saved_building_deltas(building)
		if deltas.is_empty():
			continue
		ledger.add_source(building.get_instance_id(), building, deltas)

func _get_saved_building_deltas(building: Node2D) -> Dictionary:
	if not building.has_method("get_production_deltas"):
		return {}

	var purity := building.get_node_or_null("Purity") as OptionButton
	if purity != null and purity.selected >= 0 and purity.selected < purity.item_count:
		var variant = purity.get_item_metadata(purity.selected)
		if variant != null:
			return building.get_production_deltas(variant)

	var recipe := building.get_node_or_null("Recipe") as OptionButton
	if recipe != null and recipe.selected >= 0 and recipe.selected < recipe.item_count:
		var selected_recipe = recipe.get_item_metadata(recipe.selected)
		if selected_recipe != null:
			return building.get_production_deltas(selected_recipe)

	if "recipe" in building and building.recipe != null:
		return building.get_production_deltas(building.recipe)

	return {}

func _restore_camera(camera_data: Dictionary) -> void:
	if not (camera_data is Dictionary):
		return

	var pos = camera_data.get("position", [])
	if pos is Array and pos.size() >= 2:
		camera.position = Vector2(float(pos[0]), float(pos[1]))

	var zoom_data = camera_data.get("zoom", [])
	if zoom_data is Array and zoom_data.size() >= 2:
		camera.zoom = Vector2(float(zoom_data[0]), float(zoom_data[1]))

func _sum_building_stat(loaded_buildings: Array[Node2D], stat_name: String) -> int:
	var total := 0
	for building in loaded_buildings:
		if stat_name in building:
			total += int(building.get(stat_name))
	return total
	
func _sum_building_costs(loaded_buildings: Array[Node2D]) -> Dictionary:
	var totals := {
		"bbm": 0,
		"ibm": 0,
		"meteor_cores": 0
	}

	for building in loaded_buildings:
		if not ("build_cost_amount" in building):
			continue

		var amount := int(building.get("build_cost_amount"))
		var cost_type := int(building.get("build_cost_type")) if "build_cost_type" in building else 0

		match cost_type:
			Building.BuildCostType.BBM:
				totals["bbm"] += amount
			Building.BuildCostType.IBM:
				totals["ibm"] += amount
			Building.BuildCostType.METEOR_CORE:
				totals["meteor_cores"] += amount

	return totals
	
