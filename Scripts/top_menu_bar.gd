extends PanelContainer

class_name TopMenuBar

signal command_requested(command_id: StringName)

const Palette = preload("res://Scripts/palette.gd")
const UiScale = preload("res://Scripts/ui_scale.gd")

const BAR_HEIGHT := 36.0
const CONTENT_MARGIN_X := 8
const CONTENT_MARGIN_Y := 4
const SECTION_BUTTON_MIN_WIDTH := 68.0
const SECTION_BUTTON_HEIGHT := 28.0
const SECTION_GAP := 4

var _items_by_command: Dictionary = {}
var _section_buttons: Array[MenuButton] = []
var _sections: Array = []
var _ui_scale := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0.0, _bar_height())
	_apply_panel_style()


func set_ui_scale(ui_scale: float) -> void:
	if is_equal_approx(_ui_scale, ui_scale):
		return
	_ui_scale = maxf(ui_scale, 0.001)
	custom_minimum_size = Vector2(0.0, _bar_height())
	_apply_panel_style()
	if not _sections.is_empty():
		_rebuild_sections()


func configure_sections(sections: Array) -> void:
	_sections = sections.duplicate(true)
	_rebuild_sections()


func _rebuild_sections() -> void:
	_items_by_command.clear()
	_section_buttons.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var margin := MarginContainer.new()
	margin.name = "ContentMargin"
	margin.add_theme_constant_override("margin_left", _scaled_int(CONTENT_MARGIN_X))
	margin.add_theme_constant_override("margin_top", _scaled_int(CONTENT_MARGIN_Y))
	margin.add_theme_constant_override("margin_right", _scaled_int(CONTENT_MARGIN_X))
	margin.add_theme_constant_override("margin_bottom", _scaled_int(CONTENT_MARGIN_Y))
	add_child(margin)

	var row := HBoxContainer.new()
	row.name = "MenuSections"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", _scaled_int(SECTION_GAP))
	margin.add_child(row)

	for section in _sections:
		if not (section is Dictionary):
			continue
		row.add_child(_make_section_button(section))


func set_command_enabled(command_id: StringName, enabled: bool) -> void:
	var item = _items_by_command.get(command_id, null)
	if not (item is Dictionary):
		return
	var popup := item.get("popup") as PopupMenu
	var index := int(item.get("index", -1))
	if popup == null or index < 0 or index >= popup.item_count:
		return
	popup.set_item_disabled(index, not enabled)


func set_command_pressed(command_id: StringName, pressed: bool) -> void:
	var item = _items_by_command.get(command_id, null)
	if not (item is Dictionary):
		return
	var popup := item.get("popup") as PopupMenu
	var index := int(item.get("index", -1))
	if popup == null or index < 0 or index >= popup.item_count:
		return
	popup.set_item_checked(index, pressed)


func get_preferred_size() -> Vector2:
	var width := float(_scaled(CONTENT_MARGIN_X * 2.0))
	for i in range(_section_buttons.size()):
		var button := _section_buttons[i]
		if button != null:
			width += max(_scaled(SECTION_BUTTON_MIN_WIDTH), button.get_combined_minimum_size().x)
	if _section_buttons.size() > 1:
		width += float(_scaled(SECTION_GAP) * (_section_buttons.size() - 1))
	return Vector2(width, _bar_height())


func get_command_global_rect(command_id: StringName) -> Rect2:
	var item = _items_by_command.get(command_id, null)
	if item is Dictionary:
		var button := item.get("section_button") as MenuButton
		if button != null:
			return button.get_global_rect()
	return get_global_rect()


func _make_section_button(section: Dictionary) -> MenuButton:
	var button := MenuButton.new()
	button.name = _safe_node_name(str(section.get("title", "Menu")))
	button.text = str(section.get("title", "Menu"))
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(_scaled(SECTION_BUTTON_MIN_WIDTH), _scaled(SECTION_BUTTON_HEIGHT))
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_section_button(button)
	_configure_section_popup(button, section.get("commands", []))
	_section_buttons.append(button)
	return button


func _configure_section_popup(button: MenuButton, commands) -> void:
	var popup := button.get_popup()
	popup.clear()
	popup.id_pressed.connect(_on_popup_id_pressed.bind(popup))
	_style_popup(popup)

	if not (commands is Array):
		return

	for command in commands:
		if not (command is Dictionary):
			continue
		var index := popup.item_count
		var label := str(command.get("label", command.get("id", "")))
		var command_id := StringName(command.get("id", ""))
		popup.add_check_item(label, index) if bool(command.get("toggle", false)) else popup.add_item(label, index)
		popup.set_item_metadata(index, command_id)
		popup.set_item_tooltip(index, str(command.get("tooltip", "")))
		_items_by_command[command_id] = {
			"popup": popup,
			"index": index,
			"section_button": button,
		}


func _on_popup_id_pressed(id: int, popup: PopupMenu) -> void:
	var item_index := popup.get_item_index(id)
	if item_index < 0:
		return
	var metadata = popup.get_item_metadata(item_index)
	if metadata == null:
		return
	command_requested.emit(StringName(metadata))


func _apply_panel_style() -> void:
	var style := Palette.make_panel_style(Palette.SCENE_PANEL_FILL, Palette.SCENE_PANEL_BORDER, _scaled_int(6), _scaled_int(1))
	style.shadow_size = _scaled_int(4)
	style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", style)


func _style_section_button(button: MenuButton) -> void:
	var empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("disabled", empty)
	button.add_theme_stylebox_override("hover", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(4), _scaled_int(1)))
	button.add_theme_stylebox_override("pressed", Palette.make_button_style(Palette.BUTTON_PRESSED, _scaled_int(4), _scaled_int(1)))
	button.add_theme_stylebox_override("focus", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(4), _scaled_int(1)))
	button.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", Palette.TEXT_PRIMARY)
	button.add_theme_color_override("font_pressed_color", Palette.TEXT_PRIMARY)
	button.add_theme_color_override("font_disabled_color", Palette.TEXT_MUTED)
	button.add_theme_font_size_override("font_size", UiScale.font_size(13, _ui_scale))


func _style_popup(popup: PopupMenu) -> void:
	popup.add_theme_stylebox_override("panel", Palette.make_panel_style(Palette.SCENE_PANEL_FILL, Palette.SCENE_PANEL_BORDER, _scaled_int(6), _scaled_int(1)))
	popup.add_theme_stylebox_override("hover", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(4), _scaled_int(1)))
	popup.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	popup.add_theme_color_override("font_hover_color", Palette.TEXT_PRIMARY)
	popup.add_theme_color_override("font_disabled_color", Palette.TEXT_MUTED)
	popup.add_theme_font_size_override("font_size", UiScale.font_size(12, _ui_scale))
	popup.add_theme_constant_override("v_separation", _scaled_int(4))
	popup.add_theme_constant_override("item_start_padding", _scaled_int(12))
	popup.add_theme_constant_override("item_end_padding", _scaled_int(16))


func _bar_height() -> float:
	return _scaled(BAR_HEIGHT)


func _scaled(value: float) -> float:
	return UiScale.scaled(value, _ui_scale)


func _scaled_int(value: float) -> int:
	return UiScale.scaled_int(value, _ui_scale)


func _safe_node_name(raw_name: String) -> String:
	var cleaned := raw_name.replace(".", "_").replace(" ", "_").replace("/", "_")
	return cleaned if cleaned != "" else "Menu"
