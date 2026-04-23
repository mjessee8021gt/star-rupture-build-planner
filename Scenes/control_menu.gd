extends MenuButton

const Palette = preload("res://Scripts/palette.gd")
const UiScale = preload("res://Scripts/ui_scale.gd")
const BINDINGS_CONFIG_SECTION := "input_bindings"
const BINDINGS_METADATA_SECTION := "input_bindings_metadata"
const BINDINGS_VERSION_KEY := "version"
const BINDINGS_CONFIG_VERSION := 2
const BUILD_CANCEL_ACTION := &"Build Cancel"
const REBIND_PROMPT := "Press input..."
const UNBOUND_TEXT := "-"
const POPUP_BASE_SIZE := Vector2i(460, 250)
const POPUP_MIN_SIZE := Vector2i(300, 190)
const POPUP_VIEWPORT_MARGIN := 12
const POPUP_BUTTON_OFFSET := Vector2i(50, 8)
const POPUP_MAX_WIDTH := 560
const POPUP_SCREEN_WIDTH_RATIO := 0.36
const POPUP_SCREEN_HEIGHT_RATIO := 0.45
const POPUP_CONTENT_MARGIN := 10.0
const POPUP_SCROLLBAR_RESERVE := 18.0
const ROW_HEIGHT := 28.0
const ROW_COLUMN_GAP := 12
const BINDING_COLUMN_MIN_WIDTH := 130.0
const BINDING_COLUMN_MAX_WIDTH := 220.0
const BINDING_COLUMN_WIDTH_RATIO := 0.48

##------OnReady variables------##
@onready var popup: PopupPanel = get_node(popup_path)
@onready var list_vbox: VBoxContainer = get_node(list_path)

##------Exported Variables-----##
@export var popup_path: NodePath
@export var list_path: NodePath
@export var hide_prefixes: Array[String] = ["ui_", "Show"]
@export var show_only_prefixes: Array[String] = []
@export var bindings_save_path := "user://input_bindings.cfg"

##------Object Variables-------##
var _awaiting_action := ""
var _awaiting_button: Button = null
var _capture_overlay: Control = null
var _popup_anchor_override := Rect2()
var _ui_scale := 1.0

func _ready() -> void:
	pressed.connect(toggle_panel)
	if popup != null and not popup.popup_hide.is_connected(_on_popup_hidden):
		popup.popup_hide.connect(_on_popup_hidden)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_ensure_capture_overlay()
	_load_saved_bindings()
	popup.hide()

func set_ui_scale(ui_scale: float) -> void:
	_ui_scale = maxf(ui_scale, 0.001)
	_layout_capture_overlay()
	if popup != null and popup.visible:
		_layout_popup()
		if _awaiting_action == "":
			_refresh_list()

func toggle_panel() -> void:
	if popup.visible:
		_cancel_pending_rebind()
		popup.hide()
		_popup_anchor_override = Rect2()
		return

	_layout_popup()
	_refresh_list()
	popup.popup()


func toggle_panel_at(anchor_rect: Rect2) -> void:
	_popup_anchor_override = anchor_rect
	toggle_panel()


func _on_pressed() -> void:
	toggle_panel()

func _on_viewport_size_changed() -> void:
	if popup != null and popup.visible:
		call_deferred("_layout_open_popup")

func _layout_open_popup() -> void:
	_layout_popup()
	if _awaiting_action == "":
		_refresh_list()

func _layout_popup() -> void:
	if popup == null:
		return

	var popup_size := _get_popup_size()
	popup.min_size = Vector2i.ZERO
	popup.size = popup_size
	_layout_popup_contents(popup_size)
	_position_popup(popup_size)

func _get_popup_size() -> Vector2i:
	var viewport_size = get_viewport().size
	var viewport_margin := _scaled_int(POPUP_VIEWPORT_MARGIN)
	var available_width = max(viewport_size.x - (viewport_margin * 2), 1)
	var available_height = max(viewport_size.y - (viewport_margin * 2), 1)
	var base_size := _scaled_vec2i(POPUP_BASE_SIZE)
	var min_size := _scaled_vec2i(POPUP_MIN_SIZE)
	var max_width := _scaled_int(POPUP_MAX_WIDTH)
	var target_width = min(min(max(base_size.x, int(viewport_size.x * POPUP_SCREEN_WIDTH_RATIO)), max_width), available_width)
	var target_height = min(max(base_size.y, int(viewport_size.y * POPUP_SCREEN_HEIGHT_RATIO)), available_height)
	target_width = max(min(min_size.x, available_width), target_width)
	target_height = max(min(min_size.y, available_height), target_height)
	return Vector2i(target_width, target_height)

func _layout_popup_contents(popup_size: Vector2i) -> void:
	var margin_container := popup.get_node_or_null("MarginContainer") as MarginContainer
	if margin_container == null:
		return

	margin_container.custom_minimum_size = Vector2.ZERO
	var content_margin := _scaled(POPUP_CONTENT_MARGIN)
	margin_container.position = Vector2(content_margin, content_margin)
	margin_container.size = Vector2(
		max(popup_size.x - (content_margin * 2.0), 1.0),
		max(popup_size.y - (content_margin * 2.0), 1.0)
	)

	var scroll_container := margin_container.get_node_or_null("ScrollContainer") as ScrollContainer
	if scroll_container != null:
		scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if list_vbox != null:
		list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_vbox.add_theme_constant_override("separation", _scaled_int(4))
		list_vbox.custom_minimum_size.x = _get_current_content_width()

func _position_popup(popup_size: Vector2i) -> void:
	var rect := _popup_anchor_override
	if rect.size == Vector2.ZERO:
		rect = get_global_rect()
	var viewport_size = get_viewport().size
	var popup_offset := _scaled_vec2i(POPUP_BUTTON_OFFSET)
	var viewport_margin := _scaled_int(POPUP_VIEWPORT_MARGIN)
	var preferred_x := int(rect.position.x) + popup_offset.x
	var preferred_y := int(rect.position.y) - popup_size.y - popup_offset.y
	var max_x = max(viewport_margin, viewport_size.x - popup_size.x - viewport_margin)
	var max_y = max(viewport_margin, viewport_size.y - popup_size.y - viewport_margin)
	var x = clampi(preferred_x, viewport_margin, max_x)
	var y = clampi(preferred_y, viewport_margin, max_y)
	popup.position = Vector2i(x, y)

func _refresh_list() -> void:
	for child in list_vbox.get_children():
		child.queue_free()

	var actions := InputMap.get_actions()
	actions.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a).naturalnocasecmp_to(String(b)) < 0
	)

	for action_name in actions:
		var action_text := String(action_name)
		if _starts_with_any_prefix(action_text, hide_prefixes):
			continue
		if not show_only_prefixes.is_empty() and not _starts_with_any_prefix(action_text, show_only_prefixes):
			continue

		var events := InputMap.action_get_events(action_name)
		list_vbox.add_child(_make_row(action_text, _events_to_string(events)))

func _starts_with_any_prefix(value: String, prefixes: Array[String]) -> bool:
	for prefix in prefixes:
		if value.begins_with(prefix):
			return true
	return false

func _make_row(action_name: String, bindings: String) -> Control:
	var row := HBoxContainer.new()
	var left := Label.new()
	var right := Button.new()
	var row_width := _get_current_content_width()
	var binding_width := _get_binding_column_width(row_width)
	var row_gap := _scaled(ROW_COLUMN_GAP)
	var row_height := _scaled(ROW_HEIGHT)
	var action_width = max(row_width - binding_width - row_gap, _scaled(90.0))

	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(row_width, row_height)
	row.add_theme_constant_override("separation", _scaled_int(ROW_COLUMN_GAP))

	left.text = action_name
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size = Vector2(action_width, row_height)
	left.clip_text = true
	left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	left.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	UiScale.apply_font_size(left, &"font_size", 16, _ui_scale, true)

	right.text = bindings
	right.alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.clip_text = true
	right.custom_minimum_size = Vector2(binding_width, row_height)
	right.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	right.add_theme_color_override("font_hover_color", Palette.TEXT_PRIMARY)
	right.add_theme_color_override("font_pressed_color", Palette.TEXT_PRIMARY)
	UiScale.apply_font_size(right, &"font_size", 16, _ui_scale, true)
	right.add_theme_stylebox_override("normal", Palette.make_button_style(Palette.BUTTON_FILL, _scaled_int(8), _scaled_int(1)))
	right.add_theme_stylebox_override("hover", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(8), _scaled_int(1)))
	right.add_theme_stylebox_override("pressed", Palette.make_button_style(Palette.BUTTON_PRESSED, _scaled_int(8), _scaled_int(1)))
	right.add_theme_stylebox_override("focus", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(8), _scaled_int(1)))
	right.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	right.pressed.connect(_on_binding_button_pressed.bind(action_name, right))

	row.add_child(left)
	row.add_child(right)
	return row

func _get_current_popup_width() -> float:
	if popup != null and popup.size.x > 0:
		return float(popup.size.x)
	return float(_scaled_int(POPUP_BASE_SIZE.x))

func _get_current_content_width() -> float:
	return max(
		_get_current_popup_width() - (_scaled(POPUP_CONTENT_MARGIN) * 2.0) - _scaled(POPUP_SCROLLBAR_RESERVE),
		1.0
	)

func _get_binding_column_width(row_width: float) -> float:
	var min_width := _scaled(BINDING_COLUMN_MIN_WIDTH)
	var max_width = min(_scaled(BINDING_COLUMN_MAX_WIDTH), max(min_width, row_width * 0.58))
	return clampf(row_width * BINDING_COLUMN_WIDTH_RATIO, min_width, max_width)

func _events_to_string(events: Array[InputEvent]) -> String:
	var parts: Array[String] = []
	if events.is_empty():
		return UNBOUND_TEXT

	for input_event in events:
		parts.append(input_event.as_text())
	return ", ".join(parts)

func _on_binding_button_pressed(action_name: String, button: Button) -> void:
	call_deferred("_begin_rebind", action_name, button)

func _begin_rebind(action_name: String, button: Button) -> void:
	_cancel_pending_rebind()
	_awaiting_action = action_name
	_awaiting_button = button
	if _awaiting_button != null and is_instance_valid(_awaiting_button):
		_awaiting_button.text = REBIND_PROMPT
	_show_capture_overlay()

func _cancel_pending_rebind() -> void:
	if _awaiting_button != null and is_instance_valid(_awaiting_button) and _awaiting_action != "":
		_awaiting_button.text = _events_to_string(InputMap.action_get_events(StringName(_awaiting_action)))
	_awaiting_action = ""
	_awaiting_button = null
	_hide_capture_overlay()

func _on_popup_hidden() -> void:
	_cancel_pending_rebind()
	_popup_anchor_override = Rect2()

func _ensure_capture_overlay() -> void:
	if popup == null or _capture_overlay != null:
		return

	_capture_overlay = Control.new()
	_capture_overlay.name = "RebindCaptureOverlay"
	_capture_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_capture_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_capture_overlay.focus_mode = Control.FOCUS_ALL
	_capture_overlay.visible = false
	_capture_overlay.gui_input.connect(_on_capture_overlay_gui_input)
	popup.add_child(_capture_overlay)

	var overlay_label := Label.new()
	overlay_label.name = "PromptLabel"
	overlay_label.set_anchors_preset(Control.PRESET_CENTER)
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay_label.text = REBIND_PROMPT
	overlay_label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	_capture_overlay.add_child(overlay_label)
	_layout_capture_overlay()


func _layout_capture_overlay() -> void:
	if _capture_overlay == null:
		return
	var overlay_label := _capture_overlay.get_node_or_null("PromptLabel") as Label
	if overlay_label == null:
		return
	var label_size := Vector2(_scaled(180), _scaled(24))
	overlay_label.position = Vector2(label_size.x * -0.5, label_size.y * -0.5)
	overlay_label.size = label_size
	UiScale.apply_font_size(overlay_label, &"font_size", 16, _ui_scale, true)


func _scaled(value: float) -> float:
	return UiScale.scaled(value, _ui_scale)


func _scaled_int(value: float) -> int:
	return UiScale.scaled_int(value, _ui_scale)


func _scaled_vec2i(value: Vector2i) -> Vector2i:
	return UiScale.scaled_vec2i(value, _ui_scale)


func _show_capture_overlay() -> void:
	_ensure_capture_overlay()
	if _capture_overlay == null:
		return
	_capture_overlay.show()
	_capture_overlay.grab_focus()


func _hide_capture_overlay() -> void:
	if _capture_overlay != null:
		_capture_overlay.hide()


func _on_capture_overlay_gui_input(event: InputEvent) -> void:
	if _awaiting_action == "":
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE):
			_cancel_pending_rebind()
			_capture_overlay.accept_event()
			return

	var rebound_event := _normalize_rebind_event(event)
	if rebound_event == null:
		return

	_apply_rebind(_awaiting_action, rebound_event)
	_capture_overlay.accept_event()

func _normalize_rebind_event(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return null
		var normalized_key := key_event.duplicate() as InputEventKey
		normalized_key.pressed = false
		normalized_key.echo = false
		return normalized_key

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			return null
		var normalized_mouse := mouse_event.duplicate() as InputEventMouseButton
		normalized_mouse.pressed = false
		normalized_mouse.double_click = false
		normalized_mouse.button_mask = 0
		normalized_mouse.position = Vector2.ZERO
		normalized_mouse.global_position = Vector2.ZERO
		return normalized_mouse

	if event is InputEventJoypadButton:
		var joypad_button := event as InputEventJoypadButton
		if not joypad_button.pressed:
			return null
		var normalized_button := joypad_button.duplicate() as InputEventJoypadButton
		normalized_button.pressed = false
		return normalized_button

	if event is InputEventJoypadMotion:
		var joypad_motion := event as InputEventJoypadMotion
		if abs(joypad_motion.axis_value) < 0.5:
			return null
		var normalized_motion := joypad_motion.duplicate() as InputEventJoypadMotion
		normalized_motion.axis_value = 1.0 if joypad_motion.axis_value > 0.0 else -1.0
		return normalized_motion

	return null

func _apply_rebind(action_name: String, input_event: InputEvent) -> void:
	var action := StringName(action_name)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, input_event)
	_save_bindings()
	_awaiting_action = ""
	_awaiting_button = null
	_hide_capture_overlay()
	_refresh_list()

func _save_bindings() -> void:
	var config := ConfigFile.new()
	config.set_value(BINDINGS_METADATA_SECTION, BINDINGS_VERSION_KEY, BINDINGS_CONFIG_VERSION)
	for action_name_variant in InputMap.get_actions():
		var action_name := String(action_name_variant)
		var serialized_events: Array[String] = []
		for input_event in InputMap.action_get_events(action_name_variant):
			serialized_events.append(var_to_str(input_event))
		config.set_value(BINDINGS_CONFIG_SECTION, action_name, serialized_events)

	var save_result := config.save(bindings_save_path)
	if save_result != OK:
		push_warning("Failed to save input bindings to %s" % bindings_save_path)

func _load_saved_bindings() -> void:
	var config := ConfigFile.new()
	var load_result := config.load(bindings_save_path)
	if load_result != OK or not config.has_section(BINDINGS_CONFIG_SECTION):
		return

	var saved_version := 0
	if config.has_section_key(BINDINGS_METADATA_SECTION, BINDINGS_VERSION_KEY):
		saved_version = int(config.get_value(BINDINGS_METADATA_SECTION, BINDINGS_VERSION_KEY, 0))

	for action_name in config.get_section_keys(BINDINGS_CONFIG_SECTION):
		var action := StringName(action_name)
		if not InputMap.has_action(action):
			continue

		var serialized_events = config.get_value(BINDINGS_CONFIG_SECTION, action_name, [])
		if not (serialized_events is Array):
			continue

		var restored_events: Array[InputEvent] = []
		for serialized_event in serialized_events:
			if not (serialized_event is String):
				continue
			var restored_event = str_to_var(serialized_event)
			if restored_event is InputEvent:
				restored_events.append(restored_event as InputEvent)

		if _should_skip_saved_binding(action, restored_events, saved_version):
			continue

		InputMap.action_erase_events(action)
		for restored_event in restored_events:
			InputMap.action_add_event(action, restored_event)

func _should_skip_saved_binding(action: StringName, restored_events: Array[InputEvent], saved_version: int) -> bool:
	if saved_version >= BINDINGS_CONFIG_VERSION:
		return false
	if action != BUILD_CANCEL_ACTION:
		return false
	if not _events_include_mouse_button(restored_events, MOUSE_BUTTON_RIGHT):
		return false
	return not _events_include_mouse_button(InputMap.action_get_events(action), MOUSE_BUTTON_RIGHT)

func _events_include_mouse_button(events: Array[InputEvent], mouse_button: MouseButton) -> bool:
	for input_event in events:
		if input_event is InputEventMouseButton and (input_event as InputEventMouseButton).button_index == mouse_button:
			return true
	return false
