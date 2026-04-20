extends MenuButton

@export var panel_scene: PackedScene

const PANEL_BASE_SIZE := Vector2i(900, 650)
const PANEL_MIN_SIZE := Vector2i(320, 260)
const PANEL_VIEWPORT_MARGIN := 24

var _panel: PopupPanel

func _ready() -> void:
	# Make the MenuButton act like a toggle button for the panel.
	pressed.connect(_toggle_panel)
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func _toggle_panel() -> void:
	if _panel == null:
		if panel_scene == null:
			push_warning("MenuButton: panel_scene not set.")
			return

		_panel = panel_scene.instantiate() as PopupPanel
		get_tree().root.add_child(_panel)
		
		_panel.hide()
	
	if _panel.visible:
		_panel.hide()
	else:
		call_deferred("_open_panel")

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
	var available_width = max(viewport_size.x - (PANEL_VIEWPORT_MARGIN * 2), 1)
	var available_height = max(viewport_size.y - (PANEL_VIEWPORT_MARGIN * 2), 1)
	var target_width = min(PANEL_BASE_SIZE.x, available_width)
	var target_height = min(PANEL_BASE_SIZE.y, available_height)
	target_width = max(min(PANEL_MIN_SIZE.x, available_width), target_width)
	target_height = max(min(PANEL_MIN_SIZE.y, available_height), target_height)
	return Vector2i(target_width, target_height)

func _center_panel(panel_size: Vector2i) -> void:
	var viewport_size = get_viewport().size
	var x = maxi(PANEL_VIEWPORT_MARGIN, int((viewport_size.x - panel_size.x) * 0.5))
	var y = maxi(PANEL_VIEWPORT_MARGIN, int((viewport_size.y - panel_size.y) * 0.5))
	_panel.position = Vector2i(x, y)

func _apply_panel_layout(panel_size: Vector2i) -> void:
	if _panel == null:
		return
	if _panel.has_method("apply_responsive_layout"):
		_panel.call("apply_responsive_layout", panel_size)
