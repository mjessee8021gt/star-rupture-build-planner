extends PanelContainer

# Contextual mirror toolbar for the group eyedropper.
#
# Appears automatically whenever a multi-building eyedropper build is active
# (BuildManager.group_build_changed) and drives BuildManager.mirror_group_layout,
# flipping the ghost block (and its copied rails) left<->right or top<->bottom.
# The same actions are bound to the "Mirror Horizontal"/"Mirror Vertical" keys;
# this panel just exposes them for discoverability. Styling/scaling follows the
# same Palette + UiScale conventions as the alignment toolbar.

const Palette = preload("res://Scripts/palette.gd")
const UiScale = preload("res://Scripts/ui_scale.gd")

const TOP_MARGIN := 44.0

var _build_manager: Node = null
var _ui_scale := 1.0
var _built := false

var _content: VBoxContainer = null
var _title_label: Label = null
var _hint_label: Label = null
var _styled_buttons: Array = []


func setup(build_manager: Node) -> void:
	_build_manager = build_manager
	if _build_manager != null and _build_manager.has_signal("group_build_changed"):
		var cb := Callable(self, "on_group_build_changed")
		if not _build_manager.is_connected("group_build_changed", cb):
			_build_manager.connect("group_build_changed", cb)
	_ensure_built()


func _ready() -> void:
	visible = false
	_ensure_built()


func _ensure_built() -> void:
	# May be triggered from setup() before _ready fires, so keep it idempotent.
	if _built:
		return
	_built = true
	name = "MirrorPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_build_ui()
	if not resized.is_connected(_reposition):
		resized.connect(_reposition)
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_reposition):
		get_viewport().size_changed.connect(_reposition)
	_style()


# --- Public API used by Main -------------------------------------------------

func set_ui_scale(ui_scale: float) -> void:
	_ui_scale = maxf(ui_scale, 0.001)
	_ensure_built()
	_style()
	call_deferred("_reposition")


func on_group_build_changed(active: bool) -> void:
	_ensure_built()
	visible = active
	if active:
		# Snap to content size before repositioning so a stale/oversized height
		# can never leave the panel stretched down the screen.
		call_deferred("_snap_to_content")


func _snap_to_content() -> void:
	reset_size()
	_reposition()


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	_content = VBoxContainer.new()
	add_child(_content)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Mirror layout"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	var button_row := HBoxContainer.new()
	button_row.add_child(_make_button("Mirror ⇄  (H)", "horizontal"))
	button_row.add_child(_make_button("Mirror ⇅  (G)", "vertical"))
	_content.add_child(button_row)

	# Deliberately NOT autowrapped: an autowrap Label that carries text while the
	# panel is first laid out hidden (zero width) locks in a tall minimum height
	# (one line per word), which stretches the whole PanelContainer down the
	# screen. A single non-wrapping line sizes the panel to its own width instead.
	_hint_label = Label.new()
	_hint_label.text = "Flips the block in place, rails included."
	_content.add_child(_hint_label)


func _make_button(text: String, axis: String) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_on_mirror_pressed.bind(axis))
	_styled_buttons.append(button)
	return button


func _on_mirror_pressed(axis: String) -> void:
	if _build_manager != null and _build_manager.has_method("mirror_group_layout"):
		_build_manager.call("mirror_group_layout", axis)


# --- Layout / styling --------------------------------------------------------

func _reposition() -> void:
	if get_viewport() == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var x = maxf((viewport_size.x - size.x) * 0.5, _scaled(8.0))
	position = Vector2(x, _scaled(TOP_MARGIN))


func _style() -> void:
	add_theme_stylebox_override("panel", Palette.make_panel_style(Palette.SCENE_PANEL_FILL, Palette.SCENE_PANEL_BORDER, _scaled_int(8), _scaled_int(1)))

	if _content != null:
		_content.add_theme_constant_override("separation", _scaled_int(6))
		for child in _content.get_children():
			if child is HBoxContainer:
				child.add_theme_constant_override("separation", _scaled_int(6))

	if _title_label != null:
		_title_label.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
		UiScale.apply_font_size(_title_label, &"font_size", 15, _ui_scale, true)
	if _hint_label != null:
		_hint_label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		UiScale.apply_font_size(_hint_label, &"font_size", 12, _ui_scale, true)

	for button in _styled_buttons:
		if button == null or not is_instance_valid(button):
			continue
		_style_button(button)


func _style_button(button: BaseButton) -> void:
	UiScale.apply_font_size(button, &"font_size", 13, _ui_scale, true)
	button.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", Palette.TEXT_PRIMARY)
	button.add_theme_stylebox_override("normal", Palette.make_button_style(Palette.BUTTON_FILL, _scaled_int(6), _scaled_int(1)))
	button.add_theme_stylebox_override("hover", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(6), _scaled_int(1)))
	button.add_theme_stylebox_override("pressed", Palette.make_button_style(Palette.BUTTON_PRESSED, _scaled_int(6), _scaled_int(1)))
	button.add_theme_stylebox_override("focus", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(6), _scaled_int(1)))


func _scaled(value: float) -> float:
	return UiScale.scaled(value, _ui_scale)


func _scaled_int(value: float) -> int:
	return UiScale.scaled_int(value, _ui_scale)
