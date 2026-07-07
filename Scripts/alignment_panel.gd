extends PanelContainer

# Contextual alignment toolbar for the Building Alignment Tools.
#
# Appears automatically whenever 2+ buildings are selected and drives
# BuildManager.align_selected_buildings(...). Quick actions cover the common
# align/distribute/pack/arrange commands; an "Options" section exposes the
# advanced reference mode, distribution metric, gap, strict/best-effort
# placement, and connector-port alignment. Styling/scaling follows the same
# Palette + UiScale conventions as the accessibility control menu.

const Palette = preload("res://Scripts/palette.gd")
const UiScale = preload("res://Scripts/ui_scale.gd")

const REFERENCE_VALUES := ["selection", "first", "last", "anchor", "grid"]
const REFERENCE_LABELS := ["Selection bounds", "First selected", "Last selected", "Anchor building", "Grid"]
const METRIC_VALUES := ["fixed_gap", "gap", "leading", "trailing", "center"]
const METRIC_LABELS := ["Fixed spacing", "Even gaps", "Leading edges", "Trailing edges", "Centers"]
const PORT_ROLE_VALUES := ["input", "output", "any"]
const PORT_ROLE_LABELS := ["Input ports", "Output ports", "Any port"]

const TOP_MARGIN := 44.0
const STATUS_OK := Color8(150, 214, 178, 255)
const STATUS_FAIL := Color8(228, 156, 120, 255)

var _build_manager: Node = null
var _ui_scale := 1.0
var _advanced_open := false
var _built := false

var _content: VBoxContainer = null
var _title_label: Label = null
var _anchor_label: Label = null
var _options_button: Button = null
var _advanced_box: VBoxContainer = null
var _reference_option: OptionButton = null
var _metric_option: OptionButton = null
var _gap_spin: SpinBox = null
var _strict_check: CheckButton = null
var _port_role_option: OptionButton = null
var _status_label: Label = null
var _styled_controls: Array = []


func setup(build_manager: Node) -> void:
	_build_manager = build_manager
	if _build_manager != null and _build_manager.has_signal("selection_changed"):
		var cb := Callable(self, "on_selection_changed")
		if not _build_manager.is_connected("selection_changed", cb):
			_build_manager.connect("selection_changed", cb)
	_ensure_built()


func _ready() -> void:
	visible = false
	_ensure_built()


func _ensure_built() -> void:
	# May be triggered from setup() before _ready fires (nodes added during a
	# parent's _ready have their own _ready deferred), so keep it idempotent.
	if _built:
		return
	_built = true
	name = "AlignmentPanel"
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


func on_selection_changed(selected_count: int, anchor_building: Node) -> void:
	_ensure_built()
	if selected_count < 2:
		visible = false
		return
	visible = true
	_title_label.text = "Align %d buildings" % selected_count
	if anchor_building != null and is_instance_valid(anchor_building):
		_anchor_label.text = "Anchor: %s" % _anchor_display_name(anchor_building)
		_anchor_label.visible = true
	else:
		_anchor_label.visible = false
	_status_label.text = ""
	call_deferred("_reposition")


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	_content = VBoxContainer.new()
	add_child(_content)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Align buildings"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_anchor_label = Label.new()
	_anchor_label.visible = false
	header.add_child(_anchor_label)

	_options_button = _make_button("Options ▾", "")
	_options_button.pressed.connect(_toggle_advanced)
	header.add_child(_options_button)

	# Quick action rows.
	_content.add_child(_make_action_row("Align", [
		["Left", "align_left"], ["H·Center", "align_hcenter"], ["Right", "align_right"],
		["Top", "align_top"], ["V·Center", "align_vcenter"], ["Bottom", "align_bottom"],
	]))
	_content.add_child(_make_action_row("Distribute", [
		["Horizontal", "distribute_horizontal"], ["Vertical", "distribute_vertical"],
	]))
	_content.add_child(_make_action_row("Pack", [
		["Horizontal", "pack_horizontal"], ["Vertical", "pack_vertical"],
	]))

	# Shared spacing for Pack and (fixed-spacing) Distribute, kept visible next
	# to those actions rather than buried in Options.
	_gap_spin = SpinBox.new()
	_gap_spin.min_value = 0
	_gap_spin.max_value = 32
	_gap_spin.step = 1
	_gap_spin.value = 0
	_content.add_child(_make_labeled_row("Spacing (tiles)", _gap_spin))

	_content.add_child(_make_action_row("Arrange", [
		["Row", "arrange_row"], ["Column", "arrange_column"], ["Grid", "arrange_grid"],
	]))

	_advanced_box = _build_advanced_section()
	_advanced_box.visible = false
	_content.add_child(_advanced_box)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_status_label)


func _build_advanced_section() -> VBoxContainer:
	var box := VBoxContainer.new()

	_reference_option = _make_option(REFERENCE_LABELS)
	box.add_child(_make_labeled_row("Reference", _reference_option))

	_metric_option = _make_option(METRIC_LABELS)
	box.add_child(_make_labeled_row("Distribute by", _metric_option))

	_strict_check = CheckButton.new()
	_strict_check.text = "Strict (all-or-nothing)"
	_strict_check.button_pressed = true
	_strict_check.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_styled_controls.append(_strict_check)
	box.add_child(_strict_check)

	var port_row := HBoxContainer.new()
	_port_role_option = _make_option(PORT_ROLE_LABELS)
	_port_role_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_row.add_child(_port_role_option)
	var port_x := _make_button("Align ↕→X", "port_align_x")
	var port_y := _make_button("Align ↔→Y", "port_align_y")
	port_row.add_child(port_x)
	port_row.add_child(port_y)
	box.add_child(_make_labeled_row("Ports", port_row))

	var anchor_row := HBoxContainer.new()
	var set_anchor_btn := _make_button("Set anchor", "")
	set_anchor_btn.pressed.connect(_on_set_anchor)
	var cycle_anchor_btn := _make_button("Cycle anchor", "")
	cycle_anchor_btn.pressed.connect(_on_cycle_anchor)
	anchor_row.add_child(set_anchor_btn)
	anchor_row.add_child(cycle_anchor_btn)
	box.add_child(_make_labeled_row("Anchor", anchor_row))

	return box


func _make_action_row(title: String, actions: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.name = "SectionLabel"
	row.add_child(label)
	for action in actions:
		row.add_child(_make_button(action[0], action[1]))
	return row


func _make_labeled_row(title: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.name = "FieldLabel"
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _make_button(text: String, command: String) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if command != "":
		button.pressed.connect(_run.bind(command))
	_styled_controls.append(button)
	return button


func _make_option(labels: Array) -> OptionButton:
	var option := OptionButton.new()
	for label in labels:
		option.add_item(label)
	option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_styled_controls.append(option)
	return option


# --- Actions -----------------------------------------------------------------

func _run(command: String) -> void:
	if _build_manager == null or not _build_manager.has_method("align_selected_buildings"):
		return
	var result = _build_manager.call("align_selected_buildings", command, _options())
	_show_result(result)


func _options() -> Dictionary:
	return {
		"reference_mode": REFERENCE_VALUES[_reference_option.selected] if _reference_option != null else "selection",
		"metric": METRIC_VALUES[_metric_option.selected] if _metric_option != null else "gap",
		"gap": int(_gap_spin.value) if _gap_spin != null else 0,
		"strict": _strict_check.button_pressed if _strict_check != null else true,
		"port_role": PORT_ROLE_VALUES[_port_role_option.selected] if _port_role_option != null else "input",
	}


func _show_result(result) -> void:
	if not (result is Dictionary):
		return
	var ok := bool(result.get("ok", false))
	_status_label.text = String(result.get("message", ""))
	_status_label.add_theme_color_override("font_color", STATUS_OK if ok else STATUS_FAIL)


func _toggle_advanced() -> void:
	_advanced_open = not _advanced_open
	_advanced_box.visible = _advanced_open
	_options_button.text = "Options ▴" if _advanced_open else "Options ▾"


func _on_set_anchor() -> void:
	if _build_manager != null and _build_manager.has_method("set_alignment_anchor_to_hovered_or_first"):
		_build_manager.call("set_alignment_anchor_to_hovered_or_first")


func _on_cycle_anchor() -> void:
	if _build_manager != null and _build_manager.has_method("cycle_alignment_anchor"):
		_build_manager.call("cycle_alignment_anchor")


func _anchor_display_name(building: Node) -> String:
	if "building_name" in building and String(building.building_name) != "":
		return String(building.building_name)
	return String(building.name)


# --- Layout / styling --------------------------------------------------------

func _reposition() -> void:
	if get_viewport() == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := size
	var x = maxf((viewport_size.x - panel_size.x) * 0.5, _scaled(8.0))
	position = Vector2(x, _scaled(TOP_MARGIN))


func _style() -> void:
	add_theme_stylebox_override("panel", Palette.make_panel_style(Palette.SCENE_PANEL_FILL, Palette.SCENE_PANEL_BORDER, _scaled_int(8), _scaled_int(1)))

	if _content != null:
		_content.add_theme_constant_override("separation", _scaled_int(6))
	for child in _content.get_children() if _content != null else []:
		if child is HBoxContainer or child is VBoxContainer:
			child.add_theme_constant_override("separation", _scaled_int(6))
	if _advanced_box != null:
		_advanced_box.add_theme_constant_override("separation", _scaled_int(6))
		for child in _advanced_box.get_children():
			if child is HBoxContainer:
				child.add_theme_constant_override("separation", _scaled_int(6))

	if _title_label != null:
		_title_label.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
		UiScale.apply_font_size(_title_label, &"font_size", 15, _ui_scale, true)
	if _anchor_label != null:
		_anchor_label.add_theme_color_override("font_color", Palette.TEXT_BADGE)
		UiScale.apply_font_size(_anchor_label, &"font_size", 13, _ui_scale, true)
	if _status_label != null:
		UiScale.apply_font_size(_status_label, &"font_size", 12, _ui_scale, true)
		_status_label.custom_minimum_size = Vector2(_scaled(320.0), 0.0)

	_style_section_labels(self)

	for control in _styled_controls:
		if control == null or not is_instance_valid(control):
			continue
		if control is Button:
			_style_button(control)
		elif control is OptionButton:
			_style_button(control)
	if _gap_spin != null:
		UiScale.apply_font_size(_gap_spin, &"font_size", 13, _ui_scale, true)
		_gap_spin.custom_minimum_size = Vector2(_scaled(72.0), 0.0)


func _style_section_labels(node: Node) -> void:
	for child in node.get_children():
		if child is Label and (child.name == "SectionLabel" or child.name == "FieldLabel"):
			child.add_theme_color_override("font_color", Palette.TEXT_MUTED)
			UiScale.apply_font_size(child, &"font_size", 12, _ui_scale, true)
			child.custom_minimum_size = Vector2(_scaled(74.0), 0.0)
			child.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if child.get_child_count() > 0:
			_style_section_labels(child)


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
