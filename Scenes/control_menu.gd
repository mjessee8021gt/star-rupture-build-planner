extends MenuButton

const Palette = preload("res://Scripts/palette.gd")
const BINDINGS_CONFIG_SECTION := "input_bindings"
const BINDINGS_METADATA_SECTION := "input_bindings_metadata"
const BINDINGS_VERSION_KEY := "version"
const BINDINGS_CONFIG_VERSION := 2
const BUILD_CANCEL_ACTION := &"Build Cancel"
const REBIND_PROMPT := "Press input..."
const UNBOUND_TEXT := "-"

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

func _ready() -> void:
	pressed.connect(_on_pressed)
	if popup != null and not popup.popup_hide.is_connected(_on_popup_hidden):
		popup.popup_hide.connect(_on_popup_hidden)
	_ensure_capture_overlay()
	_load_saved_bindings()
	popup.hide()

func _on_pressed() -> void:
	if popup.visible:
		_cancel_pending_rebind()
		popup.hide()
		return

	_refresh_list()
	_position_popup()
	popup.popup()

func _position_popup() -> void:
	var rect := get_global_rect()
	popup.position = Vector2i(rect.position.x + 50, rect.position.y - (4.45 * rect.size.y))

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
	var middle_spacer := Control.new()
	var right := Button.new()
	var right_padding := Control.new()

	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 20)

	left.text = action_name
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)

	middle_spacer.custom_minimum_size.x = 50.0

	right.text = bindings
	right.alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.custom_minimum_size.x = 160.0
	right.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	right.add_theme_color_override("font_hover_color", Palette.TEXT_PRIMARY)
	right.add_theme_color_override("font_pressed_color", Palette.TEXT_PRIMARY)
	right.add_theme_stylebox_override("normal", Palette.make_button_style(Palette.BUTTON_FILL))
	right.add_theme_stylebox_override("hover", Palette.make_button_style(Palette.BUTTON_HOVER))
	right.add_theme_stylebox_override("pressed", Palette.make_button_style(Palette.BUTTON_PRESSED))
	right.add_theme_stylebox_override("focus", Palette.make_button_style(Palette.BUTTON_HOVER))
	right.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	right.pressed.connect(_on_binding_button_pressed.bind(action_name, right))

	right_padding.custom_minimum_size.x = 18.0

	row.add_child(left)
	row.add_child(middle_spacer)
	row.add_child(right)
	row.add_child(right_padding)
	return row

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
	overlay_label.position = Vector2(-90, -12)
	overlay_label.size = Vector2(180, 24)
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay_label.text = REBIND_PROMPT
	overlay_label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	_capture_overlay.add_child(overlay_label)


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
