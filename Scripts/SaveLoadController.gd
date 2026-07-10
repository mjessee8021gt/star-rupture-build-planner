class_name SaveLoadController
extends RefCounted

# Owns getting a build plan to and from persistent storage: the three FileDialogs,
# desktop file read/write, the browser save/load routes (showSaveFilePicker + download
# fallback), PDF export, and the plan-state (de)serialization spine that rebuilds the
# live scene. Extracted from main.gd. The host (main) supplies live scene refs and the
# version-aware document wrappers (_collect_save_document / _apply_save_text), which own
# the Save Engine V2 version log that this controller has no part in.

# Format constants — must match main.gd's SAVE_FILE_EXTENSION / SAVE_FORMAT_VERSION.
const SAVE_FILE_EXTENSION := "srbp"
const SAVE_FORMAT_VERSION := 5

var _host: Node = null

var save_dialog: FileDialog
var load_dialog: FileDialog
var export_pdf_dialog: FileDialog

var _web_load_picker: WebFileBridge = null
var _web_save_success_callback = null
var _web_save_error_callback = null
var _web_save_pending_file_name := ""


func _init(host: Node) -> void:
	_host = host


func setup() -> void:
	save_dialog = FileDialog.new()
	save_dialog.name = "SaveDialog"
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.title = "Save Build Plan"
	save_dialog.filters = PackedStringArray(["*.%s ; SRBP Save File" % SAVE_FILE_EXTENSION])
	save_dialog.file_selected.connect(_on_save_file_selected)
	_host.add_child(save_dialog)

	load_dialog = FileDialog.new()
	load_dialog.name = "LoadDialog"
	load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	load_dialog.title = "Load Build Plan"
	load_dialog.filters = PackedStringArray(["*.%s ; SRBP Save File" % SAVE_FILE_EXTENSION, "*.json ; JSON Save File"])
	load_dialog.file_selected.connect(_on_load_file_selected)
	_host.add_child(load_dialog)

	export_pdf_dialog = FileDialog.new()
	export_pdf_dialog.name = "ExportPdfDialog"
	export_pdf_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_pdf_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_pdf_dialog.title = "Export Build Plan PDF"
	export_pdf_dialog.filters = PackedStringArray(["*.pdf ; PDF Document"])
	export_pdf_dialog.file_selected.connect(_on_export_pdf_file_selected)
	_host.add_child(export_pdf_dialog)


func is_dialog_open() -> bool:
	for dialog in [save_dialog, load_dialog, export_pdf_dialog]:
		if dialog != null and dialog.visible:
			return true
	return false


# --- Save / load / export triggers (main routes menu commands here) ----------
func request_save() -> void:
	if WebFileBridge.is_available():
		_request_save_to_browser()
		return

	save_dialog.current_file = "build_plan.%s" % SAVE_FILE_EXTENSION
	save_dialog.popup_centered_ratio(0.7)


func request_load() -> void:
	if WebFileBridge.is_available():
		_request_load_from_browser()
		return
	load_dialog.popup_centered_ratio(0.7)


func request_export_pdf() -> void:
	if WebFileBridge.is_available():
		_download_pdf_to_browser()
		return

	export_pdf_dialog.current_file = "build_plan.pdf"
	export_pdf_dialog.popup_centered_ratio(0.7)


func _on_save_file_selected(path: String) -> void:
	var result := _write_save_file(path)
	if not result:
		push_warning("Failed to save file to %s" % path)


func _on_load_file_selected(path: String) -> void:
	var loaded := _load_save_file(path)
	if not loaded:
		push_warning("Failed to load save file from %s" % path)


func _on_export_pdf_file_selected(path: String) -> void:
	var exported := _write_pdf_file(path)
	if not exported:
		push_warning("Failed to export PDF file to %s" % path)


func clear_scene_plan() -> void:
	var build_manager: Node = _host.build_manager
	if build_manager != null and build_manager.has_method("cancel_build"):
		build_manager.cancel_build()

	var path_manager: Node = _host.path_manager
	if path_manager != null and path_manager.has_method("cancel_active_path_drag"):
		path_manager.cancel_active_path_drag()

	var annotation_layer: Node = _host.annotation_layer
	if annotation_layer != null and annotation_layer.has_method("clear_annotations"):
		annotation_layer.call("clear_annotations")

	if path_manager != null:
		for child in path_manager.get_children():
			if child is Path2D:
				_detach_and_queue_free(child)

	for child in _host.buildings_root.get_children():
		_detach_and_queue_free(child)

	if build_manager != null and "occupied_cells" in build_manager:
		build_manager.occupied_cells.clear()

	_host.heat_label.text = "0"
	_host.power_label.text = "0"
	_host.bbm_cost_label.text = "0"
	_host.ibm_cost_label.text = "0"
	_host.meteor_core_cost_label.text = "0"

	var ledger := _host.get_tree().root.get_node_or_null("ProdLedger")
	if ledger == null:
		ledger = _host.get_tree().root.get_node_or_null("ProductionLedger")
	if ledger != null:
		ledger.net_totals.clear()
		ledger.gross_totals.clear()
		ledger.gross_negative_totals.clear()
		ledger.by_source.clear()
		ledger.totals_changed.emit(ledger.net_totals, ledger.gross_totals, ledger.gross_negative_totals)
	_host._clear_flow_simulation_cache()
	_host._queue_flow_simulation_refresh()


# --- Browser save -------------------------------------------------------------
func _download_save_to_browser() -> void:
	var save_state: Dictionary = _host._collect_save_document()
	var json_text := JSON.stringify(save_state, "\t")
	var bytes := json_text.to_utf8_buffer()
	WebFileBridge.download_bytes(bytes, "build_plan.%s" % SAVE_FILE_EXTENSION, "application/json")


func _request_save_to_browser() -> void:
	var window = JavaScriptBridge.get_interface("window")
	if window == null:
		_download_save_to_browser()
		return

	var install_script := """
if (!window.__srbpSaveTextFile) {
	window.__srbpSaveTextFile = function(content, suggestedName, mime, success, failure) {
		const fallbackDownload = () => {
			try {
				const blob = new Blob([content], { type: mime });
				const url = URL.createObjectURL(blob);
				const anchor = document.createElement('a');
				anchor.href = url;
				anchor.download = suggestedName;
				anchor.style.display = 'none';
				document.body.appendChild(anchor);
				anchor.click();
				setTimeout(() => {
					if (anchor.parentNode) {
						anchor.parentNode.removeChild(anchor);
					}
					URL.revokeObjectURL(url);
				}, 0);
				if (success) success('download');
			} catch (err) {
				if (failure) failure(String(err));
			}
		};

		if (!window.showSaveFilePicker) {
			fallbackDownload();
			return;
		}

		(async () => {
			try {
				const handle = await window.showSaveFilePicker({
					suggestedName,
					types: [{
						description: 'SRBP Save File',
						accept: {
							'application/json': ['.srbp', '.json']
						}
					}]
				});
				const writable = await handle.createWritable();
				await writable.write(content);
				await writable.close();
				if (success) success('picker');
			} catch (err) {
				if (err && err.name === 'AbortError') {
					if (failure) failure('AbortError');
					return;
				}
				fallbackDownload();
			}
		})();
	};
}
"""
	JavaScriptBridge.eval(install_script, true)

	var suggested_name := "build_plan.%s" % SAVE_FILE_EXTENSION
	var save_state: Dictionary = _host._collect_save_document()
	var json_text := JSON.stringify(save_state, "\t")
	_web_save_pending_file_name = suggested_name
	_web_save_success_callback = JavaScriptBridge.create_callback(_on_web_save_succeeded)
	_web_save_error_callback = JavaScriptBridge.create_callback(_on_web_save_failed)
	window.__srbpSaveTextFile(json_text, suggested_name, "application/json", _web_save_success_callback, _web_save_error_callback)


func _cleanup_web_save_callbacks() -> void:
	_web_save_success_callback = null
	_web_save_error_callback = null
	_web_save_pending_file_name = ""


func _on_web_save_succeeded(_args: Array) -> void:
	_cleanup_web_save_callbacks()


func _on_web_save_failed(args: Array) -> void:
	var error_text := ""
	if not args.is_empty():
		error_text = str(args[0])

	if error_text == "AbortError":
		_cleanup_web_save_callbacks()
		return

	push_warning("Failed to save browser-selected file %s" % _web_save_pending_file_name)
	_cleanup_web_save_callbacks()


func _download_pdf_to_browser() -> void:
	var pdf_bytes := build_pdf_bytes()
	WebFileBridge.download_bytes(pdf_bytes, "build_plan.pdf", "application/pdf")


# --- Desktop file IO ----------------------------------------------------------
func _write_save_file(path: String) -> bool:
	var save_state: Dictionary = _host._collect_save_document()
	var json_text := JSON.stringify(save_state, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(json_text)
	return true


func _write_pdf_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(build_pdf_bytes())
	return true


func _request_load_from_browser() -> void:
	if _web_load_picker == null:
		_web_load_picker = WebFileBridge.new()
	_web_load_picker.pick_text_file(
		".%s,.json,application/json" % SAVE_FILE_EXTENSION,
		_on_web_load_text_loaded,
		func() -> void: push_warning("Failed to read the browser-selected save file."))


func _on_web_load_text_loaded(raw_text: String) -> void:
	var loaded: bool = raw_text != "" and _host._apply_save_text(raw_text)
	if not loaded:
		push_warning("Failed to load the browser-selected save file.")


func _load_save_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var raw := file.get_as_text()
	return _host._apply_save_text(raw)


func _detach_and_queue_free(node: Node) -> void:
	if node == null:
		return
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()


# --- Plan-state serialization spine ------------------------------------------
func collect_save_state() -> Dictionary:
	var build_manager: Node = _host.build_manager
	var buildings_root: Node2D = _host.buildings_root
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
		building_data.append(PlanSerializer.serialize_building(building, build_manager))

	var path_data: Array[Dictionary] = PlanSerializer.serialize_paths(_host.path_manager, building_index)
	var annotation_data: Array[Dictionary] = []
	var annotation_layer: Node = _host.annotation_layer
	if annotation_layer != null and annotation_layer.has_method("serialize_annotations"):
		var serialized_annotations = annotation_layer.call("serialize_annotations")
		if serialized_annotations is Array:
			for annotation in serialized_annotations:
				if annotation is Dictionary:
					annotation_data.append(annotation)

	var camera: Camera2D = _host.camera
	return {
		"version": SAVE_FORMAT_VERSION,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"heat": int(_host.heat_label.text),
		"power": int(_host.power_label.text),
		"cost_bbm": int(_host.bbm_cost_label.text),
		"cost_ibm": int(_host.ibm_cost_label.text),
		"cost_meteor_cores": int(_host.meteor_core_cost_label.text),
		"camera": {
			"position": [camera.position.x, camera.position.y],
			"zoom": [camera.zoom.x, camera.zoom.y]
		},
		"production_panel_visible": _host.prod_panel.visible,
		"buildings": building_data,
		"occupied_cells": occupied,
		"paths": path_data,
		"annotations": annotation_data
	}


func apply_save_state(save_state: Dictionary, restore_view_state := true) -> void:
	var prod_panel: Control = _host.prod_panel
	var keep_prod_panel_visible := prod_panel.visible
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

	_rebuild_occupancy_from_scene(loaded_buildings)
	_restore_paths(save_state.get("paths", []), loaded_buildings)
	var annotation_layer: Node = _host.annotation_layer
	if annotation_layer != null and annotation_layer.has_method("load_annotations"):
		annotation_layer.call("load_annotations", save_state.get("annotations", []))
	if restore_view_state:
		_restore_camera(save_state.get("camera", {}))
		prod_panel.visible = bool(save_state.get("production_panel_visible", false))
	else:
		prod_panel.visible = keep_prod_panel_visible

	if save_state.has("heat"):
		_host.heat_label.text = str(int(save_state["heat"]))
	else:
		_host.heat_label.text = str(PlanSerializer.sum_building_stat(loaded_buildings, "heat"))

	if save_state.has("power"):
		_host.power_label.text = str(int(save_state["power"]))
	else:
		_host.power_label.text = str(PlanSerializer.sum_building_stat(loaded_buildings, "power"))

	if save_state.has("cost_bbm") and save_state.has("cost_ibm") and save_state.has("cost_meteor_cores"):
		_host.bbm_cost_label.text = str(int(save_state["cost_bbm"]))
		_host.ibm_cost_label.text = str(int(save_state["cost_ibm"]))
		_host.meteor_core_cost_label.text = str(int(save_state["cost_meteor_cores"]))
	else:
		var cost_totals := PlanSerializer.sum_building_costs(loaded_buildings)
		_host.bbm_cost_label.text = str(cost_totals.get("bbm", 0))
		_host.ibm_cost_label.text = str(cost_totals.get("ibm", 0))
		_host.meteor_core_cost_label.text = str(cost_totals.get("meteor_cores", 0))

	_host._rebuild_production_ledger(loaded_buildings)
	_host._clear_flow_simulation_cache()
	_host._queue_flow_simulation_refresh()


func _clear_existing_plan() -> void:
	var build_manager: Node = _host.build_manager
	var path_manager: Node = _host.path_manager
	if build_manager.has_method("cancel_build"):
		build_manager.cancel_build()
	if path_manager.has_method("cancel_active_path_drag"):
		path_manager.cancel_active_path_drag()
	var annotation_layer: Node = _host.annotation_layer
	if annotation_layer != null and annotation_layer.has_method("clear_annotations"):
		annotation_layer.call("clear_annotations")

	for child in path_manager.get_children():
		_detach_and_queue_free(child)

	for child in _host.buildings_root.get_children():
		_detach_and_queue_free(child)

	build_manager.occupied_cells.clear()
	_host._reset_prod_ledger()
	_host._clear_flow_simulation_cache()


func _instantiate_saved_building(data: Dictionary) -> Node2D:
	var scene: PackedScene = null

	var id_key := StringName(data.get("id", ""))
	if id_key != StringName(""):
		scene = BuildRegistry.get_scene(id_key)

	if scene == null:
		var scene_path := String(data.get("scene_path", ""))
		if scene_path != "":
			scene = load(scene_path) as PackedScene

	if scene == null:
		return null

	var instance := scene.instantiate() as Node2D
	if instance == null:
		return null

	var saved_uid := String(data.get("uid", ""))
	if saved_uid != "":
		instance.set_meta(PlanSerializer.BUILDING_UID_META, saved_uid)

	var position_data = data.get("position", [0.0, 0.0])
	if position_data is Array and position_data.size() >= 2:
		instance.global_position = Vector2(float(position_data[0]), float(position_data[1]))

	instance.rotation_degrees = float(data.get("rotation_degrees", 0.0))

	if bool(data.get("is_alternate", false)) and instance.has_method("flip_footprint") and not bool(instance.get("is_alternate")):
		instance.flip_footprint()

	if "rotatedTick" in instance:
		instance.rotatedTick = int(data.get("rotated_tick", 0))

	_host.buildings_root.add_child(instance)
	_restore_loaded_building_selection_state(
		instance,
		data.get("recipe", {}),
		data.get("purity", {}),
		data.get("core_level", {})
	)

	return instance


func _restore_loaded_building_selection_state(building: Node2D, recipe_selection: Dictionary, purity_selection: Dictionary, core_level_selection: Dictionary = {}) -> void:
	var recipe_dropdown := building.get_node_or_null("Recipe") as OptionButton
	var purity_dropdown := building.get_node_or_null("Purity") as OptionButton
	var core_level_dropdown := building.get_node_or_null("CoreLevel") as OptionButton

	_restore_option_selection(recipe_dropdown, recipe_selection)

	# Some buildings rebuild their purity choices from the selected recipe,
	# so replay that step before restoring the saved purity selection.
	if purity_dropdown != null and building.has_method("_on_purity_item_selected"):
		_host._call_option_selection_handler(building, "_on_recipe_item_selected", recipe_dropdown)

	_restore_option_selection(purity_dropdown, purity_selection)

	if not _host._call_option_selection_handler(building, "_on_purity_item_selected", purity_dropdown):
		_host._call_option_selection_handler(building, "_on_recipe_item_selected", recipe_dropdown)

	_restore_option_selection(core_level_dropdown, core_level_selection)
	_host._call_option_selection_handler(building, "_on_core_level_item_selected", core_level_dropdown)


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
	var path_manager: Node = _host.path_manager
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
		var rail_version := int(entry.get("rail_version", -1))
		var from_pos = path_manager._get_port_center(from_b, from_port)
		var to_pos = path_manager._get_port_center(to_b, to_port)
		if from_pos == null or to_pos == null:
			continue
		path_manager._finalize_path(from_b, from_port, from_pos, to_b, to_port, to_pos, rail_version, false, false)


func _rebuild_occupancy_from_scene(loaded_buildings: Array[Node2D]) -> void:
	var build_manager: Node = _host.build_manager
	build_manager.occupied_cells.clear()
	for building in loaded_buildings:
		var anchor_cell = build_manager._anchor_cell_from_building_position(building, building.global_position)
		var cells: Array[Vector2i] = build_manager.get_building_cells(building, anchor_cell)
		build_manager.occupy_cells(cells, building)


func _restore_camera(camera_data: Dictionary) -> void:
	if not (camera_data is Dictionary):
		return

	var camera: Camera2D = _host.camera
	var pos = camera_data.get("position", [])
	if pos is Array and pos.size() >= 2:
		camera.position = Vector2(float(pos[0]), float(pos[1]))

	var zoom_data = camera_data.get("zoom", [])
	if zoom_data is Array and zoom_data.size() >= 2:
		camera.zoom = Vector2(float(zoom_data[0]), float(zoom_data[1]))


# --- PDF export ---------------------------------------------------------------
func build_pdf_bytes() -> PackedByteArray:
	var save_state := collect_save_state()
	var lines: Array[String] = []
	var building_entries = save_state.get("buildings", [])
	var building_count := 0
	if building_entries is Array:
		building_count = building_entries.size()
	var path_entries = save_state.get("paths", [])
	var path_count := 0
	if path_entries is Array:
		path_count = path_entries.size()

	var bbm_total = _host.bbm_cost_label.text.to_int()
	var ibm_total = _host.ibm_cost_label.text.to_int()
	var meteor_core_total = _host.meteor_core_cost_label.text.to_int()

	lines.append("Star Rupture Build Planner")
	lines.append("Build Plan Export")
	lines.append("")
	lines.append("Generated: %s" % Time.get_datetime_string_from_system())
	lines.append("")
	lines.append("Heat: %s" % _host.heat_label.text)
	lines.append("Power: %s" % _host.power_label.text)
	lines.append("Buildings: %d" % building_count)
	lines.append("Paths: %d" % path_count)
	lines.append("BBM (sum): %.2f" % bbm_total)
	lines.append("IBM (sum): %.2f" % ibm_total)
	lines.append("Meteor Cores (sum): %.2f" % meteor_core_total)
	lines.append("")

	lines.append("Production Ledger:")
	lines.append_array(_build_production_ledger_lines())

	var content_lines: Array[String] = [
		"BT /F1 20 Tf 50 760 Td (%s) Tj ET" % PdfWriter.escape_text(lines[0]),
		"BT /F1 14 Tf 50 736 Td (%s) Tj ET" % PdfWriter.escape_text(lines[1]),
		"BT /F1 10 Tf 50 716 Td (%s) Tj ET" % PdfWriter.escape_text(lines[2])
	]

	var grid_origin := Vector2(50, 430)
	var grid_size := Vector2(480, 250)
	content_lines.append("0.5 w 0 0 0 RG %f %f %f %f re S" % [grid_origin.x, grid_origin.y, grid_size.x, grid_size.y])
	content_lines.append_array(_build_pdf_grid_commands(building_entries, grid_origin, grid_size))

	var y := 390
	for i in range(4, lines.size()):
		content_lines.append("BT /F1 11 Tf 50 %d Td (%s) Tj ET" % [y, PdfWriter.escape_text(lines[i])])
		y -= 15
		if y < 40:
			break
	var content := "\n".join(content_lines)

	var objects: Array[String] = []
	objects.append("1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj")
	objects.append("2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj")
	objects.append("3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj")
	objects.append("4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj")
	objects.append("5 0 obj << /Length %d >> stream\n%s\nendstream endobj" % [content.to_utf8_buffer().size(), content])

	return PdfWriter.assemble(objects)


func _build_pdf_grid_commands(building_entries: Variant, grid_origin: Vector2, grid_size: Vector2) -> Array[String]:
	var commands: Array[String] = []

	if not (building_entries is Array) or building_entries.is_empty():
		var grid_step_empty := 20.0
		var columns_empty := int(grid_size.x / grid_step_empty)
		var rows_empty := int(grid_size.y / grid_step_empty)
		for x in range(columns_empty + 1):
			var px_empty := grid_origin.x + (x * grid_step_empty)
			commands.append("0.85 G 0.2 w %f %f m %f %f l S" % [px_empty, grid_origin.y, px_empty, grid_origin.y + grid_size.y])
		for y in range(rows_empty + 1):
			var py_empty := grid_origin.y + (y * grid_step_empty)
			commands.append("0.85 G 0.2 w %f %f m %f %f l S" % [grid_origin.x, py_empty, grid_origin.x + grid_size.x, py_empty])
		commands.append("0 g BT /F1 12 Tf %f %f Td (No buildings placed) Tj ET" % [grid_origin.x + 180.0, grid_origin.y + (grid_size.y / 2.0)])
		return commands

	var min_cell_x := INF
	var min_cell_y := INF
	var max_cell_x := -INF
	var max_cell_y := -INF
	var building_rects: Array[Dictionary] = []
	var building_labels: Array[String] = []

	for entry in building_entries:
		if not (entry is Dictionary):
			continue
		var anchor = entry.get("anchor_cell", entry.get("anchor", [0, 0]))
		var footprint = entry.get("footprint", [1, 1])
		if not (anchor is Array) or anchor.size() < 2:
			continue
		var ax := int(anchor[0])
		var ay := int(anchor[1])
		var fw := 1
		var fh := 1
		if footprint is Array and footprint.size() >= 2:
			fw = max(1, int(footprint[0]))
			fh = max(1, int(footprint[1]))
		min_cell_x = min(min_cell_x, float(ax))
		min_cell_y = min(min_cell_y, float(ay))
		max_cell_x = max(max_cell_x, float(ax + fw))
		max_cell_y = max(max_cell_y, float(ay + fh))
		building_rects.append({
			"ax": ax,
			"ay": ay,
			"fw": fw,
			"fh": fh
		})
		building_labels.append(String(entry.get("id", "Bldg")))

	if not is_finite(min_cell_x) or not is_finite(min_cell_y) or not is_finite(max_cell_x) or not is_finite(max_cell_y):
		return commands

	var cols = max(1.0, max_cell_x - min_cell_x)
	var rows = max(1.0, max_cell_y - min_cell_y)
	var cell_size = min((grid_size.x - 20.0) / cols, (grid_size.y - 20.0) / rows)
	var drawn_width = cols * cell_size
	var drawn_height = rows * cell_size
	var x_offset = grid_origin.x + ((grid_size.x - drawn_width) * 0.5)
	var y_offset = grid_origin.y + ((grid_size.y - drawn_height) * 0.5)

	for x in range(int(cols) + 1):
		var px = x_offset + (x * cell_size)
		commands.append("0.85 G 0.2 w %f %f m %f %f l S" % [px, y_offset, px, y_offset + drawn_height])
	for y in range(int(rows) + 1):
		var py = y_offset + (y * cell_size)
		commands.append("0.85 G 0.2 w %f %f m %f %f l S" % [x_offset, py, x_offset + drawn_width, py])

	for i in range(building_rects.size()):
		var rect_data := building_rects[i]
		var ax := int(rect_data.get("ax", 0))
		var ay := int(rect_data.get("ay", 0))
		var fw := int(rect_data.get("fw", 1))
		var fh := int(rect_data.get("fh", 1))
		var id_text := building_labels[i]
		var gx = x_offset + ((float(ax) - min_cell_x) * cell_size)
		var gw = float(fw) * cell_size
		var gh = float(fh) * cell_size
		var gy = y_offset + drawn_height - (((float(ay) - min_cell_y) * cell_size) + gh)
		commands.append("0 G 1.1 w %f %f %f %f re S" % [gx, gy, gw, gh])
		commands.append("0 g BT /F1 7 Tf %f %f Td (%s) Tj ET" % [gx + 2.0, gy + gh - 8.0, PdfWriter.escape_text(id_text)])

	return commands


func _build_production_ledger_lines() -> Array[String]:
	var output: Array[String] = []
	if not _host.get_tree().root.has_node("ProdLedger"):
		output.append("- Production ledger unavailable")
		return output

	var ledger = _host.get_node("/root/ProdLedger")
	var display_keys: Dictionary = {}
	for key in ledger.net_totals.keys():
		display_keys[key] = true
	for key in ledger.gross_totals.keys():
		display_keys[key] = true
	for key in ledger.gross_negative_totals.keys():
		display_keys[key] = true

	var sorted_keys: Array[String] = []
	for key in display_keys.keys():
		sorted_keys.append(String(key))
	sorted_keys.sort()

	if sorted_keys.is_empty():
		output.append("- No production entries")
		return output

	for key in sorted_keys:
		var key_name := StringName(key)
		var net := float(ledger.net_totals.get(key_name, 0.0))
		var gross_in := float(ledger.gross_totals.get(key_name, 0.0))
		var gross_out := float(ledger.gross_negative_totals.get(key_name, 0.0))
		output.append("- %s | Net: %.2f | +: %.2f | -: %.2f" % [
			_format_resource_name(key),
			net,
			gross_in,
			gross_out
		])

	return output


func _format_resource_name(value: String) -> String:
	return value.strip_edges().replace("_", " ").replace("-", " ")
