extends PanelContainer

# First-run controls card (UAT-04).
#
# A small, dismissable card that tucks under the heat/power/cost box in the
# top-right corner and shows the handful of controls a new user most needs to
# get moving -- pan, relocate, rotate, flip, eyedropper. It surfaces once on a
# fresh install (a "seen" flag persists to user://) and is never modal: the
# player can keep building with it on screen.
#
# Key labels are read live from the InputMap, so they stay correct after the
# player rebinds anything in the Control menu (control_menu.gd). "View all
# controls" opens that full reference, so dismissing the card is never a dead
# end.

signal view_all_controls_requested

const Palette = preload("res://Scripts/palette.gd")
const UiScale = preload("res://Scripts/ui_scale.gd")

const CONFIG_PATH := "user://onboarding.cfg"
const CONFIG_SECTION := "onboarding"
const SEEN_KEY := "seen_controls_hint"
const ANCHOR_GAP := 8.0
const VIEWPORT_MARGIN := 8.0

# action name -> {label, hint}. Pan is handled separately (four actions, one row).
const CONTROL_ROWS := [
	{"action": "Move Build", "label": "Move building", "hint": "relocate a placed building"},
	{"action": "Rotate", "label": "Rotate", "hint": "while placing or moving"},
	{"action": "Alternate", "label": "Flip layout", "hint": "swap the alternate footprint"},
	{"action": "Eyedropper", "label": "Copy setup", "hint": "clone a building's config"},
]
const PAN_ACTIONS := ["Pan Up (Keyboard)", "Pan Left (Keyboard)", "Pan Down (Keyboard)", "Pan Right (Keyboard)"]

var _main: Node = null
var _ui_scale := 1.0
var _built := false
var _anchor_rect := Rect2()

var _title_label: Label = null
var _rows_grid: GridContainer = null
var _view_button: Button = null
var _dismiss_button: Button = null
var _styled_buttons: Array = []
var _key_badges: Array = []
var _text_labels: Array = []
var _hint_labels: Array = []


func setup(main_ref: Node, ui_scale: float) -> void:
	_main = main_ref
	_ui_scale = maxf(ui_scale, 0.001)
	_ensure_built()


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 4000
	_ensure_built()


func set_ui_scale(ui_scale: float) -> void:
	_ui_scale = maxf(ui_scale, 0.001)
	_ensure_built()
	_rebuild_rows()
	_style()
	# Font sizes changed the content; snap deferred so the container re-sorts first.
	call_deferred("_snap_to_content")


# Store the rect of the box we tuck under (the heat/power/cost panel) and
# reposition against it. Called from main's layout pass.
func set_anchor_rect(rect: Rect2) -> void:
	_anchor_rect = rect
	_reposition()


# Show once per install. Returns true if it actually surfaced.
func maybe_show_first_run() -> bool:
	if _load_seen_flag():
		return false
	show_hint()
	return true


func show_hint() -> void:
	_ensure_built()
	visible = true
	# Snap to content size before positioning so a stale/oversized height can never
	# leave the card stretched down the screen; deferred so the container sorts first.
	call_deferred("_snap_to_content")


func _snap_to_content() -> void:
	if not is_inside_tree():
		return
	reset_size()
	_reposition()


func _dismiss() -> void:
	visible = false
	_save_seen_flag()


# --- UI construction ---------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	name = "OnboardingHint"
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Anchor top-left so reset_size() shrinks the card to its content instead of
	# the anchors re-stretching it down the screen (see mirror_panel.gd).
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	if not resized.is_connected(_reposition):
		resized.connect(_reposition)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", _scaled_int(8))
	add_child(root)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Getting around"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_rows_grid = GridContainer.new()
	_rows_grid.columns = 2
	_rows_grid.add_theme_constant_override("h_separation", _scaled_int(14))
	_rows_grid.add_theme_constant_override("v_separation", _scaled_int(6))
	root.add_child(_rows_grid)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", _scaled_int(6))
	actions.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(actions)

	_view_button = _make_button("View all controls")
	_view_button.pressed.connect(_on_view_all_pressed)
	actions.add_child(_view_button)

	_dismiss_button = _make_button("Got it")
	_dismiss_button.pressed.connect(_dismiss)
	actions.add_child(_dismiss_button)

	_rebuild_rows()
	_style()


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_styled_buttons.append(button)
	return button


# --- Rows --------------------------------------------------------------------

func _rebuild_rows() -> void:
	if _rows_grid == null:
		return
	# Free immediately (not queue_free): a deferred free would leave old rows in the
	# grid for a frame, transiently doubling its height and inflating a size snapshot.
	for child in _rows_grid.get_children():
		_rows_grid.remove_child(child)
		child.free()
	_key_badges.clear()
	_text_labels.clear()
	_hint_labels.clear()

	_add_row("Pan", _pan_label(), "move the camera")
	for row in CONTROL_ROWS:
		_add_row(String(row.get("label", "")), _action_label(String(row.get("action", ""))), String(row.get("hint", "")))

	_style()


func _add_row(label_text: String, key_text: String, hint_text: String) -> void:
	# Left cell: name + muted hint under it.
	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 0)

	var name_label := Label.new()
	name_label.text = label_text
	_text_labels.append(name_label)
	name_box.add_child(name_label)

	if hint_text != "":
		var hint_label := Label.new()
		hint_label.text = hint_text
		_hint_labels.append(hint_label)
		name_box.add_child(hint_label)

	_rows_grid.add_child(name_box)

	# Right cell: key badge, top-aligned with the name.
	var badge_align := VBoxContainer.new()
	badge_align.size_flags_horizontal = Control.SIZE_SHRINK_END
	var badge := _make_key_badge(key_text)
	badge_align.add_child(badge)
	_rows_grid.add_child(badge_align)


func _make_key_badge(key_text: String) -> Control:
	var badge := PanelContainer.new()
	var badge_label := Label.new()
	badge_label.text = key_text if key_text != "" else "-"
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(badge_label)
	_key_badges.append({"panel": badge, "label": badge_label})
	return badge


# --- InputMap -> readable labels ---------------------------------------------

func _pan_label() -> String:
	var parts: Array[String] = []
	for action in PAN_ACTIONS:
		parts.append(_action_label(action))
	return " ".join(parts)


func _action_label(action: String) -> String:
	if action == "" or not InputMap.has_action(action):
		return "-"
	var events := InputMap.action_get_events(action)
	for event in events:
		var text := _event_label(event)
		if text != "":
			return text
	return "-"


func _event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var code := key_event.keycode
		if code == 0:
			code = key_event.physical_keycode
		var base := OS.get_keycode_string(code)
		var mods: Array[String] = []
		if key_event.ctrl_pressed:
			mods.append("Ctrl")
		if key_event.alt_pressed:
			mods.append("Alt")
		if key_event.shift_pressed:
			mods.append("Shift")
		if key_event.meta_pressed:
			mods.append("Meta")
		if base != "" and not mods.is_empty():
			return "+".join(mods) + "+" + base
		return base
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "L-Mouse"
			MOUSE_BUTTON_RIGHT:
				return "R-Mouse"
			MOUSE_BUTTON_MIDDLE:
				return "M-Mouse"
			_:
				return "Mouse"
	return event.as_text()


# --- Positioning -------------------------------------------------------------

func _reposition() -> void:
	if not visible or not is_inside_tree() or _anchor_rect.size == Vector2.ZERO:
		return
	var card_size := size
	var viewport_size := Vector2(get_viewport_rect().size)
	# Right-align the card's right edge with the anchor box, sitting just below it.
	var x := _anchor_rect.position.x + _anchor_rect.size.x - card_size.x
	var y := _anchor_rect.position.y + _anchor_rect.size.y + _scaled(ANCHOR_GAP)
	x = clampf(x, _scaled(VIEWPORT_MARGIN), maxf(viewport_size.x - card_size.x - _scaled(VIEWPORT_MARGIN), _scaled(VIEWPORT_MARGIN)))
	y = clampf(y, _anchor_rect.position.y, maxf(viewport_size.y - card_size.y - _scaled(VIEWPORT_MARGIN), _anchor_rect.position.y))
	position = Vector2(x, y)


# --- Persistence -------------------------------------------------------------

func _load_seen_flag() -> bool:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return false
	return bool(config.get_value(CONFIG_SECTION, SEEN_KEY, false))


func _save_seen_flag() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)  # ignore error; start fresh if absent
	config.set_value(CONFIG_SECTION, SEEN_KEY, true)
	config.save(CONFIG_PATH)


# --- Styling -----------------------------------------------------------------

func _on_view_all_pressed() -> void:
	view_all_controls_requested.emit()


func _style() -> void:
	add_theme_stylebox_override("panel", Palette.make_panel_style(Palette.SCENE_PANEL_FILL, Palette.SCENE_PANEL_BORDER, _scaled_int(10), _scaled_int(2)))

	if _title_label != null:
		_title_label.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
		UiScale.apply_font_size(_title_label, &"font_size", 16, _ui_scale, true)

	if _rows_grid != null:
		_rows_grid.add_theme_constant_override("h_separation", _scaled_int(14))
		_rows_grid.add_theme_constant_override("v_separation", _scaled_int(6))

	for label in _text_labels:
		if label != null and is_instance_valid(label):
			label.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
			UiScale.apply_font_size(label, &"font_size", 13, _ui_scale, true)

	for label in _hint_labels:
		if label != null and is_instance_valid(label):
			label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
			UiScale.apply_font_size(label, &"font_size", 11, _ui_scale, true)

	for badge in _key_badges:
		var panel := badge.get("panel") as PanelContainer
		var label := badge.get("label") as Label
		if panel != null and is_instance_valid(panel):
			panel.add_theme_stylebox_override("panel", Palette.make_button_style(Palette.BUTTON_FILL, _scaled_int(6), _scaled_int(1)))
		if label != null and is_instance_valid(label):
			label.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
			UiScale.apply_font_size(label, &"font_size", 12, _ui_scale, true)

	for button in _styled_buttons:
		if button != null and is_instance_valid(button):
			_style_button(button)


func _style_button(button: BaseButton) -> void:
	UiScale.apply_font_size(button, &"font_size", 12, _ui_scale, true)
	button.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", Palette.TEXT_PRIMARY)
	button.add_theme_color_override("font_pressed_color", Palette.TEXT_PRIMARY)
	button.add_theme_stylebox_override("normal", Palette.make_button_style(Palette.BUTTON_FILL, _scaled_int(6), _scaled_int(1)))
	button.add_theme_stylebox_override("hover", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(6), _scaled_int(1)))
	button.add_theme_stylebox_override("pressed", Palette.make_button_style(Palette.BUTTON_PRESSED, _scaled_int(6), _scaled_int(1)))
	button.add_theme_stylebox_override("focus", Palette.make_button_style(Palette.BUTTON_HOVER, _scaled_int(6), _scaled_int(1)))


func _scaled(value: float) -> float:
	return UiScale.scaled(value, _ui_scale)


func _scaled_int(value: float) -> int:
	return UiScale.scaled_int(value, _ui_scale)
