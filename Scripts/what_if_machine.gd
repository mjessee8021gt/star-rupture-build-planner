extends Control

const Palette = preload("res://Scripts/palette.gd")

signal close_requested
signal generate_requested(request: Dictionary)

const RECIPES_ROOT := "res://Recipes"
const RECIPE_POPUP_MAX_SIZE := Vector2i(360, 420)
const MAX_DEPENDENCY_DEPTH := 48
const TAB_BY_RECIPE := 0
const TAB_BY_BUILDING := 1
const BY_RECIPE_COLUMNS := [
	"Recipe",
	"Building",
	"Building Quantity",
	"Total Output",
	"Net Need",
]
const BY_RECIPE_COLUMN_MIN_WIDTHS := [
	200,
	180,
	130,
	110,
	100,
]
const BY_BUILDING_COLUMNS := [
	"Building",
	"Recipe",
	"Quantity",
]
const BY_BUILDING_COLUMN_MIN_WIDTHS := [
	220,
	240,
	100,
]
const WHAT_IF_PDF_FILE_NAME := "what_if_report.pdf"
const PDF_PAGE_WIDTH := 612
const PDF_PAGE_HEIGHT := 792
const PDF_TOP_Y := 760
const PDF_BOTTOM_Y := 40
const PDF_MARGIN_LEFT := 50
const PDF_DEFAULT_FONT_SIZE := 11
const PDF_DEFAULT_LINE_HEIGHT := 15
const PDF_TABLE_FONT_SIZE := 9
const PDF_TABLE_LINE_HEIGHT := 12
const V2_CHOICE_BUILDING_IDS := {
	"ExcavatorV2": &"ore_excavator_v2",
	"FabricatorV2": &"fabricator_v2",
	"FurnaceV2": &"furnace_v2",
	"CompounderV2": &"compounder_v2",
	"ConstructorizerV2": &"constructorizer_v2",
}

@onready var close_button: Button = _find_close_button()
@onready var recipe_button: MenuButton = get_node_or_null("Panel/Interaction Area/Recipe") as MenuButton
@onready var qty_textbox: LineEdit = get_node_or_null("Panel/Interaction Area/QtyTxtbox") as LineEdit
@onready var requirements_tree: Tree = _find_requirements_tree()
@onready var selector: TabBar = get_node_or_null("Panel/Output Reading/Selector") as TabBar
@onready var print_button: Button = _find_print_button()
@onready var generate_button: Button = _find_generate_button()

var selected_recipe: Recipe = null
var print_pdf_dialog: FileDialog = null
var generate_confirmation_dialog: ConfirmationDialog = null
var _available_recipes: Array[Recipe] = []
var _requirement_rows: Array[Dictionary] = []
var _v2_choice_buttons: Dictionary = {}
var _pending_pdf_bytes := PackedByteArray()
var _syncing_quantity_textbox := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_setup_close_button()
	_setup_recipe_button()
	_setup_quantity_textbox()
	_setup_v2_choice_buttons()
	_setup_print_button()
	_setup_generate_button()
	_setup_print_pdf_dialog()
	_setup_generate_confirmation_dialog()
	_setup_selector()
	_setup_requirements_tree()
	call_deferred("grab_focus")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


func _on_close_button_pressed() -> void:
	close_requested.emit()


func _setup_close_button() -> void:
	if close_button == null:
		push_warning("WhatIfMachine: CloseButton not found.")
	elif not close_button.pressed.is_connected(_on_close_button_pressed):
		close_button.pressed.connect(_on_close_button_pressed)


func _find_close_button() -> Button:
	var direct_button := get_node_or_null("Panel/HeaderBand/CloseButton") as Button
	if direct_button != null:
		return direct_button
	return find_child("CloseButton", true, false) as Button


func _find_requirements_tree() -> Tree:
	var direct_tree := get_node_or_null("Panel/Output Reading/RequirementsTree") as Tree
	if direct_tree != null:
		return direct_tree
	return get_node_or_null("Panel/Output Reading/ItemList") as Tree


func _find_print_button() -> Button:
	var output_panel_button := get_node_or_null("Panel/Output Reading/PrintButton") as Button
	if output_panel_button != null:
		return output_panel_button

	var panel_button := get_node_or_null("Panel/PrintButton") as Button
	if panel_button != null:
		return panel_button

	return find_child("PrintButton", true, false) as Button


func _find_generate_button() -> Button:
	var output_panel_button := get_node_or_null("Panel/Output Reading/GenerateButton") as Button
	if output_panel_button != null:
		return output_panel_button

	var panel_button := get_node_or_null("Panel/GenerateButton") as Button
	if panel_button != null:
		return panel_button

	return find_child("GenerateButton", true, false) as Button


func _setup_recipe_button() -> void:
	if recipe_button == null:
		push_warning("WhatIfMachine: Recipe button not found.")
		return

	var popup := recipe_button.get_popup()
	popup.max_size = RECIPE_POPUP_MAX_SIZE
	if not popup.about_to_popup.is_connected(_populate_recipe_popup):
		popup.about_to_popup.connect(_populate_recipe_popup)
	if not popup.index_pressed.is_connected(_on_recipe_popup_index_pressed):
		popup.index_pressed.connect(_on_recipe_popup_index_pressed)
	_populate_recipe_popup()


func _populate_recipe_popup() -> void:
	if recipe_button == null:
		return

	_available_recipes = _load_root_recipes()
	var popup := recipe_button.get_popup()
	popup.clear()
	popup.max_size = RECIPE_POPUP_MAX_SIZE

	if _available_recipes.is_empty():
		popup.add_item("No recipes found")
		popup.set_item_disabled(0, true)
		return

	for i in range(_available_recipes.size()):
		var recipe := _available_recipes[i]
		popup.add_item(_get_recipe_display_name(recipe), i)
		popup.set_item_metadata(i, recipe)


func _setup_quantity_textbox() -> void:
	if qty_textbox == null:
		push_warning("WhatIfMachine: QtyTxtbox not found.")
		return
	if not qty_textbox.text_changed.is_connected(_on_quantity_text_changed):
		qty_textbox.text_changed.connect(_on_quantity_text_changed)


func _setup_v2_choice_buttons() -> void:
	for button_name in V2_CHOICE_BUILDING_IDS.keys():
		var button := get_node_or_null("Panel/Interaction Area/%s" % button_name) as CheckButton
		if button == null:
			push_warning("WhatIfMachine: %s not found." % button_name)
			continue

		_v2_choice_buttons[button_name] = button
		if not button.toggled.is_connected(_on_v2_choice_toggled):
			button.toggled.connect(_on_v2_choice_toggled)


func _setup_print_button() -> void:
	if print_button == null:
		push_warning("WhatIfMachine: PrintButton not found.")
		return
	if not print_button.pressed.is_connected(_on_print_button_pressed):
		print_button.pressed.connect(_on_print_button_pressed)


func _setup_generate_button() -> void:
	if generate_button == null:
		push_warning("WhatIfMachine: GenerateButton not found.")
		return
	if not generate_button.pressed.is_connected(_on_generate_button_pressed):
		generate_button.pressed.connect(_on_generate_button_pressed)


func _setup_print_pdf_dialog() -> void:
	print_pdf_dialog = FileDialog.new()
	print_pdf_dialog.name = "WhatIfPdfDialog"
	print_pdf_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	print_pdf_dialog.access = FileDialog.ACCESS_FILESYSTEM
	print_pdf_dialog.title = "Export What If PDF"
	print_pdf_dialog.filters = PackedStringArray(["*.pdf ; PDF Document"])
	print_pdf_dialog.file_selected.connect(_on_print_pdf_file_selected)
	add_child(print_pdf_dialog)


func _setup_generate_confirmation_dialog() -> void:
	generate_confirmation_dialog = ConfirmationDialog.new()
	generate_confirmation_dialog.name = "GenerateConfirmationDialog"
	generate_confirmation_dialog.title = "Generate Plan"
	generate_confirmation_dialog.dialog_text = "Are you sure you'd like to leave the What If Scenario Analyzer?"
	generate_confirmation_dialog.exclusive = true
	generate_confirmation_dialog.confirmed.connect(_on_generate_confirmed)
	add_child(generate_confirmation_dialog)

	var yes_button := generate_confirmation_dialog.get_ok_button()
	if yes_button != null:
		yes_button.text = "Yes"

	var no_button := generate_confirmation_dialog.get_cancel_button()
	if no_button != null:
		no_button.text = "No"

	_style_generate_confirmation_dialog()


func _setup_requirements_tree() -> void:
	if requirements_tree == null:
		push_warning("WhatIfMachine: RequirementsTree not found.")
		return

	requirements_tree.set_anchors_preset(Control.PRESET_FULL_RECT)
	requirements_tree.offset_left = 8.0
	requirements_tree.offset_top = 8.0
	requirements_tree.offset_right = -8.0
	requirements_tree.offset_bottom = -8.0
	requirements_tree.hide_root = true
	requirements_tree.column_titles_visible = true
	_render_requirement_list()


func _style_generate_confirmation_dialog() -> void:
	if generate_confirmation_dialog == null:
		return

	generate_confirmation_dialog.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	generate_confirmation_dialog.add_theme_color_override("title_color", Palette.TEXT_PRIMARY)
	generate_confirmation_dialog.add_theme_stylebox_override("panel", Palette.make_panel_style(Palette.SCENE_PANEL_FILL, Palette.SCENE_PANEL_BORDER, 8, 2))
	_style_dialog_button(generate_confirmation_dialog.get_ok_button())
	_style_dialog_button(generate_confirmation_dialog.get_cancel_button())


func _style_dialog_button(button: Button) -> void:
	if button == null:
		return
	button.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	button.add_theme_color_override("font_disabled_color", Palette.TEXT_MUTED)
	button.add_theme_stylebox_override("normal", Palette.make_button_style(Palette.BUTTON_FILL, 6, 1))
	button.add_theme_stylebox_override("hover", Palette.make_button_style(Palette.BUTTON_HOVER, 6, 1))
	button.add_theme_stylebox_override("pressed", Palette.make_button_style(Palette.BUTTON_PRESSED, 6, 1))
	button.add_theme_stylebox_override("focus", Palette.make_button_style(Palette.BUTTON_HOVER, 6, 1))


func _setup_selector() -> void:
	if selector == null:
		push_warning("WhatIfMachine: Selector TabBar not found.")
		return

	selector.clear_tabs()
	selector.add_tab("By Recipe")
	selector.add_tab("By Building")
	selector.current_tab = TAB_BY_RECIPE
	if not selector.tab_changed.is_connected(_on_selector_tab_changed):
		selector.tab_changed.connect(_on_selector_tab_changed)


func _load_root_recipes() -> Array[Recipe]:
	var registry_recipes := _load_root_recipes_from_registry()
	if not registry_recipes.is_empty():
		return registry_recipes

	var recipes: Array[Recipe] = []
	var dir := DirAccess.open(RECIPES_ROOT)
	if dir == null:
		push_warning("WhatIfMachine: Could not open %s." % RECIPES_ROOT)
		return recipes

	var file_names := dir.get_files()
	file_names.sort()
	for file_name in file_names:
		if file_name.get_extension().to_lower() != "tres":
			continue

		var recipe := load(RECIPES_ROOT.path_join(file_name)) as Recipe
		if recipe == null:
			continue
		recipes.append(recipe)

	recipes.sort_custom(func(a: Recipe, b: Recipe) -> bool:
		return _get_recipe_display_name(a).nocasecmp_to(_get_recipe_display_name(b)) < 0
	)
	return recipes


func _load_root_recipes_from_registry() -> Array[Recipe]:
	var registry := get_node_or_null("/root/RecipeRegistry")
	if registry == null or not registry.has_method("get_root_recipes"):
		return []

	var loaded_recipes = registry.call("get_root_recipes")
	if not (loaded_recipes is Array):
		return []

	var recipes: Array[Recipe] = []
	for loaded_recipe in loaded_recipes:
		var recipe := loaded_recipe as Recipe
		if recipe != null:
			recipes.append(recipe)
	return recipes


func _on_recipe_popup_index_pressed(index: int) -> void:
	if recipe_button == null:
		return

	var popup := recipe_button.get_popup()
	if index < 0 or index >= popup.item_count:
		return

	var recipe := popup.get_item_metadata(index) as Recipe
	if recipe == null:
		return

	selected_recipe = recipe
	recipe_button.text = _get_recipe_display_name(recipe)
	_update_quantity_textbox(recipe)
	_refresh_requirement_list()


func _get_recipe_display_name(recipe: Recipe) -> String:
	var registry := _get_recipe_registry()
	if registry != null and registry.has_method("get_recipe_display_name"):
		return String(registry.call("get_recipe_display_name", recipe, true))

	if recipe == null:
		return ""
	var suffix := " V2" if _is_v2_recipe(recipe) else ""
	if recipe.display_name.strip_edges() != "":
		return recipe.display_name + suffix
	if String(recipe.id).strip_edges() != "":
		return String(recipe.id) + suffix
	return recipe.resource_path.get_file().get_basename().replace("_", " ")


func _update_quantity_textbox(recipe: Recipe) -> void:
	if qty_textbox == null:
		return

	_syncing_quantity_textbox = true
	if recipe == null or recipe.outputs.is_empty() or recipe.outputs[0] == null:
		qty_textbox.text = ""
		_syncing_quantity_textbox = false
		return

	qty_textbox.text = str(recipe.outputs[0].qty)
	_syncing_quantity_textbox = false


func _on_quantity_text_changed(_new_text: String) -> void:
	if _syncing_quantity_textbox:
		return
	_refresh_requirement_list()


func _on_v2_choice_toggled(_pressed: bool) -> void:
	_refresh_requirement_list()


func _on_selector_tab_changed(_tab: int) -> void:
	_render_requirement_list()


func _on_print_button_pressed() -> void:
	_refresh_requirement_list()
	_pending_pdf_bytes = _build_what_if_pdf_bytes()

	if OS.has_feature("web") and JavaScriptBridge != null:
		JavaScriptBridge.download_buffer(_pending_pdf_bytes, WHAT_IF_PDF_FILE_NAME, "application/pdf")
		return

	if print_pdf_dialog == null:
		push_warning("WhatIfMachine: PDF save dialog is not available.")
		return

	print_pdf_dialog.current_file = WHAT_IF_PDF_FILE_NAME
	print_pdf_dialog.popup_centered_ratio(0.7)


func _on_print_pdf_file_selected(path: String) -> void:
	if _pending_pdf_bytes.is_empty():
		_pending_pdf_bytes = _build_what_if_pdf_bytes()

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("WhatIfMachine: Failed to export PDF file to %s." % path)
		return
	file.store_buffer(_pending_pdf_bytes)


func _on_generate_button_pressed() -> void:
	_refresh_requirement_list()
	if selected_recipe == null:
		push_warning("WhatIfMachine: Choose a recipe before generating a plan.")
		return
	if _get_requested_quantity() <= 0.0:
		push_warning("WhatIfMachine: Enter a quantity greater than zero before generating a plan.")
		return

	if generate_confirmation_dialog == null:
		_on_generate_confirmed()
		return

	generate_confirmation_dialog.popup_centered(Vector2i(470, 150))


func _on_generate_confirmed() -> void:
	generate_requested.emit({
		"target_recipe": selected_recipe,
		"target_qty": _get_requested_quantity(),
		"enabled_v2_building_ids": _get_enabled_v2_building_ids(),
	})


func _refresh_requirement_list() -> void:
	_requirement_rows.clear()

	if selected_recipe == null:
		_render_requirement_list()
		return

	var requested_qty := _get_requested_quantity()
	if requested_qty <= 0.0:
		_render_requirement_list()
		return

	var registry := _get_recipe_registry()
	if registry == null:
		push_warning("WhatIfMachine: RecipeRegistry not available.")
		_render_requirement_list()
		return

	_requirement_rows = _build_requirement_rows(selected_recipe, requested_qty, registry)
	_render_requirement_list()


func _build_requirement_rows(target_recipe: Recipe, target_qty: float, registry: Node) -> Array[Dictionary]:
	var rows_by_key: Dictionary = {}
	var row_order: Array[String] = []
	var required_qty_by_key: Dictionary = {}
	var current_requirements: Dictionary = {}
	var expanded_building_counts: Dictionary = {}
	_merge_recipe_requirement(current_requirements, target_recipe, target_qty)

	for _depth in range(MAX_DEPENDENCY_DEPTH):
		if current_requirements.is_empty():
			break

		var next_requirements: Dictionary = {}
		for key in current_requirements.keys():
			var requirement: Dictionary = current_requirements[key]
			var recipe := requirement.get("recipe") as Recipe
			var required_qty := float(requirement.get("required_qty", 0.0))
			if recipe == null or required_qty <= 0.0:
				continue

			if not required_qty_by_key.has(key):
				required_qty_by_key[key] = 0.0
				row_order.append(key)
			required_qty_by_key[key] = float(required_qty_by_key[key]) + required_qty

			var row := _build_requirement_row(recipe, float(required_qty_by_key[key]), registry)
			rows_by_key[key] = row

			var building_count := int(row.get("building_count", 0))
			var expanded_count := int(expanded_building_counts.get(key, 0))
			var new_building_count := building_count - expanded_count
			if new_building_count <= 0:
				continue
			expanded_building_counts[key] = building_count

			for input_stack in recipe.inputs:
				if input_stack == null:
					continue

				var input_recipe := _get_best_recipe_for_output_id(registry, _get_stack_id(input_stack))
				if input_recipe == null:
					continue

				_merge_recipe_requirement(
					next_requirements,
					input_recipe,
					float(input_stack.qty) * float(new_building_count)
				)

		current_requirements = next_requirements

	var rows: Array[Dictionary] = []
	for key in row_order:
		if rows_by_key.has(key):
			rows.append(rows_by_key[key])
	return rows


func _build_requirement_row(recipe: Recipe, required_qty: float, registry: Node) -> Dictionary:
	var output_qty := _get_recipe_output_qty(recipe, registry)
	var building_count := 0
	if output_qty > 0.0:
		building_count = int(ceil(required_qty / output_qty))
	var total_output := float(building_count) * output_qty

	return {
		"recipe_name": _get_recipe_display_name(recipe),
		"building_name": _get_recipe_building_display_name(recipe, registry),
		"building_count": building_count,
		"total_output": total_output,
		"net_need": maxf(total_output - required_qty, 0.0),
	}


func _merge_recipe_requirement(requirements: Dictionary, recipe: Recipe, required_qty: float) -> void:
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


func _get_best_recipe_for_output_id(registry: Node, output_id: StringName) -> Recipe:
	if registry == null or output_id == StringName(""):
		return null
	if not registry.has_method("get_best_recipe_for_output_id"):
		return null

	return registry.call("get_best_recipe_for_output_id", output_id, _get_enabled_v2_building_ids()) as Recipe


func _get_enabled_v2_building_ids() -> Dictionary:
	var enabled_ids := {}
	for button_name in _v2_choice_buttons.keys():
		var button := _v2_choice_buttons[button_name] as CheckButton
		if button != null and button.button_pressed:
			enabled_ids[V2_CHOICE_BUILDING_IDS[button_name]] = true
	return enabled_ids


func _get_requested_quantity() -> float:
	if qty_textbox == null:
		return 0.0

	var raw_value := qty_textbox.text.strip_edges()
	if raw_value == "" or not raw_value.is_valid_float():
		return 0.0
	return maxf(raw_value.to_float(), 0.0)


func _render_requirement_list() -> void:
	if requirements_tree == null:
		return

	if _get_selected_tab() == TAB_BY_BUILDING:
		_render_by_building_tree()
	else:
		_render_by_recipe_tree()


func _render_by_recipe_tree() -> void:
	var root := _configure_requirements_tree(BY_RECIPE_COLUMNS, BY_RECIPE_COLUMN_MIN_WIDTHS)
	requirements_tree.hide_folding = true

	for row in _requirement_rows:
		_add_tree_row(root, [
			String(row.get("recipe_name", "")),
			String(row.get("building_name", "")),
			_format_quantity(float(row.get("building_count", 0))),
			_format_quantity(float(row.get("total_output", 0.0))),
			_format_quantity(float(row.get("net_need", 0.0))),
		])


func _render_by_building_tree() -> void:
	var root := _configure_requirements_tree(BY_BUILDING_COLUMNS, BY_BUILDING_COLUMN_MIN_WIDTHS)
	requirements_tree.hide_folding = false

	var grouped_rows := _group_requirement_rows_by_building()
	for group in grouped_rows:
		var group_item := _add_tree_row(root, [
			String(group.get("building_name", "")),
			_format_quantity(float(group.get("building_count", 0.0))),
		], {
			1: 2,
		})
		group_item.collapsed = false

		var recipes: Array = group.get("recipes", [])
		for recipe_row_variant in recipes:
			var recipe_row: Dictionary = recipe_row_variant
			_add_tree_row(group_item, [
				String(recipe_row.get("recipe_name", "")),
				_format_quantity(float(recipe_row.get("building_count", 0.0))),
			], {
				0: 1,
				1: 2,
			})


func _configure_requirements_tree(column_titles: Array, column_min_widths: Array) -> TreeItem:
	requirements_tree.clear()
	requirements_tree.columns = column_titles.size()
	requirements_tree.hide_root = true
	requirements_tree.column_titles_visible = true

	for column in range(column_titles.size()):
		requirements_tree.set_column_title(column, String(column_titles[column]))
		requirements_tree.set_column_expand(column, true)
		if column < column_min_widths.size():
			requirements_tree.set_column_custom_minimum_width(column, int(column_min_widths[column]))

	return requirements_tree.create_item()


func _add_tree_row(parent: TreeItem, values: Array, column_map := {}) -> TreeItem:
	var item := requirements_tree.create_item(parent)
	for value_index in range(values.size()):
		var column := int(column_map.get(value_index, value_index))
		if column < 0 or column >= requirements_tree.columns:
			continue
		item.set_text(column, String(values[value_index]))

	for column in range(requirements_tree.columns):
		item.set_selectable(column, false)
	return item


func _group_requirement_rows_by_building() -> Array[Dictionary]:
	var group_order: Array[String] = []
	var groups := {}

	for row in _requirement_rows:
		var building_name := String(row.get("building_name", "Unknown"))
		if not groups.has(building_name):
			groups[building_name] = {
				"building_name": building_name,
				"building_count": 0.0,
				"recipes": [],
			}
			group_order.append(building_name)

		var group: Dictionary = groups[building_name]
		var building_count := float(row.get("building_count", 0.0))
		group["building_count"] = float(group.get("building_count", 0.0)) + building_count
		var recipes: Array = group.get("recipes", [])
		recipes.append({
			"recipe_name": String(row.get("recipe_name", "")),
			"building_count": building_count,
		})

	var grouped_rows: Array[Dictionary] = []
	for building_name in group_order:
		grouped_rows.append(groups[building_name])
	return grouped_rows


func _get_selected_tab() -> int:
	if selector == null:
		return TAB_BY_RECIPE
	return selector.current_tab


func _build_what_if_pdf_bytes() -> PackedByteArray:
	var lines := _build_what_if_pdf_lines()
	return _build_pdf_bytes_from_lines(lines)


func _build_what_if_pdf_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	_append_pdf_line(lines, "Star Rupture Build Planner", "F1", 18, 24)
	_append_pdf_line(lines, "What If Machine Report", "F1", 14, 20)
	_append_pdf_line(lines, "Generated: %s" % Time.get_datetime_string_from_system(), "F1", 10, 16)
	_append_pdf_blank_line(lines, 8)

	var recipe_name := "No recipe selected"
	if selected_recipe != null:
		recipe_name = _get_recipe_display_name(selected_recipe)
	_append_pdf_line(lines, "Target Recipe: %s" % recipe_name)
	_append_pdf_line(lines, "Quantity/Minute: %s" % _format_quantity(_get_requested_quantity()))
	_append_pdf_line(lines, "V2 Buildings: %s" % _format_enabled_v2_choices())
	_append_pdf_blank_line(lines, 12)

	_append_by_building_pdf_section(lines)
	_append_pdf_blank_line(lines, 14)
	_append_by_recipe_pdf_section(lines)
	return lines


func _append_by_building_pdf_section(lines: Array[Dictionary]) -> void:
	_append_pdf_line(lines, "By Building", "F1", 14, 20)
	if _requirement_rows.is_empty():
		_append_pdf_line(lines, "No requirements calculated.")
		return

	var widths := [24, 28, 8]
	_append_pdf_table_header(lines, BY_BUILDING_COLUMNS, widths)
	for group in _group_requirement_rows_by_building():
		_append_pdf_table_row(lines, [
			String(group.get("building_name", "")),
			"",
			_format_quantity(float(group.get("building_count", 0.0))),
		], widths)

		var recipes: Array = group.get("recipes", [])
		for recipe_row_variant in recipes:
			var recipe_row: Dictionary = recipe_row_variant
			_append_pdf_table_row(lines, [
				"",
				String(recipe_row.get("recipe_name", "")),
				_format_quantity(float(recipe_row.get("building_count", 0.0))),
			], widths)


func _append_by_recipe_pdf_section(lines: Array[Dictionary]) -> void:
	_append_pdf_line(lines, "By Recipe", "F1", 14, 20)
	if _requirement_rows.is_empty():
		_append_pdf_line(lines, "No requirements calculated.")
		return

	var widths := [21, 18, 12, 12, 9]
	_append_pdf_table_header(lines, BY_RECIPE_COLUMNS, widths)
	for row in _requirement_rows:
		_append_pdf_table_row(lines, [
			String(row.get("recipe_name", "")),
			String(row.get("building_name", "")),
			_format_quantity(float(row.get("building_count", 0.0))),
			_format_quantity(float(row.get("total_output", 0.0))),
			_format_quantity(float(row.get("net_need", 0.0))),
		], widths)


func _append_pdf_table_header(lines: Array[Dictionary], columns: Array, widths: Array) -> void:
	_append_pdf_table_row(lines, columns, widths)
	var separators: Array[String] = []
	for width in widths:
		separators.append(_repeat_text("-", int(width)))
	_append_pdf_table_row(lines, separators, widths)


func _append_pdf_table_row(lines: Array[Dictionary], values: Array, widths: Array) -> void:
	_append_pdf_line(lines, _format_pdf_table_row(values, widths), "F2", PDF_TABLE_FONT_SIZE, PDF_TABLE_LINE_HEIGHT)


func _append_pdf_line(
	lines: Array[Dictionary],
	text: String,
	font: String = "F1",
	font_size: int = PDF_DEFAULT_FONT_SIZE,
	line_height: int = PDF_DEFAULT_LINE_HEIGHT
) -> void:
	lines.append({
		"text": text,
		"font": font,
		"font_size": font_size,
		"line_height": line_height,
	})


func _append_pdf_blank_line(lines: Array[Dictionary], line_height: int = PDF_DEFAULT_LINE_HEIGHT) -> void:
	_append_pdf_line(lines, "", "F1", PDF_DEFAULT_FONT_SIZE, line_height)


func _format_pdf_table_row(values: Array, widths: Array) -> String:
	var cells: Array[String] = []
	for i in range(widths.size()):
		var value := ""
		if i < values.size():
			value = String(values[i])
		cells.append(_fit_pdf_cell(value, int(widths[i])))
	return " | ".join(cells)


func _fit_pdf_cell(value: String, width: int) -> String:
	var text := value.strip_edges()
	if width <= 0:
		return ""
	if text.length() > width:
		text = text.substr(0, max(0, width - 1)) + "."
	return text + _repeat_text(" ", width - text.length())


func _repeat_text(value: String, count: int) -> String:
	var result := ""
	for _i in range(max(0, count)):
		result += value
	return result


func _format_enabled_v2_choices() -> String:
	var labels: Array[String] = []
	for button_name in _v2_choice_buttons.keys():
		var button := _v2_choice_buttons[button_name] as CheckButton
		if button != null and button.button_pressed:
			labels.append(button.text)
	if labels.is_empty():
		return "None"
	return ", ".join(labels)


func _build_pdf_bytes_from_lines(lines: Array[Dictionary]) -> PackedByteArray:
	var pages := _paginate_pdf_lines(lines)
	var kids: Array[String] = []
	for page_index in range(pages.size()):
		kids.append("%d 0 R" % (5 + (page_index * 2)))

	var objects: Array[String] = []
	objects.append("1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj")
	objects.append("2 0 obj << /Type /Pages /Kids [%s] /Count %d >> endobj" % [" ".join(kids), pages.size()])
	objects.append("3 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj")
	objects.append("4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Courier >> endobj")

	for page_index in range(pages.size()):
		var page_object := 5 + (page_index * 2)
		var content_object := page_object + 1
		var content := _build_pdf_page_content(pages[page_index])
		objects.append("%d 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents %d 0 R >> endobj" % [
			page_object,
			PDF_PAGE_WIDTH,
			PDF_PAGE_HEIGHT,
			content_object,
		])
		objects.append("%d 0 obj << /Length %d >> stream\n%s\nendstream endobj" % [
			content_object,
			content.to_utf8_buffer().size(),
			content,
		])

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


func _paginate_pdf_lines(lines: Array[Dictionary]) -> Array:
	var pages: Array = []
	var page_lines: Array[Dictionary] = []
	var y := PDF_TOP_Y

	for line in lines:
		var line_height := int(line.get("line_height", PDF_DEFAULT_LINE_HEIGHT))
		if not page_lines.is_empty() and y - line_height < PDF_BOTTOM_Y:
			pages.append(page_lines)
			page_lines = []
			y = PDF_TOP_Y

		var page_line := line.duplicate()
		page_line["y"] = y
		page_lines.append(page_line)
		y -= line_height

	if page_lines.is_empty():
		_append_pdf_line(page_lines, "")
	pages.append(page_lines)
	return pages


func _build_pdf_page_content(page_lines: Array) -> String:
	var commands: Array[String] = []
	for line_variant in page_lines:
		var line: Dictionary = line_variant
		var font_name := String(line.get("font", "F1"))
		var font_size := int(line.get("font_size", PDF_DEFAULT_FONT_SIZE))
		var y := int(line.get("y", PDF_TOP_Y))
		var text := _pdf_escape_text(String(line.get("text", "")))
		commands.append("BT /%s %d Tf %d %d Td (%s) Tj ET" % [
			font_name,
			font_size,
			PDF_MARGIN_LEFT,
			y,
			text,
		])
	return "\n".join(commands)


func _pdf_escape_text(value: String) -> String:
	return value.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


func _format_quantity(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.2f" % value


func _get_recipe_registry() -> Node:
	return get_node_or_null("/root/RecipeRegistry")


func _get_recipe_building_display_name(recipe: Recipe, registry: Node) -> String:
	if registry != null and registry.has_method("get_recipe_building_display_name"):
		return String(registry.call("get_recipe_building_display_name", recipe))
	return "Unknown"


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


func _is_v2_recipe(recipe: Recipe) -> bool:
	if recipe == null:
		return false
	return recipe.resource_path.get_file().get_basename().to_lower().ends_with("_v2")
