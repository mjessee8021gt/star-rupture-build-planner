extends Node2D

const Palette = preload("res://Scripts/palette.gd")
const UiScale = preload("res://Scripts/ui_scale.gd")
const WHAT_IF_MACHINE_SCENE := preload("res://Scenes/WhatIfMachine.tscn")

const SAVE_FILE_EXTENSION := "srbp"
const SAVE_FORMAT_VERSION := 3
const BASE_UI_REFERENCE_WIDTH := 1920.0
const TOP_MENU_BAR_MARGIN := 10.0
const TOP_MENU_BAR_VIEWPORT_MARGIN := 8.0
const RAIL_VERSION_OPTIONS := ["V1 Rails", "V2 Rails", "V3 Rails"]
const RAIL_VERSION_DROPDOWN_SIZE := Vector2(128, 36)
const RAIL_VERSION_DROPDOWN_MARGIN := 12.0
const RAIL_VISIBILITY_ACTION := &"Rail Visibility"
const RAIL_VISIBILITY_MODE_HIGH := 1
const RAIL_VISIBILITY_INDICATOR_SIZE := Vector2(144, 36)
const RAIL_VISIBILITY_INDICATOR_MARGIN := 8.0
const RAIL_VISIBILITY_INDICATOR_DURATION := 4.0
const RAIL_VISIBILITY_ALPHA_CONTROL_SIZE := Vector2(220, 36)
const RAIL_VISIBILITY_ALPHA_CONTROL_TOP_MARGIN := 6.0
const RAIL_VISIBILITY_ALPHA_TEXT_WIDTH := 54.0
const RAIL_VISIBILITY_ALPHA_STEP := 0.01
const TOOLBOX_BUTTON_SIZE := Vector2(64, 64)
const TOOLBOX_LEFT_MARGIN := 15.0
const TOOLBOX_TOP_OVERLAP := 30.0
const RESOURCE_PANEL_RIGHT_MARGIN := 1.0
const LEGACY_BOTTOM_TOOL_SPACING := 40.0
const HISTORY_LIMIT := 15
const HISTORY_ACTION_BUILDING_CONSTRUCTED := "Building constructed"
const HISTORY_ACTION_BUILDING_DELETED := "Building deleted"
const HISTORY_ACTION_RAIL_CREATED := "Rail created"
const HISTORY_ACTION_RAIL_DELETED := "Rail deleted"
const HISTORY_ACTION_BUILDING_MOVED := "Building moved"
const HISTORY_ACTION_WHAT_IF_GENERATED := "What If plan generated"
const PROD_PANEL_SCREEN_WIDTH_RATIO := 0.20
const PROD_PANEL_MIN_SCREEN_WIDTH := 220.0
const PROD_PANEL_WIDTH_EXTRA := 5.0
const PROD_PANEL_TOP_GAP_FROM_MATH_PANEL := 5.0
const PROD_PANEL_BOTTOM_MARGIN := 23.0
const WHAT_IF_GENERATION_MAX_DEPTH := 48
const WHAT_IF_GENERATION_COLUMN_SPACING := 2
const WHAT_IF_GENERATION_ROW_SPACING := 3
const WHAT_IF_GENERATION_START_CELL := Vector2i(-8, -8)
const WHAT_IF_GENERATION_EXISTING_PLAN_MARGIN := 8
const WHAT_IF_RAIL_V1_CAPACITY := 120.0
const WHAT_IF_RAIL_V2_CAPACITY := 240.0
const WHAT_IF_RAIL_V3_CAPACITY := 480.0
const COMMAND_NEW := &"file.new"
const COMMAND_SAVE := &"file.save"
const COMMAND_LOAD := &"file.load"
const COMMAND_EXPORT_PDF := &"file.export_pdf"
const COMMAND_UNDO := &"edit.undo"
const COMMAND_REDO := &"edit.redo"
const COMMAND_TOGGLE_PRODUCTION := &"view.production"
const COMMAND_RAIL_VIEW := &"view.rail_visibility"
const COMMAND_RAIL_FLOW_RATE := &"view.rail_flow_rate"
const COMMAND_WHAT_IF := &"tools.what_if"
const COMMAND_TOGGLE_TOOLBOX := &"tools.toggle_toolbox"
const COMMAND_CONTROLS := &"tools.controls"
const COMMAND_PATCH_NOTES := &"help.patch_notes"

@onready var camera: Camera2D = $Camera2D
@onready var tile_map_layer: TileMapLayer = $TileMapLayer
@onready var top_menu_bar: TopMenuBar = $Camera2D/CanvasLayer/TopMenuBar
@onready var toolbox_button: Button = $Camera2D/CanvasLayer/MenuButton
@onready var heat_label: Label = $Camera2D/CanvasLayer/Panel/HeatLabel
@onready var power_label: Label = $Camera2D/CanvasLayer/Panel/PowerLabel
@onready var bbm_cost_label: Label = $Camera2D/CanvasLayer/Panel/BBMCostLabel
@onready var ibm_cost_label: Label = $Camera2D/CanvasLayer/Panel/IBMCostLabel
@onready var meteor_core_cost_label: Label = $Camera2D/CanvasLayer/Panel/MeteorCoreCostLabel
@onready var controls_popup: PopupPanel = $Camera2D/CanvasLayer/PopupPanel
@onready var patch_notes_button: Node = $"Camera2D/CanvasLayer/Patch Notes"
@onready var what_if_button: Button = $Camera2D/CanvasLayer/WhatIfButton
@onready var prod_menu: Button = $Camera2D/CanvasLayer/ProdMenu
@onready var prod_panel: PanelContainer = $Camera2D/CanvasLayer/ProdMenu/ProdPanel
@onready var build_manager: Node = $BuildManager
@onready var path_manager: Node = $PathManager
@onready var buildings_root: Node2D = $buildings

var rail_version_dropdown: OptionButton
var rail_visibility_indicator: PanelContainer
var rail_visibility_indicator_label: Label
var rail_visibility_indicator_timer: Timer
var rail_alpha_controls: PanelContainer
var rail_alpha_slider: HSlider
var rail_alpha_input: LineEdit
var save_dialog: FileDialog
var load_dialog: FileDialog
var export_pdf_dialog: FileDialog
var _last_viewport_size: Vector2i = Vector2i.ZERO
var _web_load_input = null
var _web_load_reader = null
var _web_load_input_callback = null
var _web_load_read_callback = null
var _web_load_error_callback = null
var _web_load_pending_file_name := ""
var _web_save_success_callback = null
var _web_save_error_callback = null
var _web_save_pending_file_name := ""
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _is_replaying_history := false
var _syncing_rail_alpha_controls := false
var _what_if_machine_overlay: Control
var _pending_what_if_generation_request: Dictionary = {}
var _command_metadata: Dictionary = {}
var _command_handlers: Dictionary = {}
var _ui_scale := 1.0
var _ui_scale_tier := 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_refresh_ui_scale(true)
	heat_label.text = "0"
	power_label.text = "0"
	bbm_cost_label.text = "0"
	ibm_cost_label.text = "0"
	meteor_core_cost_label.text = "0"
	_setup_save_load_ui()
	_setup_top_menu_bar()
	_setup_what_if_button()
	_apply_ui_scale()
	_apply_visual_theme()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_last_viewport_size = get_viewport().size
	Adjust_ui_for_resolution()
	_sync_rail_alpha_controls_visibility()
	call_deferred("_refresh_grid_visibility")
	recenter_camera()
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	_poll_viewport_resize()
	_sync_command_bar_state()
	if is_scene_input_blocked():
		return
	if _process_history_input():
		return
	if _process_rail_visibility_input():
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


func _is_patch_notes_open() -> bool:
	return patch_notes_button != null and patch_notes_button.has_method("is_panel_open") and patch_notes_button.call("is_panel_open")


func _is_what_if_machine_open() -> bool:
	return _what_if_machine_overlay != null and is_instance_valid(_what_if_machine_overlay) and _what_if_machine_overlay.is_inside_tree()


func is_scene_input_blocked() -> bool:
	return _is_file_dialog_open() or _is_controls_menu_open() or _is_patch_notes_open() or _is_what_if_machine_open()


func _is_file_dialog_open() -> bool:
	for dialog in [save_dialog, load_dialog, export_pdf_dialog]:
		if dialog != null and dialog.visible:
			return true
	return false

func _on_prod_menu_pressed() -> void:
	_toggle_production_panel()


func _setup_what_if_button() -> void:
	if what_if_button == null:
		return
	if not what_if_button.pressed.is_connected(_on_what_if_button_pressed):
		what_if_button.pressed.connect(_on_what_if_button_pressed)


func _on_what_if_button_pressed() -> void:
	if _is_what_if_machine_open():
		_what_if_machine_overlay.call_deferred("grab_focus")
		return

	var overlay := WHAT_IF_MACHINE_SCENE.instantiate() as Control
	if overlay == null:
		push_warning("WhatIfButton: WhatIfMachine root must be a Control.")
		return

	_configure_what_if_overlay(overlay)
	$Camera2D/CanvasLayer.add_child(overlay)
	_what_if_machine_overlay = overlay
	if overlay.has_signal("close_requested"):
		overlay.connect("close_requested", Callable(self, "_close_what_if_machine_overlay"))
	if overlay.has_signal("generate_requested"):
		overlay.connect("generate_requested", Callable(self, "_on_what_if_generate_requested"))
	overlay.tree_exited.connect(_on_what_if_machine_overlay_exited)
	if overlay.has_method("refresh_overlay_layout"):
		overlay.call_deferred("refresh_overlay_layout")
	overlay.call_deferred("grab_focus")


func _configure_what_if_overlay(overlay: Control) -> void:
	overlay.name = "WhatIfMachineOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 0.0
	overlay.offset_top = 0.0
	overlay.offset_right = 0.0
	overlay.offset_bottom = 0.0
	overlay.z_index = 4096
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.focus_mode = Control.FOCUS_ALL
	if overlay.has_method("set_ui_scale"):
		overlay.call("set_ui_scale", _ui_scale)


func _close_what_if_machine_overlay() -> void:
	if not _is_what_if_machine_open():
		_what_if_machine_overlay = null
		return
	_what_if_machine_overlay.queue_free()


func _on_what_if_machine_overlay_exited() -> void:
	_what_if_machine_overlay = null


func _on_what_if_generate_requested(request: Dictionary) -> void:
	_pending_what_if_generation_request = request.duplicate()
	_close_what_if_machine_overlay()
	call_deferred("_generate_pending_what_if_plan")


func _setup_save_load_ui() -> void:
	rail_version_dropdown = OptionButton.new()
	rail_version_dropdown.name = "RailVersionDropdown"
	rail_version_dropdown.custom_minimum_size = _scaled_vec2(RAIL_VERSION_DROPDOWN_SIZE)
	rail_version_dropdown.alignment = HORIZONTAL_ALIGNMENT_CENTER
	for option_name in RAIL_VERSION_OPTIONS:
		rail_version_dropdown.add_item(option_name)
	rail_version_dropdown.select(0)
	$Camera2D/CanvasLayer.add_child(rail_version_dropdown)
	_sync_rail_version_selector()
	_setup_rail_visibility_indicator()

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


func _setup_top_menu_bar() -> void:
	_promote_prod_panel_to_canvas_layer()
	_hide_legacy_action_access_buttons()
	_register_top_menu_commands()

	if top_menu_bar == null:
		push_error("Main: TopMenuBar node is missing.")
		return

	top_menu_bar.command_requested.connect(_on_top_menu_command_requested)
	top_menu_bar.configure_sections(_build_top_menu_sections())
	_sync_command_bar_state()


func _register_top_menu_commands() -> void:
	_command_metadata.clear()
	_command_handlers.clear()
	_register_top_menu_command(COMMAND_NEW, "New", Callable(self, "_on_new_pressed"), "Start a new build plan")
	_register_top_menu_command(COMMAND_SAVE, "Save", Callable(self, "_on_save_pressed"), "Save the current build plan")
	_register_top_menu_command(COMMAND_LOAD, "Load", Callable(self, "_on_load_pressed"), "Load a saved build plan")
	_register_top_menu_command(COMMAND_EXPORT_PDF, "Export PDF", Callable(self, "_on_export_pdf_pressed"), "Export the current build plan as a PDF")
	_register_top_menu_command(COMMAND_UNDO, "Undo", Callable(self, "_undo_history"), "Undo the last build-plan action")
	_register_top_menu_command(COMMAND_REDO, "Redo", Callable(self, "_redo_history"), "Redo the last undone action")
	_register_top_menu_command(COMMAND_TOGGLE_PRODUCTION, "Production", Callable(self, "_toggle_production_panel"), "Show or hide the production panel", true)
	_register_top_menu_command(COMMAND_RAIL_VIEW, "Rail View", Callable(self, "_cycle_rail_visibility"), "Cycle rail visibility mode")
	_register_top_menu_command(COMMAND_RAIL_FLOW_RATE, "Rail Flow Rate", Callable(self, "_toggle_rail_flow_rate"), "Show or hide rail flow rate badges", true)
	_register_top_menu_command(COMMAND_WHAT_IF, "What If", Callable(self, "_on_what_if_button_pressed"), "Open the what-if scenario analyzer")
	_register_top_menu_command(COMMAND_TOGGLE_TOOLBOX, "Toggle Toolbox", Callable(self, "_toggle_toolbox_persistence"), "Keep the toolbox open after choosing a building", true)
	_register_top_menu_command(COMMAND_CONTROLS, "Controls", Callable(self, "_toggle_controls_menu"), "Open the controls layout", true)
	_register_top_menu_command(COMMAND_PATCH_NOTES, "Patch Notes", Callable(self, "_toggle_patch_notes"), "Open the patch notes", true)


func _register_top_menu_command(command_id: StringName, label: String, handler: Callable, tooltip := "", toggle := false) -> void:
	_command_handlers[command_id] = handler
	_command_metadata[command_id] = {
		"id": command_id,
		"label": label,
		"tooltip": tooltip,
		"toggle": toggle,
		"enabled": true,
	}


func _build_top_menu_sections() -> Array:
	return [
		{"title": "File", "commands": [
			_command_item(COMMAND_NEW),
			_command_item(COMMAND_SAVE),
			_command_item(COMMAND_LOAD),
			_command_item(COMMAND_EXPORT_PDF),
		]},
		{"title": "Edit", "commands": [
			_command_item(COMMAND_UNDO),
			_command_item(COMMAND_REDO),
			_command_item(COMMAND_CONTROLS),
		]},
		{"title": "View", "commands": [
			_command_item(COMMAND_TOGGLE_PRODUCTION),
			_command_item(COMMAND_RAIL_VIEW),
			_command_item(COMMAND_RAIL_FLOW_RATE),
		]},
		{"title": "Tools", "commands": [
			_command_item(COMMAND_TOGGLE_TOOLBOX),
			_command_item(COMMAND_WHAT_IF),
		]},
		{"title": "Help", "commands": [
			_command_item(COMMAND_PATCH_NOTES),
		]},
	]


func _command_item(command_id: StringName) -> Dictionary:
	var item: Dictionary = _command_metadata.get(command_id, {})
	return item.duplicate()


func _on_top_menu_command_requested(command_id: StringName) -> void:
	if not _is_top_menu_command_enabled(command_id):
		_sync_command_bar_state()
		return

	var handler: Callable = _command_handlers.get(command_id, Callable())
	if handler.is_valid():
		handler.call()
	_sync_command_bar_state()


func _is_top_menu_command_enabled(command_id: StringName) -> bool:
	match command_id:
		COMMAND_UNDO:
			return not _undo_stack.is_empty()
		COMMAND_REDO:
			return not _redo_stack.is_empty()
		COMMAND_TOGGLE_PRODUCTION:
			return prod_panel != null
		COMMAND_RAIL_VIEW:
			return path_manager != null and path_manager.has_method("cycle_rail_visibility_mode")
		COMMAND_RAIL_FLOW_RATE:
			return path_manager != null and path_manager.has_method("toggle_rail_flow_rate_visible")
		COMMAND_WHAT_IF:
			return WHAT_IF_MACHINE_SCENE != null
		COMMAND_TOGGLE_TOOLBOX:
			return toolbox_button != null and toolbox_button.has_method("toggle_keep_open_after_selection")
		COMMAND_CONTROLS:
			return controls_popup != null
		COMMAND_PATCH_NOTES:
			return patch_notes_button != null
	return true


func _sync_command_bar_state() -> void:
	if top_menu_bar == null:
		return

	for command_id in _command_metadata.keys():
		top_menu_bar.set_command_enabled(command_id, _is_top_menu_command_enabled(command_id))
	top_menu_bar.set_command_pressed(COMMAND_TOGGLE_PRODUCTION, prod_panel != null and prod_panel.visible)
	top_menu_bar.set_command_pressed(COMMAND_RAIL_FLOW_RATE, _is_rail_flow_rate_visible())
	top_menu_bar.set_command_pressed(COMMAND_WHAT_IF, _is_what_if_machine_open())
	top_menu_bar.set_command_pressed(COMMAND_TOGGLE_TOOLBOX, _is_toolbox_persistence_enabled())
	top_menu_bar.set_command_pressed(COMMAND_CONTROLS, _is_controls_menu_open())
	top_menu_bar.set_command_pressed(COMMAND_PATCH_NOTES, _is_patch_notes_open())


func _promote_prod_panel_to_canvas_layer() -> void:
	if prod_panel == null:
		return

	var canvas_layer := $Camera2D/CanvasLayer
	if prod_panel.get_parent() == canvas_layer:
		return

	var was_visible := prod_panel.visible
	var current_parent := prod_panel.get_parent()
	if current_parent != null:
		current_parent.remove_child(prod_panel)
	canvas_layer.add_child(prod_panel)
	prod_panel.visible = was_visible


func _hide_legacy_action_access_buttons() -> void:
	for access_node in [prod_menu, $Camera2D/CanvasLayer/ControlMenu, patch_notes_button, what_if_button]:
		if access_node is Control:
			(access_node as Control).visible = false
			(access_node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _toggle_production_panel() -> void:
	if prod_panel == null:
		return
	_layout_prod_panel()
	prod_panel.visible = not prod_panel.visible


func _toggle_controls_menu() -> void:
	var controls_menu := $Camera2D/CanvasLayer/ControlMenu
	var anchor_rect := _get_top_menu_command_rect(COMMAND_CONTROLS)
	if controls_menu != null and controls_menu.has_method("toggle_panel_at"):
		controls_menu.call("toggle_panel_at", anchor_rect)
		return
	if controls_menu != null and controls_menu.has_method("toggle_panel"):
		controls_menu.call("toggle_panel")


func _toggle_patch_notes() -> void:
	if patch_notes_button != null and patch_notes_button.has_method("toggle_panel"):
		patch_notes_button.call("toggle_panel")


func _toggle_toolbox_persistence() -> void:
	if toolbox_button != null and toolbox_button.has_method("toggle_keep_open_after_selection"):
		toolbox_button.call("toggle_keep_open_after_selection")


func _is_toolbox_persistence_enabled() -> bool:
	if toolbox_button != null and toolbox_button.has_method("get_keep_open_after_selection"):
		return bool(toolbox_button.call("get_keep_open_after_selection"))
	return false


func preserve_toolbox_popup_for_build_confirm() -> void:
	if toolbox_button != null and toolbox_button.has_method("preserve_for_build_confirm_click"):
		toolbox_button.call("preserve_for_build_confirm_click")


func _toggle_rail_flow_rate() -> void:
	if path_manager != null and path_manager.has_method("toggle_rail_flow_rate_visible"):
		path_manager.call("toggle_rail_flow_rate_visible")


func _is_rail_flow_rate_visible() -> bool:
	if path_manager != null and path_manager.has_method("is_rail_flow_rate_visible"):
		return bool(path_manager.call("is_rail_flow_rate_visible"))
	return true


func _get_top_menu_command_rect(command_id: StringName) -> Rect2:
	if top_menu_bar != null and top_menu_bar.has_method("get_command_global_rect"):
		var rect = top_menu_bar.call("get_command_global_rect", command_id)
		if rect is Rect2:
			return rect
	return Rect2()


func get_ui_scale() -> float:
	return _ui_scale


func get_ui_scale_tier() -> int:
	return _ui_scale_tier


func _refresh_ui_scale(force := false) -> bool:
	var viewport_size = get_viewport().size
	var next_scale := UiScale.scale_for_viewport(viewport_size)
	var next_tier := UiScale.tier_for_viewport(viewport_size)
	var changed := force or not is_equal_approx(_ui_scale, next_scale) or _ui_scale_tier != next_tier
	_ui_scale = next_scale
	_ui_scale_tier = next_tier
	return changed


func _apply_ui_scale() -> void:
	if top_menu_bar != null and top_menu_bar.has_method("set_ui_scale"):
		top_menu_bar.call("set_ui_scale", _ui_scale)

	_apply_button_visual_scale(toolbox_button, TOOLBOX_BUTTON_SIZE)
	_apply_button_visual_scale(prod_menu, Vector2(136, 136))
	_apply_button_visual_scale(what_if_button, Vector2(72, 72))

	var control_menu := $Camera2D/CanvasLayer/ControlMenu
	if control_menu != null and control_menu.has_method("set_ui_scale"):
		control_menu.call("set_ui_scale", _ui_scale)
	_apply_button_visual_scale(control_menu as BaseButton, Vector2(72, 72))

	if patch_notes_button != null and patch_notes_button.has_method("set_ui_scale"):
		patch_notes_button.call("set_ui_scale", _ui_scale)
	_apply_button_visual_scale(patch_notes_button as BaseButton, Vector2(72, 72))

	if toolbox_button != null and toolbox_button.has_method("set_ui_scale"):
		toolbox_button.call("set_ui_scale", _ui_scale)

	if prod_panel != null and prod_panel.has_method("set_ui_scale"):
		prod_panel.call("set_ui_scale", _ui_scale)

	if rail_version_dropdown != null:
		rail_version_dropdown.custom_minimum_size = _scaled_vec2(RAIL_VERSION_DROPDOWN_SIZE)
		rail_version_dropdown.size = _scaled_vec2(RAIL_VERSION_DROPDOWN_SIZE)
		UiScale.apply_font_size(rail_version_dropdown, &"font_size", 14, _ui_scale, true)
		var rail_popup := rail_version_dropdown.get_popup()
		if rail_popup != null:
			UiScale.apply_font_size(rail_popup, &"font_size", 13, _ui_scale, true)
			if UiScale.is_small(_ui_scale):
				rail_popup.remove_theme_constant_override("v_separation")
			else:
				rail_popup.add_theme_constant_override("v_separation", _scaled_int(4))

	if rail_visibility_indicator != null:
		rail_visibility_indicator.custom_minimum_size = _scaled_vec2(RAIL_VISIBILITY_INDICATOR_SIZE)
		rail_visibility_indicator.size = _scaled_vec2(RAIL_VISIBILITY_INDICATOR_SIZE)
	if rail_visibility_indicator_label != null:
		rail_visibility_indicator_label.custom_minimum_size = _scaled_vec2(RAIL_VISIBILITY_INDICATOR_SIZE)
		rail_visibility_indicator_label.add_theme_font_size_override("font_size", UiScale.font_size(14, _ui_scale))

	if rail_alpha_controls != null:
		rail_alpha_controls.custom_minimum_size = _scaled_vec2(RAIL_VISIBILITY_ALPHA_CONTROL_SIZE)
		rail_alpha_controls.size = _scaled_vec2(RAIL_VISIBILITY_ALPHA_CONTROL_SIZE)
		var alpha_row := rail_alpha_controls.get_node_or_null("AlphaRow") as HBoxContainer
		if alpha_row != null:
			alpha_row.add_theme_constant_override("separation", _scaled_int(8))
	if rail_alpha_input != null:
		rail_alpha_input.custom_minimum_size = Vector2(_scaled(RAIL_VISIBILITY_ALPHA_TEXT_WIDTH), 0.0)
		UiScale.apply_font_size(rail_alpha_input, &"font_size", 13, _ui_scale, true)

	_apply_resource_summary_scale()
	_sync_command_bar_state()


func _apply_button_visual_scale(button: BaseButton, base_size: Vector2) -> void:
	if button == null:
		return
	button.scale = Vector2.ONE
	button.custom_minimum_size = _scaled_vec2(base_size)
	button.size = _scaled_vec2(base_size)
	button.add_theme_constant_override("icon_max_width", _scaled_int(base_size.x))


func _apply_resource_summary_scale() -> void:
	var summary_panel := $Camera2D/CanvasLayer/Panel as Control
	if summary_panel == null:
		return
	summary_panel.scale = Vector2(_ui_scale, _ui_scale)


func _scaled(value: float) -> float:
	return UiScale.scaled(value, _ui_scale)


func _scaled_int(value: float) -> int:
	return UiScale.scaled_int(value, _ui_scale)


func _scaled_vec2(value: Vector2) -> Vector2:
	return UiScale.scaled_vec2(value, _ui_scale)


func _scaled_vec2i(value: Vector2i) -> Vector2i:
	return UiScale.scaled_vec2i(value, _ui_scale)


func _control_visual_size(control: Control) -> Vector2:
	if control == null:
		return Vector2.ZERO
	var base_size := control.size
	if base_size.x <= 0.0 or base_size.y <= 0.0:
		base_size = control.get_combined_minimum_size()
	return Vector2(base_size.x * abs(control.scale.x), base_size.y * abs(control.scale.y))


func _apply_visual_theme() -> void:
	_style_panel($Camera2D/CanvasLayer/Panel)
	_style_panel($Camera2D/CanvasLayer/"Debug Panel")

	if prod_panel != null:
		prod_panel.self_modulate = Color.WHITE
		_style_panel(prod_panel)

	for button in [rail_version_dropdown]:
		if button != null:
			_style_button(button)
	if rail_visibility_indicator != null:
		var indicator_style := Palette.make_panel_style(Palette.BUTTON_PRESSED, Palette.SCENE_PANEL_BORDER, _scaled_int(8), _scaled_int(1))
		indicator_style.set_content_margin(SIDE_LEFT, _scaled(10))
		indicator_style.set_content_margin(SIDE_RIGHT, _scaled(10))
		indicator_style.set_content_margin(SIDE_TOP, _scaled(4))
		indicator_style.set_content_margin(SIDE_BOTTOM, _scaled(4))
		rail_visibility_indicator.add_theme_stylebox_override("panel", indicator_style)
	if rail_visibility_indicator_label != null:
		rail_visibility_indicator_label.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
		rail_visibility_indicator_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
		rail_visibility_indicator_label.add_theme_font_size_override("font_size", UiScale.font_size(14, _ui_scale))
	if rail_alpha_controls != null:
		var alpha_style := Palette.make_panel_style(Palette.BUTTON_PRESSED, Palette.SCENE_PANEL_BORDER, _scaled_int(8), _scaled_int(1))
		alpha_style.set_content_margin(SIDE_LEFT, _scaled(8))
		alpha_style.set_content_margin(SIDE_RIGHT, _scaled(8))
		alpha_style.set_content_margin(SIDE_TOP, _scaled(5))
		alpha_style.set_content_margin(SIDE_BOTTOM, _scaled(5))
		rail_alpha_controls.add_theme_stylebox_override("panel", alpha_style)
	if rail_alpha_input != null:
		rail_alpha_input.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
		rail_alpha_input.add_theme_color_override("font_placeholder_color", Palette.TEXT_MUTED)
		rail_alpha_input.add_theme_stylebox_override("normal", Palette.make_button_style(Palette.BUTTON_FILL, _scaled_int(6), _scaled_int(1)))
		rail_alpha_input.add_theme_stylebox_override("focus", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(6), _scaled_int(1)))
		rail_alpha_input.add_theme_stylebox_override("read_only", Palette.make_button_style(Palette.BUTTON_PRESSED, _scaled_int(6), _scaled_int(1)))

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
			label.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)


func _style_panel(panel: Control) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", Palette.make_panel_style(Palette.SCENE_PANEL_FILL, Palette.SCENE_PANEL_BORDER, _scaled_int(10), _scaled_int(2)))


func _style_button(button: BaseButton) -> void:
	button.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	button.add_theme_color_override("font_disabled_color", Palette.TEXT_MUTED)
	button.add_theme_stylebox_override("normal", Palette.make_button_style(Palette.BUTTON_FILL, _scaled_int(8), _scaled_int(1)))
	button.add_theme_stylebox_override("hover", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(8), _scaled_int(1)))
	button.add_theme_stylebox_override("pressed", Palette.make_button_style(Palette.BUTTON_PRESSED, _scaled_int(8), _scaled_int(1)))
	button.add_theme_stylebox_override("focus", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(8), _scaled_int(1)))
	button.add_theme_stylebox_override("disabled", Palette.make_button_style(Palette.BUTTON_PRESSED, _scaled_int(8), _scaled_int(1)))


func Adjust_ui_for_resolution() -> void:
	_layout_top_menu_bar()
	var top_menu_bottom := _get_top_menu_bottom()
	if toolbox_button != null:
		toolbox_button.position = Vector2(_scaled(TOOLBOX_LEFT_MARGIN), max(top_menu_bottom - _scaled(TOOLBOX_TOP_OVERLAP), 0.0))
	var resource_panel := $Camera2D/CanvasLayer/Panel as Control
	if resource_panel != null:
		var resource_panel_size := _control_visual_size(resource_panel)
		resource_panel.position = Vector2(
			get_viewport().size.x - resource_panel_size.x - _scaled(RESOURCE_PANEL_RIGHT_MARGIN),
			max(top_menu_bottom - _scaled(TOOLBOX_TOP_OVERLAP), 0.0)
		)
	_layout_prod_panel()
	$Camera2D/CanvasLayer/ControlMenu.position = Vector2(_scaled(TOOLBOX_LEFT_MARGIN), get_viewport().size.y - _scaled(50))
	$"Camera2D/CanvasLayer/Patch Notes".position = Vector2(_scaled(TOOLBOX_LEFT_MARGIN), get_viewport().size.y - _scaled(50 + LEGACY_BOTTOM_TOOL_SPACING))
	if what_if_button != null:
		what_if_button.position = Vector2(_scaled(TOOLBOX_LEFT_MARGIN), get_viewport().size.y - _scaled(50 + (LEGACY_BOTTOM_TOOL_SPACING * 2.0)))

	if rail_version_dropdown != null and toolbox_button != null:
		var menu_button_width = _control_visual_size(toolbox_button).x
		rail_version_dropdown.position = Vector2(
			toolbox_button.position.x + menu_button_width + _scaled(RAIL_VERSION_DROPDOWN_MARGIN),
			toolbox_button.position.y
		)
		_layout_rail_visibility_indicator()
		_layout_rail_alpha_controls()
	
func _layout_top_menu_bar() -> void:
	if top_menu_bar == null:
		return
	var viewport_size := Vector2(get_viewport().size)
	var preferred_size := top_menu_bar.get_preferred_size() if top_menu_bar.has_method("get_preferred_size") else top_menu_bar.get_combined_minimum_size()
	var menu_width = min(preferred_size.x, max(viewport_size.x - _scaled(TOP_MENU_BAR_VIEWPORT_MARGIN * 2.0), 1.0))
	var menu_height = max(preferred_size.y, top_menu_bar.custom_minimum_size.y)
	top_menu_bar.position = Vector2(max((viewport_size.x - menu_width) * 0.5, 0.0), 0.0)
	top_menu_bar.size = Vector2(menu_width, menu_height)


func _get_top_menu_bottom() -> float:
	if top_menu_bar == null:
		return 0.0
	return top_menu_bar.position.y + max(top_menu_bar.size.y, top_menu_bar.custom_minimum_size.y)


func _layout_prod_panel() -> void:
	if prod_panel == null:
		return

	var viewport_size := Vector2(get_viewport().size)
	var reference_width = min(viewport_size.x, BASE_UI_REFERENCE_WIDTH)
	var base_panel_screen_width = max(reference_width * PROD_PANEL_SCREEN_WIDTH_RATIO, PROD_PANEL_MIN_SCREEN_WIDTH) + PROD_PANEL_WIDTH_EXTRA
	var panel_screen_width = _scaled(base_panel_screen_width)
	panel_screen_width = min(panel_screen_width, max(viewport_size.x - _scaled(24.0), 1.0))
	var panel_screen_right := viewport_size.x - _scaled(8.0)
	var panel_screen_left = panel_screen_right - panel_screen_width
	var panel_screen_top = _get_top_menu_bottom() + _scaled(TOP_MENU_BAR_MARGIN)
	var math_panel := $Camera2D/CanvasLayer/Panel as Control
	if math_panel != null:
		panel_screen_top = max(panel_screen_top, math_panel.position.y + _control_visual_size(math_panel).y + _scaled(PROD_PANEL_TOP_GAP_FROM_MATH_PANEL))
	panel_screen_top = min(panel_screen_top, viewport_size.y - 1.0)
	var panel_screen_bottom = max(panel_screen_top + 1.0, viewport_size.y - _scaled(PROD_PANEL_BOTTOM_MARGIN))
	prod_panel.position = Vector2(panel_screen_left, panel_screen_top)
	var panel_size := Vector2(
		panel_screen_width,
		panel_screen_bottom - panel_screen_top
	)
	prod_panel.custom_minimum_size = Vector2.ZERO
	prod_panel.size = panel_size
	prod_panel.custom_minimum_size = panel_size

	if prod_panel.has_method("refresh_row_layout"):
		prod_panel.call("refresh_row_layout")
		prod_panel.call_deferred("refresh_row_layout")

func _sync_rail_version_selector() -> void:
	if rail_version_dropdown == null or path_manager == null:
		return
	if path_manager.has_method("set_rail_version_selector"):
		path_manager.set_rail_version_selector(rail_version_dropdown)

func _setup_rail_visibility_indicator() -> void:
	rail_visibility_indicator = PanelContainer.new()
	rail_visibility_indicator.name = "RailVisibilityIndicator"
	rail_visibility_indicator.custom_minimum_size = _scaled_vec2(RAIL_VISIBILITY_INDICATOR_SIZE)
	rail_visibility_indicator.size = _scaled_vec2(RAIL_VISIBILITY_INDICATOR_SIZE)
	rail_visibility_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail_visibility_indicator.visible = false

	rail_visibility_indicator_label = Label.new()
	rail_visibility_indicator_label.name = "ModeLabel"
	rail_visibility_indicator_label.text = "Standard"
	rail_visibility_indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rail_visibility_indicator_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rail_visibility_indicator_label.custom_minimum_size = _scaled_vec2(RAIL_VISIBILITY_INDICATOR_SIZE)
	rail_visibility_indicator.add_child(rail_visibility_indicator_label)
	$Camera2D/CanvasLayer.add_child(rail_visibility_indicator)

	rail_visibility_indicator_timer = Timer.new()
	rail_visibility_indicator_timer.name = "RailVisibilityIndicatorTimer"
	rail_visibility_indicator_timer.one_shot = true
	rail_visibility_indicator_timer.wait_time = RAIL_VISIBILITY_INDICATOR_DURATION
	rail_visibility_indicator_timer.timeout.connect(_hide_rail_visibility_indicator)
	add_child(rail_visibility_indicator_timer)
	_setup_rail_alpha_controls()

func _layout_rail_visibility_indicator() -> void:
	if rail_visibility_indicator == null or rail_version_dropdown == null:
		return

	var indicator_size := _scaled_vec2(RAIL_VISIBILITY_INDICATOR_SIZE)
	rail_visibility_indicator.size = indicator_size
	var dropdown_width = max(rail_version_dropdown.size.x, _scaled(RAIL_VERSION_DROPDOWN_SIZE.x)) * rail_version_dropdown.scale.x
	rail_visibility_indicator.position = Vector2(
		rail_version_dropdown.position.x + dropdown_width + _scaled(RAIL_VISIBILITY_INDICATOR_MARGIN),
		rail_version_dropdown.position.y
	)

func _setup_rail_alpha_controls() -> void:
	rail_alpha_controls = PanelContainer.new()
	rail_alpha_controls.name = "RailAlphaControls"
	rail_alpha_controls.custom_minimum_size = _scaled_vec2(RAIL_VISIBILITY_ALPHA_CONTROL_SIZE)
	rail_alpha_controls.size = _scaled_vec2(RAIL_VISIBILITY_ALPHA_CONTROL_SIZE)
	rail_alpha_controls.visible = false

	var alpha_row := HBoxContainer.new()
	alpha_row.name = "AlphaRow"
	alpha_row.add_theme_constant_override("separation", _scaled_int(8))
	rail_alpha_controls.add_child(alpha_row)

	rail_alpha_slider = HSlider.new()
	rail_alpha_slider.name = "AlphaSlider"
	rail_alpha_slider.min_value = 0.0
	rail_alpha_slider.max_value = 1.0
	rail_alpha_slider.step = RAIL_VISIBILITY_ALPHA_STEP
	rail_alpha_slider.page = RAIL_VISIBILITY_ALPHA_STEP
	rail_alpha_slider.value = _get_high_visibility_alpha()
	rail_alpha_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail_alpha_slider.tooltip_text = "Rail alpha"
	rail_alpha_slider.value_changed.connect(_on_rail_alpha_slider_changed)
	alpha_row.add_child(rail_alpha_slider)

	rail_alpha_input = LineEdit.new()
	rail_alpha_input.name = "AlphaInput"
	rail_alpha_input.custom_minimum_size = Vector2(_scaled(RAIL_VISIBILITY_ALPHA_TEXT_WIDTH), 0.0)
	rail_alpha_input.text = _format_rail_alpha(_get_high_visibility_alpha())
	rail_alpha_input.placeholder_text = "1.00"
	rail_alpha_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	rail_alpha_input.tooltip_text = "Rail alpha"
	rail_alpha_input.text_submitted.connect(_on_rail_alpha_text_submitted)
	rail_alpha_input.focus_exited.connect(_commit_rail_alpha_input)
	alpha_row.add_child(rail_alpha_input)

	$Camera2D/CanvasLayer.add_child(rail_alpha_controls)

func _layout_rail_alpha_controls() -> void:
	if rail_alpha_controls == null or rail_visibility_indicator == null:
		return

	rail_alpha_controls.size = _scaled_vec2(RAIL_VISIBILITY_ALPHA_CONTROL_SIZE)
	rail_alpha_controls.position = Vector2(
		rail_visibility_indicator.position.x,
		rail_visibility_indicator.position.y + _scaled(RAIL_VISIBILITY_INDICATOR_SIZE.y) + _scaled(RAIL_VISIBILITY_ALPHA_CONTROL_TOP_MARGIN)
	)

func _process_rail_visibility_input() -> bool:
	if not InputMap.has_action(RAIL_VISIBILITY_ACTION):
		return false
	if not Input.is_action_just_pressed(RAIL_VISIBILITY_ACTION, true):
		return false
	return _cycle_rail_visibility()


func _cycle_rail_visibility() -> bool:
	if path_manager == null or not path_manager.has_method("cycle_rail_visibility_mode"):
		return false

	path_manager.call("cycle_rail_visibility_mode")
	var mode_name := "Standard"
	if path_manager.has_method("get_rail_visibility_mode_name"):
		mode_name = String(path_manager.call("get_rail_visibility_mode_name"))
	_show_rail_visibility_indicator(mode_name)
	_sync_rail_alpha_controls_visibility()
	return true

func _show_rail_visibility_indicator(mode_name: String) -> void:
	if rail_visibility_indicator_label != null:
		rail_visibility_indicator_label.text = mode_name
	if rail_visibility_indicator != null:
		_layout_rail_visibility_indicator()
		rail_visibility_indicator.visible = true
	if rail_visibility_indicator_timer != null:
		rail_visibility_indicator_timer.start(RAIL_VISIBILITY_INDICATOR_DURATION)

func _hide_rail_visibility_indicator() -> void:
	if rail_visibility_indicator != null:
		rail_visibility_indicator.visible = false

func _is_high_visibility_mode() -> bool:
	if path_manager == null or not path_manager.has_method("get_rail_visibility_mode"):
		return false
	return int(path_manager.call("get_rail_visibility_mode")) == RAIL_VISIBILITY_MODE_HIGH

func _get_high_visibility_alpha() -> float:
	if path_manager == null or not path_manager.has_method("get_high_visibility_alpha"):
		return 1.0
	return clampf(float(path_manager.call("get_high_visibility_alpha")), 0.0, 1.0)

func _set_high_visibility_alpha(alpha: float) -> void:
	var clamped_alpha := clampf(alpha, 0.0, 1.0)
	if path_manager != null and path_manager.has_method("set_high_visibility_alpha"):
		path_manager.call("set_high_visibility_alpha", clamped_alpha)
	_sync_rail_alpha_controls(clamped_alpha)

func _format_rail_alpha(alpha: float) -> String:
	return "%.2f" % clampf(alpha, 0.0, 1.0)

func _sync_rail_alpha_controls(alpha: float) -> void:
	_syncing_rail_alpha_controls = true
	if rail_alpha_slider != null:
		rail_alpha_slider.value = clampf(alpha, 0.0, 1.0)
	if rail_alpha_input != null:
		rail_alpha_input.text = _format_rail_alpha(alpha)
	_syncing_rail_alpha_controls = false

func _sync_rail_alpha_controls_visibility() -> void:
	if rail_alpha_controls == null:
		return

	rail_alpha_controls.visible = _is_high_visibility_mode()
	if rail_alpha_controls.visible:
		_layout_rail_alpha_controls()
		_sync_rail_alpha_controls(_get_high_visibility_alpha())

func _on_rail_alpha_slider_changed(value: float) -> void:
	if _syncing_rail_alpha_controls:
		return
	_set_high_visibility_alpha(value)

func _on_rail_alpha_text_submitted(_new_text: String) -> void:
	_commit_rail_alpha_input()

func _commit_rail_alpha_input() -> void:
	if _syncing_rail_alpha_controls or rail_alpha_input == null:
		return

	var raw := rail_alpha_input.text.strip_edges().replace("%", "")
	if not raw.is_valid_float():
		_sync_rail_alpha_controls(_get_high_visibility_alpha())
		return

	var parsed_alpha := raw.to_float()
	if parsed_alpha > 1.0:
		parsed_alpha /= 100.0
	_set_high_visibility_alpha(parsed_alpha)
	
func _on_viewport_size_changed() -> void:
	_last_viewport_size = get_viewport().size
	var scale_changed := _refresh_ui_scale()
	if scale_changed:
		_apply_ui_scale()
		_apply_visual_theme()
	Adjust_ui_for_resolution()
	_layout_what_if_machine_overlay()
	call_deferred("_refresh_grid_visibility")


func _layout_what_if_machine_overlay() -> void:
	if not _is_what_if_machine_open():
		return

	_configure_what_if_overlay(_what_if_machine_overlay)
	if _what_if_machine_overlay.has_method("refresh_overlay_layout"):
		_what_if_machine_overlay.call("refresh_overlay_layout")
		_what_if_machine_overlay.call_deferred("refresh_overlay_layout")
	
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
	var half_size := Vector2i(floori(float(used_rect.size.x) * 0.5), floori(float(used_rect.size.y) * 0.5))
	var center_cell := used_rect.position + half_size
	var local_pos = tile_map_layer.map_to_local(center_cell)
	
	if used_rect.size == Vector2i.ZERO:
		return Vector2i (0,0)
	
	return tile_map_layer.to_global(local_pos)


func _generate_pending_what_if_plan() -> void:
	if _pending_what_if_generation_request.is_empty():
		return

	var request := _pending_what_if_generation_request.duplicate()
	_pending_what_if_generation_request.clear()
	_generate_what_if_plan(request)


func _generate_what_if_plan(request: Dictionary) -> void:
	var target_recipe := request.get("target_recipe") as Recipe
	var target_qty := float(request.get("target_qty", 0.0))
	if target_recipe == null or target_qty <= 0.0:
		push_warning("What If generation skipped: missing recipe or quantity.")
		return

	var enabled_v2_building_ids: Dictionary = {}
	var enabled_variant = request.get("enabled_v2_building_ids", {})
	if enabled_variant is Dictionary:
		enabled_v2_building_ids = enabled_variant

	var graph := _build_what_if_generation_graph(target_recipe, target_qty, enabled_v2_building_ids)
	var nodes: Array = graph.get("nodes", [])
	if nodes.is_empty():
		push_warning("What If generation skipped: no buildable recipe graph was found.")
		return

	var history_before := _capture_history_state()
	var generated_buildings := _place_what_if_generation_buildings(graph)
	if generated_buildings.is_empty():
		push_warning("What If generation skipped: no buildings could be placed.")
		return

	_connect_what_if_generation_rails(graph)
	_refresh_plan_totals_from_scene()
	_center_camera_on_generated_buildings(generated_buildings)
	_commit_history_action(HISTORY_ACTION_WHAT_IF_GENERATED, history_before)


func _build_what_if_generation_graph(target_recipe: Recipe, target_qty: float, enabled_v2_building_ids: Dictionary) -> Dictionary:
	var registry := get_node_or_null("/root/RecipeRegistry")
	if registry == null:
		push_warning("What If generation skipped: RecipeRegistry is not available.")
		return {}

	var nodes: Array[Dictionary] = []
	var nodes_by_key: Dictionary = {}
	var edges: Array[Dictionary] = []
	var current_requirements: Dictionary = {}
	var expanded_building_counts: Dictionary = {}
	_merge_what_if_generation_requirement(current_requirements, target_recipe, target_qty)

	for level in range(WHAT_IF_GENERATION_MAX_DEPTH):
		if current_requirements.is_empty():
			break

		var next_requirements: Dictionary = {}
		for key_variant in current_requirements.keys():
			var key := String(key_variant)
			var requirement: Dictionary = current_requirements[key]
			var recipe := requirement.get("recipe") as Recipe
			var required_qty := float(requirement.get("required_qty", 0.0))
			if recipe == null or required_qty <= 0.0:
				continue

			var node := _get_or_create_what_if_generation_node(nodes, nodes_by_key, key, recipe, level, registry)
			node["required_qty"] = float(node.get("required_qty", 0.0)) + required_qty
			node["level"] = maxi(int(node.get("level", level)), level)
			_recalculate_what_if_generation_node(node, registry)

		for key_variant in current_requirements.keys():
			var key := String(key_variant)
			var node := nodes_by_key.get(key, {}) as Dictionary
			var recipe := node.get("recipe") as Recipe
			if recipe == null:
				continue

			var building_count := int(node.get("building_count", 0))
			var expanded_count := int(expanded_building_counts.get(key, 0))
			var new_building_count := building_count - expanded_count
			if new_building_count <= 0:
				continue
			expanded_building_counts[key] = building_count

			for input_index in range(recipe.inputs.size()):
				var input_stack := recipe.inputs[input_index]
				if input_stack == null:
					continue

				var input_id := _get_stack_id(input_stack)
				var input_recipe := _get_best_what_if_recipe_for_output_id(registry, input_id, enabled_v2_building_ids)
				if input_recipe == null:
					continue

				var input_key := _recipe_key(input_recipe)
				var input_required_qty := float(input_stack.qty) * float(new_building_count)
				edges.append({
					"from_key": input_key,
					"to_key": key,
					"input_index": input_index,
					"input_id": input_id,
					"required_qty": input_required_qty,
				})
				_merge_what_if_generation_requirement(next_requirements, input_recipe, input_required_qty)

		current_requirements = next_requirements

	return {
		"nodes": nodes,
		"nodes_by_key": nodes_by_key,
		"edges": edges,
	}


func _get_or_create_what_if_generation_node(
	nodes: Array[Dictionary],
	nodes_by_key: Dictionary,
	key: String,
	recipe: Recipe,
	level: int,
	registry: Node
) -> Dictionary:
	if nodes_by_key.has(key):
		return nodes_by_key[key]

	var output_id := _get_recipe_output_id(recipe)
	var building_id := StringName("")
	if registry != null and registry.has_method("get_recipe_building_id"):
		building_id = registry.call("get_recipe_building_id", recipe)

	var node := {
		"key": key,
		"recipe": recipe,
		"level": level,
		"required_qty": 0.0,
		"output_id": output_id,
		"output_qty": 0.0,
		"building_id": building_id,
		"building_count": 0,
		"total_output": 0.0,
		"instances": [],
	}
	nodes_by_key[key] = node
	nodes.append(node)
	return node


func _recalculate_what_if_generation_node(node: Dictionary, registry: Node) -> void:
	var recipe := node.get("recipe") as Recipe
	var output_qty := _get_recipe_output_qty(recipe, registry)
	var required_qty := float(node.get("required_qty", 0.0))
	var building_count := 0
	if output_qty > 0.0:
		building_count = int(ceil(required_qty / output_qty))

	node["output_qty"] = output_qty
	node["building_count"] = building_count
	node["total_output"] = float(building_count) * output_qty


func _merge_what_if_generation_requirement(requirements: Dictionary, recipe: Recipe, required_qty: float) -> void:
	if recipe == null or required_qty <= 0.0:
		return

	var key := _recipe_key(recipe)
	if not requirements.has(key):
		requirements[key] = {
			"recipe": recipe,
			"required_qty": 0.0,
		}

	var requirement: Dictionary = requirements[key]
	requirement["required_qty"] = float(requirement.get("required_qty", 0.0)) + required_qty


func _place_what_if_generation_buildings(graph: Dictionary) -> Array[Node2D]:
	var generated_buildings: Array[Node2D] = []
	var levels := _group_what_if_generation_nodes_by_level(graph.get("nodes", []))
	if levels.is_empty():
		return generated_buildings

	var level_keys: Array[int] = []
	for level_variant in levels.keys():
		level_keys.append(int(level_variant))
	level_keys.sort()

	var origin_cell := _get_what_if_generation_origin_cell()
	var row_y := origin_cell.y
	for level in level_keys:
		var level_nodes: Array = levels[level]
		var row_height := _get_what_if_generation_row_height(level_nodes)
		var x_cursor := origin_cell.x

		for node_variant in level_nodes:
			var node: Dictionary = node_variant
			var building_count := int(node.get("building_count", 0))
			var footprint := _get_what_if_generation_node_footprint(node)
			if building_count <= 0 or footprint == Vector2i.ZERO:
				continue

			var instances: Array = node.get("instances", [])
			for _i in range(building_count):
				var building := _create_what_if_generation_building(node, Vector2i(x_cursor, row_y))
				if building != null:
					instances.append(building)
					generated_buildings.append(building)
				x_cursor += footprint.x + WHAT_IF_GENERATION_COLUMN_SPACING
			node["instances"] = instances
			x_cursor += WHAT_IF_GENERATION_COLUMN_SPACING

		row_y += row_height + WHAT_IF_GENERATION_ROW_SPACING

	return generated_buildings


func _group_what_if_generation_nodes_by_level(nodes: Array) -> Dictionary:
	var levels := {}
	for node_variant in nodes:
		var node: Dictionary = node_variant
		if int(node.get("building_count", 0)) <= 0:
			continue
		if StringName(node.get("building_id", StringName(""))) == StringName(""):
			continue

		var level := int(node.get("level", 0))
		if not levels.has(level):
			levels[level] = []
		var level_nodes: Array = levels[level]
		level_nodes.append(node)
	return levels


func _get_what_if_generation_row_height(level_nodes: Array) -> int:
	var row_height := 1
	for node_variant in level_nodes:
		var node: Dictionary = node_variant
		var footprint := _get_what_if_generation_node_footprint(node)
		row_height = maxi(row_height, footprint.y)
	return row_height


func _get_what_if_generation_node_footprint(node: Dictionary) -> Vector2i:
	var stored_footprint = node.get("footprint", Vector2i.ZERO)
	if stored_footprint is Vector2i and stored_footprint != Vector2i.ZERO:
		return stored_footprint

	var building_id := StringName(node.get("building_id", StringName("")))
	var scene := BuildRegistry.get_scene(building_id)
	if scene == null:
		return Vector2i.ZERO

	var instance := scene.instantiate() as Node2D
	if instance == null:
		return Vector2i.ZERO

	var footprint := Vector2i.ONE
	if build_manager != null and build_manager.has_method("get_rotated_footprint"):
		footprint = build_manager.get_rotated_footprint(instance)
	instance.free()

	node["footprint"] = footprint
	return footprint


func _get_what_if_generation_origin_cell() -> Vector2i:
	if build_manager == null or not ("occupied_cells" in build_manager):
		return WHAT_IF_GENERATION_START_CELL

	var occupied_cells: Dictionary = build_manager.occupied_cells
	if occupied_cells.is_empty():
		return WHAT_IF_GENERATION_START_CELL

	var max_x := -2147483648
	var min_y := 2147483647
	for cell_variant in occupied_cells.keys():
		var cell: Vector2i = cell_variant
		max_x = maxi(max_x, cell.x)
		min_y = mini(min_y, cell.y)

	return Vector2i(max_x + WHAT_IF_GENERATION_EXISTING_PLAN_MARGIN, min_y)


func _create_what_if_generation_building(node: Dictionary, preferred_anchor_cell: Vector2i) -> Node2D:
	var building_id := StringName(node.get("building_id", StringName("")))
	var recipe := node.get("recipe") as Recipe
	var scene := BuildRegistry.get_scene(building_id)
	if scene == null:
		push_warning("What If generation skipped building id %s: no registered scene." % building_id)
		return null

	var building := scene.instantiate() as Node2D
	if building == null:
		return null

	var anchor_cell := _find_free_what_if_generation_anchor(building, preferred_anchor_cell)
	var cells = build_manager.get_building_cells(building, anchor_cell)
	if not build_manager.can_place_at(cells):
		building.free()
		return null

	building.global_position = build_manager._position_from_anchor_cell(building, anchor_cell)
	buildings_root.add_child(building)
	_apply_what_if_generated_recipe_selection(building, recipe)
	build_manager.occupy_cells(cells, building)
	return building


func _find_free_what_if_generation_anchor(building: Node2D, preferred_anchor_cell: Vector2i) -> Vector2i:
	for y_offset in range(0, 40):
		for x_offset in range(0, 40):
			var candidate := preferred_anchor_cell + Vector2i(x_offset, y_offset)
			var cells = build_manager.get_building_cells(building, candidate)
			if build_manager.can_place_at(cells):
				return candidate
	return preferred_anchor_cell


func _apply_what_if_generated_recipe_selection(building: Node2D, recipe: Recipe) -> void:
	if building == null or recipe == null:
		return

	var recipe_dropdown := building.get_node_or_null("Recipe") as OptionButton
	if recipe_dropdown != null:
		var recipe_index := _find_recipe_option_index(recipe_dropdown, recipe)
		if recipe_index >= 0:
			recipe_dropdown.select(recipe_index)
			_call_option_selection_handler(building, "_on_recipe_item_selected", recipe_dropdown)

	var purity_dropdown := building.get_node_or_null("Purity") as OptionButton
	if purity_dropdown != null and purity_dropdown.item_count > 0:
		purity_dropdown.select(0)
		_call_option_selection_handler(building, "_on_purity_item_selected", purity_dropdown)


func _find_recipe_option_index(option_button: OptionButton, recipe: Recipe) -> int:
	if option_button == null or recipe == null:
		return -1

	var target_key := _recipe_key(recipe)
	for index in range(option_button.item_count):
		var metadata = option_button.get_item_metadata(index)
		var metadata_recipe := metadata as Recipe
		if metadata_recipe != null and _recipe_key(metadata_recipe) == target_key:
			return index

	return -1


func _connect_what_if_generation_rails(graph: Dictionary) -> void:
	if path_manager == null or not path_manager.has_method("_finalize_path"):
		return

	var nodes_by_key: Dictionary = graph.get("nodes_by_key", {})
	var connected_paths := {}

	for edge_variant in graph.get("edges", []):
		var edge: Dictionary = edge_variant
		var from_key := String(edge.get("from_key", ""))
		var to_key := String(edge.get("to_key", ""))
		var from_node := nodes_by_key.get(from_key, {}) as Dictionary
		var to_node := nodes_by_key.get(to_key, {}) as Dictionary
		if from_node.is_empty() or to_node.is_empty():
			continue

		var producers: Array = from_node.get("instances", [])
		var consumers: Array = to_node.get("instances", [])
		if producers.is_empty() or consumers.is_empty():
			continue

		var input_index := int(edge.get("input_index", 0))
		var bus_groups := _get_what_if_bus_groups_for_node(from_node)
		for bus_index in range(bus_groups.size()):
			var bus_group: Dictionary = bus_groups[bus_index]
			var bus_producers: Array = bus_group.get("producers", [])
			if bus_producers.is_empty():
				continue

			var bus_consumers := _get_what_if_bus_consumers(consumers, bus_index, bus_groups.size())
			var rail_version := _get_what_if_rail_version_for_rate(float(bus_group.get("rate", 0.0)))
			var connection_count = maxi(bus_producers.size(), bus_consumers.size())

			for index in range(connection_count):
				var from_building := bus_producers[index % bus_producers.size()] as Node2D
				var to_building := bus_consumers[index % bus_consumers.size()] as Node2D
				if from_building == null or to_building == null:
					continue

				var to_port := _get_what_if_input_port_path(to_building, input_index)
				var from_port := _get_what_if_output_port_path(from_building)
				if String(from_port) == "" or String(to_port) == "":
					continue

				var connection_key := "%s|%s|%s" % [from_building.get_instance_id(), to_building.get_instance_id(), String(to_port)]
				if connected_paths.has(connection_key):
					continue
				connected_paths[connection_key] = true

				_connect_what_if_generation_path(from_building, from_port, to_building, to_port, rail_version)


func _connect_what_if_generation_path(from_building: Node2D, from_port: NodePath, to_building: Node2D, to_port: NodePath, rail_version: int) -> void:
	var from_pos = path_manager._get_port_center(from_building, from_port)
	var to_pos = path_manager._get_port_center(to_building, to_port)
	if from_pos == null or to_pos == null:
		return

	path_manager._finalize_path(from_building, from_port, from_pos, to_building, to_port, to_pos, rail_version, false)


func _get_what_if_output_port_path(building: Node2D) -> NodePath:
	var preferred := NodePath("Ports/Output 1")
	if building.get_node_or_null(preferred) != null:
		return preferred
	return _find_what_if_port_path(building, ["Output"])


func _get_what_if_input_port_path(building: Node2D, input_index: int) -> NodePath:
	var preferred := NodePath("Ports/Input %d" % (input_index + 1))
	if building.get_node_or_null(preferred) != null:
		return preferred
	return _find_what_if_port_path(building, ["Input", "Universal"])


func _find_what_if_port_path(building: Node2D, prefixes: Array[String]) -> NodePath:
	if building == null:
		return NodePath("")

	var ports := building.get_node_or_null("Ports")
	if ports == null:
		return NodePath("")

	for child in ports.get_children():
		for prefix in prefixes:
			if child.name.begins_with(prefix):
				return NodePath("Ports/%s" % child.name)
	return NodePath("")


func _get_what_if_bus_groups_for_node(node: Dictionary) -> Array[Dictionary]:
	var cached_groups = node.get("bus_groups", [])
	if cached_groups is Array and not cached_groups.is_empty():
		return cached_groups

	var producers: Array = node.get("instances", [])
	var output_qty := float(node.get("output_qty", 0.0))
	var groups: Array[Dictionary] = []
	for producer in producers:
		if output_qty <= 0.0:
			continue

		var target_group := _find_what_if_bus_group_for_rate(groups, output_qty)
		if target_group.is_empty():
			target_group = {
				"producers": [],
				"rate": 0.0,
			}
			groups.append(target_group)

		var group_producers: Array = target_group.get("producers", [])
		group_producers.append(producer)
		target_group["producers"] = group_producers
		target_group["rate"] = float(target_group.get("rate", 0.0)) + output_qty

	node["bus_groups"] = groups
	return groups


func _find_what_if_bus_group_for_rate(groups: Array[Dictionary], additional_rate: float) -> Dictionary:
	for group in groups:
		var current_rate := float(group.get("rate", 0.0))
		if current_rate + additional_rate <= WHAT_IF_RAIL_V3_CAPACITY:
			return group
	return {}


func _get_what_if_bus_consumers(consumers: Array, bus_index: int, bus_count: int) -> Array:
	if bus_count <= 1:
		return consumers

	var bus_consumers: Array = []
	for consumer_index in range(consumers.size()):
		if consumer_index % bus_count == bus_index:
			bus_consumers.append(consumers[consumer_index])

	if bus_consumers.is_empty():
		return consumers
	return bus_consumers


func _get_what_if_rail_version_for_rate(rate: float) -> int:
	if rate <= WHAT_IF_RAIL_V1_CAPACITY:
		return 0
	if rate <= WHAT_IF_RAIL_V2_CAPACITY:
		return 1
	return 2


func _refresh_plan_totals_from_scene() -> void:
	var scene_buildings := _get_scene_buildings()
	heat_label.text = str(_sum_building_stat(scene_buildings, "heat"))
	power_label.text = str(_sum_building_stat(scene_buildings, "power"))

	var cost_totals := _sum_building_costs(scene_buildings)
	bbm_cost_label.text = str(int(cost_totals.get("bbm", 0)))
	ibm_cost_label.text = str(int(cost_totals.get("ibm", 0)))
	meteor_core_cost_label.text = str(int(cost_totals.get("meteor_cores", 0)))

	_reset_prod_ledger()
	_rebuild_production_ledger(scene_buildings)


func _get_scene_buildings() -> Array[Node2D]:
	var scene_buildings: Array[Node2D] = []
	if buildings_root == null:
		return scene_buildings

	for child in buildings_root.get_children():
		if child is Node2D:
			scene_buildings.append(child as Node2D)
	return scene_buildings


func _center_camera_on_generated_buildings(generated_buildings: Array[Node2D]) -> void:
	if generated_buildings.is_empty():
		return

	var total := Vector2.ZERO
	var count := 0
	for building in generated_buildings:
		if building != null and is_instance_valid(building):
			total += building.global_position
			count += 1

	if count > 0:
		camera.position = total / float(count)


func _get_best_what_if_recipe_for_output_id(registry: Node, output_id: StringName, enabled_v2_building_ids: Dictionary) -> Recipe:
	if registry == null or output_id == StringName(""):
		return null
	if not registry.has_method("get_best_recipe_for_output_id"):
		return null
	return registry.call("get_best_recipe_for_output_id", output_id, enabled_v2_building_ids) as Recipe


func _get_recipe_output_id(recipe: Recipe) -> StringName:
	if recipe == null or recipe.outputs.is_empty():
		return StringName("")
	return _get_stack_id(recipe.outputs[0])


func _get_recipe_output_qty(recipe: Recipe, registry: Node) -> float:
	if registry != null and registry.has_method("get_recipe_output_qty"):
		return float(registry.call("get_recipe_output_qty", recipe))
	if recipe == null or recipe.outputs.is_empty() or recipe.outputs[0] == null:
		return 0.0
	return float(recipe.outputs[0].qty)


func _get_stack_id(stack: ItemStack) -> StringName:
	if stack == null:
		return StringName("")
	if stack.id != StringName(""):
		return stack.id
	if stack.item != null:
		return stack.item.id
	return StringName("")


func _recipe_key(recipe: Recipe) -> String:
	if recipe == null:
		return ""
	if recipe.resource_path != "":
		return recipe.resource_path
	return str(recipe.get_instance_id())

func _on_save_pressed() -> void:
	if OS.has_feature("web") and JavaScriptBridge != null:
		_request_save_to_browser()
		return

	save_dialog.current_file = "build_plan.%s" % SAVE_FILE_EXTENSION
	save_dialog.popup_centered_ratio(0.7)

func _on_load_pressed() -> void:
	if OS.has_feature("web") and JavaScriptBridge != null:
		_request_load_from_browser()
		return
	load_dialog.popup_centered_ratio(0.7)
	
func _on_export_pdf_pressed() -> void:
	if OS.has_feature("web") and JavaScriptBridge != null:
		_download_pdf_to_browser()
		return

	export_pdf_dialog.current_file = "build_plan.pdf"
	export_pdf_dialog.popup_centered_ratio(0.7)

func _on_new_pressed() -> void:
	_clear_scene_plan()
	_clear_history()

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
				_detach_and_queue_free(child)

	for child in buildings_root.get_children():
		_detach_and_queue_free(child)
		
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
	var save_state := _collect_save_state()
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

func _request_load_from_browser() -> void:
	_cleanup_web_load_picker()

	var document = JavaScriptBridge.get_interface("document")
	if document == null or document.body == null:
		push_warning("Browser file picker is unavailable in this web build.")
		return

	_web_load_input = document.createElement("input")
	if _web_load_input == null:
		push_warning("Failed to create browser file input for loading saves.")
		return

	_web_load_input.setAttribute("type", "file")
	_web_load_input.setAttribute("accept", ".%s,.json,application/json" % SAVE_FILE_EXTENSION)
	_web_load_input.setAttribute("style", "display:none")
	_web_load_input_callback = JavaScriptBridge.create_callback(_on_web_load_input_changed)
	_web_load_input.onchange = _web_load_input_callback
	document.body.appendChild(_web_load_input)
	_web_load_input.click()

func _cleanup_web_load_picker() -> void:
	if _web_load_input != null:
		if _web_load_input.parentNode != null:
			_web_load_input.parentNode.removeChild(_web_load_input)
		_web_load_input = null
	_web_load_reader = null
	_web_load_input_callback = null
	_web_load_read_callback = null
	_web_load_error_callback = null
	_web_load_pending_file_name = ""

func _on_web_load_input_changed(args: Array) -> void:
	if args.is_empty():
		_cleanup_web_load_picker()
		return

	var event = args[0]
	if event == null or event.target == null or event.target.files == null or int(event.target.files.length) < 1:
		_cleanup_web_load_picker()
		return

	var selected_file = event.target.files[0]
	_web_load_pending_file_name = str(selected_file.name)
	_web_load_reader = JavaScriptBridge.create_object("FileReader")
	if _web_load_reader == null:
		push_warning("Failed to create browser file reader for %s." % _web_load_pending_file_name)
		_cleanup_web_load_picker()
		return

	_web_load_read_callback = JavaScriptBridge.create_callback(_on_web_load_reader_loaded)
	_web_load_error_callback = JavaScriptBridge.create_callback(_on_web_load_reader_failed)
	_web_load_reader.onload = _web_load_read_callback
	_web_load_reader.onerror = _web_load_error_callback
	_web_load_reader.readAsText(selected_file)

func _on_web_load_reader_loaded(args: Array) -> void:
	var raw_text := ""
	if not args.is_empty() and args[0] != null and args[0].target != null:
		raw_text = str(args[0].target.result)

	var loaded := raw_text != "" and _apply_save_text(raw_text)
	if not loaded:
		push_warning("Failed to load save file from browser-selected file %s" % _web_load_pending_file_name)

	_cleanup_web_load_picker()

func _on_web_load_reader_failed(_args: Array) -> void:
	push_warning("Failed to read save file from browser-selected file %s" % _web_load_pending_file_name)
	_cleanup_web_load_picker()

func _load_save_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var raw := file.get_as_text()
	return _apply_save_text(raw)

func _apply_save_text(raw: String) -> bool:
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return false

	_apply_save_state(parsed)
	_clear_history()
	return true

func _process_history_input() -> bool:
	if build_manager != null and "is_dragging_building" in build_manager and bool(build_manager.is_dragging_building):
		return false
	if InputMap.has_action("Undo") and Input.is_action_just_pressed("Undo", true):
		_undo_history()
		return true
	if InputMap.has_action("Redo") and Input.is_action_just_pressed("Redo", true):
		_redo_history()
		return true
	return false

func _capture_history_state() -> Dictionary:
	var state := _collect_save_state()
	state.erase("saved_at_unix")
	state.erase("camera")
	state.erase("production_panel_visible")
	return state.duplicate(true)

func _commit_history_action(label: String, before_state: Dictionary) -> void:
	if _is_replaying_history or before_state.is_empty():
		return

	var after_state := _capture_history_state()
	if _history_states_equal(before_state, after_state):
		return

	_undo_stack.append({
		"label": label,
		"before": before_state.duplicate(true),
		"after": after_state.duplicate(true)
	})
	while _undo_stack.size() > HISTORY_LIMIT:
		_undo_stack.pop_front()
	_redo_stack.clear()

func _undo_history() -> void:
	if _undo_stack.is_empty():
		return

	var entry: Dictionary = _undo_stack.pop_back()
	var before_state = entry.get("before", {})
	if not (before_state is Dictionary):
		return

	_apply_history_state(before_state)
	_redo_stack.append(entry)

func _redo_history() -> void:
	if _redo_stack.is_empty():
		return

	var entry: Dictionary = _redo_stack.pop_back()
	var after_state = entry.get("after", {})
	if not (after_state is Dictionary):
		return

	_apply_history_state(after_state)
	_undo_stack.append(entry)

func _clear_history() -> void:
	_undo_stack.clear()
	_redo_stack.clear()

func _apply_history_state(state: Dictionary) -> void:
	_is_replaying_history = true
	if build_manager != null and build_manager.has_method("cancel_build"):
		build_manager.cancel_build()
	if path_manager != null and path_manager.has_method("cancel_active_path_drag"):
		path_manager.cancel_active_path_drag()
	_apply_save_state(state.duplicate(true), false)
	_is_replaying_history = false

func _history_states_equal(first: Dictionary, second: Dictionary) -> bool:
	return var_to_str(first) == var_to_str(second)

func _detach_and_queue_free(node: Node) -> void:
	if node == null:
		return
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()

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
	var meteor_core_total = $Camera2D/CanvasLayer/Panel/MeteorCoreCostLabel.text.to_int()
	
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
	var core_level_selection := _serialize_option_button(building.get_node_or_null("CoreLevel"))
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
		"purity": purity_selection,
		"core_level": core_level_selection
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

func _apply_save_state(save_state: Dictionary, restore_view_state := true) -> void:
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
	if restore_view_state:
		_restore_camera(save_state.get("camera", {}))
		prod_panel.visible = bool(save_state.get("production_panel_visible", false))
	else:
		prod_panel.visible = keep_prod_panel_visible

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
	if path_manager.has_method("cancel_active_path_drag"):
		path_manager.cancel_active_path_drag()

	for child in path_manager.get_children():
		_detach_and_queue_free(child)

	for child in buildings_root.get_children():
		_detach_and_queue_free(child)

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
		_call_option_selection_handler(building, "_on_recipe_item_selected", recipe_dropdown)

	_restore_option_selection(purity_dropdown, purity_selection)

	if not _call_option_selection_handler(building, "_on_purity_item_selected", purity_dropdown):
		_call_option_selection_handler(building, "_on_recipe_item_selected", recipe_dropdown)

	_restore_option_selection(core_level_dropdown, core_level_selection)
	_call_option_selection_handler(building, "_on_core_level_item_selected", core_level_dropdown)

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
		path_manager._finalize_path(from_b, from_port, from_pos, to_b, to_port, to_pos, rail_version, false)

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
	
