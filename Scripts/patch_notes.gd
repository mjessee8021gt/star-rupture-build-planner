extends MenuButton

@export var panel_scene: PackedScene

const UiScale = preload("res://Scripts/ui_scale.gd")
const PANEL_BASE_SIZE := Vector2i(900, 650)
const PANEL_MIN_SIZE := Vector2i(320, 260)
const PANEL_VIEWPORT_MARGIN := 24

var _panel: PopupPanel
var _ui_scale := 1.0

func _ready() -> void:
	# Make the MenuButton act like a toggle button for the panel.
	pressed.connect(toggle_panel)
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func set_ui_scale(ui_scale: float) -> void:
	_ui_scale = maxf(ui_scale, 0.001)
	if _panel != null and is_instance_valid(_panel) and _panel.has_method("set_ui_scale"):
		_panel.call("set_ui_scale", _ui_scale)
	if is_panel_open():
		call_deferred("_layout_open_panel")

func toggle_panel() -> void:
	if _panel == null:
		if panel_scene == null:
			push_warning("MenuButton: panel_scene not set.")
			return

		_panel = panel_scene.instantiate() as PopupPanel
		get_tree().root.add_child(_panel)
		if _panel.has_method("set_ui_scale"):
			_panel.call("set_ui_scale", _ui_scale)
		
		_panel.hide()
	
	if _panel.visible:
		_panel.hide()
	else:
		call_deferred("_open_panel")


func _toggle_panel() -> void:
	toggle_panel()

func _open_panel() -> void:
	if _panel == null:
		return
	var panel_size := _get_panel_size()
	_panel.min_size = Vector2i.ZERO
	_panel.popup_centered(panel_size)
	_apply_panel_layout(panel_size)
	if _panel.has_method("refresh"):
		_panel.call("refresh")


func is_panel_open() -> bool:
	return _panel != null and is_instance_valid(_panel) and _panel.visible

func _on_viewport_size_changed() -> void:
	if is_panel_open():
		call_deferred("_layout_open_panel")

func _layout_open_panel() -> void:
	if not is_panel_open():
		return

	var panel_size := _get_panel_size()
	_panel.min_size = Vector2i.ZERO
	_panel.size = panel_size
	_center_panel(panel_size)
	_apply_panel_layout(panel_size)

func _get_panel_size() -> Vector2i:
	var viewport_size = get_viewport().size
	var viewport_margin := _scaled_int(PANEL_VIEWPORT_MARGIN)
	var available_width = max(viewport_size.x - (viewport_margin * 2), 1)
	var available_height = max(viewport_size.y - (viewport_margin * 2), 1)
	var base_size := _scaled_vec2i(PANEL_BASE_SIZE)
	var min_size := _scaled_vec2i(PANEL_MIN_SIZE)
	var target_width = min(base_size.x, available_width)
	var target_height = min(base_size.y, available_height)
	target_width = max(min(min_size.x, available_width), target_width)
	target_height = max(min(min_size.y, available_height), target_height)
	return Vector2i(target_width, target_height)

func _center_panel(panel_size: Vector2i) -> void:
	var viewport_size = get_viewport().size
	var viewport_margin := _scaled_int(PANEL_VIEWPORT_MARGIN)
	var x = maxi(viewport_margin, int((viewport_size.x - panel_size.x) * 0.5))
	var y = maxi(viewport_margin, int((viewport_size.y - panel_size.y) * 0.5))
	_panel.position = Vector2i(x, y)

func _apply_panel_layout(panel_size: Vector2i) -> void:
	if _panel == null:
		return
	if _panel.has_method("set_ui_scale"):
		_panel.call("set_ui_scale", _ui_scale)
	if _panel.has_method("apply_responsive_layout"):
		_panel.call("apply_responsive_layout", panel_size)

func _scaled_int(value: float) -> int:
	return UiScale.scaled_int(value, _ui_scale)

func _scaled_vec2i(value: Vector2i) -> Vector2i:
	return UiScale.scaled_vec2i(value, _ui_scale)
