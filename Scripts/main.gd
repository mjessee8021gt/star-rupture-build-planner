extends Node2D

const PlannerPalette = preload("res://Scripts/palette.gd")

const SAVE_FILE_EXTENSION := "srbp"
const SAVE_FORMAT_VERSION := 2
const RAIL_VERSION_OPTIONS := ["V1 Rails", "V2 Rails", "V3 Rails"]
const RAIL_VERSION_DROPDOWN_SIZE := Vector2(128, 36)
const RAIL_VERSION_DROPDOWN_MARGIN := 12.0
const TOOLBAR_BUTTON_WIDTH_EXTRA := 10.0
const NEW_BUTTON_LEFT_SHIFT := 40.0
const SAVE_BUTTON_LEFT_SHIFT := 30.0
const LOAD_BUTTON_LEFT_SHIFT := 20.0

@onready var camera: Camera2D = $Camera2D
@onready var tile_map_layer: TileMapLayer = $TileMapLayer
@onready var heat_label: Label = $Camera2D/CanvasLayer/Panel/HeatLabel
@onready var power_label: Label = $Camera2D/CanvasLayer/Panel/PowerLabel
@onready var bbm_cost_label: Label = $Camera2D/CanvasLayer/Panel/BBMCostLabel
@onready var ibm_cost_label: Label = $Camera2D/CanvasLayer/Panel/IBMCostLabel
@onready var meteor_core_cost_label: Label = $Camera2D/CanvasLayer/Panel/MeteorCoreCostLabel
@onready var controls_popup: PopupPanel = $Camera2D/CanvasLayer/PopupPanel
@onready var prod_panel: PanelContainer = $Camera2D/CanvasLayer/ProdMenu/ProdPanel
@onready var build_manager: Node = $BuildManager
@onready var path_manager: Node = $PathManager
@onready var buildings_root: Node2D = $buildings

var save_button: Button
var new_button: Button
var load_button: Button
var export_pdf_button: Button
var rail_version_dropdown: OptionButton
var save_dialog: FileDialog
var load_dialog: FileDialog
var export_pdf_dialog: FileDialog
var _last_viewport_size: Vector2i = Vector2i.ZERO

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	heat_label.text = "0"
	power_label.text = "0"
	bbm_cost_label.text = "0"
	ibm_cost_label.text = "0"
	meteor_core_cost_label.text = "0"
	_setup_save_load_ui()
	_apply_visual_theme()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_last_viewport_size = get_viewport().size
	Adjust_ui_for_resolution()
	call_deferred("_refresh_grid_visibility")
	recenter_camera()
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	_poll_viewport_resize()
	if is_scene_input_blocked():
		return
	if Input.is_action_just_released("Zoom Out") and not _is_controls_menu_open():
		$Camera2D.zoomOut()
	elif Input.is_action_just_released("Zoom In") and not _is_controls_menu_open():
		$Camera2D.ZoomIn()
	elif (Input.is_action_just_released("Show Debug Feed")):
		if $"Camera2D/CanvasLayer/Debug Panel".visible == false:
			$"Camera2D/CanvasLayer/Debug Panel".visible = true
		else:
			$"Camera2D/CanvasLayer/Debug Panel".visible = false
	elif (Input.is_action_just_released("Recenter Camera")):
		recenter_camera()

func _is_controls_menu_open() -> bool:
	return controls_popup != null and controls_popup.visible


func is_scene_input_blocked() -> bool:
	return _is_file_dialog_open() or _is_controls_menu_open()


func _is_file_dialog_open() -> bool:
	for dialog in [save_dialog, load_dialog, export_pdf_dialog]:
		if dialog != null and dialog.visible:
			return true
	return false

func _on_prod_menu_pressed() -> void:
	$Camera2D/CanvasLayer/ProdMenu/ProdPanel.visible = not $Camera2D/CanvasLayer/ProdMenu/ProdPanel.visible

func _setup_save_load_ui() -> void:
	save_button = Button.new()
	save_button.name = "SaveButton"
	save_button.text = "Save"
	save_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_button.pressed.connect(_on_save_pressed)
	$Camera2D/CanvasLayer.add_child(save_button)

	new_button = Button.new()
	new_button.name = "NewButton"
	new_button.text = "New"
	new_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_button.pressed.connect(_on_new_pressed)
	$Camera2D/CanvasLayer.add_child(new_button)

	load_button = Button.new()
	load_button.name = "LoadButton"
	load_button.text = "Load"
	load_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	load_button.pressed.connect(_on_load_pressed)
	$Camera2D/CanvasLayer.add_child(load_button)

	export_pdf_button = Button.new()
	export_pdf_button.name = "ExportPdfButton"
	export_pdf_button.text = "Export PDF"
	export_pdf_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	export_pdf_button.pressed.connect(_on_export_pdf_pressed)
	$Camera2D/CanvasLayer.add_child(export_pdf_button)

	rail_version_dropdown = OptionButton.new()
	rail_version_dropdown.name = "RailVersionDropdown"
	rail_version_dropdown.custom_minimum_size = RAIL_VERSION_DROPDOWN_SIZE
	rail_version_dropdown.alignment = HORIZONTAL_ALIGNMENT_CENTER
	for option_name in RAIL_VERSION_OPTIONS:
		rail_version_dropdown.add_item(option_name)
	rail_version_dropdown.select(0)
	$Camera2D/CanvasLayer.add_child(rail_version_dropdown)
	_sync_rail_version_selector()

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
	
	export_pdf_dialog = FileDialog.new()
	export_pdf_dialog.name = "ExportPdfDialog"
	export_pdf_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_pdf_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_pdf_dialog.title = "Export Build Plan PDF"
	export_pdf_dialog.filters = PackedStringArray(["*.pdf ; PDF Document"])
	export_pdf_dialog.file_selected.connect(_on_export_pdf_file_selected)
	add_child(export_pdf_dialog)


func _apply_visual_theme() -> void:
	_style_panel($Camera2D/CanvasLayer/Panel)
	_style_panel($Camera2D/CanvasLayer/"Debug Panel")
	_style_panel($Camera2D/CanvasLayer/ProdMenu)

	if prod_panel != null:
		prod_panel.self_modulate = Color.WHITE
		_style_panel(prod_panel)

	for button in [save_button, new_button, load_button, export_pdf_button, rail_version_dropdown]:
		if button != null:
			_style_button(button)
	_configure_toolbar_button_widths()

	for label in [
		heat_label,
		power_label,
		bbm_cost_label,
		ibm_cost_label,
		meteor_core_cost_label,
		$Camera2D/CanvasLayer/Panel/BBMTextLabel,
		$Camera2D/CanvasLayer/Panel/IBMTextLabel,
		$Camera2D/CanvasLayer/Panel/MeteorCoreTextLabel,
		$Camera2D/CanvasLayer/"Debug Panel"/DebugFeed,
	]:
		if label != null:
			label.add_theme_color_override("font_color", PlannerPalette.TEXT_PRIMARY)


func _style_panel(panel: Control) -> void:
	panel.add_theme_stylebox_override("panel", PlannerPalette.make_panel_style(PlannerPalette.SCENE_PANEL_FILL, PlannerPalette.SCENE_PANEL_BORDER))


func _style_button(button: BaseButton) -> void:
	button.add_theme_color_override("font_color", PlannerPalette.TEXT_PRIMARY)
	button.add_theme_color_override("font_disabled_color", PlannerPalette.TEXT_MUTED)
	button.add_theme_stylebox_override("normal", PlannerPalette.make_button_style(PlannerPalette.BUTTON_FILL))
	button.add_theme_stylebox_override("hover", PlannerPalette.make_button_style(PlannerPalette.BUTTON_HOVER))
	button.add_theme_stylebox_override("pressed", PlannerPalette.make_button_style(PlannerPalette.BUTTON_PRESSED))
	button.add_theme_stylebox_override("focus", PlannerPalette.make_button_style(PlannerPalette.BUTTON_HOVER))
	button.add_theme_stylebox_override("disabled", PlannerPalette.make_button_style(PlannerPalette.BUTTON_PRESSED))


func _configure_toolbar_button_widths() -> void:
	for button in [new_button, save_button, load_button, export_pdf_button]:
		if button == null:
			continue
		button.custom_minimum_size.x = 0.0
		button.custom_minimum_size.x = button.get_combined_minimum_size().x + TOOLBAR_BUTTON_WIDTH_EXTRA
	
func Adjust_ui_for_resolution() -> void:
	$Camera2D/CanvasLayer/MenuButton.position = Vector2 (15, 15)
	$Camera2D/CanvasLayer/Panel.position = Vector2 (get_viewport().size.x - 190, 5)
	$Camera2D/CanvasLayer/ProdMenu.position = Vector2 (get_viewport().size.x - 75, 100)
	$Camera2D/CanvasLayer/ControlMenu.position = Vector2(15, get_viewport().size.y -50)
	$"Camera2D/CanvasLayer/Patch Notes".position = Vector2(15, get_viewport().size.y -90)

	if rail_version_dropdown != null:
		var menu_button := $Camera2D/CanvasLayer/MenuButton
		var menu_button_width = menu_button.size.x * menu_button.scale.x
		rail_version_dropdown.position = Vector2(
			menu_button.position.x + menu_button_width + RAIL_VERSION_DROPDOWN_MARGIN,
			menu_button.position.y
		)
	
	if new_button != null:
		new_button.position = Vector2(get_viewport().size.x - 490 - NEW_BUTTON_LEFT_SHIFT, 8)
	if save_button != null:
		save_button.position = Vector2(get_viewport().size.x - 430 - SAVE_BUTTON_LEFT_SHIFT, 8)
	if load_button != null:
		load_button.position = Vector2(get_viewport().size.x - 370 - LOAD_BUTTON_LEFT_SHIFT, 8)
	if export_pdf_button != null:
		export_pdf_button.position = Vector2(get_viewport().size.x - 310, 8)

func _sync_rail_version_selector() -> void:
	if rail_version_dropdown == null or path_manager == null:
		return
	if path_manager.has_method("set_rail_version_selector"):
		path_manager.set_rail_version_selector(rail_version_dropdown)
	
func _on_viewport_size_changed() -> void:
	_last_viewport_size = get_viewport().size
	Adjust_ui_for_resolution()
	call_deferred("_refresh_grid_visibility")
	
func _poll_viewport_resize() -> void:
	var viewport_size: Vector2i = get_viewport().size
	if viewport_size == _last_viewport_size:
		return
	_on_viewport_size_changed()

func _refresh_grid_visibility() -> void:
	if tile_map_layer == null or not is_instance_valid(tile_map_layer):
		return
	tile_map_layer.hide()
	tile_map_layer.show()
	tile_map_layer.notify_runtime_tile_data_update()
	tile_map_layer.queue_redraw()

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
	
func _on_export_pdf_pressed() -> void:
	if OS.has_feature("web") and JavaScriptBridge != null:
		_download_pdf_to_browser()
		return

	export_pdf_dialog.current_file = "build_plan.pdf"
	export_pdf_dialog.popup_centered_ratio(0.7)

func _on_new_pressed() -> void:
	_clear_scene_plan()

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

func _clear_scene_plan() -> void:
	if build_manager != null and build_manager.has_method("cancel_build"):
		build_manager.cancel_build()

	if path_manager != null and path_manager.has_method("cancel_active_path_drag"):
		path_manager.cancel_active_path_drag()
		
	if path_manager != null:
		for child in path_manager.get_children():
			if child is Path2D:
				child.queue_free()

	for child in buildings_root.get_children():
		child.queue_free()
		
	if build_manager != null and "occupied_cells" in build_manager:
		build_manager.occupied_cells.clear()

	heat_label.text = "0"
	power_label.text = "0"
	bbm_cost_label.text = "0"
	ibm_cost_label.text = "0"
	meteor_core_cost_label.text = "0"
	
	var ledger := get_tree().root.get_node_or_null("ProdLedger")
	if ledger == null:
		ledger = get_tree().root.get_node_or_null("ProductionLedger")
	if ledger != null:
		ledger.net_totals.clear()
		ledger.gross_totals.clear()
		ledger.gross_negative_totals.clear()
		ledger.by_source.clear()
		ledger.totals_changed.emit(ledger.net_totals, ledger.gross_totals, ledger.gross_negative_totals)

func _download_save_to_browser() -> void:
	var save_state := _collect_save_state()
	var json_text := JSON.stringify(save_state, "\t")
	var bytes := json_text.to_utf8_buffer()
	JavaScriptBridge.download_buffer(bytes, "build_plan.%s" % SAVE_FILE_EXTENSION, "application/json")
	
func _download_pdf_to_browser() -> void:
	var pdf_bytes := _build_pdf_bytes()
	JavaScriptBridge.download_buffer(pdf_bytes, "build_plan.pdf", "application/pdf")

func _write_save_file(path: String) -> bool:
	var save_state := _collect_save_state()
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
	file.store_buffer(_build_pdf_bytes())
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
	
func _build_pdf_bytes() -> PackedByteArray:
	var save_state := _collect_save_state()
	var lines: Array[String] = []
	var building_entries = save_state.get("buildings", [])
	var building_count := 0
	if building_entries is Array:
		building_count = building_entries.size()
	var path_entries = save_state.get("paths", [])
	var path_count := 0
	if path_entries is Array:
		path_count = path_entries.size()

	var bbm_total = $Camera2D/CanvasLayer/Panel/BBMCostLabel.text.to_int()
	var ibm_total = $Camera2D/CanvasLayer/Panel/IBMCostLabel.text.to_int()
	var meteor_core_total = $Camera2D/CanvasLayer/Panel/IBMCostLabel.text.to_int()
	
	lines.append("Star Rupture Build Planner")
	lines.append("Build Plan Export")
	lines.append("")
	lines.append("Generated: %s" % Time.get_datetime_string_from_system())
	lines.append("")
	lines.append("Heat: %s" % heat_label.text)
	lines.append("Power: %s" % power_label.text)
	lines.append("Buildings: %d" % building_count)
	lines.append("Paths: %d" % path_count)
	lines.append("BBM (sum): %.2f" % bbm_total)
	lines.append("IBM (sum): %.2f" % ibm_total)
	lines.append("Meteor Cores (sum): %.2f" % meteor_core_total)
	lines.append("")

	lines.append("Production Ledger:")
	lines.append_array(_build_production_ledger_lines())

	var content_lines: Array[String] = [
		"BT /F1 20 Tf 50 760 Td (%s) Tj ET" % _pdf_escape_text(lines[0]),
		"BT /F1 14 Tf 50 736 Td (%s) Tj ET" % _pdf_escape_text(lines[1]),
		"BT /F1 10 Tf 50 716 Td (%s) Tj ET" % _pdf_escape_text(lines[2])
	]

	var grid_origin := Vector2(50, 430)
	var grid_size := Vector2(480, 250)
	content_lines.append("0.5 w 0 0 0 RG %f %f %f %f re S" % [grid_origin.x, grid_origin.y, grid_size.x, grid_size.y])
	content_lines.append_array(_build_pdf_grid_commands(building_entries, grid_origin, grid_size))

	var y := 390
	for i in range(4, lines.size()):
		content_lines.append("BT /F1 11 Tf 50 %d Td (%s) Tj ET" % [y, _pdf_escape_text(lines[i])])
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

	var pdf := "%PDF-1.4\n"
	var offsets: Array[int] = [0]
	for object in objects:
		offsets.append(pdf.to_utf8_buffer().size())
		pdf += object + "\n"

	var xref_offset := pdf.to_utf8_buffer().size()
	pdf += "xref\n0 %d\n" % offsets.size()
	pdf += "0000000000 65535 f \n"
	for i in range(1, offsets.size()):
		pdf += "%010d 00000 n \n" % offsets[i]

	pdf += "trailer << /Size %d /Root 1 0 R >>\n" % offsets.size()
	pdf += "startxref\n%d\n%%%%EOF" % xref_offset
	return pdf.to_utf8_buffer()

func _pdf_escape_text(value: String) -> String:
	return value.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
	
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
		commands.append("0 g BT /F1 7 Tf %f %f Td (%s) Tj ET" % [gx + 2.0, gy + gh - 8.0, _pdf_escape_text(id_text)])

	return commands

func _get_production_sum(resource_keys: Array[StringName]) -> float:
	if not get_tree().root.has_node("ProdLedger"):
		return 0.0
	var ledger = get_node("/root/ProdLedger")
	var normalized_aliases: Array[String] = []
	for alias in resource_keys:
		normalized_aliases.append(_normalize_resource_key(String(alias)))
	var total := 0.0
	for raw_key in ledger.net_totals.keys():
		var key_text := _normalize_resource_key(String(raw_key))
		for alias in normalized_aliases:
			if key_text == alias or key_text.contains(alias) or alias.contains(key_text):
				total += float(ledger.net_totals.get(raw_key, 0.0))
				break
	return total
	
func _build_production_ledger_lines() -> Array[String]:
	var output: Array[String] = []
	if not get_tree().root.has_node("ProdLedger"):
		output.append("- Production ledger unavailable")
		return output

	var ledger = get_node("/root/ProdLedger")
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

func _normalize_resource_key(value: String) -> String:
	return value.strip_edges().to_lower().replace("-", "_").replace(" ", "_")

func _format_resource_name(value: String) -> String:
	return value.strip_edges().replace("_", " ").replace("-", " ")


func _serialize_building(building: Node2D) -> Dictionary:
	var recipe_selection := _serialize_option_button(building.get_node_or_null("Recipe"))
	var purity_selection := _serialize_option_button(building.get_node_or_null("Purity"))
	var saved_anchor_cell := Vector2i.ZERO
	if build_manager != null and build_manager.has_method("_anchor_cell_from_building_position"):
		saved_anchor_cell = build_manager._anchor_cell_from_building_position(building, building.global_position)
	elif build_manager != null and build_manager.has_method("world_to_cell"):
		saved_anchor_cell = build_manager.world_to_cell(building.global_position)

	var saved_footprint := Vector2i.ONE
	if build_manager != null and build_manager.has_method("get_rotated_footprint"):
		saved_footprint = build_manager.get_rotated_footprint(building)
	elif "footprint" in building and building.get("footprint") is Vector2i:
		saved_footprint = building.get("footprint")

	return {
		"id": str(building.get("id")) if building.has_method("get") else "",
		"scene_path": building.scene_file_path,
		"position": [building.global_position.x, building.global_position.y],
		"rotation_degrees": building.rotation_degrees,
		"rotated_tick": int(building.get("rotatedTick")) if "rotatedTick" in building else 0,
		"is_alternate": bool(building.get("is_alternate")) if "is_alternate" in building else false,
		"anchor_cell": [int(saved_anchor_cell.x), int(saved_anchor_cell.y)],
		"footprint": [max(1, int(saved_footprint.x)), max(1, int(saved_footprint.y))],
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

		var rail_version := -1
		if path_manager != null and path_manager.has_method("get_path_rail_version"):
			rail_version = int(path_manager.get_path_rail_version(child))
		elif child.has_meta("rail_version"):
			rail_version = int(child.get_meta("rail_version"))

		out.append({
			"from_index": int(building_index[from_building]),
			"to_index": int(building_index[to_building]),
			"from_port": str(child.get_meta("from_port")),
			"to_port": str(child.get_meta("to_port")),
			"rail_version": rail_version
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

	_rebuild_occupancy_from_scene(loaded_buildings)
	_restore_paths(save_state.get("paths", []), loaded_buildings)
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

	buildings_root.add_child(instance)
	_restore_loaded_building_selection_state(
		instance,
		data.get("recipe", {}),
		data.get("purity", {})
	)

	return instance

func _restore_loaded_building_selection_state(building: Node2D, recipe_selection: Dictionary, purity_selection: Dictionary) -> void:
	var recipe_dropdown := building.get_node_or_null("Recipe") as OptionButton
	var purity_dropdown := building.get_node_or_null("Purity") as OptionButton

	_restore_option_selection(recipe_dropdown, recipe_selection)

	# Some buildings rebuild their purity choices from the selected recipe,
	# so replay that step before restoring the saved purity selection.
	if purity_dropdown != null and building.has_method("_on_purity_item_selected"):
		_call_option_selection_handler(building, "_on_recipe_item_selected", recipe_dropdown)

	_restore_option_selection(purity_dropdown, purity_selection)

	if not _call_option_selection_handler(building, "_on_purity_item_selected", purity_dropdown):
		_call_option_selection_handler(building, "_on_recipe_item_selected", recipe_dropdown)

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
		var rail_version := int(entry.get("rail_version", -1))
		var from_pos = path_manager._get_port_center(from_b, from_port)
		var to_pos = path_manager._get_port_center(to_b, to_port)
		if from_pos == null or to_pos == null:
			continue
		path_manager._finalize_path(from_b, from_port, from_pos, to_b, to_port, to_pos, rail_version)

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
	
